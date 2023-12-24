import Foundation
import XCTest
@testable import WorkPoolDraning

final class StaticSyncWorkPoolDrainerTests: XCTestCase {
    // This test do not guarantee that `StaticSyncWorkPoolDrainer` works as expected. Better run few times
    // From other side - if it fails - we have an issue for sure
    func testIntProcessing() async throws {

        @Atomic var processIntsArray = [Int]()

        let drainer = StaticSyncWorkPoolDrainer<Int, Int>(queuesPoolSize: 20,
                                                          stack: 0..<1024) { int in
            _processIntsArray.mutate { `set` in
                if Bool.random() {
                    usleep(500)
                }
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

        let drainer = StaticSyncWorkPoolDrainer<Int, Void>(queuesPoolSize: 5,
                                                           stack: 0..<1024) { int in
            _concurrentlyRunning.mutate { counter in
                counter += 1
            }

            XCTAssertTrue(concurrentlyRunning <= 5)

            if Bool.random() {
                usleep(500)
            }

            XCTAssertTrue(concurrentlyRunning <= 5)
            _concurrentlyRunning.mutate { counter in
                counter -= 1
            }
        }

        try await drainer.wait()
    }
}
