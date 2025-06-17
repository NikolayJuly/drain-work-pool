import Foundation

protocol FutureResultCollection<Output>: AnyObject {
    associatedtype Output

    subscript(_ index: Int) -> AsyncFuture<Result<Output?, any Error>> { get }
}

public struct AsyncDrainerIterator<T: Sendable>: AsyncIteratorProtocol {

    public typealias Element = T

    public mutating func next() async throws -> Element? {
        let asyncFuture = collection[counter]
        counter += 1

        let result = try await asyncFuture.value
        return try result.get()
    }

    init(_ collection: any FutureResultCollection<Element>) {
        self.collection = collection
    }

    private var counter = 0
    private let collection: any FutureResultCollection<Element>
}
