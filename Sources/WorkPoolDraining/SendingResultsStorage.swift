// SendingResultsStorage.swift

import Foundation

/// Collects results of concurrent jobs and hands them out as `sending [T]`, so `T` does not need to be `Sendable`.
/// Ordered mode: ``reserveSlot()`` + ``store(_:at:)``. Fifo mode: ``append(_:)``.
final class SendingResultsStorage<T>: Sendable {

    init(reservingSlots count: Int = 0) {
        self.state = Atomic(State(slots: Array(repeating: nil, count: count)))
    }

    /// - returns: index of a new empty slot. Called by the single producer before it adds the job.
    func reserveSlot() -> Int {
        state.mutate { state in
            state.slots.append(nil)
            return state.slots.count - 1
        }
    }

    func store(_ value: sending T, at index: Int) {
        state.mutate { state in
            precondition(state.isTaken == false, "Results were already taken")
            precondition(state.slots[index] == nil, "Slot \(index) was written twice")
            state.slots[index] = value
        }
    }

    func append(_ value: sending T) {
        state.mutate { state in
            precondition(state.isTaken == false, "Results were already taken")
            state.slots.append(value)
        }
    }

    /// Call once, after every job finished: no job keeps a reference to a stored value, so the array can be sent.
    func take() -> sending [T] {
        state.mutate { state in
            precondition(state.isTaken == false, "Results were already taken")
            state.isTaken = true

            var slots: [T?] = []
            swap(&slots, &state.slots)
            return slots.map { slot in
                guard let slot else {
                    preconditionFailure("A slot was not written before `take()`")
                }
                return slot
            }
        }
    }

    // MARK: Private

    private struct State {
        var slots: [T?]
        var isTaken = false
    }

    private let state: Atomic<State>
}
