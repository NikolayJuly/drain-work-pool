import Foundation
import XCTest
@testable import WorkPoolDraining

final class DynamicAsyncWorkPoolDrainerTests: XCTestCase {

    // This test do not guarantee that `AsyncOperationsPool` works as expected. Better run few times
    // From other side - if it fails - we have an issue for sure
    func testIntProcessingAndAddWorkDuringDraining() async throws {
        let pool = DynamicAsyncWorkPoolDrainer<Int>(maxConcurrentOperationCount: 20)
        for i in 0..<1024 {
            pool.add {
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
                pool.add { 1024 + i/128 }
            }

            if i == 1024 {
                pool.closeIntake()
            }
        }

        let resSet = Set(resArray)

        let mysteryElements = Set(0...1032).symmetricDifference(resSet)

        XCTAssertTrue(mysteryElements.isEmpty, "We missing some elements in result set. \(mysteryElements.count) elements: \(mysteryElements)")

        XCTAssertEqual(resArray.count, 1033)
    }

    func testAddMoreWorkAfterCompleteInitialDraining() async throws {
        @Atomic var concurrentlyRunning: Int = 0
        
        let pool = DynamicAsyncWorkPoolDrainer<Int>(maxConcurrentOperationCount: 20)
        for i in 0..<1024 {
            pool.add { [_concurrentlyRunning] in
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
                        pool.add { 1024 + i }
                    }
                    pool.closeIntake()
                }
            }
        }

        let resSet = Set(resArray)

        let mysteryElements = Set(0...1031).symmetricDifference(resSet)

        XCTAssertTrue(mysteryElements.isEmpty, "We missing some elements in result set. \(mysteryElements.count) elements: \(mysteryElements)")

        XCTAssertEqual(resArray.count, 1032)
    }

    func test_addMany_SpawnsManySubtasks() async throws {
        let pool = DynamicAsyncWorkPoolDrainer<Int>(maxConcurrentOperationCount: 5)

        let _concurrentlyRunning: Atomic<Int> = 0

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

        pool.addMany(manyWorks)

        let waitFor5Tasks = XCTestExpectation(predicate: { _concurrentlyRunning.wrappedValue == 5 })
        await fulfillment(of: [waitFor5Tasks], timeout: 1)

        for element in waiters {
            await element.0.set(element.1)
        }
    }

    func test_mapSameOrderAsSource() async throws {
        let futures: [AsyncFuture<String>] = (0..<4).map { _ in AsyncFuture<String>() }

        let pool = DynamicAsyncWorkPoolDrainer<String>(maxConcurrentOperationCount: 2, resultsOrder: .keepOriginalOrder)

        let works: [@Sendable () async throws -> String] = futures.map { future in { try await future.value } }
        pool.addMany(works)

        for index in futures.indices.reversed() {
            let future = futures[index]
            await future.fulfil("\(index + 1)")
        }

        pool.closeIntake()

        let result = try await pool.collect()
        XCTAssertEqual(result, ["1", "2", "3", "4"])
    }
}


