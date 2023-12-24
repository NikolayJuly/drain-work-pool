import Foundation

extension AsyncSequence {
    /// Process items, as they arrive, limiting max concurrent operation count
    /// - note: `process` might be called not in order of a source sequence
    func process<T>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                    process: @escaping (Element) async throws -> T) async throws -> [T] {
        let poolDrainer = DynamicAsyncWorkPoolDrainer<T>(maxConcurrentOperationCount: maxConcurrentOperationCount)

        for try await element in self {
            // use '?', because I know that it throw only when we already closed intake
            try? poolDrainer.add {
                try await process(element)
            }
        }

        poolDrainer.closeIntake()

        return try await poolDrainer.collect()
    }
}
