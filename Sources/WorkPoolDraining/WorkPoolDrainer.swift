import Foundation

public enum WorkPoolDrainerError: Error {
    case cancelled
    case poolIntakeAlreadyClosed
}

public protocol WorkPoolDrainer<Element>: AsyncSequence {
    /// Cancel drain.
    ///
    /// Nothing happens if work pool is static and draining completed.
    ///
    /// In case of dynamic work pool, no new tasks can be added after that and no new tasks will be executer.
    /// Currently running tasks will continue running, but their result will be ignored.
    /// - note: if drainer was stopped, iterators will throw ``WorkPoolDrainerError/cancelled``
    func cancel()
}

public extension WorkPoolDrainer {
    func collect() async throws -> [Element] {
        try await reduce(into: [Element]()) { $0.append($1) }
    }
}

public extension WorkPoolDrainer where Element == Void {
    func wait() async throws {
        _ = try await collect()
    }
}
