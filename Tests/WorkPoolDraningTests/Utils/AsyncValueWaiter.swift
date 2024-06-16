import Foundation

public actor AsyncValueWaiter<T> {
    public init() {}

    public var value: T {
        get async {
            switch state {
            case .waiting(_, _):
                await withCheckedContinuation { continuation in
                    add(continuation)
                }
            case let .value(value):
                value
            }
        }
    }

    /// Must be called exactly once
    public func set(_ value: T) {
        switch state {
        case let .waiting(continuation, v):
            precondition(v == nil, "set() must be called exactly once")
            self.state = .waiting(continuations: continuation, value: value)
            checkStateSwitch()
        case .value:
            fatalError("set() must be called exactly once")
        }
    }

    // MARK: Private

    private enum State {
        case waiting(continuations: [CheckedContinuation<T, Never>], value: T?)
        case value(T)
    }

    private var state: State = .waiting(continuations: [], value: nil)

    private func checkStateSwitch() {
        guard case let .waiting(continuations, value) = state else {
            fatalError("We smust not arrive here with `.value` state")
        }

        guard let value else {
            return
        }

        continuations.forEach { $0.resume(returning: value) }
        self.state = .value(value)
    }

    private func add(_ continuation: CheckedContinuation<T, Never>) {
        // Extra check, because state might have changed theoretically
        switch state {
        case let .waiting(continuations, value):
            self.state = .waiting(continuations: continuations + [continuation], value: value)
            checkStateSwitch()
        case let .value(value):
            continuation.resume(returning: value)
        }
    }
}
