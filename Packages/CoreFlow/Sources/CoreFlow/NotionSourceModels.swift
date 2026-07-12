import Foundation

public enum KnownNotionClient: String, Codable, Sendable {
    case web
    case ios
}

public struct NotionClient: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var knownValue: KnownNotionClient? {
        KnownNotionClient(rawValue: rawValue)
    }

    public static let web = Self(rawValue: "web")
    public static let ios = Self(rawValue: "ios")

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum KnownNotionConnectionState: String, Codable, Sendable {
    case disconnected
    case connecting
    case connected
}

public struct NotionConnectionState: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var knownValue: KnownNotionConnectionState? {
        KnownNotionConnectionState(rawValue: rawValue)
    }

    public static let disconnected = Self(rawValue: "disconnected")
    public static let connecting = Self(rawValue: "connecting")
    public static let connected = Self(rawValue: "connected")

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct NotionConnectionStatus: Codable, Equatable, Sendable {
    public let state: NotionConnectionState
    public let workspaceID: String?
    public let workspaceName: String?

    public init(
        state: NotionConnectionState,
        workspaceID: String? = nil,
        workspaceName: String? = nil
    ) {
        self.state = state
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
    }
}

public struct NotionPage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct NotionImportReceipt: Codable, Equatable, Sendable {
    public let jobID: String
    public let acceptedPageIDs: [String]

    public init(jobID: String, acceptedPageIDs: [String] = []) {
        self.jobID = jobID
        self.acceptedPageIDs = acceptedPageIDs
    }
}

public enum KnownNotionImportJobStatus: String, Codable, Sendable {
    case queued
    case running
    case done
    case failed
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .done, .failed, .cancelled:
            true
        case .queued, .running:
            false
        }
    }
}

public struct NotionImportJobStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var knownValue: KnownNotionImportJobStatus? {
        KnownNotionImportJobStatus(rawValue: rawValue)
    }

    public var isKnownTerminal: Bool {
        knownValue?.isTerminal == true
    }

    public static let queued = Self(rawValue: "queued")
    public static let running = Self(rawValue: "running")
    public static let done = Self(rawValue: "done")
    public static let failed = Self(rawValue: "failed")
    public static let cancelled = Self(rawValue: "cancelled")

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct NotionPageFailure: Codable, Equatable, Sendable {
    public let pageID: String
    public let reason: String

    public init(pageID: String, reason: String) {
        self.pageID = pageID
        self.reason = reason
    }
}

public struct NotionImportJob: Codable, Equatable, Sendable {
    public let id: String
    public let status: NotionImportJobStatus
    public let imported: Int
    public let updated: Int
    public let skipped: Int
    public let failures: [NotionPageFailure]

    public init(
        id: String,
        status: NotionImportJobStatus,
        imported: Int,
        updated: Int,
        skipped: Int,
        failures: [NotionPageFailure]
    ) {
        self.id = id
        self.status = status
        self.imported = imported
        self.updated = updated
        self.skipped = skipped
        self.failures = failures
    }
}

public enum NotionAuthorizationResult: Equatable, Sendable {
    case success
    case cancelled
    case failed
}

public struct NotionAuthorizationRequest: Equatable, Sendable {
    public let id: UUID
    public let url: URL

    public init(id: UUID, url: URL) {
        self.id = id
        self.url = url
    }
}

public enum NotionSourcePhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed
}

public enum NotionSourceError: Error, Equatable, Sendable {
    case invalidActor
    case noPagesSelected
    case requestFailed
    case authorizationFailed
}
