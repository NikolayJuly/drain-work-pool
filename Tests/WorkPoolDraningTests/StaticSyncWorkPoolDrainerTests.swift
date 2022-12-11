import Foundation
import XCTest
@testable import WorkPoolDraning

final class StaticSyncWorkPoolDrainerTests: XCTestCase {
    // This test do not gurantee that `StaticSyncWorkPoolDrainer` works as expected. Better run few times
    // From other side - if it failes - we have an issue for sure
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
}
