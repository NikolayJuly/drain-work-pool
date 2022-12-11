import Foundation
import XCTest
@testable import WorkPoolDraning

final class DynamicAsyncWorkPoolDrainerTests: XCTestCase {

    // This test do not gurantee that `AsyncOperationsPool` works as expected. Better run few times
    // From other side - if it failes - we have an issue for sure
    func testIntProcessingAndAddWorkDuringDraining() async throws {
        let pool = DynamicAsyncWorkPoolDrainer<Int>(maxConcurrentOperationCount: 20)
        for i in 0..<1024 {
            pool.add {
                if Bool.random() {
                    try await Task.sleep(nanoseconds: 500_000)
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
        }

        let resSet = Set(resArray)

        let misteryElements = Set(0...1032).symmetricDifference(resSet)

        XCTAssertTrue(misteryElements.isEmpty, "We missing some elements in resuslt set. \(misteryElements.count) elements: \(misteryElements)")

        XCTAssertEqual(resArray.count, 1033)
    }
}


