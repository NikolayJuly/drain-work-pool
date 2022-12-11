import DequeModule
import Foundation

/// Limit number of simultaneously executed works tasks from given pool
///
/// In some cases, we need execute many heavy tests and ideally device should be responsive during this time
/// ``Swift.TaskGroup`` execute all given tasks simultaniously, so might be not sutable
/// Most common usage - run long running file precessing tasks on mac and still comfotably use mac for other tasks
///
/// Usage:
/// ```
/// let pool = AsyncOperationsPool<Int>(maxConcurrentOperationCount: 5)
/// for i in 0..<1024 {
///     pool.add { /* soem heavy task */ }
/// }
///
/// for try await i in pool {
///   // process result
/// }
/// ```
///
/// Make sure to add some work before iterating over it
public final class AsyncOperationsPool<T>: AsyncSequence, @unchecked Sendable {

    public typealias Element = T

    public struct AsyncIterator: AsyncIteratorProtocol {

        public typealias Element = T

        fileprivate init(pool: AsyncOperationsPool<T>) {
            self.pool = pool
        }

        public mutating func next() async throws -> T? {
            if let error = pool.firstError {
                throw error
            }

            pool.lock.lock()

            // I can't do `defer { pool.lock.unlock() }`, because of `await` below
            // So we should be carefull and unlock on every return/throw

            if pool.results.count > index {
                let t = pool.results[index]
                pool.lock.unlock()
                index += 1
                return t
            }

            // Make sure that pool still have work to do
            guard pool.workWaiters.isEmpty == false || pool.preWaitCount > 0 || pool.currentRunningOperationsCount > 0 else {
                pool.lock.unlock()
                return nil
            }

            // In this case `unlock` might be called with some delay, but there is no better way, as we need `continuation` before unlocking
            return try await withCheckedThrowingContinuation { continuation in
                pool.resultsWaiters.append { result in
                    let optionalResult = result.map { $0 as T? }
                    continuation.resume(with: optionalResult)
                }
                pool.lock.unlock()
            }
        }

        private let pool: AsyncOperationsPool<T>
        private var index: Int = 0
    }

    public init(maxConcurrentOperationCount: Int) {
        precondition(maxConcurrentOperationCount > 0)
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }

    /// Order of execution and order of results is not guaranteed
    public func add(_ work: @Sendable @escaping () async throws -> T) {
        lock.lock()
        preWaitCount += 1
        lock.unlock()
        Task.detached {
            await self.execute(work)
        }
    }

    // MARK: AsyncSequence

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(pool: self)
    }

    // MARK: Private

    private let maxConcurrentOperationCount: Int

    @Atomic
    private var firstError: Error?

    /// We will lock aroun all internal states. We can't make `AsyncOperationsPool`, otherwise it can't be `AsyncSequence`
    private let lock = PosixLock()

    private var results = [T]()
    private var resultsWaiters = [(Result<T, Error>) -> Void]()

    private var workWaiters = Deque<() -> Void>()
    private var currentRunningOperationsCount: Int = 0
    private var preWaitCount: Int = 0

    private func wait() async {
        await withCheckedContinuation { continuation in
            self.wait {
                continuation.resume()
            }
        }
    }

    private func wait(_ completion: @escaping () -> Void) {
        lock.lock()
        workWaiters.append(completion)
        precondition(preWaitCount > 0)
        preWaitCount -= 1
        lock.unlock()
        checkForAvailableSlot()
    }

    private func checkForAvailableSlot() {
        lock.lock()

        // Can't use `defer { lock.unlock() }`, because of waiter in the end
        // So we should be carefull and unlock on every return/throw

        guard currentRunningOperationsCount < maxConcurrentOperationCount else {
            lock.unlock()
            return
        }

        guard let waiter = workWaiters.popFirst() else {
            lock.unlock()
            return
        }

        currentRunningOperationsCount += 1
        lock.unlock()
        waiter()
    }

    private func didCompleteWork<T>(_ executeInsideLock: () -> T) -> T {
        lock.lock()
        precondition(currentRunningOperationsCount > 0)
        currentRunningOperationsCount -= 1
        let res = executeInsideLock()
        lock.unlock()
        checkForAvailableSlot()
        return res
    }

    private func execute(_ work: @Sendable @escaping () async throws -> T) async {
        guard firstError == nil else {
            return
        }

        await wait()

        guard firstError == nil else {
            didCompleteWork({})
            return
        }

        let result: Result<T, Error>

        do {
            let t = try await work()
            result = .success(t)
        } catch let exc {
            firstError = exc
            result = .failure(exc)

        }

        let waiters = didCompleteWork {
            if let t = try? result.get() {
                results.append(t)
            }
            let res = resultsWaiters
            resultsWaiters = []
            return res

        }
        waiters.forEach { $0(result) }
    }
}
