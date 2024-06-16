import Foundation
import XCTest
@testable import WorkPoolDraning

final class DynamicAsyncWorkPoolDrainerTests: XCTestCase {

    // This test do not guarantee that `AsyncOperationsPool` works as expected. Better run few times
    // From other side - if it fails - we have an issue for sure
    func testIntProcessingAndAddWorkDuringDraining() async throws {
        let pool = DynamicAsyncWorkPoolDrainer<Int>(maxConcurrentOperationCount: 20)
        for i in 0..<1024 {
            try pool.add {
                if Bool.random() {
                    try await Task.sleep(nanoseconds: 500)
                }
                return i
            }
        }

        var resArray = [Int]()
        for try await i in pool {
            resArray.append(i)
            if i % 128 == 0 {
                try pool.add { 1024 + i/128 }
            }

            if i == 1024 {
                pool.closeIntake()
            }
        }

        let resSet = Set(resArray)

        let misteryElements = Set(0...1032).symmetricDifference(resSet)

        XCTAssertTrue(misteryElements.isEmpty, "We missing some elements in resuslt set. \(misteryElements.count) elements: \(misteryElements)")

        XCTAssertEqual(resArray.count, 1033)
    }

    func testAddMoreWorkAfterCompleteInitialDraining() async throws {
        @Atomic var concurrentlyRunning: Int = 0
        
        let pool = DynamicAsyncWorkPoolDrainer<Int>(maxConcurrentOperationCount: 20)
        for i in 0..<1024 {
            try pool.add { [_concurrentlyRunning] in
                _concurrentlyRunning.increment()
                defer {
                    _concurrentlyRunning.decrement()
                }

                XCTAssertTrue(_concurrentlyRunning.wrappedValue <= 20)

                if Bool.random() {
                    try await Task.sleep(nanoseconds: 500)
                }

                XCTAssertTrue(_concurrentlyRunning.wrappedValue <= 20)

                return i
            }
        }

        var resArray = [Int]()
        for try await i in pool {
            resArray.append(i)

            if i == 1023 {
                DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(500)) {
                    for i in 0..<8 {
                        try? pool.add { 1024 + i }
                    }
                    pool.closeIntake()
                }
            }
        }

        let resSet = Set(resArray)

        let misteryElements = Set(0...1031).symmetricDifference(resSet)

        XCTAssertTrue(misteryElements.isEmpty, "We missing some elements in resuslt set. \(misteryElements.count) elements: \(misteryElements)")

        XCTAssertEqual(resArray.count, 1032)
    }

    func test_addMany_SpawnsManySubtasks() async throws {
        let pool = DynamicAsyncWorkPoolDrainer<Int>(maxConcurrentOperationCount: 5)

        @Atomic var concurrentlyRunning: Int = 0

        typealias Work = @Sendable () async throws -> Int

        let waiters = (0...10).map {
            (AsyncValueWaiter<Int>(), $0)
        }

        let manyWorks: [Work] = waiters.map { [_concurrentlyRunning] tuple in
                let work: Work = {
                    _concurrentlyRunning.increment()
                    return await tuple.0.value
                }
                return work
            }

        try pool.addMany(manyWorks)

        let waitFor5Tasks = XCTestExpectation(predicate: { _concurrentlyRunning.wrappedValue == 5 })
        await fulfillment(of: [waitFor5Tasks], timeout: 1)

        for element in waiters {
            await element.0.set(element.1)
        }
    }
}


