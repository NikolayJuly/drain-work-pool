import Foundation

public extension AsyncSequence where Element: Sendable {
    /// Process items, as they arrive, limiting max concurrent operation count.
    /// - Returns: Array of results, order might be different form order in source collection.
    /// - note: `process` might be called not in order of a source sequence.
    func process<T: Sendable>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                              process: @escaping @Sendable (Element) async throws -> T) async throws -> [T] {
        let poolDrainer = DynamicAsyncWorkPoolDrainer<T>(maxConcurrentOperationCount: maxConcurrentOperationCount)

        for try await element in self {
            poolDrainer.add {
                try await process(element)
            }
        }

        poolDrainer.closeIntake()

        return try await poolDrainer.collect()
    }

    func process(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                 process: @escaping @Sendable (Element) async throws -> Void) async throws {
        let poolDrainer = DynamicAsyncWorkPoolDrainer<Void>(maxConcurrentOperationCount: maxConcurrentOperationCount)

        for try await element in self {
            poolDrainer.add {
                try await process(element)
            }
        }

        poolDrainer.closeIntake()

        try await poolDrainer.wait()
    }
}
