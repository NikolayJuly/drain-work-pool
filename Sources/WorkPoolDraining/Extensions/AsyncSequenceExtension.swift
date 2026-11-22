// AsyncSequenceExtension.swift

import Foundation

public extension AsyncSequence where Element: Sendable {
    /// Process items, as they arrive, limiting max concurrent operation count, and wait for every result.
    ///
    /// `T` does not need to be `Sendable`: each job gives its result away (`sending T`) and the caller owns the returned array.
    /// - Returns: Array of results, order might be different form order in source collection.
    /// - Throws: The first error thrown by `process`. No job starts after it; jobs already running finish,
    ///   and their results, like every result made before the failure, are dropped.
    /// - note: `process` might be called not in order of a source `AsyncSequence`.
    /// - note: Cancellation of the calling task is not forwarded to jobs: the call throws `CancellationError`
    ///   while it waits for an unfinished job, and already added jobs keep starting.
    func process<T>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                    process: @escaping @Sendable (Element) async throws -> sending T) async throws -> sending [T] {
        let storage = SendingResultsStorage<T>()
        let poolDrainer = DynamicAsyncWorkPoolDrainer<Void>(maxConcurrentOperationCount: maxConcurrentOperationCount)
        for try await element in self {
            poolDrainer.add {
                let result = try await process(element)
                storage.append(result)
            }
        }

        poolDrainer.closeIntake()
        try await poolDrainer.wait()
        return storage.take()
    }

    /// - note: `process` might be called not in order of a source `AsyncSequence`.
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

    /// Map source `AsyncSequence` and wait for every result. Result array will have corresponding order to source `AsyncSequence`'s order.
    ///
    /// `T` does not need to be `Sendable`: each job gives its result away (`sending T`) and the caller owns the returned array.
    /// - Throws: The first error thrown by `process`. No job starts after it; jobs already running finish,
    ///   and their results, like every result made before the failure, are dropped.
    /// - note: `process` might be called not in order of a source `AsyncSequence`.
    /// - note: Cancellation of the calling task is not forwarded to jobs: the call throws `CancellationError`
    ///   while it waits for an unfinished job, and already added jobs keep starting.
    func map<T>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                process: @escaping @Sendable (Element) async throws -> sending T) async throws -> sending [T] {
        let storage = SendingResultsStorage<T>()
        let poolDrainer = DynamicAsyncWorkPoolDrainer<Void>(maxConcurrentOperationCount: maxConcurrentOperationCount)
        for try await element in self {
            let slot = storage.reserveSlot()
            poolDrainer.add {
                let result = try await process(element)
                storage.store(result, at: slot)
            }
        }

        poolDrainer.closeIntake()
        try await poolDrainer.wait()
        return storage.take()
    }
}

public extension AsyncSequence where Element: Sendable, Self: Sendable {
    /// Process items, as they arrive, limiting max concurrent operation count.
    /// - Returns: Array of results, order might be different form order in source collection.
    /// - note: `process` might be called not in order of a source `AsyncSequence`.
    func process<T: Sendable>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                              process: @escaping @Sendable (Element) async throws -> T) -> any WorkPoolDrainer<T> {
        let poolDrainer = DynamicAsyncWorkPoolDrainer<T>(maxConcurrentOperationCount: maxConcurrentOperationCount)
        Task {
            for try await element in self {
                poolDrainer.add {
                    try await process(element)
                }
            }

            poolDrainer.closeIntake()
        }

        return poolDrainer
    }

    /// Map source `AsyncSequence`. Result array will have corresponding order to source `AsyncSequence`'s order.
    /// - note: `process` might be called not in order of a source `AsyncSequence`.
    func map<T: Sendable>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                          process: @escaping @Sendable (Element) async throws -> T) -> any WorkPoolDrainer<T> {
        let poolDrainer = DynamicAsyncWorkPoolDrainer<T>(maxConcurrentOperationCount: maxConcurrentOperationCount, resultsOrder: .keepOriginalOrder)
        Task {
            for try await element in self {
                poolDrainer.add {
                    try await process(element)
                }
            }

            poolDrainer.closeIntake()
        }

        return poolDrainer
    }
}
