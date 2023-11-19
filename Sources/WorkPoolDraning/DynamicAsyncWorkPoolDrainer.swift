import Foundation

/// Drain dynamicly sized pool of work, limiting number of simultanious executions
///
/// In some cases, we need execute many heavy tasks and we want limit number of simultanious executions
/// `TaskGroup` execute all given tasks simultaniously, so it is not suitable for this scenario
///
/// `DynamicAsyncWorkPoolDrainer` allow to add work dynamically. Even if atm it was drained, you still can add more work and iterate later over all resutls.
///  But if one or tasks failed ot draining was cancelled - no new work will be added
///
/// If drain will be cancelled, it will throw `WorkPoolDrainerError.cancelled` in iterator. This happens even if all current tasks completed
///
/// Usage:
/// ```swift
/// let pool = DynamicAsyncWorkPoolDrainer<Int>(maxConcurrentOperationCount: 5)
/// for i in 0..<1024 {
///     pool.add { /* some heavy task */ }
/// }
/// pool.closeIntake()
///
/// for try await i in pool {
///   // process result
/// }
/// ```
///
/// - note: Order of iteration might be different from order of added work, because each process might take different amount of time and we prefer to provide result ASAP
public final class DynamicAsyncWorkPoolDrainer<T>: AsyncSequence, @unchecked Sendable,
                                                   ThreadSafeDrainer, ThreadUnsafeDrainer, WorkPoolDrainer {

    public typealias Element = T

    public typealias AsyncIterator = AsyncDrainerIterator<Element>

    public init(maxConcurrentOperationCount: Int) {
        precondition(maxConcurrentOperationCount > 0)
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }

    /// Order of execution and order of results are not guaranteed
    public func add(_ work: @Sendable @escaping () async throws -> T) throws {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        switch state {
        case .completed:
            throw WorkPoolDrainerError.poolIntakeAlreadyClosed
        case .draining:
            producers.append(work)
        case .failed:
            return
        }

        Task.detached {
            self.checkForAvailableSlot()
        }
    }

    public func addMany(_ works: [@Sendable () async throws -> T]) throws {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        switch state {
        case .completed:
            throw WorkPoolDrainerError.poolIntakeAlreadyClosed
        case .draining:
            producers.append(contentsOf: works)
        case .failed:
            return
        }

        Task.detached {
            self.checkForAvailableSlot()
        }
    }


    public func closeIntake() {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }
        isSealed = true

        if producers.isEmpty, currentRunningOperationsCount == 0 {
            let waiters = self.updateWaiters
            self.updateWaiters.removeAll()
            Task.detached {
                waiters.forEach { $0(.success(nil)) }
            }
            self.state = .completed
        }
    }

    public func cancel() {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }
        self.state = .failed(WorkPoolDrainerError.cancelled)
        self.producers.removeAll()
        let waiters = self.updateWaiters
        self.updateWaiters.removeAll()
        Task.detached {
            waiters.forEach { $0(.failure(WorkPoolDrainerError.cancelled)) }
        }
    }

    // MARK: AsyncSequence

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncDrainerIterator(self)
    }

    // MARK: ThreadSafeDrainer

    typealias Output = T
    let internalStateLock = PosixLock()

    func executeBehindLock<P>(_ block: (any ThreadUnsafeDrainer<T>) throws -> P) rethrows -> P {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        return try block(self)
    }


    // MARK: ThreadUnsafeDrainer

    private(set) var state: DrainerState = .draining

    private var storage = [T]()

    var updateWaiters = [UpdateWaiter<T>]()

    subscript(index: Int) -> T? {
        storage.count > index ? storage[index] : nil
    }

    // MARK: Private

    private let maxConcurrentOperationCount: Int

    private var producers = [@Sendable () async throws -> T]()

    private var currentRunningOperationsCount: Int = 0

    private var isSealed: Bool = false

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
            if currentRunningOperationsCount == 0, isSealed {
                self.state = .completed
                let waiters = self.updateWaiters
                self.updateWaiters.removeAll()
                Task.detached {
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

            Task.detached {
                waiters.forEach { $0(optionalResult) }
            }

            if case .failure = result {
                return
            }
        }

        Task.detached {
            self.checkForAvailableSlot()
        }
    }
}
