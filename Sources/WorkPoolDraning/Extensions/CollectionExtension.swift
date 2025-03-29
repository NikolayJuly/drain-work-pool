import Foundation

public extension Collection where Element: Sendable {
    /// Process collection.
    /// - Returns: Array of results, order might be different form order in source collection.
    /// - note: `process` might be called not in order of a collection.
    func process<T: Sendable>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                              process: @escaping @Sendable (Element) async throws -> T) async throws -> [T]  {
        let drainer = StaticAsyncWorkPoolDrainer(stack: self, maxConcurrentOperationCount: maxConcurrentOperationCount) { element in
            try await process(element)
        }

        return try await drainer.collect()
    }

    /// Process collection. Wait till all item processed and after this return.
    /// - note: `process` might be called not in order of a collection.
    func process(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                 process: @escaping @Sendable (Element) async throws -> Void) async throws  {
        let drainer = StaticAsyncWorkPoolDrainer(stack: self, maxConcurrentOperationCount: maxConcurrentOperationCount) { element in
            try await process(element)
        }

        try await drainer.wait()
    }
}
