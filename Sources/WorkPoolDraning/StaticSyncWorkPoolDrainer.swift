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
public final class StaticSyncWorkPoolDrainer<Input, Output>: AsyncSequence, @unchecked Sendable,
                                                             ThreadSafeDrainer, ThreadUnsafeDrainer,  WorkPoolDrainer {

    public typealias AsyncIterator = AsyncDrainerIterator

    public typealias Element = Output

    /// - parameter poolSize: number of queues in pool
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
        self.stack = Array(stack)
        self.queuesPool = queuesPool
        self.process = process
        self.state = .draining
        self.storage.reserveCapacity(stack.count)
        self.drain()
    }

    public func cancel() {
        do {
            internalStateLock.lock()
            defer { internalStateLock.unlock() }
            switch state {
            case .completed, .failed:
                return
            case .draining:
                break
            }
        }
        fail(WorkPoolDrainerError.cancelled)
    }

    // MARK: AsyncSequence

    public func makeAsyncIterator() -> AsyncIterator<Element> {
        AsyncDrainerIterator(self)
    }

    // MARK: ThreadSafeDrainer

    private let internalStateLock = PosixLock()

    func executeBehindLock<T>(_ block: (any ThreadUnsafeDrainer<Output>) throws -> T) rethrows -> T {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        return try block(self)
    }

    // MARK: ThreadUnsafeDrainer

    private(set) var state: DrainerState
    private var storage = [Output]()
    var updateWaiters = [(Result<Output?, Error>) -> Void]()

    subscript(index: Int) -> Output? {
        storage.count > index ? storage[index] : nil
    }

    // MARK: Private

    private enum State {
        case draining
        case completed
        case failed(Error)
    }

    private let queuesPool: [DispatchQueue]
    @Atomic
    private var stack: [Input]


    private let process: (Input) throws -> Output

    private var shouldContinue: Bool {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        switch state {
        case .draining:
            return true
        case .completed,
                .failed:
            return false
        }
    }

    private func drain() {

        let drainStack: (DispatchQueue) -> Void = { queue in
            queue.async {
                self.syncDrain()
            }
        }

        let group = DispatchGroup()

        // just in case, if we reach notify line before hitting any enter
        group.enter()

        for i in 0..<queuesPool.count {
            let queue = queuesPool[i]
            queue.async {
                group.enter()
            }
            drainStack(queue)
            queue.async {
                group.leave()
            }
        }

        // just in case, if we reach notify line before hitting any enter
        queuesPool.last!.async {
            group.leave()
        }

        group.notify(queue: queuesPool.last!) {
            self.complete()
        }
    }

    private func syncDrain() {
        while let nextElement = _stack.mutate( { $0.popFirst() } ) {
            guard shouldContinue else {
                return
            }
            do {
                let output = try process(nextElement)
                insert(output)
            } catch let exc {
                fail(exc)
                break
            }
        }
    }


    /// - parameter result: .success(nil) means draining was completed
    ///                     .success(.wrapped(t)) means we produced new result
    private func updateState(with result: Result<Output?, Error>) {

        let updateWaiters: [(Result<Output?, Error>) -> Void]
        let waiterResult: Result<Output?, Error>
        defer { updateWaiters.forEach { $0(waiterResult) } }

        // Inner defer will be called first, so we will unlock before calling waiters
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        switch (state, result) {
        case let (.draining, .success(value)):
            if let value {
                storage.append(value)
            } else {
                // means we completed
                self.state = .completed
            }
            waiterResult = .success(value)

        case let (.draining, .failure(error)):
            self.state = .failed(error)
            waiterResult = .failure(error)
        case let (.failed(error), _):
            waiterResult = .failure(error)
        case (.completed, _):
            fatalError("We must never call this method after completed")
        }
        updateWaiters = self.updateWaiters
        self.updateWaiters.removeAll()
    }

    private func insert(_ output: Output) {
        updateState(with: .success(output))
    }

    private func fail(_ error: Error) {
        updateState(with: .failure(error))
    }

    private func complete() {
        updateState(with: .success(nil))
    }
}
