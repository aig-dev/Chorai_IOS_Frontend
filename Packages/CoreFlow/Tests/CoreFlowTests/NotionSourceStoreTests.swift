import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class NotionSourceStoreTests: XCTestCase {
    func testLoadPublishesCanonicalDisconnectedStatus() async {
        let status = NotionConnectionStatus(
            state: .disconnected,
            workspaceID: nil,
            workspaceName: nil
        )
        let service = NotionSourceServiceSpy(statuses: [.success(status)])
        let store = NotionSourceStore(service: service)

        store.load(actorID: "human_a")
        await waitUntil { store.statusPhase == .ready }

        XCTAssertEqual(store.actorID, "human_a")
        XCTAssertEqual(store.status, status)
        XCTAssertNil(store.inlineError)
    }

    func testDuplicateConnectIsSingleFlightAndPublishesIOSAuthorizationURL() async {
        let expected = URL(string: "https://api.notion.test/oauth?state=opaque")!
        let service = NotionSourceServiceSpy(
            authorizationURLs: [.init(delay: 120_000_000, result: .success(expected))]
        )
        let store = NotionSourceStore(service: service)
        store.load(actorID: "human_a")
        await waitUntil { store.statusPhase == .ready }

        store.connect()
        store.connect()
        await waitUntil { store.authorizationURL == expected }

        let clients = await service.authorizationClients()
        XCTAssertEqual(clients, [.ios])
        XCTAssertFalse(store.isConnecting)
        XCTAssertNil(store.inlineError)
    }

    func testAuthorizationCancellationIsNeutralAndSuccessReloadsCanonicalStatus() async {
        let disconnected = NotionConnectionStatus(state: .disconnected)
        let connected = NotionConnectionStatus(
            state: .connected,
            workspaceID: "workspace_1",
            workspaceName: "Chorai"
        )
        let service = NotionSourceServiceSpy(
            statuses: [.success(disconnected), .success(connected)],
            authorizationURLs: [
                .success(URL(string: "https://notion.test/first")!),
                .success(URL(string: "https://notion.test/second")!)
            ]
        )
        let store = NotionSourceStore(service: service)
        store.load(actorID: "human_a")
        await waitUntil { store.statusPhase == .ready }

        store.connect()
        await waitUntil { store.authorizationRequest != nil }
        let cancelledRequest = try! XCTUnwrap(store.authorizationRequest)

        store.authorizationCompleted(id: cancelledRequest.id, result: .cancelled)
        await Task.yield()
        XCTAssertEqual(store.status, disconnected)
        XCTAssertNil(store.inlineError)
        let cancellationRequestCount = await service.statusRequestCount()
        XCTAssertEqual(cancellationRequestCount, 1)

        store.connect()
        await waitUntil {
            guard let request = store.authorizationRequest else { return false }
            return request.id != cancelledRequest.id
        }
        let successfulRequest = try! XCTUnwrap(store.authorizationRequest)
        store.authorizationCompleted(id: successfulRequest.id, result: .success)
        await waitUntil { store.status == connected }
        let successRequestCount = await service.statusRequestCount()
        XCTAssertEqual(successRequestCount, 2)
    }

    func testProviderFailuresStayInlineAndRetainLastCommittedState() async {
        let connected = NotionConnectionStatus(
            state: .connected,
            workspaceID: "workspace_1",
            workspaceName: "Chorai"
        )
        let page = NotionPage(id: "page_committed", title: "Committed")
        let service = NotionSourceServiceSpy(
            statuses: [.success(connected), .failure(.provider)],
            authorizationURLs: [
                .init(result: .failure(.provider)),
                .success(URL(string: "https://notion.test/retry")!)
            ],
            pages: [.success([page]), .failure(.provider)]
        )
        let store = NotionSourceStore(service: service)
        store.load(actorID: "human_a")
        await waitUntil { store.status == connected }
        store.searchPages(query: nil)
        await waitUntil { store.pages == [page] }

        store.connect()
        await waitUntil { !store.isConnecting && store.inlineError != nil }
        XCTAssertEqual(store.status, connected)

        store.searchPages(query: "broken")
        await waitUntil { store.pagesPhase == .failed }
        XCTAssertEqual(store.pages, [page])

        store.connect()
        await waitUntil { store.authorizationRequest != nil }
        let request = try! XCTUnwrap(store.authorizationRequest)
        store.authorizationCompleted(id: request.id, result: .success)
        await waitUntil { store.statusPhase == .failed }
        XCTAssertEqual(store.status, connected)
    }

    func testPageSearchPassesQueryAndSelectionDeduplicatesInFirstSeenOrder() async {
        let pages = [
            NotionPage(id: "page_a", title: "A"),
            NotionPage(id: "page_b", title: "B")
        ]
        let service = NotionSourceServiceSpy(pages: [.success(pages)])
        let store = NotionSourceStore(service: service)
        store.load(actorID: "human_a")
        await waitUntil { store.statusPhase == .ready }

        store.searchPages(query: "roadmap")
        await waitUntil { store.pages == pages }
        store.setSelectedPageIDs(["page_b", "page_a", "page_b", "page_a"])

        let queries = await service.pageQueries()
        XCTAssertEqual(queries, ["roadmap"])
        XCTAssertEqual(store.selectedPageIDs, ["page_b", "page_a"])
    }

    func testImportEnqueuesDeduplicatedSelectionAndPollsUntilKnownTerminal() async {
        let receipt = NotionImportReceipt(jobID: "job_1", acceptedPageIDs: ["page_b", "page_a"])
        let unknown = NotionImportJob(
            id: "job_1",
            status: .init(rawValue: "provider_new_state"),
            totalPages: 2,
            completedPages: 0
        )
        let running = NotionImportJob(
            id: "job_1",
            status: .running,
            totalPages: 2,
            completedPages: 1
        )
        let complete = NotionImportJob(
            id: "job_1",
            status: .completed,
            totalPages: 2,
            completedPages: 2,
            importedAssetIDs: ["asset_a", "asset_b"]
        )
        let sleeper = ImmediateNotionSleeper()
        let clock = IncrementingNotionClock()
        let service = NotionSourceServiceSpy(
            receipts: [.success(receipt)],
            jobs: [.success(unknown), .success(running), .success(complete)]
        )
        let store = NotionSourceStore(
            service: service,
            sleeper: sleeper,
            clock: clock,
            pollInterval: 0.01
        )
        store.load(actorID: "human_a")
        await waitUntil { store.statusPhase == .ready }
        store.setSelectedPageIDs(["page_b", "page_a", "page_b"])

        store.startImport()
        await waitUntil { store.importJob == complete }

        let enqueueRequests = await service.enqueuedPageIDs()
        let jobRequests = await service.jobIDs()
        let sleepCount = await sleeper.requestCount()
        XCTAssertEqual(enqueueRequests, [["page_b", "page_a"]])
        XCTAssertEqual(jobRequests, ["job_1", "job_1", "job_1"])
        XCTAssertEqual(sleepCount, 2)
        XCTAssertNotNil(store.lastImportPolledAt)
        XCTAssertFalse(store.isImporting)
        XCTAssertNil(store.inlineError)
    }

    func testDisconnectIsSingleFlightAndReloadsCanonicalStatus() async {
        let connected = NotionConnectionStatus(state: .connected, workspaceID: "workspace_1")
        let disconnected = NotionConnectionStatus(state: .disconnected)
        let service = NotionSourceServiceSpy(
            statuses: [.success(connected), .success(disconnected)],
            disconnects: [.init(delay: 100_000_000, result: .success(()))]
        )
        let store = NotionSourceStore(service: service)
        store.load(actorID: "human_a")
        await waitUntil { store.status == connected }

        store.disconnect()
        store.disconnect()
        await waitUntil { store.status == disconnected }

        let disconnectCount = await service.disconnectRequestCount()
        XCTAssertEqual(disconnectCount, 1)
        XCTAssertFalse(store.isDisconnecting)
    }

    func testDisconnectFencesAnOlderInFlightStatusReload() async {
        let connected = NotionConnectionStatus(state: .connected, workspaceID: "workspace_1")
        let disconnected = NotionConnectionStatus(state: .disconnected)
        let service = NotionSourceServiceSpy(
            statuses: [
                .success(connected),
                .init(delay: 180_000_000, result: .success(connected)),
                .success(disconnected)
            ],
            disconnects: [.success(())]
        )
        let store = NotionSourceStore(service: service)
        store.load(actorID: "human_a")
        await waitUntil { store.status == connected }

        store.reloadStatus()
        await waitUntil { store.statusPhase == .loading }
        store.disconnect()
        await waitUntil { store.status == disconnected }
        try? await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertEqual(store.status, disconnected)
    }

    func testDisconnectAndImportFailuresRetainLastCommittedState() async {
        let connected = NotionConnectionStatus(state: .connected, workspaceID: "workspace_1")
        let terminal = NotionImportJob(
            id: "job_1",
            status: .completed,
            totalPages: 1,
            completedPages: 1,
            importedAssetIDs: ["asset_1"]
        )
        let service = NotionSourceServiceSpy(
            statuses: [.success(connected)],
            receipts: [
                .success(.init(jobID: "job_1", acceptedPageIDs: ["page_1"])),
                .failure(.provider)
            ],
            jobs: [.success(terminal)],
            disconnects: [.failure(.provider)]
        )
        let store = NotionSourceStore(service: service)
        store.load(actorID: "human_a")
        await waitUntil { store.status == connected }
        store.setSelectedPageIDs(["page_1"])
        store.startImport()
        await waitUntil { store.importJob == terminal }

        store.startImport()
        await waitUntil { !store.isImporting && store.importError != nil }
        store.disconnect()
        await waitUntil { !store.isDisconnecting && store.disconnectError != nil }

        XCTAssertEqual(store.importJob, terminal)
        XCTAssertEqual(store.status, connected)
    }

    func testConnectionAndJobStatusesPreserveUnknownRawValues() {
        let state = NotionConnectionState(rawValue: "provider_future_state")
        let job = NotionImportJobStatus(rawValue: "provider_future_job")

        XCTAssertEqual(state.rawValue, "provider_future_state")
        XCTAssertNil(state.knownValue)
        XCTAssertEqual(job.rawValue, "provider_future_job")
        XCTAssertNil(job.knownValue)
        XCTAssertFalse(job.isKnownTerminal)
    }

    func testDisconnectCancelsAndFencesEveryInFlightSourceCompletion() async {
        let connected = NotionConnectionStatus(state: .connected, workspaceID: "workspace_1")
        let disconnected = NotionConnectionStatus(state: .disconnected)
        let staleURL = URL(string: "https://stale.test/oauth")!
        let stalePage = NotionPage(id: "stale_page", title: "Stale")
        let staleReceipt = NotionImportReceipt(jobID: "stale_job", acceptedPageIDs: ["page_1"])
        let service = NotionSourceServiceSpy(
            statuses: [.success(connected), .success(disconnected)],
            authorizationURLs: [.init(delay: 160_000_000, result: .success(staleURL))],
            pages: [.init(delay: 160_000_000, result: .success([stalePage]))],
            receipts: [.init(delay: 160_000_000, result: .success(staleReceipt))],
            disconnects: [.success(())]
        )
        let store = NotionSourceStore(service: service)
        store.load(actorID: "human_a")
        await waitUntil { store.status == connected }
        store.setSelectedPageIDs(["page_1"])

        store.connect()
        store.searchPages(query: "stale")
        store.startImport()
        await Task.yield()
        store.disconnect()
        await waitUntil { store.status == disconnected }
        try? await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertNil(store.authorizationURL)
        XCTAssertTrue(store.pages.isEmpty)
        XCTAssertNil(store.importReceipt)
        XCTAssertNil(store.importJob)
        XCTAssertFalse(store.isConnecting)
        XCTAssertFalse(store.isImporting)
    }

    func testReloadStartedDuringDisconnectCannotOverwriteDisconnectStatus() async {
        let connected = NotionConnectionStatus(state: .connected, workspaceID: "workspace_1")
        let disconnected = NotionConnectionStatus(state: .disconnected)
        let service = NotionSourceServiceSpy(
            statuses: [
                .success(connected),
                .success(disconnected)
            ],
            disconnects: [.init(delay: 40_000_000, result: .success(()))]
        )
        let store = NotionSourceStore(service: service)
        store.load(actorID: "human_a")
        await waitUntil { store.status == connected }

        store.disconnect()
        store.reloadStatus()
        await waitUntil { store.status == disconnected }
        try? await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertEqual(store.status, disconnected)
        let statusCount = await service.statusRequestCount()
        XCTAssertEqual(statusCount, 2)
    }

    func testCallbackFromPriorActorDoesNotReloadCurrentActor() async {
        let actorA = NotionConnectionStatus(state: .disconnected, workspaceID: "actor_a")
        let actorB = NotionConnectionStatus(state: .disconnected, workspaceID: "actor_b")
        let unexpected = NotionConnectionStatus(state: .connected, workspaceID: "actor_b")
        let service = NotionSourceServiceSpy(
            statuses: [.success(actorA), .success(actorB), .success(unexpected)],
            authorizationURLs: [.success(URL(string: "https://notion.test/a")!)]
        )
        let store = NotionSourceStore(service: service)
        store.load(actorID: "human_a")
        await waitUntil { store.status == actorA }
        store.connect()
        await waitUntil { store.authorizationRequest != nil }
        let actorARequest = try! XCTUnwrap(store.authorizationRequest)

        store.load(actorID: "human_b")
        await waitUntil { store.status == actorB }
        store.authorizationCompleted(id: actorARequest.id, result: .success)
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(store.status, actorB)
        let statusCount = await service.statusRequestCount()
        XCTAssertEqual(statusCount, 2)
    }

    func testOldAndReplayedAuthorizationCallbacksAreIgnored() async {
        let disconnected = NotionConnectionStatus(state: .disconnected)
        let connected = NotionConnectionStatus(state: .connected, workspaceID: "workspace_1")
        let service = NotionSourceServiceSpy(
            statuses: [.success(disconnected), .success(connected)],
            authorizationURLs: [
                .success(URL(string: "https://notion.test/old")!),
                .success(URL(string: "https://notion.test/current")!)
            ]
        )
        let store = NotionSourceStore(service: service)
        store.load(actorID: "human_a")
        await waitUntil { store.status == disconnected }

        store.connect()
        await waitUntil { store.authorizationRequest != nil }
        let oldRequest = try! XCTUnwrap(store.authorizationRequest)
        store.authorizationCompleted(id: oldRequest.id, result: .cancelled)
        store.connect()
        await waitUntil {
            guard let request = store.authorizationRequest else { return false }
            return request.id != oldRequest.id
        }
        let currentRequest = try! XCTUnwrap(store.authorizationRequest)

        store.authorizationCompleted(id: oldRequest.id, result: .success)
        await Task.yield()
        XCTAssertEqual(store.authorizationRequest, currentRequest)
        let beforeCurrent = await service.statusRequestCount()
        XCTAssertEqual(beforeCurrent, 1)

        store.authorizationCompleted(id: currentRequest.id, result: .success)
        await waitUntil { store.status == connected }
        store.authorizationCompleted(id: currentRequest.id, result: .success)
        await Task.yield()

        let afterReplay = await service.statusRequestCount()
        XCTAssertEqual(afterReplay, 2)
        XCTAssertEqual(store.status, connected)
    }

    func testDistinctOverlappingPageQueriesPublishOnlyLatestResult() async {
        let stale = [NotionPage(id: "page_old", title: "Old")]
        let latest = [NotionPage(id: "page_new", title: "New")]
        let service = NotionSourceServiceSpy(
            pages: [
                .init(delay: 180_000_000, result: .success(stale)),
                .success(latest)
            ]
        )
        let store = NotionSourceStore(service: service)
        store.load(actorID: "human_a")
        await waitUntil { store.statusPhase == .ready }

        store.searchPages(query: "old")
        await Task.yield()
        store.searchPages(query: "new")
        await waitUntil { store.pages == latest }
        try? await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertEqual(store.pages, latest)
        let queries = await service.pageQueries()
        XCTAssertEqual(queries, ["old", "new"])
    }

    func testActorChangeFencesStaleCompletionsAcrossOperations() async {
        let actorA = NotionConnectionStatus(state: .connected, workspaceID: "old")
        let actorB = NotionConnectionStatus(state: .disconnected, workspaceID: "new")
        let stalePage = NotionPage(id: "stale", title: "Stale")
        let service = NotionSourceServiceSpy(
            statuses: [
                .init(delay: 160_000_000, result: .success(actorA)),
                .success(actorB)
            ],
            authorizationURLs: [
                .init(
                    delay: 160_000_000,
                    result: .success(URL(string: "https://stale.test")!)
                )
            ],
            pages: [.init(delay: 160_000_000, result: .success([stalePage]))]
        )
        let store = NotionSourceStore(service: service)

        store.load(actorID: "human_a")
        store.searchPages(query: nil)
        store.connect()
        await Task.yield()
        store.load(actorID: "human_b")
        await waitUntil { store.status == actorB }
        try? await Task.sleep(nanoseconds: 220_000_000)

        XCTAssertEqual(store.actorID, "human_b")
        XCTAssertEqual(store.status, actorB)
        XCTAssertTrue(store.pages.isEmpty)
        XCTAssertNil(store.authorizationURL)
    }

    func testSuspendedPollingDoesNotRetainStoreAndCancelsOnTeardown() async {
        let sleeper = SuspendedNotionSleeper()
        let service = NotionSourceServiceSpy(
            receipts: [.success(.init(jobID: "job_1", acceptedPageIDs: ["page_a"]))],
            jobs: [.success(.init(id: "job_1", status: .running, totalPages: 1, completedPages: 0))]
        )
        var store: NotionSourceStore? = NotionSourceStore(service: service, sleeper: sleeper)
        store?.load(actorID: "human_a")
        await waitUntil { store?.statusPhase == .ready }
        store?.setSelectedPageIDs(["page_a"])
        store?.startImport()
        while !(await sleeper.didStart()) { await Task.yield() }
        weak let weakStore = store

        store = nil
        await Task.yield()
        let released = weakStore == nil
        if !released { await sleeper.resume() }

        XCTAssertTrue(released)
        if released {
            await waitUntilAsync { await sleeper.cancellationCount() == 1 }
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline { await Task.yield() }
        XCTAssertTrue(predicate())
    }

    private func waitUntilAsync(
        timeout: TimeInterval = 2,
        _ predicate: @escaping () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await predicate()), Date() < deadline { await Task.yield() }
        let finalValue = await predicate()
        XCTAssertTrue(finalValue)
    }
}

private enum NotionSpyError: Error, Equatable, Sendable { case provider }

private struct NotionStep<Value: Sendable>: Sendable {
    let delay: UInt64
    let result: Result<Value, NotionSpyError>

    init(delay: UInt64 = 0, result: Result<Value, NotionSpyError>) {
        self.delay = delay
        self.result = result
    }

    static func success(_ value: Value) -> Self { .init(result: .success(value)) }
    static func failure(_ error: NotionSpyError) -> Self { .init(result: .failure(error)) }

    func value() async throws -> Value {
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        return try result.get()
    }
}

private actor NotionSourceServiceSpy: CoreNotionSourceServing {
    private var statuses: [NotionStep<NotionConnectionStatus>]
    private var authorizationURLs: [NotionStep<URL>]
    private var pageResults: [NotionStep<[NotionPage]>]
    private var receipts: [NotionStep<NotionImportReceipt>]
    private var jobs: [NotionStep<NotionImportJob>]
    private var disconnects: [NotionStep<Void>]
    private var clients: [NotionClient] = []
    private var queries: [String?] = []
    private var enqueueRequests: [[String]] = []
    private var jobRequests: [String] = []
    private var statusCount = 0
    private var disconnectCount = 0

    init(
        statuses: [NotionStep<NotionConnectionStatus>] = [.success(.init(state: .disconnected))],
        authorizationURLs: [NotionStep<URL>] = [],
        pages: [NotionStep<[NotionPage]>] = [],
        receipts: [NotionStep<NotionImportReceipt>] = [],
        jobs: [NotionStep<NotionImportJob>] = [],
        disconnects: [NotionStep<Void>] = []
    ) {
        self.statuses = statuses
        self.authorizationURLs = authorizationURLs
        pageResults = pages
        self.receipts = receipts
        self.jobs = jobs
        self.disconnects = disconnects
    }

    func status() async throws -> NotionConnectionStatus {
        statusCount += 1
        return try await pop(&statuses).value()
    }

    func authorizationURL(client: NotionClient) async throws -> URL {
        clients.append(client)
        return try await pop(&authorizationURLs).value()
    }

    func pages(query: String?) async throws -> [NotionPage] {
        queries.append(query)
        return try await pop(&pageResults).value()
    }

    func enqueue(pageIDs: [String]) async throws -> NotionImportReceipt {
        enqueueRequests.append(pageIDs)
        return try await pop(&receipts).value()
    }

    func job(id: String) async throws -> NotionImportJob {
        jobRequests.append(id)
        return try await pop(&jobs).value()
    }

    func disconnect() async throws {
        disconnectCount += 1
        try await pop(&disconnects).value()
    }

    func authorizationClients() -> [NotionClient] { clients }
    func pageQueries() -> [String?] { queries }
    func enqueuedPageIDs() -> [[String]] { enqueueRequests }
    func jobIDs() -> [String] { jobRequests }
    func statusRequestCount() -> Int { statusCount }
    func disconnectRequestCount() -> Int { disconnectCount }

    private func pop<T>(_ values: inout [NotionStep<T>]) -> NotionStep<T> {
        values.isEmpty ? .failure(.provider) : values.removeFirst()
    }
}

private actor ImmediateNotionSleeper: NotionSourceSleeping {
    private var count = 0
    func sleep(for interval: TimeInterval) async throws { count += 1 }
    func requestCount() -> Int { count }
}

private final class IncrementingNotionClock: NotionSourceClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 100)
    func now() -> Date {
        lock.withLock {
            value = value.addingTimeInterval(1)
            return value
        }
    }
}

private actor SuspendedNotionSleeper: NotionSourceSleeping {
    private var started = false
    private var cancellations = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func sleep(for interval: TimeInterval) async throws {
        started = true
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation = $0 }
        } onCancel: {
            Task { await self.cancelled() }
        }
        try Task.checkCancellation()
    }

    func didStart() -> Bool { started }
    func cancellationCount() -> Int { cancellations }
    func resume() { continuation?.resume(); continuation = nil }

    private func cancelled() {
        cancellations += 1
        continuation?.resume()
        continuation = nil
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
