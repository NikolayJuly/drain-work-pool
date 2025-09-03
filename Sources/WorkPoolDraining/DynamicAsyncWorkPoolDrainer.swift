import Foundation


public enum OrderMode {
    /// In this mode, the iterator returns results in the order in which processor blocks complete, not the order of processors in the array.
    case fifo

    /// In this mode, the iterator will receive elements in the same order as the processors were added to the pool.
    case keepOriginalOrder
}

/// Drain dynamically sized pool of work, limiting number of simultaneous executions
///
/// In some cases, we need execute many heavy tasks and we want limit number of simultaneous executions
/// `TaskGroup` execute all given tasks simultaneously, so it is not suitable for this scenario
///
/// `DynamicAsyncWorkPoolDrainer` allow to add work dynamically. Even if atm it was drained, you still can add more work and iterate later over all resutls.
///  But if at least one task failed, draining was cancelled or intake closed - no new work will be added
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
public final class DynamicAsyncWorkPoolDrainer<T: Sendable>: AsyncSequence, Sendable, WorkPoolDrainer {

    public typealias Work = @Sendable () async throws -> T

    public typealias Element = T

    public typealias AsyncIterator = AsyncDrainerIterator<Element>

    public init(maxConcurrentOperationCount: Int, resultsOrder: OrderMode = .fifo) {
        precondition(maxConcurrentOperationCount > 0)
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
        self.innerState = InnerState(resultsOrder: resultsOrder, limit: .maxConcurrentOperationCount(maxConcurrentOperationCount))
    }

    public func add(_ work: @escaping Work) {
        innerState.addProducers([work])
        Task.detached {
            await self.checkForAvailableSlot()
        }
    }

    public func addMany(_ works: [Work]) {
        innerState.addProducers(works)

        (0..<maxConcurrentOperationCount).forEach { _ in
            Task.detached {
                await self.checkForAvailableSlot()
            }
        }
    }

    public func closeIntake() {
        innerState.seal()
    }

    /// Destructive action, it will prevent any future work and stop all iteration with error.
    /// Any future iteration will fail immediately..
    public func cancel() {
        innerState.fail(WorkPoolDrainerError.cancelled)
    }

    // MARK: AsyncSequence

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncDrainerIterator(innerState)
    }

    // MARK: Private

    private let maxConcurrentOperationCount: Int
    private let innerState: InnerState<T, Work>

    private func checkForAvailableSlot() async {
        let availability = innerState.nextWorkAvailability()
        let work: Work
        let index: Int
        switch availability {
        case .atCapacity, .finished:
            return
        case let .work(w, i):
            work = w
            index = i
        }

        do {
            let t = try await work()
            innerState.workCompleted(for: index, result: t)
        } catch {
            innerState.fail(error)
        }

        Task.detached {
            await self.checkForAvailableSlot()
        }
    }
}

