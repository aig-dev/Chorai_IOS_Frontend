import Combine
import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class ChoraProfileStoreTests: XCTestCase {
    func testGrowthRawValuesAreLosslessAndKnownValuesAreComputed() throws {
        let stages = try JSONDecoder().decode(
            [ChoraGrowthStage].self,
            from: Data("[0,1,2,3,4,5,99]".utf8)
        )
        XCTAssertEqual(
            stages.map(\.knownValue),
            [.initial, .trace, .thread, .weave, .coThink, .secondVoice, nil]
        )
        XCTAssertEqual(stages.last?.rawValue, 99)

        let unknown = try JSONDecoder().decode(
            ChoraGrowthDimension.self,
            from: Data(#""future-sense""#.utf8)
        )
        XCTAssertEqual(unknown.rawValue, "future-sense")
        XCTAssertNil(unknown.knownValue)
        XCTAssertEqual(
            ChoraGrowthDimension.canonicalRenderOrder,
            [.curiosity, .insight, .creativity, .empathy, .judgment, .resonance]
        )
    }

    func testCanonicalGrowthRenderingRequiresKnownFiniteZeroThroughTwelveValues() {
        let snapshot = ChoraGrowthSnapshot.fixture(
            stage: .init(rawValue: 88),
            dimensions: [
                .init(dimension: .resonance, value: 12),
                .init(dimension: .curiosity, value: 0),
                .init(dimension: .insight, value: 12.01),
                .init(dimension: .creativity, value: -.infinity),
                .init(dimension: .empathy, value: .nan),
                .init(dimension: .judgment, value: -0.01),
                .init(dimension: .init(rawValue: "future-sense"), value: 7)
            ]
        )

        XCTAssertNil(snapshot.committedStage.displayName)
        XCTAssertEqual(
            snapshot.canonicalDisplayValues,
            [
                .init(dimension: .curiosity, value: 0),
                .init(dimension: .resonance, value: 12)
            ]
        )
        XCTAssertNil(snapshot.dimensions[2].displayValue)
        XCTAssertNil(snapshot.dimensions[3].displayValue)
        XCTAssertNil(snapshot.dimensions[4].displayValue)
        XCTAssertNil(snapshot.dimensions[5].displayValue)
        XCTAssertNil(snapshot.dimensions[6].displayValue)
    }

    func testIdentityMustMatchRequestedHumanAndUseDistinctNonblankAgent() async {
        let cases: [(ChoraIdentity, ChoraProfileError)] = [
            (.fixture(humanActorID: "act_other"), .humanActorMismatch),
            (.fixture(agentActorID: "  "), .missingAgentActor),
            (
                .fixture(agentActorID: "act_human"),
                .humanActorUsedAsAgent
            ),
            (
                .fixture(agentActorID: " act_human "),
                .humanActorUsedAsAgent
            )
        ]

        for (identity, expectedError) in cases {
            let service = ChoraProfileServiceSpy(
                identities: [.init(result: .success(identity))]
            )
            let store = ChoraProfileStore(service: service)

            await store.load(humanActorID: "act_human")

            XCTAssertNil(store.identity)
            XCTAssertEqual(store.phase, .failed(expectedError))
            let growthRequests = await service.growthRequests()
            XCTAssertTrue(growthRequests.isEmpty)
        }
    }

    func testInvalidHumanActorClearsPreviouslyPublishedIdentityAndGrowth() async {
        let service = ChoraProfileServiceSpy(
            identities: [.init(result: .success(.fixture()))],
            growth: [.init(result: .success(.fixture()))]
        )
        let store = ChoraProfileStore(service: service)
        await store.load(humanActorID: "act_human")
        await waitUntil { store.growth != nil }

        await store.load(humanActorID: "  ")

        XCTAssertNil(store.identity)
        XCTAssertNil(store.growth)
        XCTAssertEqual(store.phase, .failed(.invalidHumanActor))
        XCTAssertEqual(store.growthPhase, .idle)
        XCTAssertEqual(store.changedFields, [])
    }

    func testLoadPublishesIdentityBeforeDelayedGrowth() async {
        let service = ChoraProfileServiceSpy(
            identities: [.init(result: .success(.fixture()))],
            growth: [.init(delay: 150_000_000, result: .success(.fixture()))]
        )
        let store = ChoraProfileStore(service: service)

        await store.load(humanActorID: "act_human")

        XCTAssertEqual(store.identity, .fixture())
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.growthPhase, .loading)
        XCTAssertNil(store.growth)
        await waitUntil { store.growth != nil }
        XCTAssertEqual(store.growthPhase, .ready)
        let growthRequests = await service.growthRequests()
        XCTAssertEqual(growthRequests, ["act_chora"])
    }

    func testGrowthFailureLeavesIdentityUsable() async {
        let service = ChoraProfileServiceSpy(
            identities: [.init(result: .success(.fixture()))],
            growth: [.init(result: .failure(.failed))]
        )
        let store = ChoraProfileStore(service: service)

        await store.load(humanActorID: "act_human")
        await waitUntil {
            store.growthPhase == .unavailable(
                .requestFailed(.requestFailed)
            )
        }

        XCTAssertEqual(store.identity, .fixture())
        XCTAssertEqual(store.phase, .ready)
        XCTAssertNil(store.growth)
    }

    func testNilGrowthIsUnavailableWithoutRequestFailure() async {
        let service = ChoraProfileServiceSpy(
            identities: [.init(result: .success(.fixture()))],
            growth: [.init(result: .success(nil))]
        )
        let store = ChoraProfileStore(service: service)

        await store.load(humanActorID: "act_human")
        await waitUntil {
            store.growthPhase == .unavailable(.noSnapshot)
        }

        XCTAssertEqual(store.identity, .fixture())
        XCTAssertNil(store.growth)
    }

    func testSuspendedGrowthDoesNotRetainStoreAndCancelsOnTeardown() async {
        let service = SuspendedGrowthService()
        var store: ChoraProfileStore? = ChoraProfileStore(service: service)
        weak let weakStore = store
        await store?.load(humanActorID: "act_human")
        while !(await service.didStartGrowth()) { await Task.yield() }

        store = nil
        await Task.yield()
        let releasedWhileSuspended = weakStore == nil
        if !releasedWhileSuspended {
            await service.finishGrowth()
            while weakStore != nil { await Task.yield() }
        }

        XCTAssertTrue(releasedWhileSuspended)
        if releasedWhileSuspended {
            while await service.cancellationCount() == 0 {
                await Task.yield()
            }
            let cancellationCount = await service.cancellationCount()
            XCTAssertEqual(cancellationCount, 1)
        }
    }

    func testActorAndGenerationChangesRejectStaleIdentityCompletions() async {
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(
                    delay: 150_000_000,
                    result: .success(.fixture(
                        humanActorID: "act_old",
                        agentActorID: "agent_old"
                    ))
                ),
                .init(result: .success(.fixture(
                    humanActorID: "act_new",
                    agentActorID: "agent_new"
                ))),
                .init(
                    delay: 150_000_000,
                    result: .success(.fixture(displayName: "stale"))
                ),
                .init(result: .success(.fixture(displayName: "fresh")))
            ],
            growth: [
                .init(result: .success(nil)),
                .init(result: .success(nil))
            ]
        )
        let store = ChoraProfileStore(service: service)

        let oldActorLoad = Task { await store.load(humanActorID: "act_old") }
        await Task.yield()
        await store.load(humanActorID: "act_new")
        await oldActorLoad.value
        XCTAssertEqual(store.identity?.humanActorID, "act_new")

        let staleGeneration = Task { await store.load(humanActorID: "act_human") }
        await Task.yield()
        await store.load(humanActorID: "act_human")
        await staleGeneration.value
        XCTAssertEqual(store.identity?.displayName, "fresh")
    }

    func testPriorAgentGrowthCompletionNeverPublishesIntoNewIdentity() async {
        let oldGrowth = ChoraGrowthSnapshot.fixture(version: "old")
        let freshGrowth = ChoraGrowthSnapshot.fixture(version: "fresh")
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(result: .success(.fixture(agentActorID: "agent_old"))),
                .init(result: .success(.fixture(agentActorID: "agent_new")))
            ],
            growth: [
                .init(delay: 160_000_000, result: .success(oldGrowth)),
                .init(result: .success(freshGrowth))
            ]
        )
        let store = ChoraProfileStore(service: service)

        await store.load(humanActorID: "act_human")
        await store.load(humanActorID: "act_human")
        await waitUntil { store.growth?.version == "fresh" }
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(store.identity?.agentActorID, "agent_new")
        XCTAssertEqual(store.growth?.version, "fresh")
    }

    func testPriorActorGrowthCompletionNeverPublishesForSharedAgentID() async {
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(result: .success(.fixture(
                    humanActorID: "act_old",
                    agentActorID: "agent_shared"
                ))),
                .init(result: .success(.fixture(
                    humanActorID: "act_new",
                    agentActorID: "agent_shared"
                )))
            ],
            growth: [
                .init(
                    delay: 160_000_000,
                    result: .success(.fixture(version: "old-actor"))
                ),
                .init(result: .success(.fixture(version: "new-actor")))
            ]
        )
        let store = ChoraProfileStore(service: service)

        await store.load(humanActorID: "act_old")
        await store.load(humanActorID: "act_new")
        await waitUntil { store.growth?.version == "new-actor" }
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(store.identity?.humanActorID, "act_new")
        XCTAssertEqual(store.growth?.version, "new-actor")
    }

    func testPriorGenerationGrowthCompletionNeverPublishesForSameIdentity() async {
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(result: .success(.fixture())),
                .init(result: .success(.fixture()))
            ],
            growth: [
                .init(
                    delay: 160_000_000,
                    result: .success(.fixture(version: "old-generation"))
                ),
                .init(result: .success(.fixture(version: "new-generation")))
            ]
        )
        let store = ChoraProfileStore(service: service)

        await store.load(humanActorID: "act_human")
        await store.load(humanActorID: "act_human")
        await waitUntil { store.growth?.version == "new-generation" }
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(store.growth?.version, "new-generation")
    }

    func testSaveSendsOnlyChangedFieldsAndLocksDuplicateSave() async {
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(result: .success(.fixture())),
                .init(
                    delay: 120_000_000,
                    result: .success(.fixture(displayName: "Nova"))
                )
            ],
            growth: [.init(result: .success(nil))],
            displayNameResults: [.success(())]
        )
        let store = ChoraProfileStore(service: service)
        await store.load(humanActorID: "act_human")
        store.setDisplayNameDraft("Nova")

        store.save()
        store.save()
        await waitUntil { !store.isSaving }

        let updateRequests = await service.updateRequests()
        XCTAssertEqual(
            updateRequests,
            [.displayName(agentActorID: "act_chora", value: "Nova")]
        )
        XCTAssertEqual(store.identity?.displayName, "Nova")
        XCTAssertFalse(store.changedFields.contains(.displayName))
    }

    func testPartialSaveReloadsCanonicalAndKeepsOnlyFailedDraft() async {
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(result: .success(.fixture())),
                .init(result: .success(.fixture(
                    displayName: "Nova",
                    preferredAddress: "Luffy"
                )))
            ],
            growth: [.init(result: .success(nil))],
            displayNameResults: [.success(())],
            addressResults: [.failure(.failed)]
        )
        let store = ChoraProfileStore(service: service)
        await store.load(humanActorID: "act_human")
        store.setDisplayNameDraft("Nova")
        store.setPreferredAddressDraft("Captain")

        store.save()
        await waitUntil { !store.isSaving }

        XCTAssertEqual(store.identity?.displayName, "Nova")
        XCTAssertEqual(store.displayNameDraft, "Nova")
        XCTAssertEqual(store.preferredAddressDraft, "Captain")
        XCTAssertFalse(store.changedFields.contains(.displayName))
        XCTAssertTrue(store.changedFields.contains(.preferredAddress))
        XCTAssertNil(store.fieldErrors[.displayName])
        XCTAssertEqual(store.fieldErrors[.preferredAddress], .requestFailed)
        let requests = await service.updateRequests()
        XCTAssertEqual(
            requests,
            [
                .displayName(agentActorID: "act_chora", value: "Nova"),
                .preferredAddress(
                    humanActorID: "act_human",
                    value: "Captain"
                )
            ]
        )
    }

    func testSuccessfulSubmittedValueDoesNotOverwriteNewerDraft() async {
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(result: .success(.fixture())),
                .init(result: .success(.fixture(displayName: "Submitted")))
            ],
            growth: [.init(result: .success(nil))],
            displayNameResults: [.success(())],
            displayNameDelays: [150_000_000]
        )
        let store = ChoraProfileStore(service: service)
        await store.load(humanActorID: "act_human")
        store.setDisplayNameDraft("Submitted")

        store.save()
        while await service.updateRequestCount() < 1 { await Task.yield() }
        store.setDisplayNameDraft("Newer")
        await waitUntil { !store.isSaving }

        XCTAssertEqual(store.identity?.displayName, "Submitted")
        XCTAssertEqual(store.displayNameDraft, "Newer")
        XCTAssertTrue(store.changedFields.contains(.displayName))
        XCTAssertNil(store.fieldErrors[.displayName])
    }

    func testFailedSubmittedValueDoesNotAttachErrorToNewerDraft() async {
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(result: .success(.fixture())),
                .init(result: .success(.fixture()))
            ],
            growth: [.init(result: .success(nil))],
            displayNameResults: [.failure(.failed)],
            displayNameDelays: [150_000_000]
        )
        let store = ChoraProfileStore(service: service)
        await store.load(humanActorID: "act_human")
        store.setDisplayNameDraft("Submitted")

        store.save()
        while await service.updateRequestCount() < 1 { await Task.yield() }
        store.setDisplayNameDraft("Newer")
        await waitUntil { !store.isSaving }

        XCTAssertEqual(store.identity?.displayName, "Chora")
        XCTAssertEqual(store.displayNameDraft, "Newer")
        XCTAssertTrue(store.changedFields.contains(.displayName))
        XCTAssertNil(store.fieldErrors[.displayName])
    }

    func testActorChangeCancelsRemainingMutationsAndKeepsSaveLockedUntilExit() async {
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(result: .success(.fixture(
                    humanActorID: "act_old",
                    agentActorID: "agent_old"
                ))),
                .init(result: .success(.fixture(
                    humanActorID: "act_new",
                    agentActorID: "agent_new",
                    displayName: "New identity"
                ))),
                .init(result: .success(.fixture(
                    humanActorID: "act_new",
                    agentActorID: "agent_new",
                    displayName: "New submitted"
                ))),
                .init(result: .success(.fixture(
                    humanActorID: "act_old",
                    agentActorID: "agent_old",
                    displayName: "Stale canonical"
                )))
            ],
            growth: [
                .init(result: .success(nil)),
                .init(result: .success(nil))
            ],
            displayNameResults: [.success(()), .success(())],
            displayNameDelays: [200_000_000, 0],
            addressResults: [.success(())]
        )
        let store = ChoraProfileStore(service: service)
        await store.load(humanActorID: "act_old")
        store.setDisplayNameDraft("Old submitted")
        store.setPreferredAddressDraft("Old address")

        store.save()
        while await service.updateRequestCount() < 1 { await Task.yield() }
        await store.load(humanActorID: "act_new")
        store.setDisplayNameDraft("New submitted")

        store.save()
        let requestsWhileOldSaveIsSuspended = await service.updateRequests()
        XCTAssertEqual(requestsWhileOldSaveIsSuspended, [
            .displayName(agentActorID: "agent_old", value: "Old submitted")
        ])
        XCTAssertTrue(store.isSaving)

        await waitUntil { !store.isSaving }
        XCTAssertFalse(store.isSaving)
        XCTAssertEqual(store.identity?.displayName, "New identity")

        store.save()
        await waitUntil { !store.isSaving }
        let finalRequests = await service.updateRequests()
        XCTAssertEqual(finalRequests, [
            .displayName(agentActorID: "agent_old", value: "Old submitted"),
            .displayName(agentActorID: "agent_new", value: "New submitted")
        ])
        XCTAssertEqual(store.identity?.displayName, "New submitted")
    }

    func testCancellationBeforeOperationReleaseIssuesNoOldMutation() async {
        let startGate = SaveOperationStartGate()
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(result: .success(.fixture(
                    humanActorID: "act_old",
                    agentActorID: "agent_old"
                ))),
                .init(result: .success(.fixture(
                    humanActorID: "act_new",
                    agentActorID: "agent_new"
                )))
            ],
            growth: [
                .init(result: .success(nil)),
                .init(result: .success(nil))
            ],
            displayNameResults: [.success(())]
        )
        let store = ChoraProfileStore(
            service: service,
            saveOperationStart: { await startGate.wait() }
        )
        await store.load(humanActorID: "act_old")
        store.setDisplayNameDraft("Old submitted")

        store.save()
        while !(await startGate.hasWaiter()) { await Task.yield() }
        await store.load(humanActorID: "act_new")
        await startGate.open()
        while store.isSaving { await Task.yield() }

        let updateRequests = await service.updateRequests()
        XCTAssertTrue(updateRequests.isEmpty)
        XCTAssertEqual(store.identity?.humanActorID, "act_new")
    }

    func testSuspendedSaveMutationDoesNotRetainStore() async {
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(result: .success(.fixture())),
                .init(result: .success(.fixture(displayName: "Submitted")))
            ],
            growth: [.init(result: .success(nil))],
            displayNameResults: [.success(())],
            displayNameDelays: [180_000_000]
        )
        var store: ChoraProfileStore? = ChoraProfileStore(service: service)
        weak let weakStore = store
        await store?.load(humanActorID: "act_human")
        store?.setDisplayNameDraft("Submitted")

        store?.save()
        while await service.updateRequestCount() < 1 { await Task.yield() }
        store = nil
        await Task.yield()
        let releasedWhileSuspended = weakStore == nil
        try? await Task.sleep(nanoseconds: 220_000_000)
        let identityRequestCount = await service.identityRequestCount()

        XCTAssertTrue(releasedWhileSuspended)
        XCTAssertEqual(identityRequestCount, 1)
    }

    func testCanonicalReloadMustRetainExactAgentIdentity() async {
        let original = ChoraIdentity.fixture(agentActorID: "act_chora")
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(result: .success(original)),
                .init(result: .success(.fixture(agentActorID: "agent_other")))
            ],
            growth: [.init(result: .success(nil))],
            displayNameResults: [.success(())]
        )
        let store = ChoraProfileStore(service: service)
        await store.load(humanActorID: "act_human")
        store.setDisplayNameDraft("Nova")

        store.save()
        await waitUntil { !store.isSaving }

        XCTAssertEqual(store.identity, original)
        XCTAssertEqual(store.displayNameDraft, "Nova")
        XCTAssertTrue(store.changedFields.contains(.displayName))
        XCTAssertEqual(store.fieldErrors[.displayName], .agentActorChanged)
    }

    func testSaveCompletionFromPriorGenerationCannotReplaceReloadedIdentity() async {
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(result: .success(.fixture(displayName: "Original"))),
                .init(
                    delay: 160_000_000,
                    result: .success(.fixture(displayName: "Stale save"))
                ),
                .init(result: .success(.fixture(displayName: "Fresh load")))
            ],
            growth: [
                .init(result: .success(nil)),
                .init(result: .success(nil))
            ],
            displayNameResults: [.success(())]
        )
        let store = ChoraProfileStore(service: service)
        await store.load(humanActorID: "act_human")
        store.setDisplayNameDraft("Stale save")

        store.save()
        while await service.identityRequestCount() < 2 { await Task.yield() }
        await store.load(humanActorID: "act_human")
        await waitUntil { !store.isSaving }

        XCTAssertEqual(store.identity?.displayName, "Fresh load")
        XCTAssertEqual(store.displayNameDraft, "Fresh load")
        XCTAssertFalse(store.isSaving)
    }

    func testLateCanonicalReloadFailureCannotAttachErrorsToNewGeneration() async {
        let service = ChoraProfileServiceSpy(
            identities: [
                .init(result: .success(.fixture(
                    humanActorID: "act_old",
                    agentActorID: "agent_old"
                ))),
                .init(delay: 180_000_000, result: .failure(.failed)),
                .init(result: .success(.fixture(
                    humanActorID: "act_new",
                    agentActorID: "agent_new",
                    displayName: "New identity"
                )))
            ],
            growth: [
                .init(result: .success(nil)),
                .init(result: .success(nil))
            ],
            displayNameResults: [.success(())]
        )
        let store = ChoraProfileStore(service: service)
        await store.load(humanActorID: "act_old")
        store.setDisplayNameDraft("Old submitted")

        store.save()
        while await service.identityRequestCount() < 2 { await Task.yield() }
        await store.load(humanActorID: "act_new")
        var fieldErrorPublications = 0
        let token = store.$fieldErrors.dropFirst().sink { _ in
            fieldErrorPublications += 1
        }
        await waitUntil { !store.isSaving }

        XCTAssertEqual(store.identity?.humanActorID, "act_new")
        XCTAssertEqual(store.identity?.displayName, "New identity")
        XCTAssertEqual(store.displayNameDraft, "New identity")
        XCTAssertTrue(store.fieldErrors.isEmpty)
        XCTAssertEqual(fieldErrorPublications, 0)
        withExtendedLifetime(token) {}
    }

    func testAvatarDraftHasTransportNeutralBytesAndMetadata() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let draft = ChoraAvatarDraft(
            data: bytes,
            filename: "chora.png",
            mimeType: "image/png"
        )
        XCTAssertEqual(draft.data, bytes)
        XCTAssertEqual(draft.filename, "chora.png")
        XCTAssertEqual(draft.mimeType, "image/png")
    }

    func testRetryGrowthKeepsIdentityDraftsAndDoesNotReloadIdentity() async {
        let service = ChoraProfileServiceSpy(
            identities: [.init(result: .success(.fixture()))],
            growth: [
                .init(result: .failure(.failed)),
                .init(result: .success(.fixture(version: "retried")))
            ]
        )
        let store = ChoraProfileStore(service: service)
        await store.load(humanActorID: "act_human")
        await waitUntil {
            if case .unavailable = store.growthPhase { return true }
            return false
        }
        store.setDisplayNameDraft("Unsaved Chora")
        store.setPreferredAddressDraft("Unsaved address")

        store.retryGrowth()
        await waitUntil { store.growth?.version == "retried" }

        let identityCount = await service.identityRequestCount()
        XCTAssertEqual(identityCount, 1)
        XCTAssertEqual(store.displayNameDraft, "Unsaved Chora")
        XCTAssertEqual(store.preferredAddressDraft, "Unsaved address")
        XCTAssertEqual(store.changedFields, [.displayName, .preferredAddress])
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline { await Task.yield() }
        XCTAssertTrue(predicate())
    }
}

private extension ChoraIdentity {
    static func fixture(
        humanActorID: String = "act_human",
        agentActorID: String = "act_chora",
        displayName: String = "Chora",
        preferredAddress: String? = "Luffy"
    ) -> ChoraIdentity {
        .init(
            humanActorID: humanActorID,
            agentActorID: agentActorID,
            displayName: displayName,
            avatarURL: "/chora.png",
            preferredAddress: preferredAddress
        )
    }
}

private extension ChoraGrowthSnapshot {
    static func fixture(
        version: String = "growth-v1",
        stage: ChoraGrowthStage = .init(rawValue: 2),
        dimensions: [ChoraGrowthDimensionValue] = []
    ) -> ChoraGrowthSnapshot {
        .init(
            version: version,
            committedStage: stage,
            dimensions: dimensions,
            computedAt: Date(timeIntervalSince1970: 1)
        )
    }
}

private actor ChoraProfileServiceSpy: CoreChoraProfileServing {
    struct IdentityScript: Sendable {
        let delay: UInt64
        let result: Result<ChoraIdentity, TestError>

        init(delay: UInt64 = 0, result: Result<ChoraIdentity, TestError>) {
            self.delay = delay
            self.result = result
        }
    }

    struct GrowthScript: Sendable {
        let delay: UInt64
        let result: Result<ChoraGrowthSnapshot?, TestError>

        init(
            delay: UInt64 = 0,
            result: Result<ChoraGrowthSnapshot?, TestError>
        ) {
            self.delay = delay
            self.result = result
        }
    }

    enum UpdateRequest: Equatable, Sendable {
        case displayName(agentActorID: String, value: String)
        case preferredAddress(humanActorID: String, value: String?)
        case avatar(agentActorID: String, value: ChoraAvatarDraft)
    }

    private var identities: [IdentityScript]
    private var growthScripts: [GrowthScript]
    private var displayNameResults: [Result<Void, TestError>]
    private var displayNameDelays: [UInt64]
    private var addressResults: [Result<Void, TestError>]
    private var avatarResults: [Result<Void, TestError>]
    private var recordedIdentityCount = 0
    private var recordedGrowth: [String] = []
    private var recordedUpdates: [UpdateRequest] = []

    init(
        identities: [IdentityScript],
        growth: [GrowthScript] = [],
        displayNameResults: [Result<Void, TestError>] = [],
        displayNameDelays: [UInt64] = [],
        addressResults: [Result<Void, TestError>] = [],
        avatarResults: [Result<Void, TestError>] = []
    ) {
        self.identities = identities
        self.growthScripts = growth
        self.displayNameResults = displayNameResults
        self.displayNameDelays = displayNameDelays
        self.addressResults = addressResults
        self.avatarResults = avatarResults
    }

    func identity(humanActorID: String) async throws -> ChoraIdentity {
        recordedIdentityCount += 1
        let script = identities.removeFirst()
        if script.delay > 0 {
            await Task.detached {
                try? await Task.sleep(nanoseconds: script.delay)
            }.value
        }
        return try script.result.get()
    }

    func growth(agentActorID: String) async throws -> ChoraGrowthSnapshot? {
        recordedGrowth.append(agentActorID)
        let script = growthScripts.removeFirst()
        if script.delay > 0 { try? await Task.sleep(nanoseconds: script.delay) }
        return try script.result.get()
    }

    func updateDisplayName(agentActorID: String, displayName: String) async throws {
        recordedUpdates.append(.displayName(
            agentActorID: agentActorID,
            value: displayName
        ))
        let delay = displayNameDelays.isEmpty
            ? 0
            : displayNameDelays.removeFirst()
        if delay > 0 {
            await Task.detached {
                try? await Task.sleep(nanoseconds: delay)
            }.value
        }
        try displayNameResults.removeFirst().get()
    }

    func updatePreferredAddress(
        humanActorID: String,
        value: String?
    ) async throws {
        recordedUpdates.append(.preferredAddress(
            humanActorID: humanActorID,
            value: value
        ))
        try addressResults.removeFirst().get()
    }

    func updateAvatar(agentActorID: String, avatar: ChoraAvatarDraft) async throws {
        recordedUpdates.append(.avatar(agentActorID: agentActorID, value: avatar))
        try avatarResults.removeFirst().get()
    }

    func growthRequests() -> [String] { recordedGrowth }
    func updateRequests() -> [UpdateRequest] { recordedUpdates }
    func updateRequestCount() -> Int { recordedUpdates.count }
    func identityRequestCount() -> Int { recordedIdentityCount }
}

private enum TestError: Error, Sendable {
    case failed
}

private actor SuspendedGrowthService: CoreChoraProfileServing {
    private var started = false
    private var cancellations = 0
    private var continuation: CheckedContinuation<ChoraGrowthSnapshot?, Error>?

    func identity(humanActorID: String) async throws -> ChoraIdentity {
        .fixture()
    }

    func growth(agentActorID: String) async throws -> ChoraGrowthSnapshot? {
        started = true
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task { await self.cancelGrowth() }
        }
    }

    func updateDisplayName(agentActorID: String, displayName: String) async throws {}
    func updatePreferredAddress(humanActorID: String, value: String?) async throws {}
    func updateAvatar(agentActorID: String, avatar: ChoraAvatarDraft) async throws {}

    func didStartGrowth() -> Bool { started }
    func cancellationCount() -> Int { cancellations }

    func finishGrowth() {
        continuation?.resume(returning: nil)
        continuation = nil
    }

    private func cancelGrowth() {
        cancellations += 1
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}

private actor SaveOperationStartGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func hasWaiter() -> Bool { continuation != nil }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
