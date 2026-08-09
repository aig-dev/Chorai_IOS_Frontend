import Foundation

public struct AccessState: Codable, Equatable, Sendable {
    public let mode: String
    public let status: String
    public let scope: String?
    public let reasonCode: String?

    public init(
        mode: String,
        status: String,
        scope: String?,
        reasonCode: String?
    ) {
        self.mode = mode
        self.status = status
        self.scope = scope
        self.reasonCode = reasonCode
    }

    public var isValid: Bool {
        let knownMode = ["open", "private_beta", "public_beta", "unavailable"]
            .contains(mode)
        let knownStatus = ["allowed", "required"].contains(status)
        let knownScope = scope == nil || scope == "product_full"
        let validUnavailable = mode != "unavailable" || status == "required"
        return knownMode && knownStatus && knownScope && validUnavailable
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case status
        case scope
        case reasonCode = "reason_code"
    }
}

public struct ClaimInput: Codable, Equatable, Sendable {
    public let accessCode: String
    public let idempotencyKey: String

    public init(accessCode: String, idempotencyKey: String) {
        self.accessCode = accessCode
        self.idempotencyKey = idempotencyKey
    }

    enum CodingKeys: String, CodingKey {
        case accessCode = "access_code"
        case idempotencyKey = "idempotency_key"
    }
}

public struct AuthAccessPair: Equatable, Sendable {
    public let code: String
    public let idempotencyKey: String

    public init?(code: String?, idempotencyKey: String?) {
        guard let code = Self.normalized(code, length: 9...64),
              let idempotencyKey = Self.normalized(idempotencyKey, length: 8...128) else {
            return nil
        }
        self.code = code
        self.idempotencyKey = idempotencyKey
    }

    public var requestFields: [String: String] {
        [
            "access_code": code,
            "idempotency_key": idempotencyKey,
        ]
    }

    private static func normalized(_ value: String?, length: ClosedRange<Int>) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard length.contains(trimmed.count) else { return nil }
        return trimmed
    }
}

public struct ClaimResult: Codable, Equatable, Sendable {
    public let access: AccessState
    public let cohort: String?

    public init(access: AccessState, cohort: String?) {
        self.access = access
        self.cohort = cohort
    }
}

public struct CampaignContent: Codable, Equatable, Sendable {
    public let title: String
    public let description: String
    public let actionLabel: String

    public init(title: String, description: String, actionLabel: String) {
        self.title = title
        self.description = description
        self.actionLabel = actionLabel
    }

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case actionLabel = "action_label"
    }
}

public struct CampaignBlock: Codable, Equatable, Sendable {
    public let campaignID: String
    public let surface: String
    public let templateKey: String
    public let content: CampaignContent

    public init(
        campaignID: String,
        surface: String,
        templateKey: String,
        content: CampaignContent
    ) {
        self.campaignID = campaignID
        self.surface = surface
        self.templateKey = templateKey
        self.content = content
    }

    public var isSupported: Bool {
        campaignID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            surface == "access.gate" &&
            templateKey == "private_beta" &&
            content.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            content.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            content.actionLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    enum CodingKeys: String, CodingKey {
        case campaignID = "campaign_id"
        case surface
        case templateKey = "template_key"
        case content
    }
}

public struct PendingCode: Equatable, Sendable {
    public let code: String

    public init(code: String) {
        self.code = code
    }
}

public protocol CodeStoring: Sendable {
    func load() -> String?
    func save(_ code: String)
    func clear()
}

public protocol AccessServing: Sendable {
    func get() async throws -> AccessState
    func claim(_ input: ClaimInput) async throws -> ClaimResult
}
