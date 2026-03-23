//
//  ContinuationManagerTests.swift
//  Tether
//
//  Created by Dmytro Dovgoshliubnyi on 2026-03-22.
//

import Testing
@testable import Tether

@Suite("ContinuationManager")
struct ContinuationManagerTests {
    @Test func duplicateContinuationKeysThrow() async throws {
        let testKey = "testKey"
        let manager = ContinuationManager<String>()

        await withCheckedContinuation { signal in
            Task {
                try? await manager.continuation(for: testKey) {
                    signal.resume()
                }
            }
        }

        await #expect(throws: ContinuationManagerError.continuationExists) {
            try await manager.continuation(for: testKey) { }
        }
    }

    @Test func duplicateContinuationWithResultKeysThrow() async throws {
        let testKey = "testKey"
        let manager = ContinuationManager<String>()

        await withCheckedContinuation { signal in
            Task {
                let _: String? = try? await manager.continuationWithResult(for: testKey) {
                    signal.resume()
                }
            }
        }

        await #expect(throws: ContinuationManagerError.continuationExists) {
            let _: String = try await manager.continuationWithResult(for: testKey) { }
        }
    }

    @Test func duplicateStreamKeysThrow() async throws {
        let testKey = "testKey"
        let manager = ContinuationManager<String>()
        let _: AsyncStream<String> = try manager.stream(for: testKey) { _ in }
        #expect(throws: ContinuationManagerError.continuationExists) {
            let _: AsyncStream<String> = try manager.stream(for: testKey) { _ in }
        }
    }

    @Test func continuationResumes() async throws {
        let testKey = "testKey"
        let manager = ContinuationManager<String>()
        try await manager.continuation(for: testKey) {
            let continuation = manager.removeContinuation(for: testKey)
            #expect(continuation != nil)
            continuation?.resume()
        }
    }

    @Test func continuationWithReturnResumes() async throws {
        let testKey = "testKey"
        let expectedResult = "expectedResult"
        let manager = ContinuationManager<String>()
        let result: String = try await manager.continuationWithResult(for: testKey) {
            let continuation = manager.removeContinuation(for: testKey, as: String.self)
            #expect(continuation != nil)
            continuation?.resume(returning: expectedResult)
        }
        #expect(result == expectedResult)
    }

    @Test func continuationThrows() async throws {
        let testKey = "testKey"
        struct TestError: Error {}
        let error = TestError()
        let manager = ContinuationManager<String>()
        await #expect(throws: TestError.self) {
            try await manager.continuation(for: testKey) {
                let continuation = manager.removeContinuation(for: testKey)
                #expect(continuation != nil)
                continuation?.resume(throwing: error)
            }
        }
    }

    @Test func continuationWithReturnThrows() async throws {
        let testKey = "testKey"
        struct TestError: Error {}
        let error = TestError()
        let manager = ContinuationManager<String>()

        await #expect(throws: TestError.self) {
            let _: String = try await manager.continuationWithResult(for: testKey) {
                let continuation = manager.removeContinuation(for: testKey, as: String.self)
                #expect(continuation != nil)
                continuation?.resume(throwing: error)
            }
        }
    }

    @Test func hasStream() async throws {
        let testKey = "testKey"
        let manager = ContinuationManager<String>()
        let _: AsyncStream<String> = try manager.stream(for: testKey) { _ in }

        #expect(manager.hasStream(for: testKey))
    }

    @Test func streamYieldAndFinish() async throws {
        let testKey = "testKey"
        let expectedValues = ["one", "two", "three"]
        let manager = ContinuationManager<String>()
        let stream: AsyncStream<String> = try manager.stream(for: testKey) { _ in }

        let task = Task {
            var results: [String] = []
            for await value in stream {
                results.append(value)
            }
            return results
        }

        for value in expectedValues {
            manager.yield(value, for: testKey)
        }
        manager.finish(testKey)

        // Verify order
        for (i, value) in await task.value.enumerated() {
            #expect(value == expectedValues[i])
        }
    }

    @Test func streamWhereYieldAndFinish() async throws {
        let prefix = "testPrefix_"
        let testKey = "\(prefix)key"
        let testKey2 = "\(prefix)key2"
        let wrongKey = "wrongKey"
        let testValue = "test_value"
        let expectedResult = [testValue]
        let manager = ContinuationManager<String>()
        let stream: AsyncStream<String> = try manager.stream(for: testKey) { _ in }
        let stream2: AsyncStream<String> = try manager.stream(for: testKey2) { _ in }
        let stream3: AsyncStream<String> = try manager.stream(for: wrongKey) { _ in }

        manager.yield(testValue) { key in
            key.contains(prefix)
        }

        manager.finish(testKey)
        manager.finish(testKey2)
        manager.finish(wrongKey)

        var results: [String: [String]] = [:]

        for await result in stream {
            results[testKey, default: []].append(result)
        }
        for await result in stream2 {
            results[testKey2, default: []].append(result)
        }
        for await result in stream3 {
            results[wrongKey, default: []].append(result)
        }

        #expect(results[testKey] == expectedResult)
        #expect(results[testKey2] == expectedResult)
        #expect(results[wrongKey] == nil)
    }
}


