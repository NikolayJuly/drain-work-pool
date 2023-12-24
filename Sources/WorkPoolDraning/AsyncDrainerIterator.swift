import Foundation

enum DrainerState {
    case draining
    case completed
    case failed(Error)
}

typealias UpdateWaiter<Output> = (Result<Output?, Error>) -> Void

protocol ThreadSafeDrainer<Output>: AnyObject {

    associatedtype Output

    /// `ThreadUnsafeDrainer` should not be used outside of block
    func executeBehindLock<T>(_ block: (any ThreadUnsafeDrainer<Output>) throws -> T) rethrows -> T
}

protocol ThreadUnsafeDrainer<Output>: AnyObject {

    associatedtype Output

    /// Should be accesses only behind `internalStateLock`
    var state: DrainerState { get }

    /// Should be accesses only behind `internalStateLock`
    var updateWaiters: [UpdateWaiter<Output>] { get set }

    /// Should be accesses only behind `internalStateLock`
    /// - returns: input at `index`, if element already processes, otherwise returns nil
    subscript(_ index: Int) -> Output? { get }
}

public struct AsyncDrainerIterator<T>: AsyncIteratorProtocol {

    public typealias Element = T

    public mutating func next() async throws -> Element? {

        typealias Touple = (result: Result<Element?, Error>?, continuation: CheckedContinuation<Element?, Error>?)

        @Atomic var tuple: Touple = (nil, nil)

        // It will be called separately from continuation and from drainer update, it will resume continuation when both call happens
        let update: (Result<Element?, Error>?, CheckedContinuation<Element?, Error>?) -> Void = { result, continuation in
            _tuple.mutate { currentTuple in
                currentTuple.result = result ?? currentTuple.result
                currentTuple.continuation = continuation ?? currentTuple.continuation
                guard let result = currentTuple.result,
                      let continuation = currentTuple.continuation else {
                    return
                }
                continuation.resume(with: result)
            }
        }

        let intermediateResult: IntermediateResult = try drainer.executeBehindLock { unsafeDrainer in

            // Increase counter, because we will get value or will stop enumeration after this
            // so when this method will be called again, we will have correct counter
            defer { counter += 1 }

            if let existed = unsafeDrainer[counter] {
                return .element(existed)
            }

            switch unsafeDrainer.state {
            case .completed:
                return .completed
            case let .failed(error):
                throw error
            case .draining:
                break
            }

            unsafeDrainer.updateWaiters.append { result in
                update(result, nil)
            }

            return .waiting
        }

        switch intermediateResult {
        case .completed:
            return nil
        case let .element(element):
            return element
        case .waiting:
            break
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

    private enum IntermediateResult {
        case element(Element)
        case completed
        case waiting
    }
}
