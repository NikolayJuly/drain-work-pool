import DequeModule
import Foundation

public enum StackDrainerError: Error {
    case cancelled
}

/// Execute havey operations on given stack of items with limit on number of simultanious execution
///
/// Most common usage - run long running file precessing tasks on mac and still comfotably use mac for other tasks
///
/// Usage:
/// ```
/// let drainer = StackDrainer(queuesPoolSize: 5, stack: files)
/// let processedFiles = drainer.drain { file in /* heavy operation on input file */ }
/// for processedFile in processedFiles {
///     // work with processed files
/// }
/// ```
public final class StackDrainer<Element> {

    /// - parameter poolSize: number of queues in pool
    public convenience init(queuesPoolSize: Int,
                            stack: some Collection<Element>) {
        precondition(queuesPoolSize > 0)
        let pool = (0..<queuesPoolSize).map { DispatchQueue(label: "Drainer_\(Element.self)_\($0)") }
        self.init(queuesPool: pool, stack: stack)
    }

    public init(queuesPool: [DispatchQueue],
                stack: some Collection<Element>) {
        precondition(queuesPool.count > 0)
        self.stack = Deque(stack)
        self.queuesPool = queuesPool
    }

    public func drain<T>(process: @escaping (Element) throws -> T) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            self.drain(process: process,
                       continuation: continuation,
                       completion: { _ in })
        }
    }

    public func drain(process: @escaping (Element) throws -> Void) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.drain(process: process) { reason in
                continuation.resume(with: reason)
            }
        }
    }

    /// - parameter completion: will be called on main queue
    public func drain(process: @escaping (Element) throws -> Void,
                      _ completion: @escaping (Result<Void, Error>) -> Void) {
        self.drain(process: process, continuation: nil, completion: completion)
    }


    public func cancel() {
        completionReason = .failure(StackDrainerError.cancelled)
        cancellationToken.cancel()
    }

    // MARK: Private

    private let queuesPool: [DispatchQueue]
    @Atomic
    private var stack: Deque<Element>

    @Atomic
    private var completionReason: Result<Void, Error> = .success(())

    private let cancellationToken = CancellationToken()

    private func drain<T>(process: @escaping (Element) throws -> T,
                          continuation: AsyncThrowingStream<T, Error>.Continuation?,
                          completion: @escaping (Result<Void, Error>) -> Void) {

        continuation?.onTermination = { _ in
            guard self.cancellationToken.isCancelled == false  else {
                return
            }
            self.cancel()
        }

        let drainStack: (DispatchQueue) -> Void = { queue in
            queue.async {
                while let nextElement = self._stack.mutate( { $0.popFirst() } ) {
                    guard self.cancellationToken.isCancelled == false else {
                        break
                    }
                    do {
                        let res = try process(nextElement)
                        continuation?.yield(res)
                    } catch let exc {
                        self.completionReason = .failure(exc)
                        self.cancellationToken.cancel()
                        continuation?.finish(throwing: exc)
                        break
                    }
                }
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

        group.notify(queue: .main) {
            completion(self.completionReason)
            continuation?.finish()
        }
    }
}

private final class CancellationToken {

    @Atomic
    private(set)
    var isCancelled: Bool = false

    init() { }

    func cancel() {
        isCancelled = true

    }
}
