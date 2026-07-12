//
//  ArcNoteApp.swift
//  ArcNote
//
//  Created by 海了个螺 on 2025/7/23.
//

import CoreFlow
import SwiftUI

#if DEBUG
import AuthenticationServices
import Combine
import Darwin
#endif

@main
struct ArcNoteApp: App {
    @StateObject private var chatHistoryDependency =
        ChatHistoryVisibilityDependency()
    #if DEBUG
    private let isAPIMigrationSmoke = APIMigrationSmokeRunner.isRequested
    private let isInterestUITestRoute = ProcessInfo.processInfo.arguments
        .contains("--ui-test-open-interests")
    private let isNotificationContractUITestRoute = ProcessInfo.processInfo.arguments
        .contains("--ui-test-notification-contract")
    private let isChoraContractUITestRoute = ProcessInfo.processInfo.arguments
        .contains("--ui-test-chora-contract")
    private let isChoraProfileUITestRoute = ProcessInfo.processInfo.arguments
        .contains("--ui-test-chora-profile")
    private let isSettingsUITestRoute = ProcessInfo.processInfo.arguments
        .contains("--ui-test-settings")
    private let isLibraryUITestRoute = ProcessInfo.processInfo.arguments
        .contains("--ui-test-library")
    private let isChatVisibilityUITestRoute = ProcessInfo.processInfo.arguments
        .contains("--ui-test-chat-visibility")
    private let isNotificationInboxUITestRoute = ProcessInfo.processInfo.arguments
        .contains("--ui-test-notification-inbox")
    private let profileUITestActorID: String? = {
        guard ProcessInfo.processInfo.arguments
            .contains("--ui-test-open-profile") else {
            return nil
        }
        return ProcessInfo.processInfo.environment[
            "CHORAI_UI_TEST_PROFILE_ACTOR_ID"
        ]
    }()
    #endif

    init() {
        #if DEBUG
        APIMigrationUITestSeed.applyIfPresent()
        APIMigrationSmokeRunner.startIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
            #if DEBUG
            if isAPIMigrationSmoke {
                Color.clear
            } else if isChoraProfileUITestRoute {
                NavigationStack {
                    ChoraProfileFixtureScreen()
                }
            } else if isSettingsUITestRoute {
                NavigationStack {
                    SettingsView()
                }
            } else if isLibraryUITestRoute {
                NavigationStack {
                    LibraryFixtureScreen()
                }
            } else if isChatVisibilityUITestRoute {
                ChatVisibilityFixtureScreen()
            } else if isChoraContractUITestRoute {
                ChoraProfileContractFixtureView()
            } else if isNotificationContractUITestRoute {
                NotificationContractFixtureView()
            } else if isNotificationInboxUITestRoute {
                NavigationStack {
                    NotificationView(
                        service: NotificationInboxFixtureService(),
                        actorID: "act_fixture",
                        usesFixtureDestinations: true
                    )
                }
            } else if isInterestUITestRoute {
                NavigationStack {
                    ChooseInterestsView()
                }
            } else if let profileUITestActorID,
                      !profileUITestActorID.isEmpty {
                NavigationStack {
                    UserProfileView(actorId: profileUITestActorID)
                }
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
            }
            .environmentObject(chatHistoryDependency)
        }
    }
}

#if DEBUG
private enum ChoraProfileFixtureMode: String {
    case loading
    case loaded
    case partialSave = "partial-save"
    case saving
    case growthError = "growth-error"
    case localImportActive = "local-import-active"
    case localImportDone = "local-import-done"
    case localImportFailure = "local-import-failure"
    case localImportCancelled = "local-import-cancelled"
    case notionDisconnected = "notion-disconnected"
    case notionConnected = "notion-connected"
    case notionConnectedError = "notion-connected-error"
    case notionStatusFailed = "notion-status-failed"
    case notionImportActive = "notion-import-active"
    case notionImportDone = "notion-import-done"
    case notionImportFailure = "notion-import-failure"
    case localInitialLoadFailure = "local-initial-load-failure"
    case localRelaunchAmbiguity = "local-relaunch-ambiguity"
    case localPreReceipt = "local-pre-receipt"
    case localCancelling = "local-cancelling"
    case localUnknown = "local-unknown"
    case notionConnecting = "notion-connecting"
    case notionUnknown = "notion-unknown"
    case notionUnknownImport = "notion-unknown-import"
    case inlineErrors = "inline-errors"
}

@MainActor
private struct ChoraProfileFixtureScreen: View {
    private let mode: ChoraProfileFixtureMode

    init() {
        mode = ChoraProfileFixtureMode(
            rawValue: ProcessInfo.processInfo.environment[
                "CHORAI_CHORA_PROFILE_FIXTURE_MODE"
            ] ?? "loaded"
        ) ?? .loaded
    }

    var body: some View {
        ChoraProfileView(
            humanActorID: "act_human_fixture",
            profileService: ChoraProfileFixtureService(mode: mode),
            noteImportService: ChoraNoteImportFixtureService(mode: mode),
            notionService: ChoraNotionFixtureService(mode: mode),
            noteImportPersistence: ChoraNoteImportFixturePersistence(
                requestID: mode.hasLocalImport ? "req_fixture" : nil
            ),
            noteImportSleeper: ChoraFixtureSleeper(),
            notionSleeper: ChoraFixtureNotionSleeper(),
            notionOAuthCoordinator: ChoraFixtureNotionOAuthCoordinator(),
            initialNoteImportFiles: mode == .localPreReceipt
                ? [Self.fixtureFile]
                : [],
            automaticallyStartNoteImport: mode == .localPreReceipt
        )
    }

    private static let fixtureFile = NoteImportFile(
        id: "fixture", sourceKey: "fixture", url: URL(fileURLWithPath: "/tmp/fixture.md"),
        filename: "fixture.md", label: "Fixture", format: .markdown, byteCount: 1
    )
}

private extension ChoraProfileFixtureMode {
    var hasLocalImport: Bool {
        self == .localImportActive
            || self == .localImportDone
            || self == .localImportFailure
            || self == .localImportCancelled
            || self == .localRelaunchAmbiguity
            || self == .localCancelling
            || self == .localUnknown
    }
}

private actor ChoraProfileFixtureService: CoreChoraProfileServing {
    private let mode: ChoraProfileFixtureMode
    private var displayName: String
    private var growthCalls = 0

    init(mode: ChoraProfileFixtureMode) {
        self.mode = mode
        displayName = mode == .partialSave ? "" : "Chora"
    }

    func identity(humanActorID: String) async throws -> ChoraIdentity {
        if mode == .loading {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        return ChoraIdentity(
            humanActorID: humanActorID,
            agentActorID: "act_agent_fixture",
            displayName: displayName,
            avatarURL: nil,
            preferredAddress: mode == .partialSave ? nil : "Avery"
        )
    }

    func growth(agentActorID: String) async throws -> ChoraGrowthSnapshot? {
        growthCalls += 1
        if mode == .growthError, growthCalls == 1 {
            throw ChoraProfileError.requestFailed
        }
        return ChoraGrowthSnapshot(
            version: "fixture",
            committedStage: ChoraGrowthStage(rawValue: 4),
            dimensions: zip(
                ChoraGrowthDimension.canonicalRenderOrder,
                [2.0, 4.0, 6.0, 8.0, 10.0, 12.0]
            ).map {
                ChoraGrowthDimensionValue(dimension: $0.0, value: $0.1)
            },
            computedAt: Date(timeIntervalSince1970: 1_786_320_000)
        )
    }

    func updateDisplayName(
        agentActorID: String,
        displayName: String
    ) async throws {
        if mode == .saving {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        self.displayName = displayName
    }

    func updatePreferredAddress(
        humanActorID: String,
        value: String?
    ) async throws {
        if mode == .partialSave {
            throw ChoraProfileError.requestFailed
        }
        if mode == .saving {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }

    func updateAvatar(
        agentActorID: String,
        avatar: ChoraAvatarDraft
    ) async throws {}
}

private actor ChoraNoteImportFixtureService: CoreNoteImportServing {
    private let mode: ChoraProfileFixtureMode

    init(mode: ChoraProfileFixtureMode) {
        self.mode = mode
    }

    func enqueue(
        files: [NoteImportFile],
        clientRequestID: String
    ) async throws -> NoteImportReceipt {
        if mode == .localPreReceipt {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        return NoteImportReceipt(
            jobID: "job_fixture",
            clientRequestID: clientRequestID,
            status: .queued,
            totalFiles: files.count,
            acceptedFiles: files.count,
            rejectedFiles: 0
        )
    }

    func jobs(limit: Int) async throws -> [NoteImportJobSummary] {
        if mode == .inlineErrors || mode == .localInitialLoadFailure {
            throw NoteImportServiceError.requestFailed(code: "fixture")
        }
        if mode == .localRelaunchAmbiguity { return [] }
        guard mode.hasLocalImport else { return [] }
        let detail = makeDetail()
        return [
            NoteImportJobSummary(
                jobID: detail.jobID,
                clientRequestID: detail.clientRequestID,
                status: detail.status,
                soulStatus: detail.soulStatus,
                soulStatusReason: detail.soulStatusReason,
                totalFiles: detail.totalFiles,
                importedCount: detail.importedCount,
                updatedCount: detail.updatedCount,
                skippedCount: detail.skippedCount,
                failedCount: detail.failedCount,
                createdAt: detail.createdAt,
                completedAt: detail.completedAt,
                cancelRequestedAt: detail.cancelRequestedAt,
                cancelledAt: detail.cancelledAt
            )
        ]
    }

    func job(id: String) async throws -> NoteImportJobDetail {
        makeDetail()
    }

    func cancel(id: String) async throws {
        if mode == .localCancelling {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }

    private func makeDetail() -> NoteImportJobDetail {
        let status: NoteImportJobStatus
        let soul: NoteImportSoulStatus
        let imported: Int
        let failed: Int
        let errorMessage: String?
        switch mode {
        case .localImportCancelled:
            status = .cancelled
            soul = .cancelled
            imported = 0
            failed = 0
            errorMessage = nil
        case .localUnknown:
            status = .init(rawValue: "future_import_state")
            soul = .notRequested
            imported = 0
            failed = 0
            errorMessage = nil
        case .localImportActive, .localCancelling:
            status = .running
            soul = .notRequested
            imported = 1
            failed = 0
            errorMessage = nil
        case .localImportFailure:
            status = .failed
            soul = .failed
            imported = 1
            failed = 1
            errorMessage = "One file couldn’t be imported."
        default:
            status = .done
            soul = .done
            imported = 2
            failed = 0
            errorMessage = nil
        }
        let date = Date(timeIntervalSince1970: 1_786_320_000)
        return NoteImportJobDetail(
            jobID: "job_fixture",
            clientRequestID: "req_fixture",
            status: status,
            soulStatus: soul,
            soulStatusReason: nil,
            totalFiles: 2,
            importedCount: imported,
            updatedCount: 0,
            skippedCount: 0,
            failedCount: failed,
            errorMessage: errorMessage,
            createdAt: date,
            completedAt: status.isTerminal ? date : nil,
            cancelRequestedAt: nil,
            cancelledAt: status == .cancelled ? date : nil,
            items: [
                NoteImportJobItem(
                    sourceKey: "source_fixture",
                    originalFilename: "long-accessible-fixture-name.md",
                    label: "Fixture",
                    originalFormat: .markdown,
                    assetID: imported > 0 ? "ast_fixture" : nil,
                    assetVersionID: nil,
                    status: mode == .localUnknown
                        ? .init(rawValue: "future_item_state")
                        : mode == .localImportCancelled ? .skipped
                        : failed > 0 ? .failed : .imported,
                    errorMessage: errorMessage,
                    processedAt: date
                )
            ]
        )
    }
}

@MainActor
private struct LibraryFixtureScreen: View {
    @State private var showSideMenu = false
    private let refreshID = UUID()

    var body: some View {
        HomeView(
            showSideMenu: $showSideMenu,
            refreshID: refreshID
        )
    }
}

private final class ChoraNoteImportFixturePersistence:
    NoteImportRequestIDPersisting,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var requestID: String?

    init(requestID: String?) {
        self.requestID = requestID
    }

    func load(actorID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return requestID
    }

    func save(_ requestID: String, actorID: String) {
        lock.lock()
        self.requestID = requestID
        lock.unlock()
    }

    func clear(actorID: String) {
        lock.lock()
        requestID = nil
        lock.unlock()
    }
}

private struct ChoraFixtureSleeper: NoteImportSleeping {
    func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: 60_000_000_000)
    }
}

private actor ChoraNotionFixtureService: CoreNotionSourceServing {
    private let mode: ChoraProfileFixtureMode
    private var statusCalls = 0

    init(mode: ChoraProfileFixtureMode) {
        self.mode = mode
    }

    func status() async throws -> NotionConnectionStatus {
        statusCalls += 1
        if mode == .inlineErrors || mode == .notionStatusFailed {
            throw NotionSourceError.requestFailed
        }
        if mode == .notionConnecting {
            return NotionConnectionStatus(state: .connecting)
        }
        if mode == .notionUnknown {
            return NotionConnectionStatus(
                state: .init(rawValue: "future_connection")
            )
        }
        if mode == .notionConnected || mode == .notionConnectedError
            || mode == .notionImportActive || mode == .notionImportDone
            || mode == .notionImportFailure || mode == .notionUnknownImport {
            return NotionConnectionStatus(
                state: .connected,
                workspaceID: "workspace_fixture",
                workspaceName: "Chorai Workspace",
                pageStatuses: mode == .notionUnknownImport
                    ? [.init(pageID: "page_fixture", assetID: nil, status: .init(rawValue: "future_sync"), lastSyncedAt: nil, errorMessage: nil, retryCount: 0)]
                    : ((mode == .notionImportDone || mode == .notionImportFailure) && statusCalls > 1
                        ? [.init(pageID: "page_fixture", assetID: "ast_fixture", status: .synced, lastSyncedAt: "now", errorMessage: nil, retryCount: 0)]
                        : [])
            )
        }
        return NotionConnectionStatus(state: .disconnected)
    }

    func authorizationURL(client: NotionClient) async throws -> URL {
        URL(string: "https://notion.example.test/connect")!
    }

    func pages(query: String?) async throws -> [NotionPage] {
        if mode == .notionConnectedError {
            throw NotionSourceError.requestFailed
        }
        return [NotionPage(id: "page_fixture", title: "A long Notion page title")]
    }

    func enqueue(pageIDs: [String]) async throws -> NotionImportReceipt {
        NotionImportReceipt(
            jobID: "notion_job_fixture",
            acceptedPageIDs: pageIDs
        )
    }

    func job(id: String) async throws -> NotionImportJob {
        let status: NotionImportJobStatus = mode == .notionUnknownImport
            ? .init(rawValue: "provider_future_job")
            : mode == .notionImportActive
                ? .running
                : mode == .notionImportFailure ? .failed : .done
        return NotionImportJob(
            id: id,
            status: status,
            imported: 1,
            updated: 2,
            skipped: 3,
            failures: mode == .notionImportFailure
                ? [NotionPageFailure(pageID: "page_fixture", reason: "Fixture failure")]
                : []
        )
    }

    func disconnect() async throws {}
}

@MainActor
private final class ChoraFixtureNotionOAuthCoordinator:
    NotionOAuthCoordinating
{
    private var cancelled = false

    func authorize(
        request: NotionAuthorizationRequest,
        completion: @escaping (UUID, NotionAuthorizationResult) -> Void
    ) {
        cancelled = false
        DispatchQueue.main.async { [weak self] in
            guard self?.cancelled == false else { return }
            completion(request.id, .cancelled)
        }
    }

    func cancel() {
        cancelled = true
    }
}

@MainActor
private final class ChatVisibilityFixtureService:
    ObservableObject,
    ChatConversationFetching,
    ChatDetailFetching
{
    private let humanActorID: String
    private let conversationID: String
    private var hasPostCutoffMessage = false
    private let conversationSubject:
        CurrentValueSubject<ConversationsResponse, Never>

    init(humanActorID: String, conversationID: String) {
        self.humanActorID = humanActorID
        self.conversationID = conversationID
        conversationSubject = CurrentValueSubject(
            Self.conversations(
                humanActorID: humanActorID,
                conversationID: conversationID,
                hasPostCutoffMessage: false
            )
        )
    }

    func publishPostCutoffMessage() {
        hasPostCutoffMessage = true
        conversationSubject.send(
            Self.conversations(
                humanActorID: humanActorID,
                conversationID: conversationID,
                hasPostCutoffMessage: true
            )
        )
    }

    func getConversations() -> AnyPublisher<ConversationsResponse, NetworkError> {
        conversationSubject
            .setFailureType(to: NetworkError.self)
            .eraseToAnyPublisher()
    }

    func getConversationDetail(
        conversationId: String
    ) -> AnyPublisher<ChatDetailResponse, NetworkError> {
        Just(
            ChatDetailResponse(
                success: true,
                data: ChatDetailConversation(
                    id: conversationId,
                    partner: ChatPartner(
                        id: "partner_\(humanActorID)",
                        username: "Fixture Partner",
                        avatarUrl: nil
                    ),
                    createdAt: Self.beforeTimestamp,
                    lastMessageTime: hasPostCutoffMessage
                        ? Self.afterTimestamp
                        : Self.beforeTimestamp
                )
            )
        )
        .setFailureType(to: NetworkError.self)
        .eraseToAnyPublisher()
    }

    func getMessages(
        conversationId: String,
        page: Int,
        perPage: Int
    ) -> AnyPublisher<MessagesListResponse, NetworkError> {
        var messages = [
            APIChatMessage(
                id: "message_before",
                content: "Before cutoff",
                senderId: "partner_\(humanActorID)",
                receiverId: humanActorID,
                createdAt: Self.beforeTimestamp,
                messageType: "text",
                isFromCurrentUser: false
            )
        ]
        if hasPostCutoffMessage {
            messages.append(
                APIChatMessage(
                    id: "message_after",
                    content: "After cutoff",
                    senderId: "partner_\(humanActorID)",
                    receiverId: humanActorID,
                    createdAt: Self.afterTimestamp,
                    messageType: "text",
                    isFromCurrentUser: false
                )
            )
        }
        return Just(
            MessagesListResponse(
                success: true,
                data: MessagesListData(
                    items: messages,
                    pagination: Self.pagination(total: messages.count)
                )
            )
        )
        .setFailureType(to: NetworkError.self)
        .eraseToAnyPublisher()
    }

    func sendMessage(
        conversationId: String,
        request: SendMessageRequest
    ) -> AnyPublisher<SendMessageResponse, NetworkError> {
        Empty<SendMessageResponse, NetworkError>(completeImmediately: true)
            .eraseToAnyPublisher()
    }

    private static func conversations(
        humanActorID: String,
        conversationID: String,
        hasPostCutoffMessage: Bool
    ) -> ConversationsResponse {
        let timestamp = hasPostCutoffMessage ? afterTimestamp : beforeTimestamp
        let messageID = hasPostCutoffMessage ? "message_after" : "message_before"
        return ConversationsResponse(
            success: true,
            data: ConversationsData(
                items: [
                    Conversation(
                        id: conversationID,
                        partner: ChatPartner(
                            id: "partner_\(humanActorID)",
                            username: "Fixture Partner",
                            avatarUrl: nil
                        ),
                        lastMessage: LastMessage(
                            content: messageID,
                            createdAt: timestamp,
                            senderId: "partner_\(humanActorID)"
                        ),
                        unreadCount: 0,
                        createdAt: beforeTimestamp
                    )
                ],
                pagination: pagination(total: 1)
            )
        )
    }

    private static func pagination(total: Int) -> ChatPagination {
        ChatPagination(
            page: 1,
            perPage: 20,
            total: total,
            pages: 1,
            hasNext: false,
            hasPrev: false
        )
    }

    private static let beforeTimestamp = "2020-01-01T00:00:00Z"
    private static let afterTimestamp = "2099-01-01T00:00:00Z"
}

@MainActor
private struct ChatVisibilityFixtureScreen: View {
    @StateObject private var visibilityDependency =
        ChatHistoryVisibilityDependency(
            visibility: ChatHistoryVisibility(
                persistence: ChatVisibilityFixturePersistence()
            )
        )
    @StateObject private var humanAService = ChatVisibilityFixtureService(
        humanActorID: "human_a",
        conversationID: "conversation_before"
    )
    @StateObject private var humanBService = ChatVisibilityFixtureService(
        humanActorID: "human_b",
        conversationID: "conversation_other_actor"
    )

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                NavigationLink("Open current actor chat") {
                    ChatView(
                        showSideMenu: .constant(false),
                        humanActorID: "human_a",
                        conversationFetcher: humanAService,
                        detailFetcher: humanAService
                    )
                }
                .accessibilityIdentifier("chat.fixture.open-list")

                NavigationLink("Open other actor chat") {
                    ChatView(
                        showSideMenu: .constant(false),
                        humanActorID: "human_b",
                        conversationFetcher: humanBService,
                        detailFetcher: humanBService
                    )
                }
                .accessibilityIdentifier("chat.fixture.open-other-list")

                NavigationLink("Open clear chat history") {
                    ChoraChatHistorySection(
                        humanActorID: "human_a",
                        visibility: visibilityDependency,
                        now: { Date() }
                    )
                    .padding(20)
                }
                .accessibilityIdentifier("chat.fixture.open-clear")

                Button("Publish post-cutoff message") {
                    humanAService.publishPostCutoffMessage()
                }
                .accessibilityIdentifier("chat.fixture.publish-post-cutoff")
            }
        }
        .environmentObject(visibilityDependency)
    }
}

private final class ChatVisibilityFixturePersistence:
    ChatHistoryCutoffPersisting,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [String: Date] = [:]

    func cutoffRecord(actorID: String) -> ChatHistoryCutoffRecord {
        lock.lock()
        defer { lock.unlock() }
        return values[actorID].map(ChatHistoryCutoffRecord.valid) ?? .missing
    }

    func saveCutoff(_ date: Date, actorID: String) {
        lock.lock()
        values[actorID] = date
        lock.unlock()
    }
}

private struct ChoraFixtureNotionSleeper: NotionSourceSleeping {
    func sleep(for interval: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: 60_000_000_000)
    }
}

private actor NotificationInboxFixtureService: CoreNotificationServing {
    private enum Mode: String {
        case loaded
        case empty
        case markReadFailure = "mark-read-failure"
    }

    private let mode: Mode
    private var readIDs: Set<String> = ["ntf_like"]

    init() {
        mode = Mode(
            rawValue: ProcessInfo.processInfo.environment[
                "CHORAI_NOTIFICATION_FIXTURE_MODE"
            ] ?? "loaded"
        ) ?? .loaded
    }

    func notifications(page: Int, perPage: Int) async throws -> NotificationPage {
        guard mode != .empty else {
            return NotificationPage(
                items: [],
                page: page,
                perPage: perPage,
                total: 0,
                unreadCount: 0
            )
        }

        let items = Self.fixtureItems.map { item -> CommunityNotification in
            var item = item
            item.isRead = readIDs.contains(item.id)
            return item
        }
        return NotificationPage(
            items: page == 1 ? items : [],
            page: page,
            perPage: perPage,
            total: items.count,
            unreadCount: items.filter { !$0.isRead }.count
        )
    }

    func markRead(notificationID: String) async throws {
        if mode == .markReadFailure {
            throw NotificationInboxError.transport(code: "fixture_mark_read")
        }
        readIDs.insert(notificationID)
    }

    private static let fixtureItems: [CommunityNotification] = [
        CommunityNotification(
            id: "ntf_follow",
            kind: .follow,
            displayText: "Mira followed you",
            sourceActor: NotificationSourceActor(
                actorID: "act_source",
                username: "Mira",
                avatarURL: nil
            ),
            target: .actor("act_source"),
            isRead: false,
            createdAt: Date().addingTimeInterval(-60)
        ),
        CommunityNotification(
            id: "ntf_like",
            kind: .like,
            displayText: "Mira liked your card",
            sourceActor: NotificationSourceActor(
                actorID: "act_source",
                username: "Mira",
                avatarURL: nil
            ),
            target: .asset("ast_card"),
            isRead: true,
            createdAt: Date().addingTimeInterval(-120)
        ),
        CommunityNotification(
            id: "ntf_system",
            kind: .system,
            displayText: "Your weekly knowledge review is ready",
            sourceActor: nil,
            target: .legacy,
            isRead: false,
            createdAt: Date().addingTimeInterval(-180)
        )
    ]
}

private struct NotificationContractFixtureView: View {
    private struct Values {
        let actor: String
        let asset: String
        let legacy: String
        let unreadCount: String
    }

    private let result: Result<Values, Error>

    init() {
        do {
            let response = try JSONDecoder().decode(
                NotificationInboxResponse.self,
                from: Data(Self.fixtureJSON.utf8)
            )
            let page = try NetworkNotificationService.map(response: response)
            let actor = page.items.compactMap { item -> String? in
                guard case .actor(let id) = item.target else { return nil }
                return id
            }.first ?? "missing"
            let asset = page.items.compactMap { item -> String? in
                guard case .asset(let id) = item.target else { return nil }
                return id
            }.first ?? "missing"
            let legacy = page.items.contains(where: { $0.target == .legacy })
                ? "legacy" : "missing"
            result = .success(Values(
                actor: actor,
                asset: asset,
                legacy: legacy,
                unreadCount: String(page.unreadCount)
            ))
        } catch {
            result = .failure(error)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            switch result {
            case .success(let values):
                fixtureValue(values.actor, id: "notification.contract.actor")
                fixtureValue(values.asset, id: "notification.contract.asset")
                fixtureValue(values.legacy, id: "notification.contract.legacy")
                fixtureValue(
                    values.unreadCount,
                    id: "notification.contract.unread-count"
                )
            case .failure(let error):
                Text(String(describing: error))
                    .accessibilityIdentifier("notification.contract.error")
            }
        }
    }

    private func fixtureValue(_ value: String, id: String) -> some View {
        Text(value)
            .accessibilityIdentifier(id)
    }

    private static let fixtureJSON = #"""
    {
      "success": true,
      "message": null,
      "data": [
        {
          "notification_id": "ntf_follow",
          "source_type": "FoLlOw",
          "payload_ref": "Mira followed you",
          "is_read": false,
          "created_at": "2026-07-12T01:02:03.456Z",
          "display_text": "Mira followed you",
          "source_actor": {
            "actor_id": "act_source",
            "username": "Mira",
            "avatar_url": null
          },
          "target": {"type": "ACTOR", "id": "act_source"}
        },
        {
          "notification_id": "ntf_like",
          "source_type": "LIKE",
          "payload_ref": "Mira liked your card",
          "is_read": true,
          "created_at": "2026-07-12T01:02:02Z",
          "display_text": "Mira liked your card",
          "source_actor": null,
          "target": {"type": "ASSET", "id": "ast_1"}
        },
        {
          "notification_id": "ntf_legacy",
          "source_type": "unknown",
          "payload_ref": "Legacy notice",
          "is_read": false,
          "created_at": "2026-07-12T01:02:01Z",
          "display_text": null,
          "source_actor": null,
          "target": {"type": "MYSTERY", "id": "unsafe"}
        }
      ],
      "meta": {"total": 3, "page": 1, "per_page": 20},
      "unread_count": 2
    }
    """#
}

private final class ChoraScopeContractRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ value: String) {
        lock.lock()
        storedValues.append(value)
        lock.unlock()
    }
}

private final class ChoraScopeContractAccessor:
    SecurityScopedResourceAccessing,
    @unchecked Sendable
{
    private let allowedPaths: [String: Bool]
    private let recorder: ChoraScopeContractRecorder
    private let lock = NSLock()
    private var storedAcquireCount = 0
    private var storedReleaseCount = 0
    private var activePaths: Set<String> = []

    init(
        allowedPaths: [String: Bool],
        recorder: ChoraScopeContractRecorder
    ) {
        self.allowedPaths = allowedPaths
        self.recorder = recorder
    }

    var acquireCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedAcquireCount
    }

    var releaseCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedReleaseCount
    }

    func startAccessing(_ url: URL) -> Bool {
        lock.lock()
        storedAcquireCount += 1
        let allowed = allowedPaths[url.lastPathComponent] ?? false
        if allowed { activePaths.insert(url.path) }
        lock.unlock()
        recorder.append("acquire:\(url.deletingPathExtension().lastPathComponent)")
        return allowed
    }

    func stopAccessing(_ url: URL) {
        lock.lock()
        storedReleaseCount += 1
        activePaths.remove(url.path)
        lock.unlock()
        recorder.append("release:\(url.deletingPathExtension().lastPathComponent)")
    }

    func isAccessing(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activePaths.contains(url.path)
    }
}

private final class ChoraScopeContractMetadataReader:
    NoteImportFileMetadataReading,
    @unchecked Sendable
{
    enum Behavior {
        case size(Int64)
        case unavailable
    }

    private let behavior: Behavior
    private let accessor: ChoraScopeContractAccessor
    private let recorder: ChoraScopeContractRecorder

    init(
        behavior: Behavior,
        accessor: ChoraScopeContractAccessor,
        recorder: ChoraScopeContractRecorder
    ) {
        self.behavior = behavior
        self.accessor = accessor
        self.recorder = recorder
    }

    func byteCount(for file: NoteImportFile) throws -> Int64 {
        guard accessor.isAccessing(file.url) else {
            throw NoteImportFileMetadataError.unavailable
        }
        recorder.append(
            "coordinate:\(file.url.deletingPathExtension().lastPathComponent)"
        )
        switch behavior {
        case .size(let size): return size
        case .unavailable: throw NoteImportFileMetadataError.unavailable
        }
    }
}

private final class ChoraScopeContractUploader:
    NoteImportUploading,
    @unchecked Sendable
{
    enum Behavior {
        case unexpected
        case cancellable(
            started: NoteImportUploadTermination,
            handle: ChoraContractUploadHandle
        )
    }

    private let behavior: Behavior
    private let recorder: ChoraScopeContractRecorder
    private let lock = NSLock()
    private var storedUploadCount = 0

    init(behavior: Behavior, recorder: ChoraScopeContractRecorder) {
        self.behavior = behavior
        self.recorder = recorder
    }

    var uploadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedUploadCount
    }

    func enqueue(
        parts: [NoteImportUploadPart],
        clientRequestID: String,
        termination: NoteImportUploadTermination
    ) -> AnyPublisher<NoteImportUploadTransportResult, NetworkError> {
        Deferred { [behavior, recorder, lock] in
            lock.lock()
            self.storedUploadCount += 1
            lock.unlock()
            recorder.append("upload")

            switch behavior {
            case .unexpected:
                termination.signal()
                return Fail<NoteImportUploadTransportResult, NetworkError>(
                    error: .unknown
                )
                .eraseToAnyPublisher()
            case .cancellable(let started, let handle):
                started.signal()
                let upstream = Empty<
                    NoteImportUploadTransportResult,
                    NetworkError
                >(
                    completeImmediately: false
                )
                .eraseToAnyPublisher()
                return MultipartUploadPublisherBuilder.publisher(
                    handle: handle,
                    upstream: upstream,
                    termination: termination
                )
            }
        }
        .eraseToAnyPublisher()
    }
}

private final class ChoraContractUploadHandle:
    MultipartUploadHandling,
    @unchecked Sendable
{
    let cancellationObserved = NoteImportUploadTermination()

    private let recorder: ChoraScopeContractRecorder
    private let lock = NSLock()
    private var terminalCallback: (@Sendable () -> Void)?

    init(recorder: ChoraScopeContractRecorder) {
        self.recorder = recorder
    }

    func cancel() {
        recorder.append("cancel")
        cancellationObserved.signal()
    }

    func observeTermination(
        _ callback: @escaping @Sendable () -> Void
    ) {
        lock.lock()
        terminalCallback = callback
        lock.unlock()
    }

    func reportTerminalResponse() {
        recorder.append("terminal")
        lock.lock()
        let callback = terminalCallback
        lock.unlock()
        callback?()
    }
}

private struct ChoraProfileContractFixtureView: View {
    @State private var result: Result<[String: String], Error>

    init() {
        let initialResult: Result<[String: String], Error>
        do {
            let decoder = JSONDecoder()
            let agentProfile = try decoder.decode(
                ChoraDataEnvelope<ChoraAgentProfileResponse>.self,
                from: Data(Self.agentProfileJSON.utf8)
            )
            let agentUsers = try decoder.decode(
                ChoraDataEnvelope<ChoraAgentUsersResponse>.self,
                from: Data(Self.agentUsersJSON.utf8)
            )
            let ownProfile = try decoder.decode(
                ChoraDataEnvelope<ChoraOwnProfileResponse>.self,
                from: Data(Self.ownProfileJSON.utf8)
            )
            let identity = try NetworkChoraProfileService.mapIdentity(
                agentProfile: agentProfile.data,
                agentUsers: agentUsers.data,
                ownProfile: ownProfile.data,
                expectedHumanActorID: "act_human_contract"
            )

            let growthResponse = try decoder.decode(
                ChoraGrowthViewEnvelope.self,
                from: Data(Self.growthJSON.utf8)
            )
            let growth = try NetworkChoraProfileService.mapGrowth(
                growthResponse.growthView,
                expectedAgentActorID: identity.agentActorID
            )
            let growthValues = Dictionary(uniqueKeysWithValues:
                growth.dimensions.map {
                    ($0.dimension.rawValue, String($0.value))
                }
            )

            let importReceiptResponse = try decoder.decode(
                NoteImportEnqueueResponse.self,
                from: Data(Self.importReceiptJSON.utf8)
            )
            let importReceipt = NetworkNoteImportService.mapReceipt(
                importReceiptResponse
            )
            let importListResponse = try decoder.decode(
                NoteImportJobListResponse.self,
                from: Data(Self.importListJSON.utf8)
            )
            let importList = try NetworkNoteImportService.mapJobs(
                importListResponse
            )
            let importDetailResponse = try decoder.decode(
                NoteImportJobDetailResponse.self,
                from: Data(Self.importDetailJSON.utf8)
            )
            let importDetail = try NetworkNoteImportService.mapJob(
                importDetailResponse
            )
            guard let importItem = importDetail.items.first else {
                throw FixtureError.missingImportItem
            }

            let notionStatusResponse = try decoder.decode(
                NotionStatusResponse.self,
                from: Data(Self.notionStatusJSON.utf8)
            )
            let notionStatus = NetworkNotionSourceService.mapStatus(
                notionStatusResponse
            )
            let notionConnectResponse = try decoder.decode(
                NotionConnectResponse.self,
                from: Data(Self.notionConnectJSON.utf8)
            )
            let notionAuthorization = try NetworkNotionSourceService
                .mapAuthorization(notionConnectResponse)
            let notionDisconnectResponse = try decoder.decode(
                NotionDisconnectResponse.self,
                from: Data(Self.notionDisconnectJSON.utf8)
            )
            try NetworkNotionSourceService.validateDisconnect(
                notionDisconnectResponse
            )
            let notionPagesResponse = try decoder.decode(
                NotionPagesResponse.self,
                from: Data(Self.notionPagesJSON.utf8)
            )
            let notionPages = NetworkNotionSourceService.mapPages(
                notionPagesResponse
            )
            let notionReceiptResponse = try decoder.decode(
                NotionEnqueueResponse.self,
                from: Data(Self.notionReceiptJSON.utf8)
            )
            let notionReceipt = NetworkNotionSourceService.mapReceipt(
                notionReceiptResponse,
                acceptedPageIDs: notionPages.map(\.id)
            )
            let notionJobResponse = try decoder.decode(
                NotionImportJobResponse.self,
                from: Data(Self.notionJobJSON.utf8)
            )
            let notionJob = NetworkNotionSourceService.mapJob(
                notionJobResponse
            )
            guard let notionPage = notionPages.first else {
                throw FixtureError.missingNotionPage
            }
            guard let notionPageStatus = notionStatus.pageStatuses.first else {
                throw FixtureError.missingNotionPageStatus
            }

            var values = Self.requestContractValues()
            values.merge(Self.platformContractValues()) { _, new in new }

            let identityValues: [String: String] = [
                "chora.contract.human-actor-id": identity.humanActorID,
                "chora.contract.agent-actor-id": identity.agentActorID,
                "chora.contract.preferred-address": identity.preferredAddress ?? "nil",
                "chora.contract.avatar-url": identity.avatarURL ?? "nil"
            ]
            values.merge(identityValues) { _, new in new }

            let growthContractValues: [String: String] = [
                "chora.contract.growth-stage": String(growth.committedStage.rawValue),
                "chora.contract.growth.curiosity": growthValues["curiosity"] ?? "nil",
                "chora.contract.growth.insight": growthValues["insight"] ?? "nil",
                "chora.contract.growth.creativity": growthValues["creativity"] ?? "nil",
                "chora.contract.growth.empathy": growthValues["empathy"] ?? "nil",
                "chora.contract.growth.judgment": growthValues["judgment"] ?? "nil",
                "chora.contract.growth.resonance": growthValues["resonance"] ?? "nil"
            ]
            values.merge(growthContractValues) { _, new in new }

            let importNullableFields: [String?] = [
                importDetail.soulStatusReason,
                importDetail.errorMessage,
                importDetail.completedAt.map(String.init(describing:)),
                importDetail.cancelRequestedAt.map(String.init(describing:)),
                importDetail.cancelledAt.map(String.init(describing:)),
                importItem.assetVersionID,
                importItem.errorMessage
            ]
            let importValues: [String: String] = [
                "chora.contract.import.client-request-id": importReceipt.clientRequestID ?? "nil",
                "chora.contract.import.job-id": importReceipt.jobID,
                "chora.contract.import.total-files": String(importReceipt.totalFiles),
                "chora.contract.import.imported-count": String(importDetail.importedCount),
                "chora.contract.import.asset-id": importItem.assetID ?? "nil",
                "chora.contract.import.nullable-fields": importNullableFields
                    .map { $0 ?? "nil" }.joined(separator: ","),
                "chora.contract.import.unknown-status": importList.first?.status.rawValue ?? "nil",
                "chora.contract.import.unknown-soul-status": importList.first?.soulStatus.rawValue ?? "nil"
            ]
            values.merge(importValues) { _, new in new }

            let notionValues: [String: String] = [
                "chora.contract.notion.workspace-id": notionStatus.workspaceID ?? "nil",
                "chora.contract.notion.page-id": notionPage.id,
                "chora.contract.notion.enqueue-job-id": notionReceipt.jobID,
                "chora.contract.notion.job-id": notionJob.id,
                "chora.contract.notion.nullable-fields": [
                    notionStatus.workspaceName,
                    notionPageStatus.assetID
                ].map { $0 ?? "nil" }.joined(separator: ","),
                "chora.contract.notion.unknown-job-status": notionJob.status.rawValue,
                "chora.contract.notion.unknown-page-status": notionPageStatus.status.rawValue,
                "chora.contract.notion.page-sync-fields": [
                    notionPageStatus.pageID,
                    notionPageStatus.assetID ?? "nil",
                    notionPageStatus.status.rawValue,
                    notionPageStatus.lastSyncedAt ?? "nil",
                    notionPageStatus.errorMessage ?? "nil",
                    String(notionPageStatus.retryCount)
                ].joined(separator: ","),
                "chora.contract.notion.connect-auth-url": notionAuthorization.url.absoluteString,
                "chora.contract.notion.connect-state": notionAuthorization.state,
                "chora.contract.notion.disconnect": "disconnected"
            ]
            values.merge(notionValues) { _, new in new }
            initialResult = .success(values)
        } catch {
            initialResult = .failure(error)
        }
        _result = State(initialValue: initialResult)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                switch result {
                case .success(let values):
                    ForEach(values.keys.sorted(), id: \.self) { key in
                        Text(values[key] ?? "nil")
                            .accessibilityIdentifier(key)
                    }
                case .failure(let error):
                    Text(String(describing: error))
                        .accessibilityIdentifier("chora.contract.error")
                }
            }
        }
        .task {
            guard case .success(var values) = result else {
                return
            }
            do {
                values.merge(try await Self.scopeContractValues()) {
                    _, new in new
                }
                result = .success(values)
            } catch {
                result = .failure(error)
            }
        }
    }

    private enum FixtureError: Error {
        case missingImportItem
        case missingNotionPage
        case missingNotionPageStatus
        case scopeContractMismatch
    }

    private static func requestContractValues() -> [String: String] {
        let profileName = ChoraSourceRequests.agentDisplayName(
            ":agent_actor_id"
        )
        let noteDetail = ChoraSourceRequests.noteImportDetail(":job_id")
        let noteCancel = ChoraSourceRequests.noteImportCancel(":job_id")
        let notionJob = ChoraSourceRequests.notionJob(":job_id")
        let specs = [
            ChoraSourceRequests.agentProfile,
            ChoraSourceRequests.agentUsers,
            ChoraSourceRequests.ownProfile,
            profileName,
            ChoraSourceRequests.preferredAddress,
            ChoraSourceRequests.agentAvatar,
            ChoraSourceRequests.growth,
            ChoraSourceRequests.noteImportEnqueue,
            ChoraSourceRequests.noteImportList,
            noteDetail,
            noteCancel,
            ChoraSourceRequests.notionConnect,
            ChoraSourceRequests.notionStatus,
            ChoraSourceRequests.notionPages,
            ChoraSourceRequests.notionEnqueue,
            notionJob,
            ChoraSourceRequests.notionDisconnect
        ]
        let presentsError = "presentsError:\(specs.contains { $0.presentsError })"

        return [
            "chora.contract.request.identity": [
                request(ChoraSourceRequests.agentProfile),
                request(ChoraSourceRequests.agentUsers),
                request(ChoraSourceRequests.ownProfile),
                presentsError
            ].joined(separator: "|"),
            "chora.contract.request.profile-writes": [
                request(profileName, fields: profileName.bodyFields),
                request(
                    ChoraSourceRequests.preferredAddress,
                    fields: ChoraSourceRequests.preferredAddress.bodyFields
                ),
                request(
                    ChoraSourceRequests.agentAvatar,
                    fields: ChoraSourceRequests.agentAvatar.multipartFields
                ),
                presentsError
            ].joined(separator: "|"),
            "chora.contract.request.growth": [
                request(
                    ChoraSourceRequests.growth,
                    fields: ChoraSourceRequests.growth.queryFields
                ),
                presentsError
            ].joined(separator: "|"),
            "chora.contract.request.note-import": [
                request(
                    ChoraSourceRequests.noteImportEnqueue,
                    fields: ChoraSourceRequests.noteImportEnqueue.multipartFields
                ) + " threshold=\(ChoraSourceRequests.noteImportEnqueue.multipartEncodingThreshold ?? UInt64.max)",
                request(
                    ChoraSourceRequests.noteImportList,
                    fields: ChoraSourceRequests.noteImportList.queryFields
                ),
                request(noteDetail),
                request(noteCancel),
                presentsError
            ].joined(separator: "|"),
            "chora.contract.request.notion": [
                request(
                    ChoraSourceRequests.notionConnect,
                    fields: [
                        "client=\(ChoraSourceRequests.notionConnect.queryValues["client"] ?? "nil")"
                    ]
                ),
                request(ChoraSourceRequests.notionStatus),
                request(
                    ChoraSourceRequests.notionPages,
                    fields: ChoraSourceRequests.notionPages.queryFields
                ),
                request(
                    ChoraSourceRequests.notionEnqueue,
                    fields: ChoraSourceRequests.notionEnqueue.bodyFields
                ),
                request(notionJob),
                request(ChoraSourceRequests.notionDisconnect),
                presentsError
            ].joined(separator: "|")
        ]
    }

    private static func platformContractValues() -> [String: String] {
        let descriptors = [
            NoteImportDocumentDescriptorBuilder.descriptor(
                for: URL(fileURLWithPath: "/tmp/notes.md"),
                byteCount: 4
            ),
            NoteImportDocumentDescriptorBuilder.descriptor(
                for: URL(fileURLWithPath: "/tmp/page.htm"),
                byteCount: 5
            ),
            NoteImportDocumentDescriptorBuilder.descriptor(
                for: URL(fileURLWithPath: "/tmp/empty.md"),
                byteCount: 0
            ),
            NoteImportDocumentDescriptorBuilder.descriptor(
                for: URL(fileURLWithPath: "/tmp/unsupported.txt"),
                byteCount: 3
            )
        ]
        let successURL = URL(
            string: "arcnote://notion-connected?result=success&credential=ignored"
        )!
        let failedURL = URL(
            string: "arcnote://arbitrary-target?result=success"
        )!
        let duplicateResultURL = URL(
            string: "arcnote://notion-connected?result=success&result=cancelled"
        )!
        let cancellation = NSError(
            domain: ASWebAuthenticationSessionError.errorDomain,
            code: ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
        )
        let resultText: (NotionAuthorizationResult) -> String = { result in
            switch result {
            case .success: "success"
            case .cancelled: "cancelled"
            case .failed: "failed"
            }
        }
        let replayID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000010"
        )!
        var requestFence = NotionOAuthRequestFence()
        let beganRequest = requestFence.begin(replayID)
        let acceptedFirstCompletion = requestFence.consume(replayID)
        let ignoredReplay = !requestFence.consume(replayID)
        var lifecycleCoordinator: ChoraFixtureNotionOAuthCoordinator? =
            ChoraFixtureNotionOAuthCoordinator()
        weak var weakLifecycleCoordinator:
            ChoraFixtureNotionOAuthCoordinator?
        weakLifecycleCoordinator = lifecycleCoordinator
        let lifecycleHolder = NotionOAuthCoordinatorHolder(
            lifecycleCoordinator!
        )
        lifecycleCoordinator = nil
        let lifecycleRetained = weakLifecycleCoordinator != nil
            && lifecycleHolder.coordinator === weakLifecycleCoordinator
        let sourceURL = URL(fileURLWithPath: "/private/fixture/a/notes.md")
        let sameSource = [
            NoteImportDocumentDescriptorBuilder.descriptor(
                for: sourceURL,
                byteCount: 4
            ),
            NoteImportDocumentDescriptorBuilder.descriptor(
                for: sourceURL,
                byteCount: 4
            )
        ]
        let differentSource = NoteImportDocumentDescriptorBuilder.descriptor(
            for: URL(fileURLWithPath: "/private/fixture/b/notes.md"),
            byteCount: 4
        )
        let sameKey = sameSource[0].sourceKey == sameSource[1].sourceKey
        let differentKey = sameSource[0].sourceKey != differentSource.sourceKey
        let opaqueKey = !sameSource[0].sourceKey.contains("/private/fixture")
        return [
            "chora.contract.picker.content-types":
                NoteImportDocumentDescriptorBuilder.supportedContentTypes
                    .map(\.identifier).joined(separator: ","),
            "chora.contract.picker.multiple-selection": String(
                NoteImportDocumentDescriptorBuilder.allowsMultipleSelection
            ),
            "chora.contract.picker.descriptors": descriptors.map {
                "\($0.filename):\($0.format.rawValue):\($0.byteCount)"
            }.joined(separator: ","),
            "chora.contract.picker.source-key": [
                "same:\(sameKey)",
                "different:\(differentKey)",
                "opaque:\(opaqueKey)"
            ].joined(separator: ","),
            "chora.contract.oauth.success": resultText(
                NotionOAuthCoordinator.authorizationResult(
                    callbackURL: successURL,
                    error: nil
                )
            ),
            "chora.contract.oauth.cancelled": resultText(
                NotionOAuthCoordinator.authorizationResult(
                    callbackURL: nil,
                    error: cancellation
                )
            ),
            "chora.contract.oauth.failed": resultText(
                NotionOAuthCoordinator.authorizationResult(
                    callbackURL: failedURL,
                    error: nil
                )
            ),
            "chora.contract.oauth.duplicate-result": resultText(
                NotionOAuthCoordinator.authorizationResult(
                    callbackURL: duplicateResultURL,
                    error: nil
                )
            ),
            "chora.contract.oauth.lifecycle-owner": lifecycleRetained
                ? "retained"
                : "released",
            "chora.contract.oauth.request-id-replay":
                beganRequest && acceptedFirstCompletion && ignoredReplay
                    ? "ignored"
                    : "accepted"
        ]
    }

    private static func request(
        _ spec: ChoraSourceRequestSpec,
        fields: [String] = []
    ) -> String {
        let suffix = fields.isEmpty ? "" : " \(fields.joined(separator: ","))"
        return "\(spec.method.rawValue) \(spec.endpoint)\(suffix)"
    }

    private static func scopeContractValues() async throws -> [String: String] {
        let firstURL = URL(fileURLWithPath: "/tmp/a.md")
        let secondURL = URL(fileURLWithPath: "/tmp/b.md")

        let atomicRecorder = ChoraScopeContractRecorder()
        let atomicAccessor = ChoraScopeContractAccessor(
            allowedPaths: ["a.md": true, "b.md": false],
            recorder: atomicRecorder
        )
        let atomicUploader = ChoraScopeContractUploader(
            behavior: .unexpected,
            recorder: atomicRecorder
        )
        let atomicService = NetworkNoteImportService(
            resourceAccessor: atomicAccessor,
            uploader: atomicUploader
        )
        _ = try? await atomicService.enqueue(
            files: [
                fixtureFile(id: "a", url: firstURL),
                fixtureFile(id: "b", url: secondURL)
            ],
            clientRequestID: "scope-atomic"
        )
        if atomicUploader.uploadCount == 0 {
            atomicRecorder.append("no-upload")
        }
        guard atomicRecorder.values == [
            "acquire:a", "acquire:b", "release:a", "no-upload"
        ] else {
            throw FixtureError.scopeContractMismatch
        }

        let emptyRecorder = ChoraScopeContractRecorder()
        let emptyAccessor = ChoraScopeContractAccessor(
            allowedPaths: ["a.md": true],
            recorder: emptyRecorder
        )
        let emptyUploader = ChoraScopeContractUploader(
            behavior: .unexpected,
            recorder: emptyRecorder
        )
        let emptyService = NetworkNoteImportService(
            resourceAccessor: emptyAccessor,
            uploader: emptyUploader,
            metadataReader: ChoraScopeContractMetadataReader(
                behavior: .size(0),
                accessor: emptyAccessor,
                recorder: emptyRecorder
            )
        )
        let emptyResult: String
        do {
            _ = try await emptyService.enqueue(
                files: [fixtureFile(id: "a", url: firstURL)],
                clientRequestID: "scope-empty"
            )
            emptyResult = "uploaded"
        } catch NoteImportServiceError.selection(
            .emptyFile(let filename)
        ) {
            emptyResult = "empty:\(filename)"
        } catch {
            emptyResult = "wrong-error"
        }
        if emptyUploader.uploadCount == 0 { emptyRecorder.append("no-upload") }

        let metadataRecorder = ChoraScopeContractRecorder()
        let metadataAccessor = ChoraScopeContractAccessor(
            allowedPaths: ["a.md": true],
            recorder: metadataRecorder
        )
        let metadataUploader = ChoraScopeContractUploader(
            behavior: .unexpected,
            recorder: metadataRecorder
        )
        let metadataService = NetworkNoteImportService(
            resourceAccessor: metadataAccessor,
            uploader: metadataUploader,
            metadataReader: ChoraScopeContractMetadataReader(
                behavior: .unavailable,
                accessor: metadataAccessor,
                recorder: metadataRecorder
            )
        )
        let metadataResult: String
        do {
            _ = try await metadataService.enqueue(
                files: [fixtureFile(id: "a", url: firstURL)],
                clientRequestID: "scope-metadata"
            )
            metadataResult = "uploaded"
        } catch NoteImportServiceError.preflight(
            code: "file_metadata_unavailable"
        ) {
            metadataResult = "metadata-unavailable"
        } catch {
            metadataResult = "wrong-error"
        }
        if metadataUploader.uploadCount == 0 {
            metadataRecorder.append("no-upload")
        }

        let cancelRecorder = ChoraScopeContractRecorder()
        let cancelAccessor = ChoraScopeContractAccessor(
            allowedPaths: ["a.md": true],
            recorder: cancelRecorder
        )
        let uploadStarted = NoteImportUploadTermination()
        let uploadHandle = ChoraContractUploadHandle(
            recorder: cancelRecorder
        )
        let cancelUploader = ChoraScopeContractUploader(
            behavior: .cancellable(
                started: uploadStarted,
                handle: uploadHandle
            ),
            recorder: cancelRecorder
        )
        let cancelService = NetworkNoteImportService(
            resourceAccessor: cancelAccessor,
            uploader: cancelUploader
        )
        let task = Task { () -> String in
            defer { cancelRecorder.append("completion") }
            do {
                _ = try await cancelService.enqueue(
                    files: [
                        fixtureFile(id: "first", url: firstURL),
                        fixtureFile(id: "duplicate", url: firstURL)
                    ],
                    clientRequestID: "scope-cancel"
                )
                return "success"
            } catch is CancellationError {
                return "CancellationError"
            } catch {
                return String(describing: type(of: error))
            }
        }
        await uploadStarted.wait()
        task.cancel()
        await uploadHandle.cancellationObserved.wait()
        let cancelImmediate = cancelRecorder.values.contains("cancel")
            && !cancelRecorder.values.contains("terminal")
        let pendingBeforeTerminal = !cancelRecorder.values.contains("terminal")
            && !cancelRecorder.values.contains("release:a")
            && !cancelRecorder.values.contains("completion")
        cancelRecorder.append("pending")
        uploadHandle.reportTerminalResponse()
        let cancellationResult = await task.value
        guard cancelRecorder.values == [
            "acquire:a", "upload", "cancel", "pending", "terminal",
            "release:a", "completion"
        ] else {
            throw FixtureError.scopeContractMismatch
        }

        let scopeCancelOrder = cancelRecorder.values.compactMap {
            value -> String? in
            switch value {
            case "pending", "completion": nil
            case "terminal": "terminated"
            default: value
            }
        }
        let transportOrder = cancelRecorder.values.filter {
            !$0.hasPrefix("acquire:") && $0 != "upload"
        }

        return [
            "chora.contract.scope.atomic-failure": atomicRecorder.values
                .joined(separator: ","),
            "chora.contract.scope.cancel-order": scopeCancelOrder
                .joined(separator: ","),
            "chora.contract.scope.cancel-result": cancellationResult,
            "chora.contract.scope.duplicate-count": [
                "acquire:\(cancelAccessor.acquireCount)",
                "release:\(cancelAccessor.releaseCount)"
            ].joined(separator: ","),
            "chora.contract.scope.empty-preflight":
                emptyRecorder.values.joined(separator: ",")
                    + "|\(emptyResult)",
            "chora.contract.scope.metadata-failure":
                metadataRecorder.values.joined(separator: ",")
                    + "|\(metadataResult)",
            "chora.contract.transport.cancel-immediate": String(
                cancelImmediate
            ),
            "chora.contract.transport.pending-before-terminal": String(
                pendingBeforeTerminal
            ),
            "chora.contract.transport.terminal-order": transportOrder
                .joined(separator: ",")
        ]
    }

    private static func fixtureFile(id: String, url: URL) -> NoteImportFile {
        NoteImportFile(
            id: id,
            sourceKey: "source-\(id)",
            url: url,
            filename: url.lastPathComponent,
            label: id,
            format: .markdown,
            byteCount: 1
        )
    }

    private static let agentProfileJSON = #"""
    {
      "success": true,
      "data": {
        "human_actor_id": "act_human_contract",
        "active_agent_actor_id": "act_agent_contract",
        "binding_id": "bind_contract",
        "is_primary": true,
        "agent_status": "FUTURE_ACTIVE",
        "soul_version": 7,
        "proactive_enabled": true,
        "timezone": "Asia/Shanghai"
      }
    }
    """#

    private static let agentUsersJSON = #"""
    {
      "success": true,
      "data": {
        "human_actor_id": "act_human_contract",
        "agent_users": [{
          "agent_user_id": "agu_contract",
          "actor_id": "act_agent_contract",
          "agent_actor_id": "act_agent_contract",
          "display_name": "Chora Contract",
          "username": "chora-contract",
          "avatar_url": "https://cdn.chorai.test/agent.png",
          "follower_count": 3,
          "following_count": 4,
          "agent_kind": "companion",
          "binding_id": "bind_contract",
          "binding_type": "PRIMARY",
          "is_primary": true,
          "status": "FUTURE_BOUND"
        }]
      }
    }
    """#

    private static let ownProfileJSON = #"""
    {
      "success": true,
      "data": {
        "actor_id": "act_human_contract",
        "username": "avery",
        "preferred_address": "Avery",
        "email": "avery@example.com",
        "follower_count": 10,
        "following_count": 11,
        "interest_selection_completed": true,
        "created_at": "2026-07-12T01:02:03.456Z"
      }
    }
    """#

    private static let growthJSON = #"""
    {
      "growth_view": {
        "actor_id": "act_agent_contract",
        "growth_version": "growth_v0_1_balanced_seed",
        "dimension_scores": {
          "curiosity": 1.25,
          "insight": 2.5,
          "creativity": 3.75,
          "empathy": 5.0,
          "judgment": 6.25,
          "resonance": 7.5
        },
        "weighted_score": 4.375,
        "weakest_dimension": "curiosity",
        "calculated_stage": 5,
        "committed_stage": 4,
        "candidate_stage_diagnostics": {"future_gate": true},
        "computed_at": "2026-07-12T01:02:03.456Z"
      }
    }
    """#

    private static let importReceiptJSON = #"""
    {
      "job_id": "job_import_contract",
      "client_request_id": "req_import_contract",
      "status": "queued",
      "total_files": 2,
      "accepted_files": 2,
      "rejected_files": 0
    }
    """#

    private static let importListJSON = #"""
    {
      "jobs": [{
        "job_id": "job_future_contract",
        "status": "future_import_state",
        "soul_status": "future_soul_state",
        "total_files": 2,
        "imported_count": 0,
        "updated_count": 0,
        "skipped_count": 0,
        "failed_count": 0,
        "created_at": "2026-07-12T01:02:03Z"
      }]
    }
    """#

    private static let importDetailJSON = #"""
    {
      "job_id": "job_import_contract",
      "client_request_id": "req_import_contract",
      "status": "running",
      "soul_status": "not_requested",
      "total_files": 2,
      "imported_count": 1,
      "updated_count": 0,
      "skipped_count": 0,
      "failed_count": 0,
      "created_at": "2026-07-12T01:02:03.456Z",
      "items": [{
        "source_key": "source-contract",
        "original_filename": "contract.md",
        "label": "Contract",
        "original_format": "markdown",
        "asset_id": "ast_import_contract",
        "status": "imported"
      }]
    }
    """#

    private static let notionStatusJSON = #"""
    {
      "connected": true,
      "workspace_id": "workspace_contract",
      "pages": [{
        "notion_page_id": "page_contract",
        "status": "future_page_state",
        "retry_count": 0
      }]
    }
    """#

    private static let notionConnectJSON = #"""
    {
      "auth_url": "https://api.notion.test/oauth?state=opaque_contract",
      "state": "state_contract"
    }
    """#

    private static let notionPagesJSON = #"""
    {
      "pages": [{
        "page_id": "page_contract",
        "title": "Contract page",
        "last_edited_time": "2026-07-12T01:02:03.456Z",
        "url": "https://notion.so/page_contract"
      }]
    }
    """#

    private static let notionReceiptJSON = #"""
    {"job_id": "job_notion_contract", "status": "queued"}
    """#

    private static let notionJobJSON = #"""
    {
      "job_id": "job_notion_detail_contract",
      "status": "future_notion_state",
      "imported": 0,
      "updated": 0,
      "skipped": 0,
      "failed": []
    }
    """#

    private static let notionDisconnectJSON = #"""
    {"disconnected": true}
    """#
}

private enum APIMigrationUITestSeed {
    static func applyIfPresent() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CHORAI_UI_TEST"] == "1" else {
            return
        }

        let defaults = UserDefaults.standard
        if let token = environment["CHORAI_UI_TEST_AUTH_TOKEN"], !token.isEmpty {
            SessionTokenStore.delete()
            SessionTokenStore.save(token)
            defaults.removeObject(forKey: "auth_token")
            NetworkManager.shared.setAuthToken(token)
        }

        if let actorId = environment["CHORAI_UI_TEST_ACTOR_ID"], !actorId.isEmpty {
            defaults.set(true, forKey: "is_logged_in")
            defaults.set(actorId, forKey: "actor_id")
            defaults.set(environment["CHORAI_UI_TEST_EMAIL"] ?? "ui-test@example.com", forKey: "email")
            defaults.set(environment["CHORAI_UI_TEST_USERNAME"] ?? "ui-test-user", forKey: "username")
            defaults.set(0, forKey: "credit")
            defaults.set(
                environment["CHORAI_UI_TEST_CREATED_AT"]
                    ?? "2026-01-01T00:00:00Z",
                forKey: "created_at"
            )
            if let token = environment["CHORAI_UI_TEST_AUTH_TOKEN"],
               !token.isEmpty {
                AuthManager.shared.installUITestSession(
                    token: token,
                    actorID: actorId,
                    email: environment["CHORAI_UI_TEST_EMAIL"]
                        ?? "ui-test@example.com",
                    username: environment["CHORAI_UI_TEST_USERNAME"]
                        ?? "ui-test-user",
                    createdAt: environment["CHORAI_UI_TEST_CREATED_AT"]
                        ?? "2026-01-01T00:00:00Z"
                )
            } else {
                AuthManager.shared.loadUserSession()
            }
        }
    }
}

private final class APIMigrationSmokeRunner {
    private static let marker = "API_MIGRATION_SMOKE"

    static var isRequested: Bool {
        let defaults = UserDefaults.standard
        let environment = ProcessInfo.processInfo.environment
        let requestedByArgument = ProcessInfo.processInfo.arguments.contains("--api-migration-smoke")
        let requestedByDefaults = defaults.bool(forKey: "api_migration_smoke_enabled")
        let requestedByEnvironment = environment["CHORAI_API_SMOKE"] == "1"
        return requestedByArgument || requestedByDefaults || requestedByEnvironment
    }

    static func startIfRequested() {
        guard isRequested else {
            return
        }

        UserDefaults.standard.set(false, forKey: "api_migration_smoke_enabled")

        Task {
            let code = await run()
            fflush(stdout)
            fflush(stderr)
            exit(Int32(code))
        }
    }

    private static func run() async -> Int {
        let defaults = UserDefaults.standard
        let environment = ProcessInfo.processInfo.environment
        let shouldUploadAvatar = defaults.bool(forKey: "api_migration_smoke_avatar_upload")
            || environment["CHORAI_API_SMOKE_AVATAR_UPLOAD"] == "1"
        let socialTargetId = (defaults.string(forKey: "api_migration_smoke_social_target")
            ?? environment["CHORAI_API_SMOKE_SOCIAL_TARGET"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(false, forKey: "api_migration_smoke_avatar_upload")

        let token = SessionTokenStore.load() ?? defaults.string(forKey: "auth_token")
        guard let token, !token.isEmpty else {
            log("FAIL missing auth_token")
            return 2
        }
        defaults.removeObject(forKey: "auth_token")

        guard let actorId = defaults.string(forKey: "actor_id"), !actorId.isEmpty else {
            log("FAIL missing actor_id")
            return 2
        }

        NetworkManager.shared.setAuthToken(token)
        log("START base_url=\(APIConfiguration.baseURL)")

        var createdCardIds: [String] = []

        do {
            _ = try await expect("health") {
                NetworkManager.shared.healthCheck()
            }
            _ = try await expect("verify-token") {
                NetworkManager.shared.verifyToken()
            }
            _ = try await expect("profile-me") {
                NetworkManager.shared.getCurrentUserProfile()
            }
            if shouldUploadAvatar {
                _ = try await expect("avatar-upload") {
                    NetworkManager.shared.uploadAvatar(imageData: smokeAvatarImageData())
                }
                _ = try await expect("profile-me-after-avatar") {
                    NetworkManager.shared.getCurrentUserProfile()
                }
            }

            let interests = try await expect("interests-options") {
                NetworkManager.shared.getInterests()
            }
            let domains = Array(interests.data.prefix(2).map(\.id))
            if !domains.isEmpty {
                _ = try await expect("save-interests") {
                    NetworkManager.shared.saveUserInterests(request: SaveUserInterestsRequest(domains: domains))
                }
            }

            let recommended = try await expect("recommended") {
                NetworkManager.shared.getRecommendedCards(limit: 3)
            }
            _ = try await expect("my-cards") {
                NetworkManager.shared.getCards(page: 1, perPage: 3)
            }
            if let socialTargetId, !socialTargetId.isEmpty, socialTargetId != actorId {
                _ = try await expect("public-profile") {
                    NetworkManager.shared.getUserProfile(actorId: socialTargetId)
                }
                _ = try await expect("follow-status-before") {
                    NetworkManager.shared.checkFollowStatus(targetActorIds: [socialTargetId])
                }
                _ = try await expect("follow") {
                    NetworkManager.shared.followUser(targetActorId: socialTargetId)
                }
                _ = try await expect("follow-status-after-follow") {
                    NetworkManager.shared.checkFollowStatus(targetActorIds: [socialTargetId])
                }
                _ = try await expect("unfollow") {
                    NetworkManager.shared.unfollowUser(targetActorId: socialTargetId)
                }
                _ = try await expect("follow-status-after-unfollow") {
                    NetworkManager.shared.checkFollowStatus(targetActorIds: [socialTargetId])
                }
                _ = try await expect("block") {
                    NetworkManager.shared.blockUser(blockedActorId: socialTargetId)
                }
                _ = try await expect("unblock") {
                    NetworkManager.shared.unblockUser(blockedActorId: socialTargetId)
                }
            }

            let suffix = Int(Date().timeIntervalSince1970)
            let firstCard = try await expect("create-card-primary") {
                NetworkManager.shared.createCard(CreateCardRequest(
                    title: "iOS Go API smoke \(suffix)",
                    content: "iOS Go API migration smoke primary \(suffix)",
                    tags: ["ios-smoke", "go-api"],
                    isPublic: true
                ))
            }
            let firstCardId = firstCard.data.id
            createdCardIds.append(firstCardId)

            let secondCard = try await expect("create-card-linked") {
                NetworkManager.shared.createCard(CreateCardRequest(
                    title: "iOS Go API smoke linked \(suffix)",
                    content: "iOS Go API migration smoke linked \(suffix)",
                    tags: ["ios-smoke"],
                    isPublic: false
                ))
            }
            let secondCardId = secondCard.data.id
            createdCardIds.append(secondCardId)

            _ = try await expect("get-card") {
                NetworkManager.shared.getCard(id: firstCardId)
            }
            _ = try await expect("update-card") {
                NetworkManager.shared.updateCard(
                    id: firstCardId,
                    request: UpdateCardRequest(
                        title: "iOS Go API smoke updated \(suffix)",
                        content: "iOS Go API migration smoke updated \(suffix)",
                        tags: ["ios-smoke", "updated"]
                    )
                )
            }
            _ = try await expect("search-cards") {
                NetworkManager.shared.searchCards(SearchRequest(
                    query: "ios-smoke",
                    sortBy: "updated_at",
                    sortOrder: "desc",
                    tags: nil,
                    page: 1,
                    perPage: 5
                ))
            }
            _ = try await expectCommentCreate(cardId: firstCardId)
            _ = try await expectCommentList(cardId: firstCardId)

            _ = try await expect("favorite") {
                NetworkManager.shared.favoriteCard(cardId: firstCardId)
            }
            _ = try await expect("favorite-status") {
                NetworkManager.shared.checkFavoriteStatus(cardIds: firstCardId)
            }
            _ = try await expect("unfavorite") {
                NetworkManager.shared.unfavoriteCard(cardId: firstCardId)
            }
            _ = try await expect("like") {
                NetworkManager.shared.likeCard(cardId: firstCardId)
            }
            _ = try await expect("unlike") {
                NetworkManager.shared.unlikeCard(cardId: firstCardId)
            }
            _ = try await expect("pin") {
                NetworkManager.shared.pinCard(cardId: firstCardId)
            }
            _ = try await expect("unpin") {
                NetworkManager.shared.unpinCard(cardId: firstCardId)
            }
            _ = try await expect("visibility-private") {
                NetworkManager.shared.updateCardVisibility(cardId: firstCardId, isPublic: false)
            }
            _ = try await expect("visibility-public") {
                NetworkManager.shared.updateCardVisibility(cardId: firstCardId, isPublic: true)
            }

            _ = try await expect("create-link") {
                NetworkManager.shared.createCardLink(cardId: firstCardId, reques: LinkRequest(linkedCardId: secondCardId))
            }
            _ = try await expect("get-card-links") {
                NetworkManager.shared.getCardLinks(cardId: firstCardId)
            }
            _ = try await expect("get-my-links") {
                NetworkManager.shared.getUserAllLinks(limit: 5)
            }
            _ = try await expect("delete-link") {
                NetworkManager.shared.deleteCardLink(cardId: firstCardId, linkedCardId: secondCardId)
            }
            _ = try await expect("trash-delete-restore-target") {
                NetworkManager.shared.deleteCard(id: secondCardId)
            }
            _ = try await expectTrashList(name: "trash-list-before-restore")
            _ = try await expect("restore-card") {
                NetworkManager.shared.restoreCard(cardId: secondCardId)
            }
            _ = try await expectTrashList(name: "trash-list-after-restore")
            let sparkCardId = defaults.string(forKey: "api_migration_smoke_spark_asset_id") ?? "ast_cs_art_88ba36bc8dea"
            _ = try await expect("spark") {
                NetworkManager.shared.generateRelatedCards(cardId: sparkCardId)
            }
            let chatParticipantId = defaults.string(forKey: "api_migration_smoke_chat_participant") ?? "act_ag_art"
            let conversation = try await expect("chat-create-conversation") {
                NetworkManager.shared.createConversation(request: CreateConversationRequest(participantId: chatParticipantId))
            }
            _ = try await expect("chat-list-conversations") {
                NetworkManager.shared.getConversations()
            }
            _ = try await expect("chat-send-message") {
                NetworkManager.shared.sendMessage(
                    conversationId: conversation.conversation.id,
                    request: SendMessageRequest(content: "iOS Go API smoke message \(suffix)")
                )
            }
            _ = try await expect("chat-list-messages") {
                NetworkManager.shared.getMessages(conversationId: conversation.conversation.id, page: 1, perPage: 5)
            }

            let notifications = try await expect("notifications") {
                NetworkManager.shared.getNotificationInbox(
                    GetNotificationsRequest(page: 1, perPage: 5)
                )
            }
            if let notification = notifications.data.first {
                _ = try await expect("notification-mark-read") {
                    NetworkManager.shared.markNotificationRead(
                        notificationId: notification.notificationID
                    )
                }
            } else {
                log("PASS notification-mark-read-skipped-empty")
            }
            let referral = try await expect("invitation-referral") {
                NetworkManager.shared.getUserGroup()
            }
            _ = try await expect("invitation-validate") {
                NetworkManager.shared.validateInvitationCode(ValidateInvitationRequest(code: referral.data.code))
            }
            _ = try await expect("invitation-track") {
                NetworkManager.shared.trackInvitationClick(InvitationTrackRequest(code: referral.data.code, deviceFingerprint: "ios-api-smoke"))
            }
            _ = try await expect("invitation-records") {
                NetworkManager.shared.getInvitationRecords(page: 1, limit: 5)
            }
            _ = try await expect("invitation-rewards") {
                NetworkManager.shared.getInvitationRewards(page: 1, limit: 5)
            }

            for cardId in createdCardIds.reversed() {
                _ = try await expect("delete-card-\(cardId)") {
                    NetworkManager.shared.deleteCard(id: cardId)
                }
            }

            log("PASS complete")
            return 0
        } catch {
            log("FAIL \(error)")

            for cardId in createdCardIds.reversed() {
                do {
                    _ = try await awaitPublisher(NetworkManager.shared.deleteCard(id: cardId))
                    log("PASS cleanup-\(cardId)")
                } catch {
                    log("WARN cleanup-\(cardId) \(error)")
                }
            }

            return 1
        }
    }

    private static func expect<T>(_ name: String, operation: () -> AnyPublisher<T, NetworkError>) async throws -> T {
        let value = try await awaitPublisher(operation())
        log("PASS \(name)")
        return value
    }

    private static func expectCommentCreate(cardId: String) async throws -> CreateCommentResponse {
        let response = try await awaitCallback { completion in
            NetworkManager.shared.createComment(
                cardId: cardId,
                request: CreateCommentRequest(content: "iOS Go API smoke comment"),
                completion: completion
            )
        }
        log("PASS comment-create")
        return response
    }

    private static func expectCommentList(cardId: String) async throws -> CommentListResponse {
        let response = try await awaitCallback { completion in
            NetworkManager.shared.getComments(cardId: cardId, page: 1, perPage: 5, completion: completion)
        }
        log("PASS comment-list")
        return response
    }

    private static func expectTrashList(name: String) async throws -> TrashListResponse {
        let response = try await awaitCallback { completion in
            NetworkManager.shared.getTrashCards(page: 1, perPage: 5, completion: completion)
        }
        log("PASS \(name)")
        return response
    }

    private static func smokeAvatarImageData() -> Data {
        let base64 = """
        /9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAH/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAEFAqf/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/ASP/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/ASP/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAY/Al//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/IV//2gAMAwEAAgADAAAAEP/EFBQRAQAAAAAAAAAAAAAAAAAAABH/2gAIAQMBAT8QH//EFBQRAQAAAAAAAAAAAAAAAAAAABH/2gAIAQIBAT8QH//EFBQBAQAAAAAAAAAAAAAAAAAAABH/2gAIAQEAAT8QH//Z
        """
        return Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)) ?? Data()
    }

    private static func awaitPublisher<T>(_ publisher: AnyPublisher<T, NetworkError>) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            var didResume = false

            cancellable = publisher
                .first()
                .sink(
                    receiveCompletion: { completion in
                        guard !didResume else { return }
                        if case .failure(let error) = completion {
                            didResume = true
                            continuation.resume(throwing: error)
                        }
                        cancellable?.cancel()
                    },
                    receiveValue: { value in
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume(returning: value)
                        cancellable?.cancel()
                    }
                )
        }
    }

    private static func awaitCallback<T>(
        _ operation: (@escaping (Result<T, NetworkError>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            operation { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func log(_ message: String) {
        print("\(marker) \(message)")
    }
}
#endif
