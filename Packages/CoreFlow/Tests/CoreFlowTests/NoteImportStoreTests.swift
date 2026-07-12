import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class NoteImportStoreTests: XCTestCase {
    func testActionCapabilitiesRequireExactRecoverablePrerequisites() async {
        let failedService = NoteImportServiceSpy(jobsFail: true)
        let failedStore = makeStore(service: failedService)
        await failedStore.load(actorID: "act_1")
        XCTAssertTrue(failedStore.canReload)
        XCTAssertFalse(failedStore.canRetrySubmission)
        XCTAssertFalse(failedStore.canCancelCurrentJob)

        let persistence = NoteImportPersistenceSpy(values: ["act_1": "req_old"])
        let ambiguousStore = makeStore(
            service: NoteImportServiceSpy(jobLists: [[]]),
            persistence: persistence
        )
        await ambiguousStore.load(actorID: "act_1")
        XCTAssertTrue(ambiguousStore.needsFileReselectionForRetry)
        XCTAssertFalse(ambiguousStore.canRetrySubmission)

        let suspendedService = NoteImportServiceSpy(enqueueSuspended: true)
        let submittingStore = makeStore(service: suspendedService)
        await submittingStore.load(actorID: "act_1")
        submittingStore.select([file("one.md", format: .markdown)])
        submittingStore.start()
        await waitUntil { await suspendedService.enqueueCount() == 1 }
        XCTAssertFalse(submittingStore.canCancelCurrentJob)
    }

    func testSelectionAcceptsOnlySupportedNonemptyDescriptorsBeforeServiceCall() async {
        let service = NoteImportServiceSpy()
        let persistence = NoteImportPersistenceSpy()
        let store = makeStore(service: service, persistence: persistence)
        await store.load(actorID: "act_1")

        let supported = [
            file("one.md", format: .markdown),
            file("two.markdown", format: .markdown),
            file("three.html", format: .html),
            file("four.htm", format: .html)
        ]
        store.select(supported)
        XCTAssertEqual(store.selectedFiles, supported)

        store.select([file("image.png", format: .init(rawValue: "png"))])
        store.start()
        await settle()
        XCTAssertEqual(store.phase, .invalidSelection(.unsupportedFormat(filename: "image.png")))
        let unsupportedEnqueues = await service.enqueueCount()
        XCTAssertEqual(unsupportedEnqueues, 0)

        store.select([file("empty.md", format: .markdown, byteCount: 0)])
        store.start()
        await settle()
        XCTAssertEqual(store.phase, .invalidSelection(.emptyFile(filename: "empty.md")))
        let emptyEnqueues = await service.enqueueCount()
        XCTAssertEqual(emptyEnqueues, 0)
    }

    func testAdapterDetectedEmptyFileReturnsToSelectionAndClearsRequestID() async {
        let service = NoteImportServiceSpy(
            enqueueResults: [
                .failure(.selection(.emptyFile(filename: "provider.md")))
            ]
        )
        let persistence = NoteImportPersistenceSpy()
        let store = makeStore(service: service, persistence: persistence)
        await store.load(actorID: "act_1")
        store.select([
            file("provider.md", format: .markdown, byteCount: -1)
        ])

        store.start()
        await waitUntil {
            store.phase == .invalidSelection(
                .emptyFile(filename: "provider.md")
            )
        }

        XCTAssertNil(store.clientRequestID)
        XCTAssertNil(persistence.value(actorID: "act_1"))
        XCTAssertEqual(persistence.clearedActors, ["act_1"])
    }

    func testAdapterMetadataFailureStaysDistinctAndClearsRequestID() async {
        let service = NoteImportServiceSpy(
            enqueueResults: [
                .failure(.preflight(code: "file_metadata_unavailable"))
            ]
        )
        let persistence = NoteImportPersistenceSpy()
        let store = makeStore(service: service, persistence: persistence)
        await store.load(actorID: "act_1")
        store.select([
            file("provider.md", format: .markdown, byteCount: -1)
        ])

        store.start()
        await waitUntil {
            store.phase == .failed(
                .preflight(code: "file_metadata_unavailable")
            )
        }

        XCTAssertNil(store.clientRequestID)
        XCTAssertNil(persistence.value(actorID: "act_1"))
        XCTAssertEqual(persistence.clearedActors, ["act_1"])
        XCTAssertFalse(store.canRetrySubmission)
    }

    func testSecurityScopeDenialClearsUnsubmittedRequestID() async {
        let service = NoteImportServiceSpy(
            enqueueResults: [
                .failure(.preflight(code: "security_scope_denied"))
            ]
        )
        let persistence = NoteImportPersistenceSpy()
        let store = makeStore(service: service, persistence: persistence)
        await store.load(actorID: "act_1")
        store.select([
            file("provider.md", format: .markdown, byteCount: -1)
        ])

        store.start()
        await waitUntil {
            store.phase == .failed(
                .preflight(code: "security_scope_denied")
            )
        }

        XCTAssertNil(store.clientRequestID)
        XCTAssertNil(persistence.value(actorID: "act_1"))
        XCTAssertEqual(persistence.clearedActors, ["act_1"])
        XCTAssertFalse(store.canRetrySubmission)
    }

    func testEverySupportedExtensionActuallyReachesEnqueue() async {
        let files = [
            file("one.md", format: .markdown),
            file("two.markdown", format: .markdown),
            file("three.html", format: .html),
            file("four.htm", format: .html)
        ]
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            details: [.fixture(status: .done)]
        )
        let store = makeStore(service: service)
        await store.load(actorID: "act_1")
        store.select(files)

        store.start()
        await waitUntil { store.phase == .terminal }

        let submitted = await service.submittedFiles()
        XCTAssertEqual(submitted, [files])
    }

    func testStartPersistsActorScopedRequestIDBeforeEnqueueAndIsSingleFlight() async {
        let service = NoteImportServiceSpy(
            details: [.fixture(clientRequestID: "req_fixed", status: .done)],
            enqueueSuspended: true
        )
        let persistence = NoteImportPersistenceSpy()
        let store = makeStore(
            service: service,
            persistence: persistence,
            requestID: { "req_fixed" }
        )
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])

        store.start()
        store.start()
        await waitUntil { await service.enqueueCount() == 1 }

        XCTAssertEqual(store.clientRequestID, "req_fixed")
        XCTAssertEqual(persistence.events, ["save:act_1:req_fixed"])
        let enqueueCount = await service.enqueueCount()
        let requestIDs = await service.enqueueRequestIDs()
        XCTAssertEqual(enqueueCount, 1)
        XCTAssertEqual(requestIDs, ["req_fixed"])
        await service.resumeEnqueue(with: .success(.receipt(clientRequestID: "req_fixed")))
        await waitUntil { store.detail?.jobID == "job_1" }
    }

    func testAmbiguousEnqueueReconcilesByExactRequestIDBeforeRetryAndReusesID() async {
        let exact = NoteImportJobSummary.fixture(
            jobID: "job_exact",
            clientRequestID: "req_fixed",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let newerWrong = NoteImportJobSummary.fixture(
            jobID: "job_newest",
            clientRequestID: "req_other",
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let service = NoteImportServiceSpy(
            enqueueResults: [.failure(.ambiguous(.timeout))],
            jobLists: [[], [newerWrong, exact]],
            details: [.fixture(jobID: "job_exact", clientRequestID: "req_fixed", status: .done)]
        )
        let persistence = NoteImportPersistenceSpy()
        let store = makeStore(
            service: service,
            persistence: persistence,
            requestID: { "req_fixed" }
        )
        await store.load(actorID: "act_1")
        store.select([file("same-name.md", format: .markdown)])

        store.start()
        await waitUntil { store.detail?.jobID == "job_exact" }

        let calls = await service.calls()
        XCTAssertEqual(calls, [
            "jobs:50",
            "enqueue:req_fixed",
            "jobs:50",
            "job:job_exact"
        ])
        XCTAssertEqual(store.phase, .terminal)
        XCTAssertEqual(store.clientRequestID, "req_fixed")
        XCTAssertEqual(persistence.clearedActors, ["act_1"])
    }

    func testRetryReconcilesFirstThenReenqueuesWithStableRequestIDWhenNoExactJobExists() async {
        let service = NoteImportServiceSpy(
            enqueueResults: [
                .failure(.ambiguous(.connectionLost)),
                .success(.receipt(clientRequestID: "req_stable"))
            ],
            jobLists: [[], [], []],
            details: [.fixture(clientRequestID: "req_stable", status: .done)]
        )
        let persistence = NoteImportPersistenceSpy()
        let store = makeStore(
            service: service,
            persistence: persistence,
            requestID: { "req_stable" }
        )
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])
        store.start()
        await waitUntil { store.phase == .ambiguous }

        store.retry()
        await waitUntil { store.phase == .terminal }

        let requestIDs = await service.enqueueRequestIDs()
        let calls = await service.calls()
        XCTAssertEqual(requestIDs, ["req_stable", "req_stable"])
        XCTAssertEqual(calls, [
            "jobs:50",
            "enqueue:req_stable",
            "jobs:50",
            "jobs:50",
            "enqueue:req_stable",
            "job:job_1"
        ])
    }

    func testStartAgainAfterAmbiguityReconcilesExactIDWithoutSecondEnqueue() async {
        let exact = NoteImportJobSummary.fixture(
            jobID: "job_exact",
            clientRequestID: "req_stable",
            status: .running
        )
        let service = NoteImportServiceSpy(
            enqueueResults: [.failure(.ambiguous(.timeout))],
            jobLists: [[], [], [exact]],
            details: [
                .fixture(
                    jobID: "job_exact",
                    clientRequestID: "req_stable",
                    status: .done
                )
            ]
        )
        let store = makeStore(service: service, requestID: { "req_stable" })
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])
        store.start()
        await waitUntil { store.phase == .ambiguous }

        store.start()
        await waitUntil { store.phase == .terminal }

        let calls = await service.calls()
        XCTAssertEqual(calls, [
            "jobs:50",
            "enqueue:req_stable",
            "jobs:50",
            "jobs:50",
            "job:job_exact"
        ])
        let enqueueCount = await service.enqueueCount()
        XCTAssertEqual(enqueueCount, 1)
    }

    func testUndecodableSuccessReconcilesByExactRequestID() async {
        let exact = NoteImportJobSummary.fixture(
            jobID: "job_exact",
            clientRequestID: "req_decode"
        )
        let service = NoteImportServiceSpy(
            enqueueResults: [
                .failure(.ambiguous(.undecodableSuccess(statusCode: 202)))
            ],
            jobLists: [[], [exact]],
            details: [
                .fixture(
                    jobID: "job_exact",
                    clientRequestID: "req_decode",
                    status: .done
                )
            ]
        )
        let store = makeStore(service: service, requestID: { "req_decode" })
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])

        store.start()
        await waitUntil { store.phase == .terminal }

        let calls = await service.calls()
        XCTAssertEqual(calls, [
            "jobs:50", "enqueue:req_decode", "jobs:50", "job:job_exact"
        ])
    }

    func testRelaunchRestoresPersistedExactActiveJob() async {
        let persistence = NoteImportPersistenceSpy(values: ["act_1": "req_active"])
        let service = NoteImportServiceSpy(
            jobLists: [[
                .fixture(jobID: "job_other", clientRequestID: "req_other"),
                .fixture(jobID: "job_active", clientRequestID: "req_active", status: .running)
            ]],
            details: [.fixture(jobID: "job_active", clientRequestID: "req_active", status: .done)]
        )
        let store = makeStore(service: service, persistence: persistence)

        await store.load(actorID: "act_1")
        await waitUntil { store.phase == .terminal }

        XCTAssertEqual(store.clientRequestID, "req_active")
        XCTAssertEqual(store.detail?.jobID, "job_active")
        let detailIDs = await service.detailIDs()
        XCTAssertEqual(detailIDs, ["job_active"])
    }

    func testLoadWithoutPersistenceRestoresLatestActiveCanonicalJob() async {
        let persistence = NoteImportPersistenceSpy()
        let service = NoteImportServiceSpy(
            jobLists: [[
                .fixture(
                    jobID: "job_terminal",
                    clientRequestID: "req_terminal",
                    status: .done,
                    createdAt: Date(timeIntervalSince1970: 30)
                ),
                .fixture(
                    jobID: "job_old",
                    clientRequestID: "req_old",
                    status: .running,
                    createdAt: Date(timeIntervalSince1970: 10)
                ),
                .fixture(
                    jobID: "job_latest",
                    clientRequestID: "req_latest",
                    status: .running,
                    createdAt: Date(timeIntervalSince1970: 20)
                )
            ]],
            details: [
                .fixture(
                    jobID: "job_latest",
                    clientRequestID: "req_latest",
                    status: .done
                )
            ]
        )
        let store = makeStore(service: service, persistence: persistence)

        await store.load(actorID: "act_1")
        await waitUntil { store.phase == .terminal }

        XCTAssertEqual(store.detail?.jobID, "job_latest")
        XCTAssertEqual(persistence.events, ["save:act_1:req_latest"])
    }

    func testUnknownJobAndSoulStatusesStayLosslessAndKeepPolling() async {
        let persistence = NoteImportPersistenceSpy()
        let sleeper = NoteImportSleeperSpy()
        let unknownJob = NoteImportJobStatus(rawValue: "future_job")
        let unknownSoul = NoteImportSoulStatus(rawValue: "future_soul")
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            details: [
                .fixture(status: unknownJob, soulStatus: .done),
                .fixture(status: .done, soulStatus: unknownSoul),
                .fixture(status: .done, soulStatus: .done)
            ]
        )
        let store = makeStore(
            service: service,
            persistence: persistence,
            sleeper: sleeper
        )
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])

        store.start()
        await waitUntil { await sleeper.callCount() == 1 }
        XCTAssertEqual(store.detail?.status.rawValue, "future_job")
        XCTAssertEqual(store.phase, .polling)
        XCTAssertEqual(persistence.value(actorID: "act_1"), "req_generated")
        XCTAssertTrue(persistence.clearedActors.isEmpty)

        await sleeper.resumeNext()
        await waitUntil { await sleeper.callCount() == 2 }
        XCTAssertEqual(store.detail?.soulStatus.rawValue, "future_soul")
        XCTAssertEqual(store.detail?.status, .done)
        XCTAssertEqual(store.phase, .polling)
        XCTAssertEqual(persistence.value(actorID: "act_1"), "req_generated")
        XCTAssertTrue(persistence.clearedActors.isEmpty)

        await sleeper.resumeNext()
        await waitUntil { store.phase == .terminal }
        XCTAssertEqual(persistence.clearedActors, ["act_1"])
    }

    func testPollingUsesInjectedThreeSecondSleeperAndStopsAtTerminal() async {
        let sleeper = NoteImportSleeperSpy()
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            details: [
                .fixture(status: .running, soulStatus: .notRequested),
                .fixture(status: .done, soulStatus: .running),
                .fixture(status: .done, soulStatus: .done)
            ]
        )
        let store = makeStore(service: service, sleeper: sleeper)
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])

        store.start()
        await waitUntil { await sleeper.callCount() == 1 }
        let firstSleeps = await sleeper.nanoseconds()
        XCTAssertEqual(firstSleeps, [3_000_000_000])
        await sleeper.resumeNext()
        await waitUntil { await sleeper.callCount() == 2 }
        let secondSleeps = await sleeper.nanoseconds()
        XCTAssertEqual(secondSleeps, [3_000_000_000, 3_000_000_000])
        await sleeper.resumeNext()
        await waitUntil { store.phase == .terminal }
        await settle()

        let finalSleeps = await sleeper.nanoseconds()
        let detailIDs = await service.detailIDs()
        XCTAssertEqual(finalSleeps, [3_000_000_000, 3_000_000_000])
        XCTAssertEqual(detailIDs, ["job_1", "job_1", "job_1"])
    }

    func testCancelCallsCanonicalRouteThenReloadsDetail() async {
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            details: [
                .fixture(status: .running),
                .fixture(status: .cancelled, soulStatus: .cancelled)
            ]
        )
        let sleeper = NoteImportSleeperSpy()
        let store = makeStore(service: service, sleeper: sleeper)
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])
        store.start()
        await waitUntil { await sleeper.callCount() == 1 }

        store.cancel()
        await waitUntil { store.phase == .terminal }

        let calls = await service.calls()
        XCTAssertEqual(calls, [
            "jobs:50", "enqueue:req_generated", "job:job_1", "cancel:job_1", "job:job_1"
        ])
    }

    func testCancelFailureStillReloadsCanonicalDetail() async {
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            details: [
                .fixture(status: .running),
                .fixture(status: .cancelled, soulStatus: .cancelled)
            ],
            cancelResult: .failure(.requestFailed(code: "cancel_failed"))
        )
        let sleeper = NoteImportSleeperSpy()
        let store = makeStore(service: service, sleeper: sleeper)
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])
        store.start()
        await waitUntil { await sleeper.callCount() == 1 }

        store.cancel()
        await waitUntil { store.phase == .terminal }

        let calls = await service.calls()
        XCTAssertEqual(calls, [
            "jobs:50", "enqueue:req_generated", "job:job_1", "cancel:job_1", "job:job_1"
        ])
    }

    func testServiceCancellationDuringEnqueueReleasesLockForReconciledStart() async {
        let service = NoteImportServiceSpy(
            jobLists: [[], []],
            details: [.fixture(status: .done)],
            enqueueCancellationCalls: [1]
        )
        let store = makeStore(service: service)
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])

        store.start()
        await waitUntil {
            store.phase == .failed(.requestFailed(code: "cancelled"))
        }
        store.start()
        await waitUntil { store.phase == .terminal }

        let calls = await service.calls()
        XCTAssertEqual(calls, [
            "jobs:50",
            "enqueue:req_generated",
            "jobs:50",
            "enqueue:req_generated",
            "job:job_1"
        ])
    }

    func testServiceCancellationDuringPollReleasesLockForExactReconciliation() async {
        let exact = NoteImportJobSummary.fixture(
            clientRequestID: "req_generated",
            status: .running
        )
        let sleeper = NoteImportSleeperSpy()
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            jobLists: [[], [exact]],
            details: [
                .fixture(status: .running),
                .fixture(status: .done)
            ],
            jobCancellationCalls: [2]
        )
        let store = makeStore(service: service, sleeper: sleeper)
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])
        store.start()
        await waitUntil { await sleeper.callCount() == 1 }

        await sleeper.resumeNext()
        await waitUntil {
            store.phase == .failed(.requestFailed(code: "cancelled"))
        }
        store.start()
        await waitUntil { store.phase == .terminal }

        let calls = await service.calls()
        XCTAssertEqual(calls, [
            "jobs:50",
            "enqueue:req_generated",
            "job:job_1",
            "job:job_1",
            "jobs:50",
            "job:job_1"
        ])
    }

    func testServiceCancellationFromCancelRouteStillReloadsCanonicalDetail() async {
        let sleeper = NoteImportSleeperSpy()
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            details: [
                .fixture(status: .running),
                .fixture(status: .cancelled, soulStatus: .cancelled)
            ],
            cancelThrowsCancellation: true
        )
        let store = makeStore(service: service, sleeper: sleeper)
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])
        store.start()
        await waitUntil { await sleeper.callCount() == 1 }

        store.cancel()
        await waitUntil { store.phase == .terminal }

        let calls = await service.calls()
        XCTAssertEqual(calls, [
            "jobs:50", "enqueue:req_generated", "job:job_1",
            "cancel:job_1", "job:job_1"
        ])
    }

    func testServiceCancellationFromCancelReloadUnlocksForRetry() async {
        let sleeper = NoteImportSleeperSpy()
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            details: [
                .fixture(status: .running),
                .fixture(status: .cancelled, soulStatus: .cancelled)
            ],
            jobCancellationCalls: [2]
        )
        let store = makeStore(service: service, sleeper: sleeper)
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])
        store.start()
        await waitUntil { await sleeper.callCount() == 1 }

        store.cancel()
        await waitUntil {
            store.phase == .failed(.requestFailed(code: "cancelled"))
        }
        store.cancel()
        await waitUntil { store.phase == .terminal }

        let calls = await service.calls()
        XCTAssertEqual(calls, [
            "jobs:50", "enqueue:req_generated", "job:job_1",
            "cancel:job_1", "job:job_1", "cancel:job_1", "job:job_1"
        ])
    }

    func testCancellingCapabilityLocksDuplicateCancelTaps() async {
        let sleeper = NoteImportSleeperSpy()
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            details: [.fixture(status: .running)],
            cancelSuspended: true
        )
        let store = makeStore(service: service, sleeper: sleeper)
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])
        store.start()
        await waitUntil { await sleeper.callCount() == 1 }
        XCTAssertTrue(store.canCancelCurrentJob)

        store.cancel()
        await waitUntil { await service.didStartCancel() }
        XCTAssertEqual(store.phase, .cancelling)
        XCTAssertFalse(store.canCancelCurrentJob)
        store.cancel()
        await Task.yield()

        let calls = await service.calls()
        let cancelCalls = calls.filter { $0 == "cancel:job_1" }
        XCTAssertEqual(cancelCalls.count, 1)
        store.stop()
    }

    func testActorChangeDuringCancelDoesNotReloadOrPublishOldJob() async {
        let sleeper = NoteImportSleeperSpy()
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            jobLists: [[], []],
            details: [.fixture(status: .running)],
            cancelSuspended: true
        )
        let store = makeStore(service: service, sleeper: sleeper)
        await store.load(actorID: "act_old")
        store.select([file("one.md", format: .markdown)])
        store.start()
        await waitUntil { await sleeper.callCount() == 1 }
        store.cancel()
        await waitUntil { await service.didStartCancel() }

        await store.load(actorID: "act_new")
        await waitUntil { await service.cancelCancellations() == 1 }

        XCTAssertEqual(store.actorID, "act_new")
        XCTAssertEqual(store.phase, .ready)
        XCTAssertNil(store.detail)
        let detailIDs = await service.detailIDs()
        XCTAssertEqual(detailIDs, ["job_1"])
    }

    func testActorChangeClearsSelectionAndRequestAndFencesOldCompletion() async {
        let service = NoteImportServiceSpy(enqueueSuspended: true)
        let persistence = NoteImportPersistenceSpy()
        let store = makeStore(service: service, persistence: persistence)
        await store.load(actorID: "act_old")
        store.select([file("old.md", format: .markdown)])
        store.start()
        await waitUntil { await service.enqueueCount() == 1 }

        await store.load(actorID: "act_new")
        await service.resumeEnqueue(with: .success(.receipt(clientRequestID: "req_generated")))
        await settle()

        XCTAssertEqual(store.actorID, "act_new")
        XCTAssertEqual(store.selectedFiles, [])
        XCTAssertNil(store.clientRequestID)
        XCTAssertNil(store.receipt)
        XCTAssertNil(store.detail)
        let detailIDs = await service.detailIDs()
        XCTAssertFalse(detailIDs.contains("job_1"))
    }

    func testActorSwitchDuringPollingCancelsOldPollAndClearsState() async {
        let sleeper = NoteImportSleeperSpy()
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            jobLists: [[], []],
            details: [.fixture(status: .running)]
        )
        let store = makeStore(service: service, sleeper: sleeper)
        await store.load(actorID: "act_old")
        store.select([file("old.md", format: .markdown)])
        store.start()
        await waitUntil { await sleeper.callCount() == 1 }

        await store.load(actorID: "act_new")
        await sleeper.resumeNext()
        await settle()

        XCTAssertEqual(store.actorID, "act_new")
        XCTAssertEqual(store.phase, .ready)
        XCTAssertNil(store.clientRequestID)
        XCTAssertNil(store.detail)
        let detailIDs = await service.detailIDs()
        XCTAssertEqual(detailIDs, ["job_1"])
    }

    func testTeardownCancelsSuspendedPollingWithoutRetainingStore() async {
        let sleeper = CancellableNoteImportSleeper()
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            details: [.fixture(status: .running)]
        )
        var store: NoteImportStore? = NoteImportStore(
            service: service,
            persistence: NoteImportPersistenceSpy(),
            sleeper: sleeper,
            requestID: { "req_generated" }
        )
        weak let weakStore = store
        await store?.load(actorID: "act_1")
        store?.select([file("one.md", format: .markdown)])
        store?.start()
        await waitUntil { await sleeper.didStart() }

        store = nil
        for _ in 0..<20 { await Task.yield() }
        let releasedWhileSuspended = weakStore == nil
        if !releasedWhileSuspended {
            weakStore?.stop()
            for _ in 0..<20 { await Task.yield() }
        }

        XCTAssertTrue(releasedWhileSuspended)
        if releasedWhileSuspended {
            await waitUntil { await sleeper.cancellations() == 1 }
            let cancellations = await sleeper.cancellations()
            XCTAssertEqual(cancellations, 1)
        }
    }

    func testTeardownDoesNotRetainStoreAcrossSuspendedEnqueue() async {
        let service = NoteImportServiceSpy(enqueueSuspended: true)
        var store: NoteImportStore? = makeStore(service: service)
        weak let weakStore = store
        await store?.load(actorID: "act_1")
        store?.select([file("one.md", format: .markdown)])
        store?.start()
        await waitUntil { await service.enqueueCount() == 1 }

        store = nil
        for _ in 0..<20 { await Task.yield() }
        let releasedWhileSuspended = weakStore == nil
        if !releasedWhileSuspended {
            weakStore?.stop()
        }
        await service.resumeEnqueue(with: .success(.receipt()))

        XCTAssertTrue(releasedWhileSuspended)
    }

    func testTeardownCancelsSuspendedCancelWithoutRetainingStore() async {
        let sleeper = NoteImportSleeperSpy()
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            details: [.fixture(status: .running)],
            cancelSuspended: true
        )
        var store: NoteImportStore? = makeStore(
            service: service,
            sleeper: sleeper
        )
        weak let weakStore = store
        await store?.load(actorID: "act_1")
        store?.select([file("one.md", format: .markdown)])
        store?.start()
        await waitUntil { await sleeper.callCount() == 1 }
        store?.cancel()
        await waitUntil { await service.didStartCancel() }

        store = nil
        await settle()
        let releasedWhileSuspended = weakStore == nil
        if !releasedWhileSuspended { weakStore?.stop() }
        await waitUntil { await service.cancelCancellations() == 1 }
        await sleeper.resumeNext()

        XCTAssertTrue(releasedWhileSuspended)
        let cancellations = await service.cancelCancellations()
        XCTAssertEqual(cancellations, 1)
    }

    func testTeardownCancelsSuspendedReconciliationWithoutRetainingStore() async {
        let persistence = NoteImportPersistenceSpy(
            values: ["act_1": "req_persisted"]
        )
        let service = NoteImportServiceSpy(
            jobLists: [[], []],
            jobsSuspendedCalls: [2]
        )
        var store: NoteImportStore? = makeStore(
            service: service,
            persistence: persistence
        )
        weak let weakStore = store
        await store?.load(actorID: "act_1")
        store?.select([file("one.md", format: .markdown)])
        store?.start()
        await waitUntil { await service.suspendedJobsStarts() == 1 }

        store = nil
        await settle()
        let releasedWhileSuspended = weakStore == nil
        if !releasedWhileSuspended { weakStore?.stop() }
        await waitUntil { await service.jobsCancellations() == 1 }

        XCTAssertTrue(releasedWhileSuspended)
        let cancellations = await service.jobsCancellations()
        XCTAssertEqual(cancellations, 1)
    }

    func testTerminalCountsAndPerFileAssetIDsRemainLossless() async {
        let terminal = NoteImportJobDetail.fixture(
            status: .done,
            soulStatus: .failed,
            totalFiles: 5,
            importedCount: 1,
            updatedCount: 2,
            skippedCount: 1,
            failedCount: 1,
            items: [
                .fixture(filename: "one.md", assetID: "ast_exact_1", status: .imported),
                .fixture(filename: "two.md", assetID: "ast_exact_2", status: .updated),
                .fixture(filename: "three.md", assetID: nil, status: .failed)
            ]
        )
        let service = NoteImportServiceSpy(
            enqueueResults: [.success(.receipt())],
            details: [terminal]
        )
        let store = makeStore(service: service)
        await store.load(actorID: "act_1")
        store.select([file("one.md", format: .markdown)])

        store.start()
        await waitUntil { store.phase == .terminal }

        XCTAssertEqual(store.detail, terminal)
        XCTAssertEqual(store.detail?.items.map(\.assetID), ["ast_exact_1", "ast_exact_2", nil])
    }

    private func makeStore(
        service: NoteImportServiceSpy,
        persistence: NoteImportPersistenceSpy = .init(),
        sleeper: NoteImportSleeperSpy = .init(immediate: true),
        requestID: @escaping @Sendable () -> String = { "req_generated" }
    ) -> NoteImportStore {
        NoteImportStore(
            service: service,
            persistence: persistence,
            sleeper: sleeper,
            requestID: requestID
        )
    }

    private func file(
        _ filename: String,
        format: NoteImportFormat,
        byteCount: Int64 = 10
    ) -> NoteImportFile {
        .init(
            id: "id_\(filename)",
            sourceKey: "source_\(filename)",
            url: URL(fileURLWithPath: "/tmp/\(filename)"),
            filename: filename,
            label: filename,
            format: format,
            byteCount: byteCount
        )
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<2_000 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Condition not met", file: file, line: line)
    }
}

private final class NoteImportPersistenceSpy: NoteImportRequestIDPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private(set) var events: [String] = []
    private(set) var clearedActors: [String] = []

    init(values: [String: String] = [:]) { self.values = values }

    func load(actorID: String) -> String? {
        lock.withLock { values[actorID] }
    }

    func save(_ requestID: String, actorID: String) {
        lock.withLock {
            values[actorID] = requestID
            events.append("save:\(actorID):\(requestID)")
        }
    }

    func clear(actorID: String) {
        lock.withLock {
            values[actorID] = nil
            clearedActors.append(actorID)
        }
    }

    func value(actorID: String) -> String? {
        lock.withLock { values[actorID] }
    }
}

private actor NoteImportServiceSpy: CoreNoteImportServing {
    private var enqueueResults: [Result<NoteImportReceipt, NoteImportServiceError>]
    private var jobLists: [[NoteImportJobSummary]]
    private var details: [NoteImportJobDetail]
    private let enqueueSuspended: Bool
    private var enqueueContinuation: CheckedContinuation<NoteImportReceipt, Error>?
    private var callLog: [String] = []
    private var enqueuedRequestIDs: [String] = []
    private var requestedDetailIDs: [String] = []
    private let cancelResult: Result<Void, NoteImportServiceError>
    private var enqueuedFiles: [[NoteImportFile]] = []
    private let enqueueCancellationCalls: Set<Int>
    private let jobCancellationCalls: Set<Int>
    private let cancelThrowsCancellation: Bool
    private let cancelSuspended: Bool
    private let jobsSuspendedCalls: Set<Int>
    private let jobsFail: Bool
    private var cancelStarted = false
    private var cancelCancellationCount = 0
    private var suspendedJobsStartCount = 0
    private var jobsCancellationCount = 0

    init(
        enqueueResults: [Result<NoteImportReceipt, NoteImportServiceError>] = [],
        jobLists: [[NoteImportJobSummary]] = [[]],
        details: [NoteImportJobDetail] = [.fixture(status: .done)],
        cancelResult: Result<Void, NoteImportServiceError> = .success(()),
        enqueueCancellationCalls: Set<Int> = [],
        jobCancellationCalls: Set<Int> = [],
        cancelThrowsCancellation: Bool = false,
        cancelSuspended: Bool = false,
        jobsSuspendedCalls: Set<Int> = [],
        enqueueSuspended: Bool = false,
        jobsFail: Bool = false
    ) {
        self.enqueueResults = enqueueResults
        self.jobLists = jobLists
        self.details = details
        self.cancelResult = cancelResult
        self.enqueueCancellationCalls = enqueueCancellationCalls
        self.jobCancellationCalls = jobCancellationCalls
        self.cancelThrowsCancellation = cancelThrowsCancellation
        self.cancelSuspended = cancelSuspended
        self.jobsSuspendedCalls = jobsSuspendedCalls
        self.enqueueSuspended = enqueueSuspended
        self.jobsFail = jobsFail
    }

    func enqueue(files: [NoteImportFile], clientRequestID: String) async throws -> NoteImportReceipt {
        callLog.append("enqueue:\(clientRequestID)")
        enqueuedRequestIDs.append(clientRequestID)
        enqueuedFiles.append(files)
        if enqueueCancellationCalls.contains(enqueuedRequestIDs.count) {
            throw CancellationError()
        }
        if enqueueSuspended {
            return try await withCheckedThrowingContinuation { enqueueContinuation = $0 }
        }
        guard !enqueueResults.isEmpty else { return .receipt(clientRequestID: clientRequestID) }
        return try enqueueResults.removeFirst().get()
    }

    func jobs(limit: Int) async throws -> [NoteImportJobSummary] {
        callLog.append("jobs:\(limit)")
        if jobsFail { throw NoteImportServiceError.requestFailed(code: "offline") }
        let call = callLog.filter { $0 == "jobs:\(limit)" }.count
        if jobsSuspendedCalls.contains(call) {
            suspendedJobsStartCount += 1
            do {
                try await Task.sleep(nanoseconds: 3_600_000_000_000)
            } catch is CancellationError {
                jobsCancellationCount += 1
                throw CancellationError()
            }
        }
        return jobLists.isEmpty ? [] : jobLists.removeFirst()
    }

    func job(id: String) async throws -> NoteImportJobDetail {
        callLog.append("job:\(id)")
        requestedDetailIDs.append(id)
        if jobCancellationCalls.contains(requestedDetailIDs.count) {
            throw CancellationError()
        }
        return details.isEmpty ? .fixture(jobID: id, status: .done) : details.removeFirst()
    }

    func cancel(id: String) async throws {
        callLog.append("cancel:\(id)")
        cancelStarted = true
        if cancelSuspended {
            do {
                try await Task.sleep(nanoseconds: 3_600_000_000_000)
            } catch is CancellationError {
                cancelCancellationCount += 1
                throw CancellationError()
            }
        }
        if cancelThrowsCancellation { throw CancellationError() }
        try cancelResult.get()
    }

    func resumeEnqueue(with result: Result<NoteImportReceipt, NoteImportServiceError>) {
        guard let enqueueContinuation else { return }
        self.enqueueContinuation = nil
        enqueueContinuation.resume(with: result.mapError { $0 as Error })
    }

    func enqueueCount() -> Int { enqueuedRequestIDs.count }
    func enqueueRequestIDs() -> [String] { enqueuedRequestIDs }
    func detailIDs() -> [String] { requestedDetailIDs }
    func calls() -> [String] { callLog }
    func submittedFiles() -> [[NoteImportFile]] { enqueuedFiles }
    func didStartCancel() -> Bool { cancelStarted }
    func cancelCancellations() -> Int { cancelCancellationCount }
    func suspendedJobsStarts() -> Int { suspendedJobsStartCount }
    func jobsCancellations() -> Int { jobsCancellationCount }
}

private actor NoteImportSleeperSpy: NoteImportSleeping {
    private let immediate: Bool
    private var calls: [UInt64] = []
    private var continuations: [CheckedContinuation<Void, Error>] = []

    init(immediate: Bool = false) { self.immediate = immediate }

    func sleep(nanoseconds: UInt64) async throws {
        calls.append(nanoseconds)
        if immediate { return }
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }

    func resumeNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }

    func nanoseconds() -> [UInt64] { calls }
    func callCount() -> Int { calls.count }
}

private actor CancellableNoteImportSleeper: NoteImportSleeping {
    private var started = false
    private var cancellationCount = 0

    func sleep(nanoseconds: UInt64) async throws {
        started = true
        do {
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
        } catch is CancellationError {
            cancellationCount += 1
            throw CancellationError()
        }
    }

    func didStart() -> Bool { started }
    func cancellations() -> Int { cancellationCount }
}

private extension NoteImportReceipt {
    static func receipt(clientRequestID: String = "req_generated") -> Self {
        .init(
            jobID: "job_1",
            clientRequestID: clientRequestID,
            status: .queued,
            totalFiles: 1,
            acceptedFiles: 1,
            rejectedFiles: 0
        )
    }
}

private extension NoteImportJobSummary {
    static func fixture(
        jobID: String = "job_1",
        clientRequestID: String? = "req_generated",
        status: NoteImportJobStatus = .queued,
        createdAt: Date = Date(timeIntervalSince1970: 1)
    ) -> Self {
        .init(
            jobID: jobID,
            clientRequestID: clientRequestID,
            status: status,
            soulStatus: .notRequested,
            soulStatusReason: nil,
            totalFiles: 1,
            importedCount: 0,
            updatedCount: 0,
            skippedCount: 0,
            failedCount: 0,
            createdAt: createdAt,
            completedAt: nil,
            cancelRequestedAt: nil,
            cancelledAt: nil
        )
    }
}

private extension NoteImportJobDetail {
    static func fixture(
        jobID: String = "job_1",
        clientRequestID: String? = "req_generated",
        status: NoteImportJobStatus = .queued,
        soulStatus: NoteImportSoulStatus = .notRequested,
        totalFiles: Int = 1,
        importedCount: Int = 0,
        updatedCount: Int = 0,
        skippedCount: Int = 0,
        failedCount: Int = 0,
        items: [NoteImportJobItem] = []
    ) -> Self {
        .init(
            jobID: jobID,
            clientRequestID: clientRequestID,
            status: status,
            soulStatus: soulStatus,
            soulStatusReason: nil,
            totalFiles: totalFiles,
            importedCount: importedCount,
            updatedCount: updatedCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            errorMessage: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            completedAt: status.isTerminal ? Date(timeIntervalSince1970: 2) : nil,
            cancelRequestedAt: nil,
            cancelledAt: nil,
            items: items
        )
    }
}

private extension NoteImportJobItem {
    static func fixture(
        filename: String,
        assetID: String?,
        status: NoteImportItemStatus
    ) -> Self {
        .init(
            sourceKey: "source_\(filename)",
            originalFilename: filename,
            label: filename,
            originalFormat: .markdown,
            assetID: assetID,
            assetVersionID: nil,
            status: status,
            errorMessage: nil,
            processedAt: Date(timeIntervalSince1970: 2)
        )
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
