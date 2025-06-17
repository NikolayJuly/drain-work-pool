import Swift

private enum DrainerState: Sendable {
    case expectingWork
    case sealed(Int) // number of elements
    case failed(Error)
}

enum AvailabilityLimit {
    case maxConcurrentOperationCount(Int)
    case none
}

// This class will be used in sync and async pools, so I can't make `Work` a closure type and connect T with `Work` return type
final class InnerState<T: Sendable, Work>: @unchecked Sendable, FutureResultCollection {
    enum WorkAvailability: Equatable {
        case work(Work, Int)
        case atCapacity
        case finished

        var work: Work? {
            switch self {
            case let .work(work, _):  work
            case .atCapacity, .finished: nil
            }
        }

        static func == (lhs: WorkAvailability, rhs: WorkAvailability) -> Bool {
            switch (lhs, rhs) {
            case let (.work(_, lhsIndex), .work(_, rhsIndex)):
                lhsIndex == rhsIndex
            case (.atCapacity, .atCapacity), (.finished, .finished):
                true
            default:
                false
            }
        }
    }

    let resultsOrder: OrderMode
    let limit: AvailabilityLimit

    init(resultsOrder: OrderMode, limit: AvailabilityLimit) {
        self.resultsOrder = resultsOrder
        self.limit = limit

        switch resultsOrder {
        case .fifo:
            self.fulfillmentOrder = FifoFulfillmentOrder()
        case .keepOriginalOrder:
            self.fulfillmentOrder = OriginalOrderFulfillmentOrder()
        }
    }

    func addProducers(_ producers: [Work]) {
        guard producers.isEmpty == false else {
            return
        }

        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        switch state {
        case .expectingWork:
            break
        case .sealed:
            fatalError("We must not add more work after intake was closed")
        case .failed:
            // We already failed, no reason to add more work
            return
        }

        works.append(contentsOf: producers)
        let futures: [ResultType] = (0..<producers.count).map { _ in .waiting(FutureResult()) }
        results.append(contentsOf: futures)
    }

    func nextWorkAvailability() -> WorkAvailability {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        return unsafeNextWorkAvailability()
    }

    func workCompleted(for index: Int, result: T) {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        switch state {
        case .expectingWork, .sealed:
            break
        case .failed:
            return
        }

        let index = fulfillmentOrder.resultPosition(forExecutionWithIndex: index)
        results[index].setResult(.success(result))
    }

    func seal() {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        switch state {
        case .expectingWork:
            break
        case .sealed, .failed:
            return
        }

        state = .sealed(results.count - 1)
        results[results.count - 1].setResult(.success(nil))
    }

    func fail(_ error: any Error) {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        switch state {
        case .expectingWork, .sealed:
            break
        case .failed:
            return
        }

        state = .failed(error)

        works.removeAll()

        let futureResults = results.compactMap { $0.waitingFutureResult }
        results.removeAll()

        Task {
            for future in futureResults {
                await future.fulfil(.failure(error))
            }
        }
    }

    subscript(index: Int) -> AsyncFuture<Result<T?, any Error>> {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        switch state {
        case let .failed(error):
            return AsyncFuture(.failure(error))
        case .expectingWork, .sealed:
            break
        }

        return results[index].futureResult
    }

    // MARK: Private

    private let internalStateLock = PosixLock()

    private var works: [Work] = []
    private var state: DrainerState = .expectingWork

    private var fulfillmentOrder: any FulfillmentOrder<T>

    typealias FutureResult = AsyncFuture<Result<T?, any Error>>

    /// While we iterating,  we might receive subscript for index, which is one more than number of works we received.
    /// This is case when we not sealed yet, but already iterated over all produced elements.
    /// So we will always have one extra in array
    private var results: [ResultType<T>] = [.waiting(FutureResult())]

    private func unsafeNextWorkAvailability() -> WorkAvailability {
        switch state {
        case .failed:
            return .finished
        case .expectingWork, .sealed:
            break
        }

        switch limit {
        case let .maxConcurrentOperationCount(limit):
            guard fulfillmentOrder.numberOfExecutions < limit else {
                return .atCapacity
            }
            break
        case .none:
            break
        }

        guard let nextWork = works.popFirst() else {
            return .finished
        }

        let pendingResultIndex = fulfillmentOrder.addExecution()

        return .work(nextWork, pendingResultIndex)
    }
}

private enum ResultType<T: Sendable> {
    case waiting(AsyncFuture<Result<T?, any Error>>)
    case result(Result<T?, any Error>)

    mutating func setResult(_ result: Result<T?, any Error>) {
        switch self {
        case let .waiting(resultWaiter):
            Task { await resultWaiter.fulfil(result) }
            self = .result(result)
        case .result:
            fatalError("We must not set result twice")
        }
    }

    /// - returns: non-nil, only if we still waiting for actual value
    var waitingFutureResult: AsyncFuture<Result<T?, any Error>>? {
        switch self {
        case let .waiting(futureResult):
            futureResult
        case .result:
            nil
        }
    }

    /// - returns: fulfilled future,  if value already known
    var futureResult: AsyncFuture<Result<T?, any Error>> {
        switch self {
        case let .result(result):
            return AsyncFuture(result)
        case let .waiting(future):
            return future
        }
    }
}

private protocol FulfillmentOrder<T> {

    associatedtype T: Sendable

    typealias FutureResult = AsyncFuture<Result<T?, any Error>>

    var numberOfExecutions: Int { get }

    /// - returns: index of added execution
    mutating func addExecution() -> Int

    mutating func resultPosition(forExecutionWithIndex index: Int) -> Int
}

private struct FifoFulfillmentOrder<T: Sendable>: FulfillmentOrder {

    var numberOfExecutions: Int {
        executionRange.count
    }

    mutating func addExecution() -> Int {
        executionRange = executionRange.lowerBound..<(executionRange.upperBound + 1)
        return executionRange.upperBound - 1
    }
    
    mutating func resultPosition(forExecutionWithIndex index: Int) -> Int {
        let res = executionRange.lowerBound
        executionRange = (executionRange.lowerBound + 1)..<executionRange.upperBound
        return res
    }

    // MARK: Private

    private var executionRange: Range<Int> = 0..<0
}

private struct OriginalOrderFulfillmentOrder<T: Sendable>: FulfillmentOrder {

    var numberOfExecutions: Int {
        executingIndices.count
    }

    mutating func addExecution() -> Int {
        let res = nextExecutionIndex
        nextExecutionIndex += 1
        executingIndices.insert(res)
        return res
    }

    mutating func resultPosition(forExecutionWithIndex index: Int) -> Int {
        precondition(executingIndices.contains(index))
        executingIndices.remove(index)
        return index
    }

    // MARK: Private

    private var executingIndices: Set<Int> = []
    private var nextExecutionIndex: Int = 0
}
