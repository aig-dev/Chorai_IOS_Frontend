import Foundation

public enum InvitationCode {
    public static func normalized(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

public enum CreditTier: Equatable, Hashable, Sendable {
    case credit
    case premiumCredit
    case unknown(String)

    public init(canonical: String) {
        switch canonical {
        case "credit": self = .credit
        case "premium_credit": self = .premiumCredit
        default: self = .unknown(canonical)
        }
    }

    public var canonical: String {
        switch self {
        case .credit: return "credit"
        case .premiumCredit: return "premium_credit"
        case .unknown(let value): return value
        }
    }
}

public enum InvitationStatus: Equatable, Hashable, Sendable {
    case registered
    case qualified
    case rewarded
    case expired
    case rejected
    case unknown(String)

    public init(canonical: String) {
        switch canonical {
        case "registered": self = .registered
        case "qualified": self = .qualified
        case "rewarded": self = .rewarded
        case "expired": self = .expired
        case "rejected": self = .rejected
        default: self = .unknown(canonical)
        }
    }

    public var canonical: String {
        switch self {
        case .registered: return "registered"
        case .qualified: return "qualified"
        case .rewarded: return "rewarded"
        case .expired: return "expired"
        case .rejected: return "rejected"
        case .unknown(let value): return value
        }
    }
}

public enum InvitationRewardStatus: Equatable, Hashable, Sendable {
    case pending
    case issued
    case failed
    case clawedBack
    case unknown(String)

    public init(canonical: String) {
        switch canonical {
        case "pending": self = .pending
        case "issued": self = .issued
        case "failed": self = .failed
        case "clawed_back": self = .clawedBack
        default: self = .unknown(canonical)
        }
    }

    public var canonical: String {
        switch self {
        case .pending: return "pending"
        case .issued: return "issued"
        case .failed: return "failed"
        case .clawedBack: return "clawed_back"
        case .unknown(let value): return value
        }
    }
}

public enum LedgerDirection: Equatable, Hashable, Sendable {
    case earn
    case spend
    case unknown(String)

    public init(canonical: String) {
        switch canonical {
        case "earn": self = .earn
        case "spend": self = .spend
        default: self = .unknown(canonical)
        }
    }

    public var canonical: String {
        switch self {
        case .earn: return "earn"
        case .spend: return "spend"
        case .unknown(let value): return value
        }
    }
}

public enum LedgerStatus: Equatable, Hashable, Sendable {
    case pending
    case settled
    case refunded
    case unknown(String)

    public init(canonical: String) {
        switch canonical {
        case "pending": self = .pending
        case "settled": self = .settled
        case "refunded": self = .refunded
        default: self = .unknown(canonical)
        }
    }

    public var canonical: String {
        switch self {
        case .pending: return "pending"
        case .settled: return "settled"
        case .refunded: return "refunded"
        case .unknown(let value): return value
        }
    }
}

public struct InvitationReferral: Equatable, Sendable {
    public let code: String
    public let link: String
    public let usedCount: Int
    public let nextMilestone: Int?

    public init(code: String, link: String, usedCount: Int, nextMilestone: Int?) {
        self.code = code
        self.link = link
        self.usedCount = usedCount
        self.nextMilestone = nextMilestone
    }

    public var sharePayload: String? {
        InvitationCode.normalized(link) ?? InvitationCode.normalized(code)
    }
}

public struct InvitationValidation: Equatable, Sendable {
    public let valid: Bool

    public init(valid: Bool) {
        self.valid = valid
    }
}

public struct InvitationRedemption: Equatable, Sendable {
    public let recordID: String
    public let status: InvitationStatus

    public init(recordID: String, status: InvitationStatus) {
        self.recordID = recordID
        self.status = status
    }
}

public struct InvitationRecord: Equatable, Identifiable, Sendable {
    public let id: String
    public let status: InvitationStatus
    public let createdAt: Date

    public init(id: String, status: InvitationStatus, createdAt: Date) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
    }
}

public struct InvitationReward: Equatable, Identifiable, Sendable {
    public let id: String
    public let recipientRole: String
    public let tier: CreditTier
    public let amount: Int
    public let isMilestoneBonus: Bool
    public let status: InvitationRewardStatus
    public let createdAt: Date

    public init(
        id: String,
        recipientRole: String,
        tier: CreditTier,
        amount: Int,
        isMilestoneBonus: Bool,
        status: InvitationRewardStatus,
        createdAt: Date
    ) {
        self.id = id
        self.recipientRole = recipientRole
        self.tier = tier
        self.amount = amount
        self.isMilestoneBonus = isMilestoneBonus
        self.status = status
        self.createdAt = createdAt
    }
}

public struct CreditBalance: Equatable, Sendable {
    public let tier: CreditTier
    public let balance: Int
    public let updatedAt: Date?

    public init(tier: CreditTier, balance: Int, updatedAt: Date?) {
        self.tier = tier
        self.balance = balance
        self.updatedAt = updatedAt
    }
}

public struct CreditBalances: Equatable, Sendable {
    public let regular: Int
    public let premium: Int

    public init(regular: Int, premium: Int) {
        self.regular = regular
        self.premium = premium
    }

    public static func normalized(_ entries: [CreditBalance]) -> Self {
        Self(
            regular: entries.first(where: { $0.tier == .credit })?.balance ?? 0,
            premium: entries.first(where: { $0.tier == .premiumCredit })?.balance ?? 0
        )
    }
}

public struct CreditLedgerEntry: Equatable, Identifiable, Sendable {
    public let id: String
    public let transactionID: String
    public let tier: CreditTier
    public let direction: LedgerDirection
    public let delta: Int
    public let runningBalance: Int
    public let status: LedgerStatus
    public let actionType: String
    public let category: String
    public let createdAt: Date

    public init(
        id: String,
        transactionID: String,
        tier: CreditTier,
        direction: LedgerDirection,
        delta: Int,
        runningBalance: Int,
        status: LedgerStatus,
        actionType: String,
        category: String,
        createdAt: Date
    ) {
        self.id = id
        self.transactionID = transactionID
        self.tier = tier
        self.direction = direction
        self.delta = delta
        self.runningBalance = runningBalance
        self.status = status
        self.actionType = actionType
        self.category = category
        self.createdAt = createdAt
    }
}

public struct InvitationPage: Equatable, Sendable {
    public let items: [InvitationRecord]
    public let total: Int
    public let page: Int
    public let limit: Int

    public init(items: [InvitationRecord], total: Int, page: Int, limit: Int) {
        self.items = items
        self.total = total
        self.page = page
        self.limit = limit
    }

    public var hasMore: Bool {
        guard page > 0, limit > 0 else { return false }
        return page * limit < total
    }
}

public struct InvitationRewardPage: Equatable, Sendable {
    public let items: [InvitationReward]
    public let total: Int
    public let page: Int
    public let limit: Int

    public init(items: [InvitationReward], total: Int, page: Int, limit: Int) {
        self.items = items
        self.total = total
        self.page = page
        self.limit = limit
    }

    public var hasMore: Bool {
        guard page > 0, limit > 0 else { return false }
        return page * limit < total
    }
}

public struct CreditLedgerPage: Equatable, Sendable {
    public let entries: [CreditLedgerEntry]
    public let cursor: String?
    public let hasMore: Bool

    public init(entries: [CreditLedgerEntry], cursor: String?, hasMore: Bool) {
        self.entries = entries
        self.cursor = cursor
        self.hasMore = hasMore
    }
}

public enum InvitationCreditError: Error, Equatable, Sendable {
    case invalidActor
    case invalidCode
    case unauthorized
    case contract(code: String)
    case requestFailed(message: String?)
}

public enum InvitationCreditSectionPhase: Equatable, Sendable {
    case idle
    case loading
    case refreshing
    case ready
    case failed(InvitationCreditError)
}

public enum InvitationCreditListPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case empty
    case loadingMore
    case failed(InvitationCreditError)
}

public struct InvitationAccountRegistrationRequest: Equatable, Sendable {
    public let username: String
    public let email: String
    public let password: String
    public let verificationCode: String

    public init(
        username: String,
        email: String,
        password: String,
        verificationCode: String
    ) {
        self.username = username
        self.email = email
        self.password = password
        self.verificationCode = verificationCode
    }
}

public struct InvitationRegisteredAccount: Equatable, Sendable {
    public let actorID: String
    public let isNewUser: Bool

    public init(actorID: String, isNewUser: Bool) {
        self.actorID = actorID
        self.isNewUser = isNewUser
    }
}
