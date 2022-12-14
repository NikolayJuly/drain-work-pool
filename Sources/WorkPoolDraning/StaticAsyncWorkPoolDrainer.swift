import Foundation

/// Executed async process block on predefined stack of elements, limiting number of simultanious executions
///
/// In some cases, we need execute many heavy tasks and we want limit number of simultanious executions
/// ``Swift.TaskGroup`` execute all given tasks simultaniously, so it is not suitable for this scenario
///
/// If drain will be cancelled in the middle of process, it will throw `WorkPoolDrainer.cancelled` in iterator
///
/// Usage:
/// ```
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
public final class StaticAsyncWorkPoolDrainer<Input, Output>: AsyncSequence, @unchecked Sendable, ThreadSafeDrainer {

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
        pool.cancel()
    }

    // MARK: AsyncSequence

    public func makeAsyncIterator() -> AsyncDrainerIterator<Element> {
        pool.makeAsyncIterator()
    }

    // MARK: ThreadSafeDrainer

    var internalStateLock: PosixLock { pool.internalStateLock }

    var state: DrainerState { pool.state }

    var storage: [Output] { pool.storage }

    var updateWaiters: [UpdateWaiter<Output>] {
        get { pool.updateWaiters }
        set { pool.updateWaiters = newValue }
    }

    // MARK: Private

    private let pool: DynamicAsyncWorkPoolDrainer<Output>
}

