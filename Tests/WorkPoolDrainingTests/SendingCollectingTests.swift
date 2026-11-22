// SendingCollectingTests.swift

import Foundation
import XCTest

@testable import WorkPoolDraining

final class SendingCollectingTests: XCTestCase {

    // MARK: Collection.mapAndCollect

    /// Runs 1024 jobs whose completion order is shuffled, each making a non-Sendable object.
    /// The result must hold 1024 objects in source order (`result[i].value == i`), each a distinct instance.
    func testMapAndCollectKeepsSourceOrderOfNonSendableResults() async throws {
        let made = try await (0..<1024).mapAndCollect(limitingMaxConcurrentOperationCountTo: 20) { int in
            try await Self.randomShortSleep()
            return Made(value: int)
        }

        XCTAssertEqual(made.count, 1024)
        for (index, object) in made.enumerated() {
            XCTAssertEqual(object.value, index)
        }
        let identifiers = Set(made.map { ObjectIdentifier($0) })
        XCTAssertEqual(identifiers.count, 1024)
    }

    /// The caller owns the returned non-Sendable objects: it mutates each one after the call and reads the new value back.
    /// The test itself compiling in Swift 6 mode with no concurrency diagnostic is part of the check.
    func testMapAndCollectCallerOwnsResults() async throws {
        let made = try await (0..<256).mapAndCollect(limitingMaxConcurrentOperationCountTo: 8) { int in
            try await Self.randomShortSleep()
            return Made(value: int)
        }

        for object in made {
            object.value *= 2
        }

        XCTAssertEqual(made.map(\.value), (0..<256).map { $0 * 2 })
    }

    /// Counts jobs in flight. The count must never exceed `maxConcurrentOperationCount` and must reach it at least once.
    func testMapAndCollectRespectsConcurrencyLimit() async throws {
        let limit = 5
        let inFlight: Atomic<Int> = 0
        let peak: Atomic<Int> = 0

        _ = try await (0..<256).mapAndCollect(limitingMaxConcurrentOperationCountTo: limit) { int in
            let current = inFlight.mutate { value in
                value += 1
                return value
            }
            peak.mutate { value in
                value = max(value, current)
            }
            defer {
                inFlight.decrement()
            }

            try await Task.sleep(nanoseconds: 1_000_000)
            return Made(value: int)
        }

        XCTAssertLessThanOrEqual(peak.wrappedValue, limit)
        XCTAssertEqual(peak.wrappedValue, limit)
    }

    /// One job throws. The call must throw that error, and the number of started jobs must stop growing after the call returns.
    func testMapAndCollectFailingJobStopsNewJobs() async throws {
        let started: Atomic<Int> = 0

        do {
            _ = try await (0..<1024).mapAndCollect(limitingMaxConcurrentOperationCountTo: 4) { int in
                started.increment()
                try await Task.sleep(nanoseconds: 1_000_000)
                if int == 50 {
                    throw TestError.failed
                }
                return Made(value: int)
            }
            XCTFail("The call must throw")
        } catch TestError.failed {
            // expected
        }

        // Let jobs taken from the queue right before the failure register themselves.
        try await Task.sleep(nanoseconds: 20_000_000)
        let startedAfterFailure = started.wrappedValue
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(started.wrappedValue, startedAfterFailure)
        XCTAssertLessThan(startedAfterFailure, 1024)
    }

    /// Scenario: the parent task is cancelled while slow jobs run.
    /// The call must throw `CancellationError`. Cancellation is not forwarded to jobs, so they keep starting
    /// until the input is drained; the test pins this current behaviour.
    func testMapAndCollectParentCancellationThrowsCancellationError() async throws {
        let count = 32
        let started: Atomic<Int> = 0

        let task = Task {
            try await (0..<count).mapAndCollect(limitingMaxConcurrentOperationCountTo: 2) { int in
                started.increment()
                try await Task.sleep(nanoseconds: 5_000_000)
                return int
            }
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()

        let result = await task.result
        switch result {
        case .success:
            XCTFail("The call must throw")
        case let .failure(error):
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)")
        }

        let drained = XCTestExpectation(predicate: { started.wrappedValue == count })
        await fulfillment(of: [drained], timeout: 5)
    }

    /// Empty input: the call returns `[]` and never calls `process`.
    func testMapAndCollectEmptyInput() async throws {
        let calls: Atomic<Int> = 0

        let made = try await [Int]().mapAndCollect(limitingMaxConcurrentOperationCountTo: 4) { int in
            calls.increment()
            return Made(value: int)
        }

        XCTAssertTrue(made.isEmpty)
        XCTAssertEqual(calls.wrappedValue, 0)
    }

    // MARK: Collection.process

    /// `Collection.process` with a non-Sendable result: every value comes back (in completion order), and the caller can mutate it.
    func testCollectionProcessReturnsNonSendableResults() async throws {
        let made = try await (0..<1024).process(limitingMaxConcurrentOperationCountTo: 20) { int in
            try await Self.randomShortSleep()
            return Made(value: int)
        }

        XCTAssertEqual(Set(made.map(\.value)), Set(0..<1024))
        XCTAssertEqual(Set(made.map { ObjectIdentifier($0) }).count, 1024)

        for object in made {
            object.value += 1
        }
        XCTAssertEqual(Set(made.map(\.value)), Set(1...1024))
    }

    // MARK: AsyncSequence.process

    /// `AsyncSequence.process` with a non-Sendable result: every value comes back (in completion order), and the caller can mutate it.
    func testAsyncSequenceProcessReturnsNonSendableResults() async throws {
        let made = try await Self.stream(of: 0..<1024).process(limitingMaxConcurrentOperationCountTo: 20) { int in
            try await Self.randomShortSleep()
            return Made(value: int)
        }

        XCTAssertEqual(Set(made.map(\.value)), Set(0..<1024))
        XCTAssertEqual(Set(made.map { ObjectIdentifier($0) }).count, 1024)

        for object in made {
            object.value += 1
        }
        XCTAssertEqual(Set(made.map(\.value)), Set(1...1024))
    }

    // MARK: AsyncSequence.map

    /// `AsyncSequence.map` with a non-Sendable result: values come back in source order, and the caller can mutate them.
    func testAsyncSequenceMapReturnsNonSendableResultsInOrder() async throws {
        let made = try await Self.stream(of: 0..<1024).map(limitingMaxConcurrentOperationCountTo: 20) { int in
            try await Self.randomShortSleep()
            return Made(value: int)
        }

        XCTAssertEqual(made.map(\.value), Array(0..<1024))

        for object in made {
            object.value += 1
        }
        XCTAssertEqual(made.map(\.value), Array(1...1024))
    }

    /// Scenario: the source yields slowly, so slots are reserved while earlier jobs already run and finish.
    /// The result must still follow the source order.
    func testAsyncSequenceMapKeepsOrderWhileSourceStillYields() async throws {
        let source = AsyncStream<Int> { continuation in
            Task {
                for int in 0..<64 {
                    if Bool.random() {
                        try await Task.sleep(nanoseconds: 200_000)
                    }
                    continuation.yield(int)
                }
                continuation.finish()
            }
        }

        let made = try await source.map(limitingMaxConcurrentOperationCountTo: 4) { int in
            try await Self.randomShortSleep()
            return Made(value: int)
        }

        XCTAssertEqual(made.map(\.value), Array(0..<64))
    }

    // MARK: Private

    private enum TestError: Error {
        case failed
    }

    private static func randomShortSleep() async throws {
        if Bool.random() {
            try await Task.sleep(nanoseconds: 500)
        }
    }

    private static func stream(of range: Range<Int>) -> AsyncStream<Int> {
        AsyncStream { continuation in
            for int in range {
                continuation.yield(int)
            }
            continuation.finish()
        }
    }
}

/// Deliberately not `Sendable`: a mutable class, like a texture or any other object with state.
private final class Made {
    var value: Int

    init(value: Int) {
        self.value = value
    }
}
