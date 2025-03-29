//
//  InnerState.swift
//  drain-work-pool
//
//  Created by Nikolay Dzhulay on 28/03/2025.
//

import Swift

enum OrderMode {
    /// In this mode, the iterator returns results in the order in which processor blocks complete, not the order of processors in the array.
    case fifo

    /// In this mode, the iterator will receive elements in the same order as the processors were added to the pool.
    case keepOriginalOrder
}

private enum DrainerState: Sendable {
    case expectingWork
    case sealed(Int) // number of elements
    case failed(Error)
}

enum AvilaibilityLimit {
    case maxConcurrentOperationCount(Int)
    case none
}

final class InnerState<T: Sendable, Work>: @unchecked Sendable, ResultWaiterCollection {
    enum WorkAvailability {
        case work(Work, Int)
        case atCapacity
        case finished

        var work: Work? {
            switch self {
            case let .work(work, _):  work
            case .atCapacity, .finished: nil
            }
        }
    }

    typealias ResultWaiter = ValueWaiter<Result<T?, any Error>>

    let orderMode: OrderMode
    let limit: AvilaibilityLimit

    init(orderMode: OrderMode, limit: AvilaibilityLimit) {
        self.orderMode = orderMode
        self.limit = limit
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
        let waiters = producers.map { _ in ResultWaiter() }
        results.append(contentsOf: waiters.map { .waiting($0) })
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

        executingIndeces.remove(index)
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

        let valueWaiters = results.compactMap { $0.resultWaiter }

        works.removeAll()
        results.removeAll()

        Task {
            for valueWaiter in valueWaiters {
                await valueWaiter.set(.failure(error))
            }
        }
    }

    subscript(index: Int) -> ResultWaiter {
        internalStateLock.lock()
        defer { internalStateLock.unlock() }

        switch state {
        case let .failed(error):
            return ValueWaiter(.failure(error))
        case .expectingWork, .sealed:
            break
        }

        let result = results[index]
        switch result {
        case let .waiting(valueWaiter):
            return valueWaiter
        case let .result(result):
            return ValueWaiter(result)
        }
    }

    // MARK: Private

    private enum ResultType {
        case waiting(ResultWaiter)
        case result(Result<T?, any Error>)

        mutating func setResult(_ result: Result<T?, any Error>) {
            switch self {
            case let .waiting(resultWaiter):
                Task { await resultWaiter.set(result) }
                self = .result(result)
            case .result:
                fatalError("We must not set result twice")
            }
        }

        var resultWaiter: ResultWaiter? {
            switch self {
            case let .waiting(resultWaiter):
                resultWaiter
            case .result:
                nil
            }
        }
    }

    private let internalStateLock = PosixLock()

    private var works: [Work] = []
    private var executingIndeces: Set<Int> = []
    private var state: DrainerState = .expectingWork
    private var nextExecutionIndex: Int = 0

    /// While we iterating,  we might receive subscript for index, which is one more than number of works we received.
    /// This is case when we not sealed yet,  but already iterated over all produced elements.
    /// So we will always have one extra in array
    private var results: [ResultType] = [.waiting(ResultWaiter())]

    func unsafeNextWorkAvailability() -> WorkAvailability {
        switch state {
        case .failed:
            return .finished
        case .expectingWork, .sealed:
            break
        }

        switch limit {
        case let .maxConcurrentOperationCount(limit):
            guard executingIndeces.count < limit else {
                return .atCapacity
            }
            break
        case .none:
            break
        }

        guard let nextWork = works.first else {
            return .finished
        }

        works = Array(works.dropFirst())

        executingIndeces.insert(nextExecutionIndex)

        defer {
            nextExecutionIndex += 1
        }

        return .work(nextWork, nextExecutionIndex)
    }
}
