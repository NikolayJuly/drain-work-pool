import Foundation

public enum WorkPoolDrainerError: Error {
    case cancelled
}

public protocol WorkPoolDrainer<Element>: AsyncSequence {

    func cancel()

    func collect() async throws -> [Element]
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
