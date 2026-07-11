import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class InterestSelectionStoreTests: XCTestCase {
    func testLoadMergesOptionsAndCurrentSelectionInGoOrder() async {
        let service = ScriptedInterestService(
            options: [.success([" Art ", "Technology", "art"])],
            selections: [.success(["ART"])],
            saves: []
        )
        let store = InterestSelectionStore(service: service)

        store.load(actorID: "act_1")
        await waitUntil { store.phase == .ready }

        XCTAssertEqual(store.options.map(\.value), ["Art", "Technology"])
        XCTAssertEqual(store.selectedDomains, ["Art"])
    }

    func testSelectionCapsAtNineAndNextRequiresOne() async {
        let values = (1...10).map { "Domain \($0)" }
        let service = ScriptedInterestService(
            options: [.success(values)],
            selections: [.success([])],
            saves: []
        )
        let store = InterestSelectionStore(service: service)

        store.load(actorID: "act_1")
        await waitUntil { store.phase == .ready }
        XCTAssertFalse(store.canSave)

        values.forEach(store.toggle)

        XCTAssertEqual(store.selectedDomains, Array(values.prefix(9)))
        XCTAssertTrue(store.canSave)
    }

    func testSkipCancelsLoadAndNeverSaves() async {
        let service = ScriptedInterestService(
            optionScripts: [
                .init(delayNanoseconds: 100_000_000, result: .success(["Art"]))
            ],
            selectionScripts: [
                .init(delayNanoseconds: 100_000_000, result: .success([]))
            ],
            saves: []
        )
        let store = InterestSelectionStore(service: service)

        store.load(actorID: "act_1")
        await Task.yield()
        store.skip()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(store.phase, .skipped)
        let saves = await service.savedDomains()
        XCTAssertEqual(saves, [])
    }

    func testSaveFailurePreservesSelectionAndRetryCommitsOnce() async {
        let service = ScriptedInterestService(
            options: [.success(["Art", "Culture"])],
            selections: [.success([])],
            saves: [
                .failure(.transport(code: "offline")),
                .success(["Art"])
            ]
        )
        let store = InterestSelectionStore(service: service)
        store.load(actorID: "act_1")
        await waitUntil { store.phase == .ready }
        store.toggle("Art")

        store.save()
        await waitUntil {
            store.phase == .failed(.save, .transport(code: "offline"))
        }

        XCTAssertEqual(store.selectedDomains, ["Art"])

        store.save()
        await waitUntil { store.phase == .saved }

        let saves = await service.savedDomains()
        XCTAssertEqual(saves, [["Art"], ["Art"]])
    }

    func testNewActorLoadIgnoresOlderActorResponse() async {
        let service = ScriptedInterestService(
            optionScripts: [
                .init(delayNanoseconds: 100_000_000, result: .success(["Old"])),
                .init(delayNanoseconds: 0, result: .success(["New"]))
            ],
            selectionScripts: [
                .init(delayNanoseconds: 100_000_000, result: .success([])),
                .init(delayNanoseconds: 0, result: .success(["New"]))
            ],
            saves: []
        )
        let store = InterestSelectionStore(service: service)

        store.load(actorID: "act_old")
        await Task.yield()
        store.load(actorID: "act_new")
        await waitUntil { store.phase == .ready }
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(store.options.map(\.value), ["New"])
        XCTAssertEqual(store.selectedDomains, ["New"])
    }

    func testInvalidActorFailsWithoutCallingService() async {
        let service = ScriptedInterestService(
            options: [.success(["Art"])],
            selections: [.success([])],
            saves: []
        )
        let store = InterestSelectionStore(service: service)

        store.load(actorID: "  ")

        XCTAssertEqual(store.phase, .failed(.load, .invalidActor))
        let counts = await service.fetchCounts()
        XCTAssertEqual(counts, .init(options: 0, selections: 0))
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(predicate())
    }
}

private actor ScriptedInterestService: CoreInterestSelectionServing {
    struct Script {
        let delayNanoseconds: UInt64
        let result: Result<[String], InterestSelectionError>
    }

    struct FetchCounts: Equatable {
        let options: Int
        let selections: Int
    }

    private var optionScripts: [Script]
    private var selectionScripts: [Script]
    private var saveResults: [Result<[String], InterestSelectionError>]
    private var recordedSaves: [[String]] = []
    private var optionFetchCount = 0
    private var selectionFetchCount = 0

    init(
        options: [Result<[String], InterestSelectionError>],
        selections: [Result<[String], InterestSelectionError>],
        saves: [Result<[String], InterestSelectionError>]
    ) {
        optionScripts = options.map {
            Script(delayNanoseconds: 0, result: $0)
        }
        selectionScripts = selections.map {
            Script(delayNanoseconds: 0, result: $0)
        }
        saveResults = saves
    }

    init(
        optionScripts: [Script],
        selectionScripts: [Script],
        saves: [Result<[String], InterestSelectionError>]
    ) {
        self.optionScripts = optionScripts
        self.selectionScripts = selectionScripts
        saveResults = saves
    }

    func fetchOptions() async throws -> [String] {
        optionFetchCount += 1
        let script = optionScripts.removeFirst()
        return try await Self.run(script)
    }

    func fetchSelection() async throws -> [String] {
        selectionFetchCount += 1
        let script = selectionScripts.removeFirst()
        return try await Self.run(script)
    }

    func save(domains: [String]) async throws -> [String] {
        recordedSaves.append(domains)
        return try saveResults.removeFirst().get()
    }

    func savedDomains() -> [[String]] {
        recordedSaves
    }

    func fetchCounts() -> FetchCounts {
        .init(options: optionFetchCount, selections: selectionFetchCount)
    }

    private static func run(_ script: Script) async throws -> [String] {
        if script.delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: script.delayNanoseconds)
        }
        return try script.result.get()
    }
}
