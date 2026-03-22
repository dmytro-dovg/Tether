//
//  ContinuationManager.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-18.
//

import Foundation

struct TypedContinuation<T: Sendable>: Sendable {
    private let wrapped: AnyContinuation

    init(_ wrapped: AnyContinuation) { self.wrapped = wrapped }

    func resume(returning value: T) { wrapped.resume(returning: value) }
    func resume(throwing error: Error) { wrapped.resume(throwing: error) }
}

extension TypedContinuation where T == Void {
    func resume() { wrapped.resume() }
}

struct AnyContinuation: Sendable {
    private let _resumeWithAny: @Sendable (Any) -> Void
    private let _resumeWithError: @Sendable (Error) -> Void

    init<T: Sendable>(_ continuation: CheckedContinuation<T, Error>) {
        _resumeWithAny = { value in
            // Safe: this closure captures CheckedContinuation<T, Error> at construction time.
            // The only retrieval path is via ContinuationManager.removeContinuation(for:as:) which returns
            // TypedContinuation<T> ensuring resume(returning:) can only be called with
            // a value of the same T that was used to construct this continuation.
            // swiftlint:disable force_cast
            continuation.resume(returning: value as! T)
            // swiftlint:enable force_cast
        }
        _resumeWithError = { continuation.resume(throwing: $0) }
    }

    func resume<T: Sendable>(returning value: T) { _resumeWithAny(value) }
    func resume(throwing error: Error) { _resumeWithError(error) }
    func resume() { _resumeWithAny(()) }
}

struct AnyStreamContinuation: Sendable {
    private let _yield: @Sendable (Any) -> Void
    private let _finish: @Sendable () -> Void

    init<T: Sendable>(_ continuation: AsyncStream<T>.Continuation) {
        _yield = { value in
            if let typed = value as? T { continuation.yield(typed) }
        }
        _finish = { continuation.finish() }
    }

    func yield<T: Sendable>(_ value: T) { _yield(value) }
    func finish() { _finish() }
}

final class ContinuationManager<Key: Hashable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [Key: AnyContinuation] = [:]
    private var streamContinuations: [Key: AnyStreamContinuation] = [:]

    // MARK: - Void continuations
    func continuation(for key: Key, _ begin: @Sendable () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            lock.lock()
            guard !continuations.keys.contains(key) else {
                lock.unlock()
                continuation.resume(throwing: ContinuationManagerError.continuationExists)
                return
            }
            continuations[key] = AnyContinuation(continuation)
            lock.unlock()
            begin()
        }
    }

    func continuationWithResult<T: Sendable>(for key: Key, _ begin: @Sendable () -> Void) async throws -> T {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Swift.Error>) in
            lock.lock()
            guard !continuations.keys.contains(key) else {
                lock.unlock()
                continuation.resume(throwing: ContinuationManagerError.continuationExists)
                return
            }
            continuations[key] = AnyContinuation(continuation)
            lock.unlock()
            begin()
        }
    }

    func removeContinuation<T: Sendable>(for key: Key, as type: T.Type = Void.self) -> TypedContinuation<T>? {
        return lock.withLock {
            guard let continuation = continuations.removeValue(forKey: key) else { return nil }
            return TypedContinuation<T>(continuation)
        }
    }

    // MARK: - Stream continuations
    func stream<T: Sendable>(for key: Key, _ begin: @Sendable (AsyncStream<T>.Continuation) -> Void) throws -> AsyncStream<T> {
        let (stream, continuation) = AsyncStream<T>.makeStream()
        try lock.withLock {
            guard !streamContinuations.keys.contains(key) else {
                throw ContinuationManagerError.continuationExists
            }
            streamContinuations[key] = AnyStreamContinuation(continuation)
        }
        begin(continuation)
        return stream
    }

    func hasStream(for key: Key) -> Bool {
        lock.withLock {
            streamContinuations.keys.contains(key)
        }
    }

    func yield<T: Sendable>(_ value: T, for key: Key) {
        lock.withLock {
            streamContinuations[key]?.yield(value)
        }
    }

    func yield<T: Sendable>(_ value: T, where predicate: (Key) -> Bool) {
        lock.withLock {
            let keys = streamContinuations.keys.filter { predicate($0) }
            for key in keys {
                streamContinuations[key]?.yield(value)
            }
        }
    }

    func finish(_ key: Key) {
        lock.withLock {
            streamContinuations.removeValue(forKey: key)?.finish()
        }
    }
}
