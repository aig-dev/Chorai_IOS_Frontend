import Foundation

public struct CardEditingDraft: Equatable, Sendable {
    public let title: String?
    public let content: String
    public let tags: [String]
    public let isPublic: Bool

    public init(
        title: String?,
        content: String,
        tags: [String],
        isPublic: Bool
    ) {
        self.title = title
        self.content = content
        self.tags = Self.normalize(tags)
        self.isPublic = isPublic
    }

    private static func normalize(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for value in values {
            let tag = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(
                    of: #"^#+\s*"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, seen.insert(tag).inserted else { continue }
            normalized.append(tag)
            if normalized.count == 10 { break }
        }
        return normalized
    }
}

public struct CardEditingSnapshot: Equatable, Sendable {
    public let id: String
    public let title: String?
    public let content: String
    public let tags: [String]
    public let isPublic: Bool
    public let backgroundMediaRef: String?

    public init(
        id: String,
        title: String?,
        content: String,
        tags: [String],
        isPublic: Bool,
        backgroundMediaRef: String?
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.tags = tags
        self.isPublic = isPublic
        self.backgroundMediaRef = backgroundMediaRef
    }
}

public struct CardEditingLink: Equatable, Sendable {
    public let sourceCardID: String
    public let targetCardID: String
    public let title: String

    public init(sourceCardID: String, targetCardID: String, title: String) {
        self.sourceCardID = sourceCardID
        self.targetCardID = targetCardID
        self.title = title
    }
}

public struct CardEditingImage: Equatable, Sendable {
    public static let maxBackgroundBytes = 10 * 1024 * 1024

    public let data: Data
    public let filename: String
    public let mimeType: String

    public init(data: Data, filename: String, mimeType: String) {
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
    }

    public var isValidBackground: Bool {
        !data.isEmpty
            && data.count <= Self.maxBackgroundBytes
            && mimeType.lowercased().hasPrefix("image/")
    }
}

public enum CardEditingError: Error, Equatable, Sendable {
    case invalidDraft(code: String)
    case transport(code: String)
}

public enum CardEditingPhase: Equatable, Sendable {
    case idle
    case saving
    case linking
    case updatingBackground
    case ready
    case failed(CardEditingError)
}
