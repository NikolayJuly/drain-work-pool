import Swift

actor AsyncFuture<T: Sendable> {
    init() {}

    init(_ t: T) {
        self.state = .success(t)
    }

    init(_ error: Error) {
        self.state = .failure(error)
    }

    var value: T {
        get async throws {
            switch state {
            case let .success(t):
                return t
            case let .failure(error):
                throw error
            case .pending:
                let currentCounter = pendingCounter
                pendingCounter += 1

                return try await withTaskCancellationHandler(
                    operation: {
                        try await withCheckedThrowingContinuation { continuation in
                            addContinuation(continuation, for: currentCounter)
                        }
                    },
                    onCancel: {
                        Task {
                            await cancelContinuation(for: currentCounter)
                        }
                    }
                )
            }
        }
    }

    func fulfil(_ result: T) {
        guard case let .pending(currentContinuationsMap, _) = state else {
            return
        }

        state = .success(result)

        for continuation in currentContinuationsMap.values {
            continuation.resume(returning: result)
        }
    }

    func fail(_ error: Error) {
        guard case let .pending(currentContinuationsMap, _) = state else {
            return
        }

        state = .failure(error)

        for continuation in currentContinuationsMap.values {
            continuation.resume(throwing: error)
        }
    }

    // MARK: Private

    private enum State {
        case pending([Int: CheckedContinuation<T, Error>], cancelled: Set<Int>)
        case success(T)
        case failure(Error)
    }

    private var state: State = .pending([:], cancelled: [])

    private var pendingCounter: Int = 0

    private func addContinuation(_ continuation: CheckedContinuation<T, Error>, for key: Int) {
        switch state {
        case var .pending(map, cancelled):
            if cancelled.contains(key) {
                continuation.resume(throwing: CancellationError())
                cancelled.remove(key)
            } else {
                map[key] = continuation
            }

            self.state = .pending(map, cancelled: cancelled)
        case let .success(t):
            continuation.resume(returning: t)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    private func cancelContinuation(for key: Int) {
        guard case var .pending(map, cancelled) = state else {
            return
        }

        if let existed = map[key] {
            existed.resume(throwing: CancellationError())
        } else {
            cancelled.insert(key)
        }

        map[key] = nil
        self.state = .pending(map, cancelled: cancelled)
    }
}

