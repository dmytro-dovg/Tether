//
//  ContinuationManager.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-18.
//

import Foundation

enum ContinuationManagerError: Error {
    case continuationAlreadyExists
}

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
            // The only retrieval path is via ContinuationManager.continuation(for:as:) which returns
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

actor ContinuationManager<Key: Hashable> {
    private var continuations: [Key: AnyContinuation] = [:]
    private var streamContinuations: [Key: AnyStreamContinuation] = [:]

    // MARK: - Void continuations
    func waitForContinuation(for key: Key, _ begin: @Sendable () -> Void) async throws {
        guard !continuations.keys.contains(key) else {
            throw ContinuationManagerError.continuationAlreadyExists
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            continuations[key] = AnyContinuation(continuation)
            begin()
        }
    }

    func waitForContinuationWithResult<T: Sendable>(for key: Key, _ begin: @Sendable () -> Void) async throws -> T {
        guard !continuations.keys.contains(key) else {
            throw ContinuationManagerError.continuationAlreadyExists
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            continuations[key] = AnyContinuation(continuation)
            begin()
        }
    }

    func continuation<T: Sendable>(for key: Key, as type: T.Type = Void.self) -> TypedContinuation<T>? {
        guard let continuation = continuations.removeValue(forKey: key) else { return nil }
        return TypedContinuation<T>(continuation)
    }

    // MARK: - Stream continuations
    func waitForStream<T: Sendable>(for key: Key, _ begin: @Sendable (AsyncStream<T>.Continuation) -> Void) async throws -> AsyncStream<T> {
        guard !streamContinuations.keys.contains(key) else {
            throw ContinuationManagerError.continuationAlreadyExists
        }
        return AsyncStream(T.self) { continuation in
            streamContinuations[key] = AnyStreamContinuation(continuation)
            begin(continuation)
        }
    }

    func hasStream(for key: Key) -> Bool {
        streamContinuations.keys.contains(key)
    }

    func yield<T: Sendable>(_ value: T, for key: Key) {
        if let continuation = streamContinuations[key] {
            continuation.yield(value)
        }
    }

    func finish(_ key: Key) {
        if let continuation = streamContinuations.removeValue(forKey: key) {
            continuation.finish()
        }

    }
}
