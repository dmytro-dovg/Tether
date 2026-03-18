//
//  ContinuationManager.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-18.
//


enum ContinuationManagerError: Error {
    case continuationAlreadyExists
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
    var continuations: [Key: CheckedContinuation<Void, Error>] = [:]
    var streamContinuations: [Key: AnyStreamContinuation] = [:]

    func waitForContinuation(for key: Key, _ begin: @Sendable () -> Void) async throws {
        if continuations.keys.contains(key) {
            throw ContinuationManagerError.continuationAlreadyExists
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            continuations[key] = continuation
            begin()
        }
    }

    func waitForStream<T: Sendable>(for key: Key, _ begin: @Sendable (AsyncStream<T>.Continuation) -> Void) async throws -> AsyncStream<T> {
        if streamContinuations.keys.contains(key) {
            throw ContinuationManagerError.continuationAlreadyExists
        }
        return AsyncStream(T.self) { continuation in
            streamContinuations[key] = AnyStreamContinuation(continuation)
            begin(continuation)
        }
    }

    func continuation(for key: Key) -> CheckedContinuation<Void, Error>? {
        continuations.removeValue(forKey: key)
    }

    func yield<T: Sendable>(_ value: T, for key: Key) {
        if let continuation = streamContinuations[key] {
            continuation.yield(value)
        }
    }

    func finish(_ key: Key) {
        if let continuation = streamContinuations[key] {
            streamContinuations.removeValue(forKey: key)
            continuation.finish()
        }

    }
}
