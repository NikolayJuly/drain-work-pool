// CollectionExtension.swift

import Foundation

public extension Collection where Element: Sendable {
    /// Process collection and wait for every result.
    ///
    /// `T` does not need to be `Sendable`: each job gives its result away (`sending T`) and the caller owns the returned array.
    /// - Returns: Array of results, order might be different form order in source collection.
    /// - Throws: The first error thrown by `process`. No job starts after it; jobs already running finish,
    ///   and their results, like every result made before the failure, are dropped.
    /// - note: `process` might be called not in order of a collection.
    /// - note: Cancellation of the calling task is not forwarded to jobs: the call throws `CancellationError`
    ///   while it waits for an unfinished job, and jobs keep starting until the collection is drained.
    func process<T>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                    process: @escaping @Sendable (Element) async throws -> sending T) async throws -> sending [T] {
        let storage = SendingResultsStorage<T>()
        let drainer = StaticAsyncWorkPoolDrainer<Element, Void>(stack: self, maxConcurrentOperationCount: maxConcurrentOperationCount) { element in
            let result = try await process(element)
            storage.append(result)
        }

        try await drainer.wait()
        return storage.take()
    }

    /// Process collection.
    /// - Returns: `WorkPoolDrainer<T>`, order might be different form order in source collection.
    /// - note: `process` might be called not in order of a collection.
    func process<T: Sendable>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                              process: @escaping @Sendable (Element) async throws -> T) -> any WorkPoolDrainer<T>  {
        StaticAsyncWorkPoolDrainer(stack: self, maxConcurrentOperationCount: maxConcurrentOperationCount) { element in
            try await process(element)
        }
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

    /// Map source `Collection`. Result array will have corresponding order to source `Collection`'s order.
    /// - note: `process` might be called not in order of a source `AsyncSequence`.
    func map<T: Sendable>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                          process: @escaping @Sendable (Element) async throws -> T) -> any WorkPoolDrainer<T> {
        StaticAsyncWorkPoolDrainer(stack: self, maxConcurrentOperationCount: maxConcurrentOperationCount, resultsOrder: .keepOriginalOrder) { element in
            try await process(element)
        }
    }

    /// Map source `Collection` and wait for every result. Result array will have corresponding order to source `Collection`'s order.
    ///
    /// `T` does not need to be `Sendable`: each job gives its result away (`sending T`) and the caller owns the returned array.
    /// For `Sendable` results it is the same as `map(limitingMaxConcurrentOperationCountTo:process:).collect()`.
    /// - Throws: The first error thrown by `process`. No job starts after it; jobs already running finish,
    ///   and their results, like every result made before the failure, are dropped.
    /// - note: `process` might be called not in order of a source `Collection`.
    /// - note: Cancellation of the calling task is not forwarded to jobs: the call throws `CancellationError`
    ///   while it waits for an unfinished job, and jobs keep starting until the collection is drained.
    func mapAndCollect<T>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                          process: @escaping @Sendable (Element) async throws -> sending T) async throws -> sending [T] {
        let enumerated = Array(self.enumerated())
        let storage = SendingResultsStorage<T>(reservingSlots: enumerated.count)
        let drainer = StaticAsyncWorkPoolDrainer<(offset: Int, element: Element), Void>(stack: enumerated,
                                                                                       maxConcurrentOperationCount: maxConcurrentOperationCount) { pair in
            let result = try await process(pair.element)
            storage.store(result, at: pair.offset)
        }

        try await drainer.wait()
        return storage.take()
    }
}
