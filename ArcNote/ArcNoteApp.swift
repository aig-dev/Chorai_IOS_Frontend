//
//  ArcNoteApp.swift
//  ArcNote
//
//  Created by 海了个螺 on 2025/7/23.
//

import CoreFlow
import SwiftUI

#if DEBUG
import Combine
import Darwin
#endif

@main
struct ArcNoteApp: App {
    #if DEBUG
    private let isAPIMigrationSmoke = APIMigrationSmokeRunner.isRequested
    private let isInterestUITestRoute = ProcessInfo.processInfo.arguments
        .contains("--ui-test-open-interests")
    private let isNotificationContractUITestRoute = ProcessInfo.processInfo.arguments
        .contains("--ui-test-notification-contract")
    private let isChoraContractUITestRoute = ProcessInfo.processInfo.arguments
        .contains("--ui-test-chora-contract")
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
            #if DEBUG
            if isAPIMigrationSmoke {
                Color.clear
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
    }
}

#if DEBUG
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

private struct ChoraProfileContractFixtureView: View {
    private let result: Result<[String: String], Error>

    init() {
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

            result = .success([
                "chora.contract.human-actor-id": identity.humanActorID,
                "chora.contract.agent-actor-id": identity.agentActorID,
                "chora.contract.preferred-address": identity.preferredAddress ?? "nil",
                "chora.contract.avatar-url": identity.avatarURL ?? "nil",
                "chora.contract.growth-stage": String(growth.committedStage.rawValue),
                "chora.contract.growth.curiosity": growthValues["curiosity"] ?? "nil",
                "chora.contract.growth.insight": growthValues["insight"] ?? "nil",
                "chora.contract.growth.creativity": growthValues["creativity"] ?? "nil",
                "chora.contract.growth.empathy": growthValues["empathy"] ?? "nil",
                "chora.contract.growth.judgment": growthValues["judgment"] ?? "nil",
                "chora.contract.growth.resonance": growthValues["resonance"] ?? "nil",
                "chora.contract.import.client-request-id": importReceipt.clientRequestID ?? "nil",
                "chora.contract.import.job-id": importReceipt.jobID,
                "chora.contract.import.total-files": String(importReceipt.totalFiles),
                "chora.contract.import.imported-count": String(importDetail.importedCount),
                "chora.contract.import.asset-id": importItem.assetID ?? "nil",
                "chora.contract.import.nullable-fields": [
                    importDetail.soulStatusReason,
                    importDetail.errorMessage,
                    importDetail.completedAt.map(String.init(describing:)),
                    importDetail.cancelRequestedAt.map(String.init(describing:)),
                    importDetail.cancelledAt.map(String.init(describing:)),
                    importItem.assetVersionID,
                    importItem.errorMessage
                ].map { $0 ?? "nil" }.joined(separator: ","),
                "chora.contract.import.unknown-status": importList.first?.status.rawValue ?? "nil",
                "chora.contract.import.unknown-soul-status": importList.first?.soulStatus.rawValue ?? "nil",
                "chora.contract.notion.workspace-id": notionStatus.workspaceID ?? "nil",
                "chora.contract.notion.page-id": notionPage.id,
                "chora.contract.notion.enqueue-job-id": notionReceipt.jobID,
                "chora.contract.notion.job-id": notionJob.id,
                "chora.contract.notion.nullable-fields": [
                    notionStatus.workspaceName,
                    notionJob.failureReason
                ].map { $0 ?? "nil" }.joined(separator: ","),
                "chora.contract.notion.unknown-job-status": notionJob.status.rawValue
            ])
        } catch {
            result = .failure(error)
        }
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
    }

    private enum FixtureError: Error {
        case missingImportItem
        case missingNotionPage
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
