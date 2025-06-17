import Testing
@testable import WorkPoolDraining

struct AsyncFutureTests {

    @Test("Happy path")
    func happyPath() async throws {
        let future = AsyncFuture<Int>()

        // Simulate a producer that completes after a short delay
        Task.detached {
            await future.fulfil(42)
        }

        let result = try await future.value
        #expect(result == 42)
    }

    @Test("Cancellation")
    func cancellation() async throws {
        let future = AsyncFuture<Int>()

        let waiting = Task<Int, Error> {
            try await future.value
        }
        waiting.cancel()

        do {
            _ = try await waiting.value
            #expect(Bool(false), "Expected CancellationError to be thrown")
        } catch is CancellationError {
            #expect(true)
        } catch {
            #expect(Bool(false), "Wrong type of error. We got \(error)")
        }
    }

    @Test("Cancellation after fulfil")
    func cancellationAfterFulfil() async throws {
        let future = AsyncFuture<Int>()

        let waiting = Task<Int, Error> {
            try await future.value
        }

        await future.fulfil(42)
        _ = try await future.value
        waiting.cancel()

        let result = try await waiting.value
        #expect(result == 42)
    }
}
