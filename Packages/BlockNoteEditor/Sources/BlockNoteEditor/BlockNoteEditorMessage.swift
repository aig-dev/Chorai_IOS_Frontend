import Foundation

public struct BlockNoteSnapshot: Equatable, Sendable {
    public let requestID: String
    public let revision: Int
    public let contentJSON: String
    public let fallbackMarkdown: String

    public init(
        requestID: String,
        revision: Int,
        contentJSON: String,
        fallbackMarkdown: String
    ) {
        self.requestID = requestID
        self.revision = revision
        self.contentJSON = contentJSON
        self.fallbackMarkdown = fallbackMarkdown
    }
}

public struct BlockNoteDocumentRevision: Equatable, Sendable {
    public let revision: Int
    public let contentJSON: String
    public let fallbackMarkdown: String

    public init(revision: Int, contentJSON: String, fallbackMarkdown: String) {
        self.revision = revision
        self.contentJSON = contentJSON
        self.fallbackMarkdown = fallbackMarkdown
    }
}

public enum BlockNoteSelectionBlockType: String, Codable, CaseIterable, Sendable {
    case paragraph
    case heading2
    case heading3
    case bullet
    case numbered
    case checklist
    case unsupported
}

public struct BlockNoteSelectionFormats: Codable, Equatable, Sendable {
    public let bold: Bool
    public let italic: Bool
    public let underline: Bool
    public let strike: Bool

    public init(bold: Bool, italic: Bool, underline: Bool, strike: Bool) {
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strike = strike
    }
}

public struct BlockNoteSelectionState: Codable, Equatable, Sendable {
    public let blockType: BlockNoteSelectionBlockType
    public let formats: BlockNoteSelectionFormats

    public init(blockType: BlockNoteSelectionBlockType, formats: BlockNoteSelectionFormats) {
        self.blockType = blockType
        self.formats = formats
    }
}

public enum BlockNoteEditorMessage: Codable, Equatable, Sendable {
    case ready(protocolVersion: Int, schemaVersion: Int)
    case documentChanged(
        revision: Int,
        contentJSON: String,
        fallbackMarkdown: String
    )
    case selectionChanged(BlockNoteSelectionState)
    case bodyFocusChanged(isFocused: Bool)
    case heightChanged(contentHeight: Double)
    case requestCardLink
    case snapshot(
        requestID: String,
        revision: Int,
        contentJSON: String,
        fallbackMarkdown: String
    )
    case compatibilityBlocked(code: String, details: String)
    case bridgeError(code: String)

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion
        case schemaVersion
        case revision
        case contentJSON
        case fallbackMarkdown
        case selectionState
        case isFocused
        case contentHeight
        case requestID
        case code
        case details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "ready":
            self = .ready(
                protocolVersion: try container.decode(Int.self, forKey: .protocolVersion),
                schemaVersion: try container.decode(Int.self, forKey: .schemaVersion)
            )

        case "documentChanged":
            let revision = try Self.decodeRevision(from: container)
            self = .documentChanged(
                revision: revision,
                contentJSON: try container.decode(String.self, forKey: .contentJSON),
                fallbackMarkdown: try container.decode(String.self, forKey: .fallbackMarkdown)
            )

        case "selectionChanged":
            self = .selectionChanged(
                try container.decode(BlockNoteSelectionState.self, forKey: .selectionState)
            )

        case "bodyFocusChanged":
            self = .bodyFocusChanged(
                isFocused: try container.decode(Bool.self, forKey: .isFocused)
            )

        case "heightChanged":
            let height = try container.decode(Double.self, forKey: .contentHeight)
            guard height.isFinite, height >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .contentHeight,
                    in: container,
                    debugDescription: "Content height must be finite and nonnegative."
                )
            }
            self = .heightChanged(contentHeight: height)

        case "requestCardLink":
            self = .requestCardLink

        case "snapshot":
            let requestID = try container.decode(String.self, forKey: .requestID)
            guard !requestID.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .requestID,
                    in: container,
                    debugDescription: "Snapshot request IDs cannot be empty."
                )
            }
            self = .snapshot(
                requestID: requestID,
                revision: try Self.decodeRevision(from: container),
                contentJSON: try container.decode(String.self, forKey: .contentJSON),
                fallbackMarkdown: try container.decode(String.self, forKey: .fallbackMarkdown)
            )

        case "compatibilityBlocked":
            self = .compatibilityBlocked(
                code: try container.decode(String.self, forKey: .code),
                details: try container.decode(String.self, forKey: .details)
            )

        case "bridgeError":
            self = .bridgeError(code: try container.decode(String.self, forKey: .code))

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown BlockNote event type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .ready(protocolVersion, schemaVersion):
            try container.encode("ready", forKey: .type)
            try container.encode(protocolVersion, forKey: .protocolVersion)
            try container.encode(schemaVersion, forKey: .schemaVersion)

        case let .documentChanged(revision, contentJSON, fallbackMarkdown):
            try container.encode("documentChanged", forKey: .type)
            try container.encode(revision, forKey: .revision)
            try container.encode(contentJSON, forKey: .contentJSON)
            try container.encode(fallbackMarkdown, forKey: .fallbackMarkdown)

        case let .selectionChanged(selectionState):
            try container.encode("selectionChanged", forKey: .type)
            try container.encode(selectionState, forKey: .selectionState)

        case let .bodyFocusChanged(isFocused):
            try container.encode("bodyFocusChanged", forKey: .type)
            try container.encode(isFocused, forKey: .isFocused)

        case let .heightChanged(contentHeight):
            try container.encode("heightChanged", forKey: .type)
            try container.encode(contentHeight, forKey: .contentHeight)

        case .requestCardLink:
            try container.encode("requestCardLink", forKey: .type)

        case let .snapshot(requestID, revision, contentJSON, fallbackMarkdown):
            try container.encode("snapshot", forKey: .type)
            try container.encode(requestID, forKey: .requestID)
            try container.encode(revision, forKey: .revision)
            try container.encode(contentJSON, forKey: .contentJSON)
            try container.encode(fallbackMarkdown, forKey: .fallbackMarkdown)

        case let .compatibilityBlocked(code, details):
            try container.encode("compatibilityBlocked", forKey: .type)
            try container.encode(code, forKey: .code)
            try container.encode(details, forKey: .details)

        case let .bridgeError(code):
            try container.encode("bridgeError", forKey: .type)
            try container.encode(code, forKey: .code)
        }
    }

    private static func decodeRevision(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Int {
        let revision = try container.decode(Int.self, forKey: .revision)
        guard revision >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .revision,
                in: container,
                debugDescription: "Document revisions cannot be negative."
            )
        }
        return revision
    }
}
