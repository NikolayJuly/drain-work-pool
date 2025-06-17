import Swift

actor AsyncValueWaiter<T: Sendable> {
    init() {}

    init(_ t: T) {
        self.state = .value(t)
    }

    /// - note: This async operation is not cancellable. It means, that it will be kept in memory until value will be set or forever... use `AsyncFuture` if cancellation support is needed
    var value: T {
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
    func set(_ value: T) {
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

