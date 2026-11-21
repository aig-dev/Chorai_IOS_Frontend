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

public enum CardEditingTag {
    public static let maximumCount = 10

    public static func normalized(_ value: String) -> String? {
        let tag = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^#+\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? nil : tag
    }

    public static func normalize(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            guard let tag = normalized(value), seen.insert(tag).inserted else {
                continue
            }
            result.append(tag)
            if result.count == maximumCount { break }
        }
        return result
    }

    public static func appending(
        _ candidate: String,
        to values: [String]
    ) -> [String]? {
        let current = normalize(values)
        guard current.count < maximumCount,
              let tag = normalized(candidate),
              !current.contains(tag) else {
            return nil
        }
        return current + [tag]
    }
}

public struct CardEditingDraft: Equatable, Sendable {
    public let title: String?
    public let content: String
    public let contentJSON: String?
    public let editorAtmosphere: String
    public let tags: [String]
    public let isPublic: Bool
    private let commitJSONProjection: CommitJSONProjection

    public init(
        title: String?,
        content: String,
        contentJSON: String? = nil,
        editorAtmosphere: String = "none",
        tags: [String],
        isPublic: Bool
    ) {
        let normalizedContentJSON = Self.nonEmpty(contentJSON)
        self.title = CardEditingTitle.normalized(title)
        self.content = content
        self.contentJSON = normalizedContentJSON
        self.editorAtmosphere = editorAtmosphere
        self.tags = CardEditingTag.normalize(tags)
        self.isPublic = isPublic
        self.commitJSONProjection = Self.commitJSONProjection(
            normalizedContentJSON
        )
    }

    public func isCommitEquivalent(to other: Self) -> Bool {
        if self == other { return true }

        guard title == other.title,
              editorAtmosphere == other.editorAtmosphere,
              tags == other.tags,
              isPublic == other.isPublic else {
            return false
        }

        switch (commitJSONProjection, other.commitJSONProjection) {
        case (.none, .none):
            return content == other.content
        case let (.blocks(lhsBlocks), .blocks(rhsBlocks)):
            return lhsBlocks == rhsBlocks
        case let (.root(lhsRoot), .root(rhsRoot)):
            return content == other.content && lhsRoot == rhsRoot
        case (.invalid, .invalid):
            return content == other.content && contentJSON == other.contentJSON
        default:
            return false
        }
    }

    public var hasMeaningfulContent: Bool {
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        guard let contentJSON,
              let root = Self.structuredJSONRoot(contentJSON),
              root is [Any] || root is [String: Any] else {
            return false
        }
        return Self.containsMeaningfulContent(root)
    }

    public var validationError: CardEditingError? {
        if let contentJSON, !Self.hasStructuredJSONRoot(contentJSON) {
            return .invalidDraft(code: "invalid_content_json")
        }
        if !hasMeaningfulContent {
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

    private enum CommitJSONProjection: Equatable, Sendable {
        case none
        case blocks(Data)
        case root(Data)
        case invalid
    }

    private static func commitJSONProjection(
        _ value: String?
    ) -> CommitJSONProjection {
        guard let value else { return .none }
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .invalid
        }

        if let blocks = object as? [Any] {
            return canonicalJSONData(blocks).map(CommitJSONProjection.blocks)
                ?? .invalid
        }
        if let envelope = object as? [String: Any] {
            if envelope.keys.contains("blocks") {
                guard let blocks = envelope["blocks"] as? [Any] else {
                    return .invalid
                }
                return canonicalJSONData(blocks)
                    .map(CommitJSONProjection.blocks) ?? .invalid
            }
            return canonicalJSONData(envelope).map(CommitJSONProjection.root)
                ?? .invalid
        }
        return .invalid
    }

    private static func canonicalJSONData(_ value: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject(value) else { return nil }
        return try? JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys]
        )
    }

    private static func hasStructuredJSONRoot(_ value: String) -> Bool {
        guard let root = structuredJSONRoot(value) else {
            return false
        }
        if root is [Any] { return true }
        guard let object = root as? [String: Any] else { return false }
        if object.keys.contains("blocks") {
            return object["blocks"] is [Any]
        }
        return true
    }

    private static func structuredJSONRoot(_ value: String) -> Any? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        )
    }

    private static func containsMeaningfulContent(_ value: Any) -> Bool {
        if let text = value as? String {
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let values = value as? [Any] {
            return values.contains(where: containsMeaningfulContent)
        }
        guard let object = value as? [String: Any] else { return false }

        if let type = object["type"] as? String,
           ["image", "audio", "video", "file"].contains(type.lowercased()),
           hasMediaSource(object) {
            return true
        }

        for key in ["text", "content", "children", "blocks", "rows", "cells"] {
            if let candidate = object[key], containsMeaningfulContent(candidate) {
                return true
            }
        }
        return false
    }

    private static func hasMediaSource(_ object: [String: Any]) -> Bool {
        let containers = [object, object["props"] as? [String: Any]].compactMap { $0 }
        for container in containers {
            for key in ["url", "src", "mediaRef", "media_ref"] {
                guard let value = container[key] as? String else { continue }
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }
            }
        }
        return false
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
    public let noteLinkID: String?
    public let title: String
    public let previewHTML: String?
    public let authorName: String?
    public let authorAvatarURL: String?

    public init(
        sourceCardID: String,
        targetCardID: String,
        title: String,
        noteLinkID: String? = nil,
        previewHTML: String? = nil,
        authorName: String? = nil,
        authorAvatarURL: String? = nil
    ) {
        self.sourceCardID = sourceCardID
        self.targetCardID = targetCardID
        self.noteLinkID = noteLinkID
        self.title = title
        self.previewHTML = previewHTML
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
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

public enum CardEditingBackgroundIntent: Equatable, Sendable {
    case unchanged
    case replace(CardEditingImage)
    case remove
}

public struct CardEditingInlineImageUpload: Equatable, Sendable {
    public let mediaRef: String
    public let url: URL

    public init(mediaRef: String, url: URL) {
        self.mediaRef = mediaRef
        self.url = url
    }
}

public enum CardEditingMediaURLResolver {
    public static func resolve(
        _ rawValue: String,
        canonicalizeRelativePath: (String) -> String
    ) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("/"), !value.hasPrefix("//") {
            return validatedHTTPURL(canonicalizeRelativePath(value))
        }
        return validatedHTTPURL(value)
    }

    private static func validatedHTTPURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
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
