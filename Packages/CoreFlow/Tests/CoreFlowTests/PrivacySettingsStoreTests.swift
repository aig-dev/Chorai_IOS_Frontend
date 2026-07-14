import XCTest
@testable import CoreFlow

@MainActor
final class PrivacySettingsStoreTests: XCTestCase {
    func testLoadPublishesCanonicalSettings() async {
        let expected = settings(showEmail: true)
        let service = PrivacySettingsServiceStub(loads: [.init(result: .success(expected))])
        let store = PrivacySettingsStore(service: service)

        await store.load(actorID: " act_a ")

        XCTAssertEqual(store.actorID, "act_a")
        XCTAssertEqual(store.settings, expected)
        XCTAssertEqual(store.phase, .ready)
    }

    func testLoadFailureCanRetry() async {
        let expected = settings(showLocation: true)
        let service = PrivacySettingsServiceStub(loads: [
            .init(result: .failure(.requestFailed(message: "Unavailable"))),
            .init(result: .success(expected))
        ])
        let store = PrivacySettingsStore(service: service)
        await store.load(actorID: "act_a")

        XCTAssertEqual(
            store.phase,
            .failed(.requestFailed(message: "Unavailable"))
        )

        await store.retryLoad()

        XCTAssertEqual(store.settings, expected)
        XCTAssertEqual(store.phase, .ready)
    }

    func testUpdateIsOptimisticSerializedAndCommitsCanonicalResponse() async {
        let initial = settings()
        let canonical = settings(showEmail: true, showPhone: true)
        let service = PrivacySettingsServiceStub(
            loads: [.init(result: .success(initial))],
            updates: [.init(result: .success(canonical), delayNanoseconds: 80_000_000)]
        )
        let store = PrivacySettingsStore(service: service)
        await store.load(actorID: "act_a")

        let first = Task { await store.set(.showEmail, enabled: true) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(store.settings?.showEmail, true)
        XCTAssertEqual(store.savingSetting, .showEmail)

        await store.set(.showPhone, enabled: true)
        await first.value

        XCTAssertEqual(store.settings, canonical)
        XCTAssertNil(store.savingSetting)
        let updateCallCount = await service.updateCallCount()
        XCTAssertEqual(updateCallCount, 1)
    }

    func testUpdateFailureRollsBackExactValueAndRetryCommits() async {
        let initial = settings(showBirthday: false)
        let canonical = settings(showBirthday: true)
        let service = PrivacySettingsServiceStub(
            loads: [.init(result: .success(initial))],
            updates: [
                .init(result: .failure(.requestFailed(message: "Try again"))),
                .init(result: .success(canonical))
            ]
        )
        let store = PrivacySettingsStore(service: service)
        await store.load(actorID: "act_a")

        await store.set(.showBirthday, enabled: true)

        XCTAssertEqual(store.settings, initial)
        XCTAssertEqual(
            store.failedUpdate,
            .init(setting: .showBirthday, enabled: true)
        )
        XCTAssertEqual(store.updateError, .requestFailed(message: "Try again"))

        await store.retryFailedUpdate()

        XCTAssertEqual(store.settings, canonical)
        XCTAssertNil(store.failedUpdate)
        XCTAssertNil(store.updateError)
    }

    func testActorChangeRejectsDelayedPreviousLoad() async {
        let service = PrivacySettingsServiceStub(loads: [
            .init(result: .success(settings(showEmail: true)), delayNanoseconds: 80_000_000),
            .init(result: .success(settings(showPhone: true)))
        ])
        let store = PrivacySettingsStore(service: service)

        let oldLoad = Task { await store.load(actorID: "act_old") }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await store.load(actorID: "act_new")
        await oldLoad.value

        XCTAssertEqual(store.actorID, "act_new")
        XCTAssertEqual(store.settings, settings(showPhone: true))
    }

    func testActorChangeRejectsDelayedPreviousUpdate() async {
        let oldSettings = settings()
        let newSettings = settings(showLocation: true)
        let service = PrivacySettingsServiceStub(
            loads: [
                .init(result: .success(oldSettings)),
                .init(result: .success(newSettings))
            ],
            updates: [
                .init(
                    result: .failure(.requestFailed(message: "Old failure")),
                    delayNanoseconds: 80_000_000
                )
            ]
        )
        let store = PrivacySettingsStore(service: service)
        await store.load(actorID: "act_old")

        let oldUpdate = Task { await store.set(.showEmail, enabled: true) }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await store.load(actorID: "act_new")
        await oldUpdate.value

        XCTAssertEqual(store.actorID, "act_new")
        XCTAssertEqual(store.settings, newSettings)
        XCTAssertNil(store.failedUpdate)
        XCTAssertNil(store.updateError)
    }

    func testInvalidActorFailsWithoutRequest() async {
        let service = PrivacySettingsServiceStub()
        let store = PrivacySettingsStore(service: service)

        await store.load(actorID: "  ")

        XCTAssertEqual(store.phase, .failed(.invalidActor))
        let loadCallCount = await service.loadCallCount()
        XCTAssertEqual(loadCallCount, 0)
    }

    private func settings(
        showEmail: Bool = false,
        showPhone: Bool = false,
        showLocation: Bool = false,
        showBirthday: Bool = false,
        allowFollow: Bool = true,
        showFollowLists: Bool = false
    ) -> PrivacySettings {
        PrivacySettings(
            showEmail: showEmail,
            showPhone: showPhone,
            showLocation: showLocation,
            showBirthday: showBirthday,
            allowFollow: allowFollow,
            showFollowLists: showFollowLists
        )
    }
}

private actor PrivacySettingsServiceStub: CorePrivacySettingsServing {
    struct StubbedResult: Sendable {
        let result: Result<PrivacySettings, PrivacySettingsError>
        let delayNanoseconds: UInt64

        init(
            result: Result<PrivacySettings, PrivacySettingsError>,
            delayNanoseconds: UInt64 = 0
        ) {
            self.result = result
            self.delayNanoseconds = delayNanoseconds
        }
    }

    private var loads: [StubbedResult]
    private var updates: [StubbedResult]
    private var loadCalls = 0
    private var updateCalls = 0

    init(loads: [StubbedResult] = [], updates: [StubbedResult] = []) {
        self.loads = loads
        self.updates = updates
    }

    func privacySettings(actorID: String) async throws -> PrivacySettings {
        loadCalls += 1
        guard !loads.isEmpty else {
            throw PrivacySettingsError.requestFailed(message: nil)
        }
        let value = loads.removeFirst()
        if value.delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: value.delayNanoseconds)
        }
        return try value.result.get()
    }

    func updatePrivacySetting(
        actorID: String,
        setting: PrivacySetting,
        enabled: Bool
    ) async throws -> PrivacySettings {
        updateCalls += 1
        guard !updates.isEmpty else {
            throw PrivacySettingsError.requestFailed(message: nil)
        }
        let value = updates.removeFirst()
        if value.delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: value.delayNanoseconds)
        }
        return try value.result.get()
    }

    func loadCallCount() -> Int { loadCalls }
    func updateCallCount() -> Int { updateCalls }
}
