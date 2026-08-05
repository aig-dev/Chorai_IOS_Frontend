import Foundation

struct CreditBalanceData: Codable {
    let balance: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case balance
        case updatedAt = "updated_at"
    }
}

struct UseInvitationRequest: Codable {
    let code: String
}

struct ValidateInvitationRequest: Codable {
    let code: String
}

struct InvitationValidateResponse: Codable {
    let success: Bool
    let message: String?
    let data: InvitationValidateData
}

struct InvitationValidateData: Codable {
    let valid: Bool
}

struct InvitationRedeemResponse: Codable {
    let success: Bool
    let message: String?
    let data: InvitationRedeemData
}

struct InvitationRedeemData: Codable {
    let invitationRecordId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case invitationRecordId = "invitation_record_id"
        case status
    }
}

struct InvitationReferralResponse: Codable {
    let success: Bool
    let message: String?
    let data: InvitationReferralData
}

struct InvitationReferralData: Codable {
    let code: String
    let link: String
    let usedCount: Int
    let nextMilestone: Int?

    enum CodingKeys: String, CodingKey {
        case code, link
        case usedCount = "used_count"
        case nextMilestone = "next_milestone"
    }
}

struct InvitationTrackRequest: Codable {
    let code: String
    let deviceFingerprint: String?

    enum CodingKeys: String, CodingKey {
        case code
        case deviceFingerprint = "device_fingerprint"
    }
}

struct InvitationTrackResponse: Codable {
    let success: Bool
    let message: String?
    let data: InvitationTrackData
}

struct InvitationTrackData: Codable {
    let tracked: Bool
}

struct InvitationRecordsResponse: Codable {
    let success: Bool
    let message: String?
    let data: InvitationPaginatedData<InvitationRecordItem>
}

struct InvitationRewardsResponse: Codable {
    let success: Bool
    let message: String?
    let data: InvitationPaginatedData<InvitationRewardItem>
}

struct InvitationPaginatedData<Item: Codable>: Codable {
    let items: [Item]
    let total: Int
    let page: Int
    let limit: Int
}

struct InvitationRecordItem: Codable, Identifiable {
    let invitationRecordId: String
    let inviterActorId: String
    let inviteeActorId: String
    let status: String
    let createdAt: String
    let qualifiedAt: String?
    let rewardedAt: String?

    var id: String { invitationRecordId }

    enum CodingKeys: String, CodingKey {
        case invitationRecordId = "invitation_record_id"
        case inviterActorId = "inviter_actor_id"
        case inviteeActorId = "invitee_actor_id"
        case status
        case createdAt = "created_at"
        case qualifiedAt = "qualified_at"
        case rewardedAt = "rewarded_at"
    }
}

struct InvitationRewardItem: Codable, Identifiable {
    let invitationRewardId: String
    let recipientRole: String
    let amount: Int
    let milestoneThreshold: Int
    let status: String
    let createdAt: String

    var id: String { invitationRewardId }

    enum CodingKeys: String, CodingKey {
        case invitationRewardId = "invitation_reward_id"
        case recipientRole = "recipient_role"
        case amount
        case milestoneThreshold = "milestone_threshold"
        case status
        case createdAt = "created_at"
    }
}

struct CreditLedgerResponse: Codable {
    let success: Bool
    let message: String?
    let data: CreditLedgerData
}

struct CreditLedgerData: Codable {
    let entries: [CreditLedgerEntryResponse]
    let cursor: String?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case entries, cursor
        case hasMore = "has_more"
    }
}

struct CreditLedgerEntryResponse: Codable {
    let logId: String
    let transactionId: String
    let account: String
    let direction: String
    let delta: Int
    let runningBalance: Int
    let status: String
    let ruleId: String
    let actionType: String
    let category: String
    let referenceId: String
    let referenceType: String
    let activityId: String?
    let createdAt: String
    let settledAt: String?
    let refundedAt: String?

    enum CodingKeys: String, CodingKey {
        case account, delta, direction, status, category
        case logId = "log_id"
        case transactionId = "transaction_id"
        case runningBalance = "running_balance"
        case ruleId = "rule_id"
        case actionType = "action_type"
        case referenceId = "reference_id"
        case referenceType = "reference_type"
        case activityId = "activity_id"
        case createdAt = "created_at"
        case settledAt = "settled_at"
        case refundedAt = "refunded_at"
    }
}
