import Foundation
import XCTest
@testable import WorkPoolDraning

final class StaticSyncWorkPoolDrainerTests: XCTestCase {
    // This test do not gurantee that `StaticSyncWorkPoolDrainer` works as expected. Better run few times
    // From other side - if it failes - we have an issue for sure
    func testIntProcessing() async throws {

        @Atomic var processInts = Set<Int>()

        let drainer = StaticSyncWorkPoolDrainer<Int, Int>(queuesPoolSize: 20,
                                                          stack: 0..<1024) { int in
            _processInts.mutate { `set` in
                if Bool.random() {
                    usleep(500)
                }
                `set`.insert(int)
            }
            return int
        }

        var resSet = Set<Int>()
        for try await i in drainer {
            resSet.insert(i)
        }

        let ferSet = Set(0..<1024)
        XCTAssertEqual(resSet, ferSet)
        XCTAssertEqual(processInts, ferSet)
    }
}
