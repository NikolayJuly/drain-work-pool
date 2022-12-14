import DequeModule
import Foundation

/// Drain dynamicly sized pool of work, limiting number of simultanious executions
///
/// In some cases, we need execute many heavy tasks and we want limit number of simultanious executions
/// ``Swift.TaskGroup`` execute all given tasks simultaniously, so it is not suitable for this scenario
///
/// `DynamicAsyncWorkPoolDrainer` allow to add work dynamically. Even if atm it was drained, you still can add more work and iterate later over all resutls.
///  But if one of tasks failed ot draining was cancelled, no new work will be added
///
/// If drain will be cancelled in the middle of process, it will throw `WorkPoolDrainer.cancelled` in iterator
///
/// Usage:
/// ```
/// let pool = DynamicAsyncWorkPoolDrainer<Int>(maxConcurrentOperationCount: 5)
/// for i in 0..<1024 {
///     pool.add { /* soem heavy task */ }
/// }
///
/// for try await i in pool {
///   // process result
/// }
/// ```
///
/// - note: Adding extra work when iteration is almost completed might lead to undefined iterator behaviour. So better to add all work and start iteration after that.
///
/// Order of iteration might be different from order of added work, because each process might take different amount of time and we prefer to provide result ASAP
public final class DynamicAsyncWorkPoolDrainer<T>: AsyncSequence, @unchecked Sendable, ThreadSafeDrainer {

    public typealias Element = T

    public typealias AsyncIterator = AsyncDrainerIterator<Element>

    public init(maxConcurrentOperationCount: Int) {
        precondition(maxConcurrentOperationCount > 0)
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }

    /// Order of execution and order of results is not guaranteed
    public func add(_ work: @Sendable @escaping () async throws -> T) {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        switch state {
        case .completed:
            self.state = .draining
            fallthrough
        case .draining:
            producers.append(work)
        case .failed:
            return
        }

        DispatchQueue.global().async {
            self.checkForAvailableSlot()
        }
    }

    public func cancel() {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }
        self.state = .failed(WorkPoolDrainer.cancelled)
        self.producers.removeAll()
        let waiters = self.updateWaiters
        self.updateWaiters.removeAll()
        DispatchQueue.global().async {
            waiters.forEach { $0(.failure(WorkPoolDrainer.cancelled)) }
        }
    }

    // MARK: AsyncSequence

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncDrainerIterator(self)
    }

    // MARK: ThreadSafeDrainer

    typealias Output = T

    let internalStateLock = PosixLock()

    private(set) var state: DrainerState = .completed

    private(set) var storage = [T]()

    var updateWaiters = [UpdateWaiter<T>]()

    // MARK: Private

    private let maxConcurrentOperationCount: Int

    private var producers = Deque<() async throws -> T>()

    private var currentRunningOperationsCount: Int = 0
    private var preWaitCount: Int = 0

    private func checkForAvailableSlot() {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        switch state {
        case .failed:
            return
        case .completed:
            return
        case .draining:
            break
        }

        guard currentRunningOperationsCount < maxConcurrentOperationCount else {
            return
        }

        guard let producer = producers.popFirst() else {
            if currentRunningOperationsCount == 0 {
                self.state = .completed
                let waiters = self.updateWaiters
                self.updateWaiters.removeAll()
                DispatchQueue.global().async {
                    waiters.forEach { $0(.success(nil)) }
                }
            }
            return
        }

        currentRunningOperationsCount += 1

        Task.detached {
            await self.produce(from: producer)
        }
    }

    private func produce(from producer: () async throws -> T) async {
        let result: Result<T, Error>

        do {
            let t = try await producer()
            result = .success(t)
        } catch let exc {
            result = .failure(exc)
        }

        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        precondition(currentRunningOperationsCount > 0)
        currentRunningOperationsCount -= 1

        switch state {
        case .failed:
            return
        case .completed:
            fatalError("Must never happen at this state")
        case .draining:
            switch result {
            case let .success(t):
                self.storage.append(t)
            case let .failure(error):
                self.state = .failed(error)
                self.producers.removeAll()
            }

            let waiters = self.updateWaiters
            self.updateWaiters.removeAll()

            let optionalResult = result.map { $0 as T? }

            DispatchQueue.global().async {
                waiters.forEach { $0(optionalResult) }
            }

            if case .failure = result {
                return
            }
        }

        DispatchQueue.global().async {
            self.checkForAvailableSlot()
        }
    }
}
