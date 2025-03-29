import Foundation

protocol ResultWaiterCollection<Output>: AnyObject {
    associatedtype Output

    subscript(_ index: Int) -> ValueWaiter<Result<Output?, any Error>> { get }
}

public struct AsyncDrainerIterator<T: Sendable>: AsyncIteratorProtocol {

    public typealias Element = T

    public mutating func next() async throws -> Element? {
        let valueWaiter = collection[counter]
        counter += 1

        let result = await valueWaiter.value
        return try result.get()
    }

    init(_ collection: any ResultWaiterCollection<Element>) {
        self.collection = collection
    }

    private var counter = 0
    private let collection: any ResultWaiterCollection<Element>
}
