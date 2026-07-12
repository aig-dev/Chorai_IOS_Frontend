import Foundation
import CoreFlow

enum ChoraRequestMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct ChoraSourceRequestSpec {
    let method: ChoraRequestMethod
    let endpoint: String
    let queryFields: [String]
    let queryValues: [String: String]
    let bodyFields: [String]
    let multipartFields: [String]
    let presentsError: Bool
    let multipartEncodingThreshold: UInt64?

    init(
        method: ChoraRequestMethod,
        endpoint: String,
        queryFields: [String] = [],
        queryValues: [String: String] = [:],
        bodyFields: [String] = [],
        multipartFields: [String] = [],
        presentsError: Bool = false,
        multipartEncodingThreshold: UInt64? = nil
    ) {
        self.method = method
        self.endpoint = endpoint
        self.queryFields = queryFields
        self.queryValues = queryValues
        self.bodyFields = bodyFields
        self.multipartFields = multipartFields
        self.presentsError = presentsError
        self.multipartEncodingThreshold = multipartEncodingThreshold
    }
}

enum ChoraSourceRequests {
    static let agentProfile = ChoraSourceRequestSpec(
        method: .get,
        endpoint: "/api/agent/profile"
    )
    static let agentUsers = ChoraSourceRequestSpec(
        method: .get,
        endpoint: "/api/agent/users"
    )
    static let ownProfile = ChoraSourceRequestSpec(
        method: .get,
        endpoint: "/api/v1/profile/me"
    )
    static let growth = ChoraSourceRequestSpec(
        method: .get,
        endpoint: "/api/v1/growth/view",
        queryFields: ["actor_id"]
    )
    static func agentDisplayName(_ agentActorID: String) -> ChoraSourceRequestSpec {
        ChoraSourceRequestSpec(
            method: .patch,
            endpoint: "/api/agent/users/\(agentActorID)",
            bodyFields: ["display_name"]
        )
    }
    static let preferredAddress = ChoraSourceRequestSpec(
        method: .put,
        endpoint: "/api/v1/profile/me",
        bodyFields: ["preferred_address"]
    )
    static let agentAvatar = ChoraSourceRequestSpec(
        method: .put,
        endpoint: "/api/v1/profile/agent/avatar",
        multipartFields: ["agent_actor_id", "avatar"]
    )
    static let noteImportEnqueue = ChoraSourceRequestSpec(
        method: .post,
        endpoint: "/api/v1/imports/notes",
        multipartFields: [
            "files", "source_keys", "labels", "client_request_id"
        ],
        multipartEncodingThreshold: 0
    )
    static let noteImportList = ChoraSourceRequestSpec(
        method: .get,
        endpoint: "/api/v1/imports/notes",
        queryFields: ["limit"]
    )
    static func noteImportDetail(_ jobID: String) -> ChoraSourceRequestSpec {
        ChoraSourceRequestSpec(
            method: .get,
            endpoint: "/api/v1/imports/notes/\(jobID)"
        )
    }
    static func noteImportCancel(_ jobID: String) -> ChoraSourceRequestSpec {
        ChoraSourceRequestSpec(
            method: .post,
            endpoint: "/api/v1/imports/notes/\(jobID)/cancel"
        )
    }
    static let notionStatus = ChoraSourceRequestSpec(
        method: .get,
        endpoint: "/api/v1/integrations/notion/status"
    )
    static let notionConnect = ChoraSourceRequestSpec(
        method: .get,
        endpoint: "/api/v1/integrations/notion/connect",
        queryFields: ["client"],
        queryValues: ["client": "ios"]
    )
    static let notionPages = ChoraSourceRequestSpec(
        method: .get,
        endpoint: "/api/v1/integrations/notion/pages",
        queryFields: ["q"]
    )
    static let notionEnqueue = ChoraSourceRequestSpec(
        method: .post,
        endpoint: "/api/v1/integrations/notion/import",
        bodyFields: ["page_ids"]
    )
    static func notionJob(_ jobID: String) -> ChoraSourceRequestSpec {
        ChoraSourceRequestSpec(
            method: .get,
            endpoint: "/api/v1/integrations/notion/import/\(jobID)"
        )
    }
    static let notionDisconnect = ChoraSourceRequestSpec(
        method: .delete,
        endpoint: "/api/v1/integrations/notion/connect"
    )
}

struct ChoraDataEnvelope<Value: Codable>: Codable {
    let success: Bool
    let data: Value
}

struct ChoraAgentProfileResponse: Codable {
    let humanActorID: String
    let activeAgentActorID: String
    let bindingID: String?
    let isPrimary: Bool
    let agentStatus: String
    let soulVersion: Int
    let proactiveEnabled: Bool
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case humanActorID = "human_actor_id"
        case activeAgentActorID = "active_agent_actor_id"
        case bindingID = "binding_id"
        case isPrimary = "is_primary"
        case agentStatus = "agent_status"
        case soulVersion = "soul_version"
        case proactiveEnabled = "proactive_enabled"
        case timezone
    }
}

struct ChoraAgentUsersResponse: Codable {
    let humanActorID: String
    let agentUsers: [ChoraAgentUserResponse]

    enum CodingKeys: String, CodingKey {
        case humanActorID = "human_actor_id"
        case agentUsers = "agent_users"
    }
}

struct ChoraAgentUserResponse: Codable {
    let agentUserID: String
    let actorID: String
    let agentActorID: String
    let displayName: String
    let username: String
    let avatarURL: String?
    let bio: String?
    let followerCount: Int
    let followingCount: Int
    let agentKind: String
    let bindingID: String
    let bindingType: String
    let isPrimary: Bool
    let status: String

    enum CodingKeys: String, CodingKey {
        case agentUserID = "agent_user_id"
        case actorID = "actor_id"
        case agentActorID = "agent_actor_id"
        case displayName = "display_name"
        case username
        case avatarURL = "avatar_url"
        case bio
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case agentKind = "agent_kind"
        case bindingID = "binding_id"
        case bindingType = "binding_type"
        case isPrimary = "is_primary"
        case status
    }
}

struct ChoraOwnProfileResponse: Codable {
    let actorID: String
    let username: String
    let preferredAddress: String?
    let email: String
    let avatarURL: String?
    let backgroundURL: String?
    let bio: String?
    let gender: String?
    let birthday: String?
    let province: String?
    let city: String?
    let phoneNumber: String?
    let followerCount: Int
    let followingCount: Int
    let interestSelectionCompleted: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case actorID = "actor_id"
        case username
        case preferredAddress = "preferred_address"
        case email
        case avatarURL = "avatar_url"
        case backgroundURL = "background_url"
        case bio
        case gender
        case birthday
        case province
        case city
        case phoneNumber = "phone_number"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case interestSelectionCompleted = "interest_selection_completed"
        case createdAt = "created_at"
    }
}

struct ChoraGrowthViewEnvelope: Codable {
    let growthView: ChoraGrowthViewResponse

    enum CodingKeys: String, CodingKey {
        case growthView = "growth_view"
    }
}

struct ChoraGrowthViewResponse: Codable {
    let actorID: String
    let growthVersion: String
    let dimensionScores: ChoraGrowthDimensionScoresResponse
    let weightedScore: Double
    let weakestDimension: String
    let calculatedStage: Int
    let committedStage: Int
    let candidateStageDiagnostics: [String: MergeJSONValue]
    let computedAt: String

    enum CodingKeys: String, CodingKey {
        case actorID = "actor_id"
        case growthVersion = "growth_version"
        case dimensionScores = "dimension_scores"
        case weightedScore = "weighted_score"
        case weakestDimension = "weakest_dimension"
        case calculatedStage = "calculated_stage"
        case committedStage = "committed_stage"
        case candidateStageDiagnostics = "candidate_stage_diagnostics"
        case computedAt = "computed_at"
    }
}

struct ChoraGrowthDimensionScoresResponse: Codable {
    let curiosity: Double
    let insight: Double
    let creativity: Double
    let empathy: Double
    let judgment: Double
    let resonance: Double
}

struct NoteImportUploadPart {
    let url: URL
    let filename: String
    let mimeType: String
    let sourceKey: String
    let label: String
}

enum NoteImportUploadTransportResult {
    case response(NoteImportEnqueueResponse)
    case undecodableSuccess(statusCode: Int)
}

struct NoteImportEnqueueResponse: Codable {
    let jobID: String
    let clientRequestID: String?
    let status: String
    let totalFiles: Int
    let acceptedFiles: Int
    let rejectedFiles: Int

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case clientRequestID = "client_request_id"
        case status
        case totalFiles = "total_files"
        case acceptedFiles = "accepted_files"
        case rejectedFiles = "rejected_files"
    }
}

struct NoteImportJobListResponse: Codable {
    let jobs: [NoteImportJobSummaryResponse]
}

struct NoteImportJobSummaryResponse: Codable {
    let jobID: String
    let clientRequestID: String?
    let status: String
    let soulStatus: String
    let soulStatusReason: String?
    let totalFiles: Int
    let importedCount: Int
    let updatedCount: Int
    let skippedCount: Int
    let failedCount: Int
    let createdAt: String
    let completedAt: String?
    let cancelRequestedAt: String?
    let cancelledAt: String?

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case clientRequestID = "client_request_id"
        case status
        case soulStatus = "soul_status"
        case soulStatusReason = "soul_status_reason"
        case totalFiles = "total_files"
        case importedCount = "imported_count"
        case updatedCount = "updated_count"
        case skippedCount = "skipped_count"
        case failedCount = "failed_count"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case cancelRequestedAt = "cancel_requested_at"
        case cancelledAt = "cancelled_at"
    }
}

struct NoteImportJobDetailResponse: Codable {
    let jobID: String
    let clientRequestID: String?
    let status: String
    let soulStatus: String
    let soulStatusReason: String?
    let totalFiles: Int
    let importedCount: Int
    let updatedCount: Int
    let skippedCount: Int
    let failedCount: Int
    let errorMessage: String?
    let createdAt: String
    let completedAt: String?
    let cancelRequestedAt: String?
    let cancelledAt: String?
    let items: [NoteImportJobItemResponse]

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case clientRequestID = "client_request_id"
        case status
        case soulStatus = "soul_status"
        case soulStatusReason = "soul_status_reason"
        case totalFiles = "total_files"
        case importedCount = "imported_count"
        case updatedCount = "updated_count"
        case skippedCount = "skipped_count"
        case failedCount = "failed_count"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case cancelRequestedAt = "cancel_requested_at"
        case cancelledAt = "cancelled_at"
        case items
    }
}

struct NoteImportJobItemResponse: Codable {
    let sourceKey: String
    let originalFilename: String
    let label: String?
    let originalFormat: String
    let assetID: String?
    let assetVersionID: String?
    let status: String
    let errorMessage: String?
    let processedAt: String?

    enum CodingKeys: String, CodingKey {
        case sourceKey = "source_key"
        case originalFilename = "original_filename"
        case label
        case originalFormat = "original_format"
        case assetID = "asset_id"
        case assetVersionID = "asset_version_id"
        case status
        case errorMessage = "error_message"
        case processedAt = "processed_at"
    }
}

struct NoteImportCancelResponse: Codable {
    let jobID: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
    }
}

struct NotionConnectResponse: Codable {
    let authURL: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case authURL = "auth_url"
        case state
    }
}

struct NotionStatusResponse: Codable {
    let connected: Bool
    let workspaceID: String?
    let pages: [NotionPageStatusResponse]

    enum CodingKeys: String, CodingKey {
        case connected
        case workspaceID = "workspace_id"
        case pages
    }
}

struct NotionPageStatusResponse: Codable {
    let notionPageID: String
    let assetID: String?
    let status: String
    let lastSyncedAt: String?
    let errorMessage: String?
    let retryCount: UInt8

    enum CodingKeys: String, CodingKey {
        case notionPageID = "notion_page_id"
        case assetID = "asset_id"
        case status
        case lastSyncedAt = "last_synced_at"
        case errorMessage = "error_message"
        case retryCount = "retry_count"
    }
}

struct NotionPagesResponse: Codable {
    let pages: [NotionPageResponse]
}

struct NotionPageResponse: Codable {
    let pageID: String
    let title: String
    let lastEditedTime: String
    let url: String

    enum CodingKeys: String, CodingKey {
        case pageID = "page_id"
        case title
        case lastEditedTime = "last_edited_time"
        case url
    }
}

struct NotionEnqueueResponse: Codable {
    let jobID: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
    }
}

struct NotionImportJobResponse: Codable {
    let jobID: String
    let status: String
    let imported: Int
    let updated: Int
    let skipped: Int
    let failed: [NotionPageFailureResponse]

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
        case imported
        case updated
        case skipped
        case failed
    }
}

struct NotionPageFailureResponse: Codable {
    let pageID: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case pageID = "page_id"
        case reason
    }
}

struct NotionDisconnectResponse: Codable {
    let disconnected: Bool
}

enum ChoraContractDateParser {
    static func date(from value: String) -> Date? {
        fractional.date(from: value) ?? standard.date(from: value)
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standard = ISO8601DateFormatter()
}
