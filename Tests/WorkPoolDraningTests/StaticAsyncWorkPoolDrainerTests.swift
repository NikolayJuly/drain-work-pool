import Foundation
import XCTest
@testable import WorkPoolDraning

final class StaticAsyncWorkPoolDrainerTests: XCTestCase {
    // This test do not gurantee that `StaticSyncWorkPoolDrainer` works as expected. Better run few times
    // From other side - if it failes - we have an issue for sure
    func testIntProcessing() async throws {

        @Atomic var processIntsArray = [Int]()

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

        let processIntsSet = Set(processIntsArray)
        let resIntsSet = Set(resIntsArray)

        let ferSet = Set(0..<1024)
        XCTAssertEqual(resIntsSet, ferSet)
        XCTAssertEqual(processIntsSet, ferSet)

        XCTAssertEqual(processIntsArray.count, 1024)
        XCTAssertEqual(resIntsSet.count, 1024)
    }

    func testMacConcurrentExecution() async throws {

        @Atomic var concurrentlyRunning = 0

        let drainer = StaticAsyncWorkPoolDrainer<Int, Void>(stack: 0..<1024,
                                                            maxConcurrentOperationCount: 5) { int in
            _concurrentlyRunning.mutate { counter in
                counter += 1
            }

            XCTAssertTrue(concurrentlyRunning <= 5)

            if Bool.random() {
                try await Task.sleep(nanoseconds: 500)
            }

            XCTAssertTrue(concurrentlyRunning <= 5)
            _concurrentlyRunning.mutate { counter in
                counter -= 1
            }
        }

        try await drainer.wait()
    }
}
