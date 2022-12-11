import Foundation

enum DrainerState {
    case draining
    case completed
    case failed(Error)
}

typealias UpdateWaiter<Output> = (Result<Output?, Error>) -> Void

protocol ThreadSafeDrainer<Output>: AnyObject {

    associatedtype Output

    var internalStateLock: PosixLock { get }

    /// Should be accesses only behind `internalStateLock`
    var state: DrainerState { get }

    /// Should be accesses only behind `internalStateLock`
    var storage: [Output] { get }

    /// Should be accesses only behind `internalStateLock`
    var updateWaiters: [UpdateWaiter<Output>] { get set }
}

public struct AsyncDrainerIterator<T>: AsyncIteratorProtocol {

    public typealias Element = T

    public mutating func next() async throws -> Element? {

        typealias Touple = (result: Result<Element?, Error>?, continuation: CheckedContinuation<Element?, Error>?)

        @Atomic var touple: Touple = (nil, nil)

        let update: (Result<Element?, Error>?, CheckedContinuation<Element?, Error>?) -> Void = { result, continuation in
            _touple.mutate { currentTuple in
                currentTuple.result = result ?? currentTuple.result
                currentTuple.continuation = continuation ?? currentTuple.continuation
                guard let result = currentTuple.result,
                      let continuation = currentTuple.continuation else {
                    return
                }
                continuation.resume(with: result)
            }
        }

        do {
            drainer.internalStateLock.lock()
            defer { drainer.internalStateLock.unlock() }

            if drainer.storage.count > counter {
                defer { counter += 1 }
                return drainer.storage[counter]
            }

            switch drainer.state {
            case .completed:
                return nil
            case let .failed(error):
                throw error
            case .draining:
                break
            }

            // Increase counter, because we will get value or will stop enumeration after this
            // so when this method will be called again, we will have correct counter
            counter += 1

            drainer.updateWaiters.append { result in
                update(result, nil)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            update(nil, continuation)
        }
    }

    init(_ drainer: any ThreadSafeDrainer<Element>) {
        self.drainer = drainer
    }

    private var counter = 0
    private let drainer: any ThreadSafeDrainer<Element>
}
