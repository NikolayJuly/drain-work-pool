import Swift

actor ValueWaiter<T: Sendable> {
    public init() {}

    public init(_ t: T) {
        self.state = .value(t)
    }

    public var value: T {
        get async {
            switch state {
            case .waiting(_):
                await withCheckedContinuation { continuation in
                    add(continuation)
                }
            case let .value(value):
                value
            }
        }
    }

    /// - note: Must be called exactly once
    public func set(_ value: T) {
        switch state {
        case let .waiting(continuations):
            self.state = .value(value)
            continuations.forEach { $0.resume(returning: value) }
        case .value:
            fatalError("set() must be called exactly once")
        }
    }

    // MARK: Private

    private enum State {
        case waiting(continuations: [CheckedContinuation<T, Never>])
        case value(T)
    }

    private var state: State = .waiting(continuations: [])

    private func add(_ continuation: CheckedContinuation<T, Never>) {
        switch state {
        case let .waiting(continuations):
            self.state = .waiting(continuations: continuations + [continuation])
        case let .value(value):
            continuation.resume(returning: value)
        }
    }
}

