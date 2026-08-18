import Foundation

public struct MergeArtifactEditableDocument: Equatable, Sendable {
    public let blockNoteJSON: String
    public let fallbackMarkdown: String
    public let preservationManifest: Data

    public init(
        blockNoteJSON: String,
        fallbackMarkdown: String,
        preservationManifest: Data
    ) {
        self.blockNoteJSON = blockNoteJSON
        self.fallbackMarkdown = fallbackMarkdown
        self.preservationManifest = preservationManifest
    }
}

public enum MergeArtifactEditorCodecError: Error, Equatable, Sendable {
    case invalidCardDocument
    case invalidBlockNoteDocument
    case unsupportedDocument
    case losslessRoundTripFailed
}

public enum MergeArtifactEditorCodec {
    public static func decode(
        cardDocumentJSON: Data
    ) throws -> MergeArtifactEditableDocument {
        let document: CodecJSON
        do {
            document = try CodecJSON.parse(cardDocumentJSON)
        } catch {
            throw MergeArtifactEditorCodecError.invalidCardDocument
        }

        guard case .object(let root) = document,
              root["schemaVersion"] == .string("card_doc.v1"),
              case .array(let serverBlocks)? = root["blocks"],
              case .object? = root["meta"] else {
            throw MergeArtifactEditorCodecError.invalidCardDocument
        }
        try requireOnlyKeys(
            root,
            allowed: ["schemaVersion", "title", "subtitle", "blocks", "meta"],
            error: .invalidCardDocument
        )

        var context = DecodeContext()
        let editorBlocks = try serverBlocks.enumerated().map { index, block in
            try editorBlock(
                from: block,
                path: [index],
                context: &context
            )
        }
        let canonicalDocument = try document.canonicalData()
        let manifest = PreservationManifest(
            schemaVersion: PreservationManifest.currentSchemaVersion,
            originalDocumentJSON: canonicalDocument,
            passthrough: context.passthrough
        )
        let manifestData: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            manifestData = try encoder.encode(manifest)
        } catch {
            throw MergeArtifactEditorCodecError.invalidCardDocument
        }

        return MergeArtifactEditableDocument(
            blockNoteJSON: try CodecJSON.array(editorBlocks).canonicalString(),
            fallbackMarkdown: context.markdown.joined(separator: "\n"),
            preservationManifest: manifestData
        )
    }

    public static func encode(
        blockNoteJSON: String,
        preserving manifest: Data
    ) throws -> Data {
        let preservation: PreservationManifest
        do {
            preservation = try JSONDecoder().decode(
                PreservationManifest.self,
                from: manifest
            )
        } catch {
            throw MergeArtifactEditorCodecError.losslessRoundTripFailed
        }
        guard preservation.schemaVersion == PreservationManifest.currentSchemaVersion else {
            throw MergeArtifactEditorCodecError.losslessRoundTripFailed
        }

        let original: CodecJSON
        do {
            original = try CodecJSON.parse(preservation.originalDocumentJSON)
        } catch {
            throw MergeArtifactEditorCodecError.losslessRoundTripFailed
        }
        guard case .object(var root) = original,
              case .array(let originalBlocks)? = root["blocks"] else {
            throw MergeArtifactEditorCodecError.losslessRoundTripFailed
        }

        let editorDocument: CodecJSON
        do {
            editorDocument = try CodecJSON.parse(Data(blockNoteJSON.utf8))
        } catch {
            throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
        }
        guard case .array(let editorBlocks) = editorDocument else {
            throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
        }

        var originalByID: [String: CodecJSON] = [:]
        try collectOriginalBlocks(
            originalBlocks,
            into: &originalByID
        )
        var context = EncodeContext(
            originalByID: originalByID,
            passthrough: preservation.passthrough
        )
        let encodedBlocks = try editorBlocks.enumerated().map { index, block in
            try serverBlock(
                from: block,
                path: [index],
                context: &context
            )
        }
        guard context.seenPassthrough == Set(preservation.passthrough.keys) else {
            throw MergeArtifactEditorCodecError.losslessRoundTripFailed
        }

        root["blocks"] = .array(encodedBlocks)
        return try CodecJSON.object(root).canonicalData()
    }
}

private extension MergeArtifactEditorCodec {
    struct DecodeContext {
        var blockIDs = Set<String>()
        var passthrough: [String: PassthroughEntry] = [:]
        var markdown: [String] = []
    }

    struct EncodeContext {
        let originalByID: [String: CodecJSON]
        let passthrough: [String: PassthroughEntry]
        var seenBlockIDs = Set<String>()
        var seenPassthrough = Set<String>()
    }

    static func editorBlock(
        from value: CodecJSON,
        path: [Int],
        context: inout DecodeContext
    ) throws -> CodecJSON {
        guard case .object(let block) = value,
              case .string(let id)? = block["id"],
              !id.isEmpty,
              context.blockIDs.insert(id).inserted,
              case .string(let type)? = block["type"] else {
            throw MergeArtifactEditorCodecError.invalidCardDocument
        }
        try requireOnlyKeys(
            block,
            allowed: ["id", "type", "content", "props", "children"],
            error: .invalidCardDocument
        )

        let children = try serverChildren(block)
        let editorChildren = try children.enumerated().map { index, child in
            try editorBlock(
                from: child,
                path: path + [index],
                context: &context
            )
        }

        let editorType: String
        let editorProps: [String: CodecJSON]
        let editorContent: [CodecJSON]
        let isPassthrough: Bool

        switch type {
        case "paragraph":
            editorType = "paragraph"
            editorProps = [:]
            editorContent = try editorInlineContent(block)
            isPassthrough = false
        case "heading":
            let props = try serverProps(block)
            try requireOnlyKeys(
                props,
                allowed: ["level"],
                error: .invalidCardDocument
            )
            guard let level = props["level"]?.integerValue,
                  level == 2 || level == 3 else {
                throw MergeArtifactEditorCodecError.invalidCardDocument
            }
            editorType = "heading"
            editorProps = ["level": .number(String(level))]
            editorContent = try editorInlineContent(block)
            isPassthrough = false
        case "bullet_list":
            editorType = "bulletListItem"
            editorProps = [:]
            editorContent = try editorInlineContent(block)
            isPassthrough = false
        case "numbered_list":
            editorType = "numberedListItem"
            editorProps = [:]
            editorContent = try editorInlineContent(block)
            isPassthrough = false
        case "checklist":
            let props = try serverProps(block)
            try requireOnlyKeys(
                props,
                allowed: ["checked"],
                error: .invalidCardDocument
            )
            guard case .bool(let checked)? = props["checked"] else {
                throw MergeArtifactEditorCodecError.invalidCardDocument
            }
            editorType = "checkListItem"
            editorProps = ["checked": .bool(checked)]
            editorContent = try editorInlineContent(block)
            isPassthrough = false
        case "image":
            let props = try serverProps(block)
            try requireOnlyKeys(
                props,
                allowed: [
                    "alignment", "mediaRef", "origin", "prominence", "semanticRole",
                ],
                error: .invalidCardDocument
            )
            guard case .string(let mediaRef)? = props["mediaRef"],
                  !mediaRef.isEmpty,
                  case .string(let prominence)? = props["prominence"],
                  let previewWidth = previewWidth(for: prominence),
                  case .string(let alignment)? = props["alignment"],
                  ["left", "center", "right"].contains(alignment) else {
                throw MergeArtifactEditorCodecError.invalidCardDocument
            }
            editorType = "image"
            editorProps = [
                "mediaRef": .string(mediaRef),
                "previewWidth": .number(String(previewWidth)),
                "textAlignment": .string(alignment),
            ]
            editorContent = []
            isPassthrough = true
        case "quote":
            editorType = "quote"
            editorProps = [:]
            editorContent = try editorInlineContent(block)
            isPassthrough = true
        case "code":
            editorType = "codeBlock"
            editorProps = [:]
            editorContent = try editorInlineContent(block)
            isPassthrough = true
        case "divider":
            let content = try editorInlineContent(block)
            guard content.isEmpty else {
                throw MergeArtifactEditorCodecError.invalidCardDocument
            }
            editorType = "paragraph"
            editorProps = [:]
            editorContent = []
            isPassthrough = true
        default:
            throw MergeArtifactEditorCodecError.unsupportedDocument
        }

        let editor: CodecJSON = .object([
            "children": .array(editorChildren),
            "content": .array(editorContent),
            "id": .string(id),
            "props": .object(editorProps),
            "type": .string(editorType),
        ])

        if isPassthrough {
            context.passthrough[id] = PassthroughEntry(
                path: path,
                serverBlockJSON: try value.canonicalData(),
                editorBlockJSON: try editor.canonicalData()
            )
        }
        context.markdown.append(
            markdownLine(
                type: type,
                props: try serverProps(block),
                content: editorContent,
                depth: max(0, path.count - 1)
            )
        )
        return editor
    }

    static func serverBlock(
        from value: CodecJSON,
        path: [Int],
        context: inout EncodeContext
    ) throws -> CodecJSON {
        guard case .object(let block) = value,
              case .string(let id)? = block["id"],
              !id.isEmpty,
              context.seenBlockIDs.insert(id).inserted else {
            throw MergeArtifactEditorCodecError.losslessRoundTripFailed
        }
        try requireOnlyKeys(
            block,
            allowed: ["id", "type", "content", "props", "children"],
            error: .invalidBlockNoteDocument
        )

        if let passthrough = context.passthrough[id] {
            try validateLockedSubtree(
                value,
                path: path,
                context: &context
            )
            guard path == passthrough.path,
                  try value.canonicalData() == passthrough.editorBlockJSON,
                  let restored = try? CodecJSON.parse(passthrough.serverBlockJSON) else {
                throw MergeArtifactEditorCodecError.losslessRoundTripFailed
            }
            return restored
        }

        guard case .string(let editorType)? = block["type"] else {
            throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
        }
        let cardType: String
        var cardProps: [String: CodecJSON] = [:]
        let editorProps = try blockNoteProps(block)
        try validateBlockNoteVisualProps(editorProps, for: editorType)

        switch editorType {
        case "paragraph":
            cardType = "paragraph"
        case "heading":
            guard let level = editorProps["level"]?.integerValue,
                  level == 2 || level == 3 else {
                throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
            }
            cardType = "heading"
            cardProps["level"] = .number(String(level))
        case "bulletListItem":
            cardType = "bullet_list"
        case "numberedListItem":
            cardType = "numbered_list"
        case "checkListItem":
            guard case .bool(let checked)? = editorProps["checked"] else {
                throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
            }
            cardType = "checklist"
            cardProps["checked"] = .bool(checked)
        default:
            throw MergeArtifactEditorCodecError.losslessRoundTripFailed
        }

        let content = try serverInlineContent(block)
        let editorChildren = try blockNoteChildren(block)
        let children = try editorChildren.enumerated().map { index, child in
            try serverBlock(
                from: child,
                path: path + [index],
                context: &context
            )
        }
        let original = context.originalByID[id]?.objectValue
        var result: [String: CodecJSON] = [
            "id": .string(id),
            "type": .string(cardType),
        ]
        if !content.isEmpty || original?["content"] != nil {
            result["content"] = .array(content)
        }
        if !cardProps.isEmpty {
            result["props"] = .object(cardProps)
        }
        if !children.isEmpty || original?["children"] != nil {
            result["children"] = .array(children)
        }
        return .object(result)
    }

    static func validateLockedSubtree(
        _ value: CodecJSON,
        path: [Int],
        context: inout EncodeContext
    ) throws {
        guard case .object(let block) = value,
              case .string(let id)? = block["id"] else {
            throw MergeArtifactEditorCodecError.losslessRoundTripFailed
        }
        if let entry = context.passthrough[id] {
            guard entry.path == path,
                  try value.canonicalData() == entry.editorBlockJSON else {
                throw MergeArtifactEditorCodecError.losslessRoundTripFailed
            }
            context.seenPassthrough.insert(id)
        }
        let children = try blockNoteChildren(block)
        for (index, child) in children.enumerated() {
            try validateLockedSubtree(
                child,
                path: path + [index],
                context: &context
            )
        }
    }

    static func collectOriginalBlocks(
        _ blocks: [CodecJSON],
        into result: inout [String: CodecJSON]
    ) throws {
        for value in blocks {
            guard case .object(let block) = value,
                  case .string(let id)? = block["id"],
                  result[id] == nil else {
                throw MergeArtifactEditorCodecError.losslessRoundTripFailed
            }
            result[id] = value
            try collectOriginalBlocks(
                try serverChildren(block),
                into: &result
            )
        }
    }

    static func editorInlineContent(
        _ block: [String: CodecJSON]
    ) throws -> [CodecJSON] {
        guard let content = block["content"] else { return [] }
        guard case .array(let values) = content else {
            throw MergeArtifactEditorCodecError.invalidCardDocument
        }
        return try values.map(editorInline)
    }

    static func editorInline(_ value: CodecJSON) throws -> CodecJSON {
        guard case .object(let inline) = value,
              case .string(let type)? = inline["type"] else {
            throw MergeArtifactEditorCodecError.invalidCardDocument
        }
        switch type {
        case "text":
            try requireOnlyKeys(
                inline,
                allowed: ["type", "text", "styles"],
                error: .invalidCardDocument
            )
            guard case .string(let text)? = inline["text"] else {
                throw MergeArtifactEditorCodecError.invalidCardDocument
            }
            let styles = try normalizedStyles(
                inline["styles"],
                error: .invalidCardDocument
            )
            return .object([
                "styles": .object(styles),
                "text": .string(text),
                "type": .string("text"),
            ])
        case "link":
            try requireOnlyKeys(
                inline,
                allowed: ["type", "href", "content"],
                error: .invalidCardDocument
            )
            guard case .string(let href)? = inline["href"],
                  isGovernedLink(href),
                  case .array(let content)? = inline["content"],
                  !content.isEmpty else {
                throw MergeArtifactEditorCodecError.invalidCardDocument
            }
            let children = try content.map { child -> CodecJSON in
                guard case .object(let childObject) = child,
                      childObject["type"] == .string("text") else {
                    throw MergeArtifactEditorCodecError.invalidCardDocument
                }
                return try editorInline(child)
            }
            return .object([
                "content": .array(children),
                "href": .string(href),
                "type": .string("link"),
            ])
        default:
            throw MergeArtifactEditorCodecError.unsupportedDocument
        }
    }

    static func serverInlineContent(
        _ block: [String: CodecJSON]
    ) throws -> [CodecJSON] {
        guard let content = block["content"] else { return [] }
        guard case .array(let values) = content else {
            throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
        }
        return try values.map(serverInline)
    }

    static func serverInline(_ value: CodecJSON) throws -> CodecJSON {
        guard case .object(let inline) = value,
              case .string(let type)? = inline["type"] else {
            throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
        }
        switch type {
        case "text":
            try requireOnlyKeys(
                inline,
                allowed: ["type", "text", "styles"],
                error: .invalidBlockNoteDocument
            )
            guard case .string(let text)? = inline["text"] else {
                throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
            }
            let styles = try normalizedStyles(
                inline["styles"],
                error: .invalidBlockNoteDocument
            )
            var result: [String: CodecJSON] = [
                "text": .string(text),
                "type": .string("text"),
            ]
            if !styles.isEmpty {
                result["styles"] = .object(styles)
            }
            return .object(result)
        case "link":
            try requireOnlyKeys(
                inline,
                allowed: ["type", "href", "content"],
                error: .invalidBlockNoteDocument
            )
            guard case .string(let href)? = inline["href"],
                  isGovernedLink(href),
                  case .array(let content)? = inline["content"],
                  !content.isEmpty else {
                throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
            }
            let children = try content.map { child -> CodecJSON in
                guard case .object(let childObject) = child,
                      childObject["type"] == .string("text") else {
                    throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
                }
                return try serverInline(child)
            }
            return .object([
                "content": .array(children),
                "href": .string(href),
                "type": .string("link"),
            ])
        default:
            throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
        }
    }

    static func normalizedStyles(
        _ value: CodecJSON?,
        error: MergeArtifactEditorCodecError
    ) throws -> [String: CodecJSON] {
        guard let value else { return [:] }
        guard case .object(let styles) = value else { throw error }
        try requireOnlyKeys(
            styles,
            allowed: ["bold", "italic", "underline", "strike"],
            error: error
        )
        var normalized: [String: CodecJSON] = [:]
        for (key, value) in styles {
            guard case .bool(let enabled) = value else { throw error }
            if enabled {
                normalized[key] = .bool(true)
            }
        }
        return normalized
    }

    static func serverChildren(
        _ block: [String: CodecJSON]
    ) throws -> [CodecJSON] {
        guard let children = block["children"] else { return [] }
        guard case .array(let values) = children else {
            throw MergeArtifactEditorCodecError.invalidCardDocument
        }
        return values
    }

    static func blockNoteChildren(
        _ block: [String: CodecJSON]
    ) throws -> [CodecJSON] {
        guard let children = block["children"] else { return [] }
        guard case .array(let values) = children else {
            throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
        }
        return values
    }

    static func serverProps(
        _ block: [String: CodecJSON]
    ) throws -> [String: CodecJSON] {
        guard let props = block["props"] else { return [:] }
        guard case .object(let values) = props else {
            throw MergeArtifactEditorCodecError.invalidCardDocument
        }
        return values
    }

    static func blockNoteProps(
        _ block: [String: CodecJSON]
    ) throws -> [String: CodecJSON] {
        guard let props = block["props"] else { return [:] }
        guard case .object(let values) = props else {
            throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
        }
        return values
    }

    static func validateBlockNoteVisualProps(
        _ props: [String: CodecJSON],
        for type: String
    ) throws {
        var allowed = Set(["backgroundColor", "textColor", "textAlignment"])
        if type == "heading" { allowed.insert("level") }
        if type == "checkListItem" { allowed.insert("checked") }
        try requireOnlyKeys(
            props,
            allowed: allowed,
            error: .invalidBlockNoteDocument
        )
        for key in ["backgroundColor", "textColor", "textAlignment"] {
            if let value = props[key], case .string = value {
                continue
            } else if props[key] != nil {
                throw MergeArtifactEditorCodecError.invalidBlockNoteDocument
            }
        }
    }

    static func requireOnlyKeys(
        _ object: [String: CodecJSON],
        allowed: Set<String>,
        error: MergeArtifactEditorCodecError
    ) throws {
        guard Set(object.keys).isSubset(of: allowed) else { throw error }
    }

    static func isGovernedLink(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            return false
        }
        return true
    }

    static func previewWidth(for prominence: String) -> Int? {
        switch prominence {
        case "narrow": return 320
        case "standard": return 640
        case "wide": return 960
        case "full": return 1280
        default: return nil
        }
    }

    static func markdownLine(
        type: String,
        props: [String: CodecJSON],
        content: [CodecJSON],
        depth: Int
    ) -> String {
        let text = content.map(inlineText).joined()
        let indent = String(repeating: "  ", count: depth)
        switch type {
        case "heading":
            let level = props["level"]?.integerValue ?? 2
            return String(repeating: "#", count: level) + " " + text
        case "bullet_list":
            return indent + "- " + text
        case "numbered_list":
            return indent + "1. " + text
        case "checklist":
            let checked = props["checked"] == .bool(true)
            return indent + (checked ? "- [x] " : "- [ ] ") + text
        case "quote":
            return "> " + text
        case "code":
            return "```\n" + text + "\n```"
        case "image":
            return "[Image]"
        case "divider":
            return "---"
        default:
            return text
        }
    }

    static func inlineText(_ value: CodecJSON) -> String {
        guard case .object(let inline) = value else { return "" }
        if case .string(let text)? = inline["text"] { return text }
        if case .array(let content)? = inline["content"] {
            return content.map(inlineText).joined()
        }
        return ""
    }
}

private struct PreservationManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "merge_artifact_editor_manifest.v1"

    let schemaVersion: String
    let originalDocumentJSON: Data
    let passthrough: [String: PassthroughEntry]
}

private struct PassthroughEntry: Codable, Equatable, Sendable {
    let path: [Int]
    let serverBlockJSON: Data
    let editorBlockJSON: Data
}

private indirect enum CodecJSON: Equatable {
    case string(String)
    case number(String)
    case bool(Bool)
    case object([String: CodecJSON])
    case array([CodecJSON])
    case null

    static func parse(_ data: Data) throws -> CodecJSON {
        var parser = CodecJSONParser(bytes: Array(data))
        return try parser.parseDocument()
    }

    var objectValue: [String: CodecJSON]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var integerValue: Int? {
        guard case .number(let value) = self,
              !value.contains("."),
              !value.contains("e"),
              !value.contains("E") else {
            return nil
        }
        return Int(value)
    }

    func canonicalString() throws -> String {
        String(decoding: try canonicalData(), as: UTF8.self)
    }

    func canonicalData() throws -> Data {
        var data = Data()
        try appendCanonical(to: &data)
        return data
    }

    private func appendCanonical(to data: inout Data) throws {
        switch self {
        case .string(let value):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            data.append(try encoder.encode(value))
        case .number(let value):
            data.append(contentsOf: value.utf8)
        case .bool(let value):
            data.append(contentsOf: (value ? "true" : "false").utf8)
        case .object(let object):
            data.append(UInt8(ascii: "{"))
            let keys = object.keys.sorted { lhs, rhs in
                lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
            }
            for (index, key) in keys.enumerated() {
                if index > 0 { data.append(UInt8(ascii: ",")) }
                try CodecJSON.string(key).appendCanonical(to: &data)
                data.append(UInt8(ascii: ":"))
                if let value = object[key] {
                    try value.appendCanonical(to: &data)
                }
            }
            data.append(UInt8(ascii: "}"))
        case .array(let values):
            data.append(UInt8(ascii: "["))
            for (index, value) in values.enumerated() {
                if index > 0 { data.append(UInt8(ascii: ",")) }
                try value.appendCanonical(to: &data)
            }
            data.append(UInt8(ascii: "]"))
        case .null:
            data.append(contentsOf: "null".utf8)
        }
    }
}

private struct CodecJSONParser {
    let bytes: [UInt8]
    var index = 0

    mutating func parseDocument() throws -> CodecJSON {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        guard index == bytes.count else { throw ParseFailure.invalidJSON }
        return value
    }

    private mutating func parseValue() throws -> CodecJSON {
        guard index < bytes.count else { throw ParseFailure.invalidJSON }
        switch bytes[index] {
        case UInt8(ascii: "{"):
            return try parseObject()
        case UInt8(ascii: "["):
            return try parseArray()
        case UInt8(ascii: "\""):
            return .string(try parseString())
        case UInt8(ascii: "t"):
            try consume("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try consume("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try consume("null")
            return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return .number(try parseNumber())
        default:
            throw ParseFailure.invalidJSON
        }
    }

    private mutating func parseObject() throws -> CodecJSON {
        index += 1
        skipWhitespace()
        var object: [String: CodecJSON] = [:]
        if consumeIf(UInt8(ascii: "}")) { return .object(object) }

        while true {
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                throw ParseFailure.invalidJSON
            }
            let key = try parseString()
            guard object[key] == nil else { throw ParseFailure.invalidJSON }
            skipWhitespace()
            guard consumeIf(UInt8(ascii: ":")) else { throw ParseFailure.invalidJSON }
            skipWhitespace()
            object[key] = try parseValue()
            skipWhitespace()
            if consumeIf(UInt8(ascii: "}")) { return .object(object) }
            guard consumeIf(UInt8(ascii: ",")) else { throw ParseFailure.invalidJSON }
            skipWhitespace()
        }
    }

    private mutating func parseArray() throws -> CodecJSON {
        index += 1
        skipWhitespace()
        var values: [CodecJSON] = []
        if consumeIf(UInt8(ascii: "]")) { return .array(values) }

        while true {
            values.append(try parseValue())
            skipWhitespace()
            if consumeIf(UInt8(ascii: "]")) { return .array(values) }
            guard consumeIf(UInt8(ascii: ",")) else { throw ParseFailure.invalidJSON }
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                index += 1
                let token = Data(bytes[start..<index])
                return try JSONDecoder().decode(String.self, from: token)
            }
            if byte == UInt8(ascii: "\\") {
                index += 1
                guard index < bytes.count else { throw ParseFailure.invalidJSON }
                if bytes[index] == UInt8(ascii: "u") {
                    guard index + 4 < bytes.count else { throw ParseFailure.invalidJSON }
                    for offset in 1...4 where !isHex(bytes[index + offset]) {
                        throw ParseFailure.invalidJSON
                    }
                    index += 5
                } else {
                    guard [UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"),
                           UInt8(ascii: "b"), UInt8(ascii: "f"), UInt8(ascii: "n"),
                           UInt8(ascii: "r"), UInt8(ascii: "t")].contains(bytes[index]) else {
                        throw ParseFailure.invalidJSON
                    }
                    index += 1
                }
                continue
            }
            guard byte >= 0x20 else { throw ParseFailure.invalidJSON }
            index += 1
        }
        throw ParseFailure.invalidJSON
    }

    private mutating func parseNumber() throws -> String {
        let start = index
        _ = consumeIf(UInt8(ascii: "-"))
        guard index < bytes.count else { throw ParseFailure.invalidJSON }
        if consumeIf(UInt8(ascii: "0")) {
            if index < bytes.count, isDigit(bytes[index]) {
                throw ParseFailure.invalidJSON
            }
        } else {
            guard index < bytes.count,
                  (UInt8(ascii: "1")...UInt8(ascii: "9")).contains(bytes[index]) else {
                throw ParseFailure.invalidJSON
            }
            index += 1
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if consumeIf(UInt8(ascii: ".")) {
            guard index < bytes.count, isDigit(bytes[index]) else {
                throw ParseFailure.invalidJSON
            }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count,
           bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            if index < bytes.count,
               bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                index += 1
            }
            guard index < bytes.count, isDigit(bytes[index]) else {
                throw ParseFailure.invalidJSON
            }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func consume(_ literal: StaticString) throws {
        let expected = Array(String(describing: literal).utf8)
        guard index + expected.count <= bytes.count,
              Array(bytes[index..<(index + expected.count)]) == expected else {
            throw ParseFailure.invalidJSON
        }
        index += expected.count
    }

    private mutating func consumeIf(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while index < bytes.count,
              [UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t")]
                .contains(bytes[index]) {
            index += 1
        }
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private func isHex(_ byte: UInt8) -> Bool {
        isDigit(byte)
            || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
    }

    private enum ParseFailure: Error {
        case invalidJSON
    }
}
