import Foundation

public enum CardEditingTitle {
    public static func normalized(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

public struct CardEditingDraft: Equatable, Sendable {
    public let title: String?
    public let content: String
    public let contentJSON: String?
    public let editorAtmosphere: String
    public let tags: [String]
    public let isPublic: Bool

    public init(
        title: String?,
        content: String,
        contentJSON: String? = nil,
        editorAtmosphere: String = "none",
        tags: [String],
        isPublic: Bool
    ) {
        self.title = CardEditingTitle.normalized(title)
        self.content = content
        self.contentJSON = Self.nonEmpty(contentJSON)
        self.editorAtmosphere = editorAtmosphere
        self.tags = Self.normalize(tags)
        self.isPublic = isPublic
    }

    public var validationError: CardEditingError? {
        if let contentJSON, !Self.hasStructuredJSONRoot(contentJSON) {
            return .invalidDraft(code: "invalid_content_json")
        }
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           contentJSON == nil {
            return .invalidDraft(code: "empty_content")
        }
        return nil
    }

    public func updatingMetadataAndFallback(
        title: String?,
        content: String,
        tags: [String],
        isPublic: Bool
    ) -> CardEditingDraft {
        CardEditingDraft(
            title: title,
            content: content,
            contentJSON: contentJSON,
            editorAtmosphere: editorAtmosphere,
            tags: tags,
            isPublic: isPublic
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private static func hasStructuredJSONRoot(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
              ) else {
            return false
        }
        return root is [Any] || root is [String: Any]
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
    public let contentJSON: String?
    public let editorAtmosphere: String
    public let tags: [String]
    public let isPublic: Bool
    public let backgroundMediaRef: String?

    public init(
        id: String,
        title: String?,
        content: String,
        contentJSON: String? = nil,
        editorAtmosphere: String = "none",
        tags: [String],
        isPublic: Bool,
        backgroundMediaRef: String?
    ) {
        self.id = id
        self.title = CardEditingTitle.normalized(title)
        self.content = content
        self.contentJSON = contentJSON
        self.editorAtmosphere = editorAtmosphere
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

public enum CardEditingFailureStage: Equatable, Sendable {
    case creatingCard
    case updatingCard
    case replacingBackground
    case removingBackground
    case creatingLink
    case deletingLink
}
