import Foundation
import XCTest
@testable import WorkPoolDraining

final class StaticAsyncWorkPoolDrainerTests: XCTestCase {
    // This test do not guarantee that `StaticAsyncWorkPoolDrainerTests` works as expected. Better run few times
    // From other side - if it fails - we have an issue for sure
    func testIntProcessing() async throws {

        let _processIntsArray: Atomic<[Int]> = []

        let drainer = StaticAsyncWorkPoolDrainer<Int, Int>(stack: 0..<1024,
                                                           maxConcurrentOperationCount: 20) { int in
            if Bool.random() {
                try await Task.sleep(nanoseconds: 500)
            }
            _processIntsArray.mutate { `set` in
                `set`.append(int)
            }
            return int
        }

        var resIntsArray = [Int]()
        for try await i in drainer {
            resIntsArray.append(i)
        }

        let processIntsSet = Set(_processIntsArray.wrappedValue)
        let resIntsSet = Set(resIntsArray)

        let ferSet = Set(0..<1024)
        XCTAssertEqual(resIntsSet, ferSet)
        XCTAssertEqual(processIntsSet, ferSet)

        XCTAssertEqual(_processIntsArray.wrappedValue.count, 1024)
        XCTAssertEqual(resIntsSet.count, 1024)
    }

    func testMacConcurrentExecution() async throws {

        let _concurrentlyRunning: Atomic<Int> = 0

        let drainer = StaticAsyncWorkPoolDrainer<Int, Void>(stack: 0..<1024,
                                                            maxConcurrentOperationCount: 5) { int in
            _concurrentlyRunning.increment()
            defer {
                _concurrentlyRunning.decrement()
            }

            XCTAssertTrue(_concurrentlyRunning.wrappedValue <= 5)

            if Bool.random() {
                try await Task.sleep(nanoseconds: 500)
            }

            XCTAssertTrue(_concurrentlyRunning.wrappedValue <= 5)
        }

        try await drainer.wait()
    }
}
