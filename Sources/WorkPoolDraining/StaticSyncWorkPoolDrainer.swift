import Dispatch
import Foundation

/// Executed sync process block on predefined stack of elements, limiting number of simultaneous executions
///
/// Execute heavy operations on given stack of items with limit on number of simultaneous execution.
/// Build on DispatchQueue concepts. Limit of simultaneous execution is defined by number of serial queues created inside (or provided in init)
/// This class useful when work on each element can be presented as sync block and amount of work known in advance
///
/// If drain will be cancelled in the middle of process, it will throw `WorkPoolDrainerError.cancelled` in iterator
///
/// Usage:
/// ```swift
/// let drainer = StaticSyncWorkPoolDrainer(queuesPoolSize: 5, stack: files) { file in
///     // heavy operation on input file
/// }
///
/// for try await processedFile in drainer {
///     // post-processing
/// }
/// ```
///
/// - note: Order of iteration might be different from order of input stack, because each process might take different amount of time and we prefer to provide result ASAP
public final class StaticSyncWorkPoolDrainer<Input, Output>: AsyncSequence, Sendable,
                                                             WorkPoolDrainer where Input: Sendable, Output: Sendable {
    typealias ProcessBlock = () throws -> Output

    public typealias AsyncIterator = AsyncDrainerIterator

    public typealias Element = Output

    /// - parameter queuesPoolSize: number of queues in pool
    public convenience init(queuesPoolSize: Int,
                            stack: some Collection<Input>,
                            qos: DispatchQoS = .unspecified,
                            autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency = .inherit,
                            process: @escaping (Input) throws -> Output) {
        precondition(queuesPoolSize > 0)
        let pool = (0..<queuesPoolSize).map { DispatchQueue(label: "Drainer_\(Element.self)_\($0)") }
        self.init(queuesPool: pool, stack: stack, process: process)
    }

    /// - parameter queuesPool: array of serial queues
    public init(queuesPool: [DispatchQueue],
                stack: some Collection<Input>,
                process: @escaping (Input) throws -> Output) {
        precondition(queuesPool.count > 0)
        self.innerState = InnerState(resultsOrder: .fifo, limit: .none)
        let producers: [() throws -> Output] = stack.map { item in
            let block: () throws -> Output = { try process(item) }
            return block
        }
        innerState.addProducers(producers)
        innerState.seal()
        self.queuesPool = queuesPool
        self.drain()
    }

    public func cancel() {
        innerState.fail(WorkPoolDrainerError.cancelled)
    }

    // MARK: AsyncSequence

    public func makeAsyncIterator() -> AsyncIterator<Element> {
        AsyncDrainerIterator(innerState)
    }

    // MARK: Private

    private let queuesPool: [DispatchQueue]

    private let innerState: InnerState<Output, ProcessBlock>

    private func drain() {
        for queue in queuesPool {
            queue.async {
                self.syncDrain()
            }
        }
    }

    private func syncDrain() {
        while true {
            let work = innerState.nextWorkAvailability()

            guard case let .work(block, index) = work else {
                break
            }

            do {
                let output = try block()
                innerState.workCompleted(for: index, result: output)
            } catch {
                innerState.fail(error)
                break
            }
        }
    }
}
