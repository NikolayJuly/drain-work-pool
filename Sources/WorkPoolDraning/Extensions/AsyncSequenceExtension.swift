import AnyAsyncSequence
import Foundation

public extension AsyncSequence {
    /// Process items, as they arrive, limiting max concurrent operation count.
    /// - Returns: AsyncSequence<T>, order might be different form order in source collection.
    /// - note: `process` might be called not in order of a source sequence.
    func process<T>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                    process: @escaping (Element) async throws -> T) async throws -> AnyAsyncSequence<T> {
        let poolDrainer = try await _process(
            limitingMaxConcurrentOperationCountTo: maxConcurrentOperationCount,
            process: process
        )

        return AnyAsyncSequence(poolDrainer)
    }

    /// Process items, as they arrive, limiting max concurrent operation count.
    /// - Returns: Array of results, order might be different form order in source collection.
    /// - note: `process` might be called not in order of a source sequence.
    func process<T>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                    process: @escaping (Element) async throws -> T) async throws -> [T] {
        let poolDrainer = try await _process(
            limitingMaxConcurrentOperationCountTo: maxConcurrentOperationCount,
            process: process
        )

        return try await poolDrainer.collect()
    }

    func process(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                 process: @escaping (Element) async throws -> Void) async throws {
        let poolDrainer = DynamicAsyncWorkPoolDrainer<Void>(maxConcurrentOperationCount: maxConcurrentOperationCount)

        for try await element in self {
            // use '?', because I know that it throw only when we already closed intake
            try? poolDrainer.add {
                try await process(element)
            }
        }

        poolDrainer.closeIntake()

        try await poolDrainer.wait()
    }

    private func _process<T>(limitingMaxConcurrentOperationCountTo maxConcurrentOperationCount: Int,
                             process: @escaping (Element) async throws -> T) async throws -> any WorkPoolDrainer<T> {
        let poolDrainer = DynamicAsyncWorkPoolDrainer<T>(maxConcurrentOperationCount: maxConcurrentOperationCount)

        for try await element in self {
            // use '?', because I know that it throw only when we already closed intake
            try? poolDrainer.add {
                try await process(element)
            }
        }

        poolDrainer.closeIntake()

        return poolDrainer
    }
}
