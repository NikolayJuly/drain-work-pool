import Foundation

/// Executed async process block on predefined stack of elements, limiting number of simultanious executions
///
/// In some cases, we need execute many heavy tasks and we want limit number of simultanious executions
/// `TaskGroup` execute all given tasks simultaniously, so it is not suitable for this scenario
///
/// If drain will be cancelled in the middle of process, it will throw `WorkPoolDrainerError.cancelled` in iterator
///
/// Usage:
/// ```swift
/// let drainer = StaticAsyncWorkPoolDrainer(stack: files, maxConcurrentOperationCount: 5) { file in
///     // heavy operation on input file
/// }
///
/// for try await processedFile in drainer {
///     // post-processing
/// }
/// ```
///
/// - note: Order of iteration might be different from order of input stack, because each process might take different amount of time and we prefer to provide result ASAP
public final class StaticAsyncWorkPoolDrainer<Input, Output>: AsyncSequence, @unchecked Sendable, WorkPoolDrainer {

    public typealias Element = Output

    public typealias AsyncIterator = AsyncDrainerIterator<Element>

    public init(stack: some Collection<Input>,
                maxConcurrentOperationCount: Int,
                process: @escaping (Input) async throws -> Output) {
        precondition(maxConcurrentOperationCount > 0)
        self.pool = DynamicAsyncWorkPoolDrainer(maxConcurrentOperationCount: maxConcurrentOperationCount)
        for element in stack {
            pool.add {
                try await process(element)
            }
        }
    }

    public func cancel() {
        pool.internalStateLock.lock()
        defer { pool.internalStateLock.unlock() }
        switch pool.state {
        case .completed, .failed:
            return
        case .draining:
            break
        }
        pool.cancel()
    }

    // MARK: AsyncSequence

    public func makeAsyncIterator() -> AsyncDrainerIterator<Element> {
        pool.makeAsyncIterator()
    }

    // MARK: Private

    private let pool: DynamicAsyncWorkPoolDrainer<Output>
}

