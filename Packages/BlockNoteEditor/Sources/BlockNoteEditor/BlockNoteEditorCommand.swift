import Foundation

public enum BlockNoteEditorProtocol {
    public static let version = 2
    public static let schemaVersion = 1
    public static let webKitHandlerName = "blockNoteEditor"
    static let javaScriptBridgeName = "ChoraiBlockNoteEditor"
    static let javaScriptQueueName = "__choraiEditorCommandQueue"
}

public struct BlockNoteInitialDocument: Equatable, Sendable {
    public let contentJSON: String?
    public let fallbackMarkdown: String

    public init(contentJSON: String?, fallbackMarkdown: String) {
        self.contentJSON = contentJSON
        self.fallbackMarkdown = fallbackMarkdown
    }
}

public enum BlockNoteFormat: String, Codable, CaseIterable, Sendable {
    case bold
    case italic
    case underline
    case strike
}

public enum BlockNoteBlockType: String, Codable, CaseIterable, Sendable {
    case paragraph
    case heading2
    case heading3
}

public enum BlockNoteListType: String, Codable, CaseIterable, Sendable {
    case bullet
    case numbered
    case checklist
}

public enum BlockNoteEditorCommand: Equatable, Sendable, Codable {
    case initialize(
        protocolVersion: Int,
        documentJSON: String?,
        fallbackMarkdown: String,
        editable: Bool
    )
    case applyFormat(BlockNoteFormat)
    case setBlockType(BlockNoteBlockType)
    case toggleList(BlockNoteListType)
    case insertLink(url: String, text: String)
    case insertImage(url: String, alt: String)
    case undo
    case redo
    case focus
    case blur
    case requestSnapshot(requestID: String)

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion
        case documentJSON
        case fallbackMarkdown
        case editable
        case format
        case blockType
        case listType
        case url
        case text
        case alt
        case requestID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "initialize":
            let documentJSON: String?
            if try container.decodeNil(forKey: .documentJSON) {
                documentJSON = nil
            } else {
                documentJSON = try container.decode(String.self, forKey: .documentJSON)
            }
            self = .initialize(
                protocolVersion: try container.decode(Int.self, forKey: .protocolVersion),
                documentJSON: documentJSON,
                fallbackMarkdown: try container.decode(String.self, forKey: .fallbackMarkdown),
                editable: try container.decode(Bool.self, forKey: .editable)
            )

        case "applyFormat":
            self = .applyFormat(try container.decode(BlockNoteFormat.self, forKey: .format))

        case "setBlockType":
            self = .setBlockType(try container.decode(BlockNoteBlockType.self, forKey: .blockType))

        case "toggleList":
            self = .toggleList(try container.decode(BlockNoteListType.self, forKey: .listType))

        case "insertLink":
            self = .insertLink(
                url: try container.decode(String.self, forKey: .url),
                text: try container.decode(String.self, forKey: .text)
            )

        case "insertImage":
            self = .insertImage(
                url: try container.decode(String.self, forKey: .url),
                alt: try container.decode(String.self, forKey: .alt)
            )

        case "undo":
            self = .undo
        case "redo":
            self = .redo
        case "focus":
            self = .focus
        case "blur":
            self = .blur

        case "requestSnapshot":
            let requestID = try container.decode(String.self, forKey: .requestID)
            guard !requestID.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .requestID,
                    in: container,
                    debugDescription: "Snapshot request IDs cannot be empty."
                )
            }
            self = .requestSnapshot(requestID: requestID)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown BlockNote command type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .initialize(protocolVersion, documentJSON, fallbackMarkdown, editable):
            try container.encode("initialize", forKey: .type)
            try container.encode(protocolVersion, forKey: .protocolVersion)
            if let documentJSON {
                try container.encode(documentJSON, forKey: .documentJSON)
            } else {
                try container.encodeNil(forKey: .documentJSON)
            }
            try container.encode(fallbackMarkdown, forKey: .fallbackMarkdown)
            try container.encode(editable, forKey: .editable)

        case let .applyFormat(format):
            try container.encode("applyFormat", forKey: .type)
            try container.encode(format, forKey: .format)

        case let .setBlockType(blockType):
            try container.encode("setBlockType", forKey: .type)
            try container.encode(blockType, forKey: .blockType)

        case let .toggleList(listType):
            try container.encode("toggleList", forKey: .type)
            try container.encode(listType, forKey: .listType)

        case let .insertLink(url, text):
            try container.encode("insertLink", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(text, forKey: .text)

        case let .insertImage(url, alt):
            try container.encode("insertImage", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encode(alt, forKey: .alt)

        case .undo:
            try container.encode("undo", forKey: .type)
        case .redo:
            try container.encode("redo", forKey: .type)
        case .focus:
            try container.encode("focus", forKey: .type)
        case .blur:
            try container.encode("blur", forKey: .type)

        case let .requestSnapshot(requestID):
            guard !requestID.isEmpty else {
                throw EncodingError.invalidValue(
                    requestID,
                    .init(
                        codingPath: encoder.codingPath,
                        debugDescription: "Snapshot request IDs cannot be empty."
                    )
                )
            }
            try container.encode("requestSnapshot", forKey: .type)
            try container.encode(requestID, forKey: .requestID)
        }
    }

    var isMutation: Bool {
        switch self {
        case .applyFormat, .setBlockType, .toggleList, .insertLink, .insertImage, .undo, .redo:
            return true
        case .initialize, .focus, .blur, .requestSnapshot:
            return false
        }
    }

    var snapshotRequestID: String? {
        guard case let .requestSnapshot(requestID) = self else { return nil }
        return requestID
    }
}
