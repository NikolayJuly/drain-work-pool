import Testing
@testable import WorkPoolDraining

struct InnerStateTests {

    @Test("Seal after work done")
    func testSealAfterWorkDone() async throws {
        typealias Work = () async -> Int
        let sut = InnerState<Int, Work>(resultsOrder: .fifo, limit: .none)

        sut.addProducers([{ 42 }])
        let availability = sut.nextWorkAvailability()
        #expect(availability.work != nil)

        sut.workCompleted(for: 0, result: 42)

        let firstElement = try await sut[0].value.get()

        #expect(firstElement == 42)

        sut.seal()

        let endElement = try await sut[1].value.get()

        #expect(endElement == nil)
    }

    @Test("Test concurrency limit in availability")
    func testConcurrentLimit() async throws {
        typealias Work = () async -> Int
        let sut = InnerState<Int, Work>(resultsOrder: .fifo, limit: .maxConcurrentOperationCount(2))

        sut.addProducers([{1}, {2}, {3}, {4}])

        let availability1 = sut.nextWorkAvailability()
        let availability2 = sut.nextWorkAvailability()
        let availability3 = sut.nextWorkAvailability()

        #expect(availability1.work != nil)
        #expect(availability2.work != nil)
        #expect(availability3 == .atCapacity)

        sut.workCompleted(for: 0, result: 1)

        let availability4 = sut.nextWorkAvailability()
        #expect(availability4.work != nil)
    }

    @Test("Test that InnerState keep initial order in .keepOriginalOrder mode")
    func testKeepResultsOrder() async throws {
        typealias Work = () async -> Int
        let sut = InnerState<Int, Work>(resultsOrder: .keepOriginalOrder, limit: .none)

        sut.addProducers([{1}, {2}, {3}, {4}])

        let availabilities = (0..<4).map { _ in sut.nextWorkAvailability() }
        let works = availabilities.compactMap { $0.work }

        #expect(works.count == 4, "No limit, so we should return all works")

        for index in works.indices.reversed() {
            let work = works[index]
            await sut.workCompleted(for: index, result: work())
        }

        let elements = try await (0..<4).asyncMap { try await sut[$0].value.get() }
        #expect(elements == [1, 2, 3, 4])
    }

    @Test("Test that InnerState keep expected order in .fifo mode")
    func testFifoResultsOrder() async throws {
        typealias Work = () async -> Int
        let sut = InnerState<Int, Work>(resultsOrder: .fifo, limit: .none)

        sut.addProducers([{1}, {2}, {3}, {4}])

        let availabilities = (0..<4).map { _ in sut.nextWorkAvailability() }
        let works = availabilities.compactMap { $0.work }

        #expect(works.count == 4, "No limit, so we should return all works")

        for index in works.indices.reversed() {
            let work = works[index]
            await sut.workCompleted(for: index, result: work())
        }

        let elements = try await (0..<4).asyncMap { try await sut[$0].value.get() }
        #expect(elements == [4, 3, 2, 1])
    }

    @Test("Test InnerState fail mid process")
    func testFailInnerProcess() async throws {
        typealias Work = () async -> Int
        let sut = InnerState<Int, Work>(resultsOrder: .fifo, limit: .none)

        sut.addProducers([{1}, {2}, {3}, {4}])

        let availabilities = (0..<4).map { _ in sut.nextWorkAvailability() }
        let works = availabilities.compactMap { $0.work }

        #expect(works.count == 4, "No limit, so we should return all works")

        sut.workCompleted(for: 0, result: 0)
        sut.workCompleted(for: 1, result: 1)

        sut.fail(CancellationError())

        sut.workCompleted(for: 2, result: 2)

        await #expect(throws: CancellationError.self) {
            try await sut[2].value.get()
        }

        await #expect(throws: CancellationError.self) {
            try await sut[0].value.get()
        }
    }
}

