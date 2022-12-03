import XCTest
@testable import WorkPoolDraning

final class AsyncOperationsPoolTests: XCTestCase {

    // This test do not gurantee that `AsyncOperationsPool` works as expected. Better run few times
    // From other side - if it failes - we have an issue for sure
    func testExample() async throws {
        let pool = AsyncOperationsPool<Int>(maxConcurrentOperationCount: 20)
        for i in 0..<1024 {
            pool.add { i }
        }

        var resSet = Set<Int>()
        for try await i in pool {
            if Bool.random() {
                try await Task.sleep(nanoseconds: 500_000)
            }
            resSet.insert(i)
        }

        XCTAssertEqual(resSet, Set(0..<1024))
    }
}