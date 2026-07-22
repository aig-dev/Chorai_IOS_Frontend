import Foundation

public enum ContentReportReason: String, CaseIterable, Equatable, Identifiable, Sendable {
    case spam = "SPAM"
    case harassment = "HARASSMENT"
    case misinformation = "MISINFORMATION"
    case copyright = "COPYRIGHT"
    case other = "OTHER"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .spam: return "Spam"
        case .harassment: return "Harassment"
        case .misinformation: return "Misinformation"
        case .copyright: return "Copyright"
        case .other: return "Other"
        }
    }
}

public enum ContentReportTargetType: String, Equatable, Sendable {
    case asset = "ASSET"
    case actor = "ACTOR"
    case comment = "COMMENT"
}

public struct ContentReportRequest: Equatable, Sendable {
    public let targetType: String
    public let targetID: String
    public let reasonCode: String
    public let detail: String?

    public init(
        targetType: String,
        targetID: String,
        reasonCode: String,
        detail: String?
    ) {
        self.targetType = targetType
        self.targetID = targetID
        self.reasonCode = reasonCode
        self.detail = detail
    }
}

public struct ContentReportReceipt: Equatable, Sendable {
    public let reportID: String
    public let status: String
    public let updatedAt: String

    public init(reportID: String, status: String, updatedAt: String) {
        self.reportID = reportID
        self.status = status
        self.updatedAt = updatedAt
    }
}

public enum ContentReportError: Error, Equatable, Sendable {
    case transport(code: String)
    case invalidResponse(code: String)

    public var code: String {
        switch self {
        case .transport(let code), .invalidResponse(let code):
            return code
        }
    }
}

public enum ContentReportPhase: Equatable, Sendable {
    case editing
    case submitting
    case submitted(ContentReportReceipt)
    case failed(ContentReportError)

    public var isSubmitted: Bool {
        if case .submitted = self { return true }
        return false
    }

    public var receipt: ContentReportReceipt? {
        guard case .submitted(let receipt) = self else { return nil }
        return receipt
    }
}
