import Foundation

/// Executed async process block on predefined stack of elements, limiting number of simultaneous executions
///
/// In some cases, we need execute many heavy tasks and we want limit number of simultaneous executions
/// `TaskGroup` execute all given tasks simultaneously, so it is not suitable for this scenario
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
public final class StaticAsyncWorkPoolDrainer<Input: Sendable, Output: Sendable>: AsyncSequence, Sendable, WorkPoolDrainer {

    public typealias Element = Output

    public typealias AsyncIterator = AsyncDrainerIterator<Element>

    public init(stack: some Collection<Input>,
                maxConcurrentOperationCount: Int,
                process: @escaping @Sendable (Input) async throws -> Output) {
        precondition(maxConcurrentOperationCount > 0)
        self.pool = DynamicAsyncWorkPoolDrainer(maxConcurrentOperationCount: maxConcurrentOperationCount)

        let works: [@Sendable () async throws -> Output] = stack.map { element in
            { try await process(element) }
        }

        pool.addMany(works)
        pool.closeIntake()
    }

    public func cancel() {
        pool.cancel()
    }

    // MARK: AsyncSequence

    public func makeAsyncIterator() -> AsyncDrainerIterator<Element> {
        pool.makeAsyncIterator()
    }

    // MARK: Private

    private let pool: DynamicAsyncWorkPoolDrainer<Output>
}

