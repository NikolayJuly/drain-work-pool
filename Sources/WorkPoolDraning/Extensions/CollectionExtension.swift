import Foundation

public extension Collection {
    /// Process collection.
    /// - note: `process` might be called not in order of a collection.
    func process<T>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                    process: @escaping (Element) async throws -> T) async throws -> [T]  {
        let drainer = StaticAsyncWorkPoolDrainer(stack: self, maxConcurrentOperationCount: maxConcurrentOperationCount) { element in
            try await process(element)
        }

        return try await drainer.collect()
    }

    /// Process collection. Wait till all item processed and after this return.
    /// - note: `process` might be called not in order of a collection.
    func process(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                 process: @escaping (Element) async throws -> Void) async throws  {
        let drainer = StaticAsyncWorkPoolDrainer(stack: self, maxConcurrentOperationCount: maxConcurrentOperationCount) { element in
            try await process(element)
        }

        try await drainer.wait()
    }
}
