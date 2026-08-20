import Foundation

public enum BlockNoteEditorAvailability: Equatable, Sendable {
    case loading
    case ready
    case readOnly(reason: String)
    case failed(code: String)
}

public enum BlockNoteEditorFailure: Error, Equatable, Sendable {
    case notAttached
    case snapshotTimedOut(requestID: String)
    case requestCancelled(requestID: String)
    case tornDown
    case compatibilityBlocked(code: String)
    case bridgeFailed(code: String)
}

extension BlockNoteEditorFailure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAttached:
            return "The BlockNote editor is not attached to a view."
        case let .snapshotTimedOut(requestID):
            return "Snapshot request \(requestID) timed out."
        case let .requestCancelled(requestID):
            return "Snapshot request \(requestID) was cancelled."
        case .tornDown:
            return "The BlockNote editor was torn down."
        case let .compatibilityBlocked(code):
            return "The document is read-only because compatibility was blocked: \(code)."
        case let .bridgeFailed(code):
            return "The BlockNote bridge failed: \(code)."
        }
    }
}

public enum BlockNoteEditorEvent: Equatable, Sendable {
    case availabilityChanged(BlockNoteEditorAvailability)
    case documentChanged(BlockNoteDocumentRevision)
    case selectionChanged(BlockNoteSelectionState)
    case bodyFocusChanged(isFocused: Bool)
    case heightChanged(Double)
    case requestCardLink
    case compatibilityBlocked(code: String, details: String)
    case bridgeError(code: String)
}

struct BlockNoteSnapshotRequestFailure: Equatable, Sendable {
    let requestID: String
    let failure: BlockNoteEditorFailure
}

public struct BlockNoteEditorStateUpdate: Equatable, Sendable {
    public let events: [BlockNoteEditorEvent]
    public let snapshot: BlockNoteSnapshot?
    public let becameReady: Bool
    public let snapshotFailure: BlockNoteEditorFailure?
    let snapshotRequestFailure: BlockNoteSnapshotRequestFailure?

    init(
        events: [BlockNoteEditorEvent] = [],
        snapshot: BlockNoteSnapshot? = nil,
        becameReady: Bool = false,
        snapshotFailure: BlockNoteEditorFailure? = nil,
        snapshotRequestFailure: BlockNoteSnapshotRequestFailure? = nil
    ) {
        self.events = events
        self.snapshot = snapshot
        self.becameReady = becameReady
        self.snapshotFailure = snapshotFailure
        self.snapshotRequestFailure = snapshotRequestFailure
    }
}

public struct BlockNoteEditorState: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        case idle
        case awaitingReady
        case ready
        case blocked
        case failed
    }

    public private(set) var availability: BlockNoteEditorAvailability = .loading
    public private(set) var latestDocument: BlockNoteDocumentRevision?
    public private(set) var selectionState: BlockNoteSelectionState?
    public private(set) var contentHeight: Double = 0
    public private(set) var isBridgeReady = false

    let editable: Bool
    private let supportedProtocolVersion: Int
    private let supportedSchemaVersion: Int
    private var phase: Phase = .idle
    private var blockingFailure: BlockNoteEditorFailure?

    public init(
        editable: Bool,
        supportedProtocolVersion: Int = BlockNoteEditorProtocol.version,
        supportedSchemaVersion: Int = BlockNoteEditorProtocol.schemaVersion
    ) {
        self.editable = editable
        self.supportedProtocolVersion = supportedProtocolVersion
        self.supportedSchemaVersion = supportedSchemaVersion
    }

    public mutating func beginInitialization() {
        phase = .awaitingReady
        availability = .loading
        latestDocument = nil
        selectionState = nil
        isBridgeReady = false
        blockingFailure = nil
    }

    public mutating func receive(_ message: BlockNoteEditorMessage) -> BlockNoteEditorStateUpdate {
        switch message {
        case let .ready(protocolVersion, schemaVersion):
            guard phase == .awaitingReady else {
                return fail(code: "unexpected_ready")
            }
            guard protocolVersion == supportedProtocolVersion else {
                return blockCompatibility(
                    code: "protocol_mismatch",
                    details: "Expected protocol \(supportedProtocolVersion) but received \(protocolVersion)."
                )
            }
            guard schemaVersion == supportedSchemaVersion else {
                return blockCompatibility(
                    code: "schema_mismatch",
                    details: "Expected schema \(supportedSchemaVersion) but received \(schemaVersion)."
                )
            }

            phase = .ready
            isBridgeReady = true
            availability = editable ? .ready : .readOnly(reason: "editable_false")
            return .init(
                events: [.availabilityChanged(availability)],
                becameReady: true
            )

        case let .documentChanged(revision, contentJSON, fallbackMarkdown):
            guard isBridgeReady else {
                return fail(code: "unexpected_document")
            }
            guard latestDocument.map({ revision > $0.revision }) ?? true else {
                return .init()
            }

            let document = BlockNoteDocumentRevision(
                revision: revision,
                contentJSON: contentJSON,
                fallbackMarkdown: fallbackMarkdown
            )
            latestDocument = document
            return .init(events: [.documentChanged(document)])

        case let .selectionChanged(selection):
            guard isBridgeReady else {
                return fail(code: "unexpected_selection")
            }
            selectionState = selection
            return .init(events: [.selectionChanged(selection)])

        case let .bodyFocusChanged(isFocused):
            guard isBridgeReady else {
                return .init(events: [
                    .bridgeError(code: "unexpected_body_focus"),
                ])
            }
            return .init(events: [.bodyFocusChanged(isFocused: isFocused)])

        case let .heightChanged(contentHeight):
            guard contentHeight.isFinite, contentHeight >= 0 else {
                return .init()
            }
            self.contentHeight = contentHeight
            return .init(events: [.heightChanged(contentHeight)])

        case .requestCardLink:
            guard isBridgeReady else {
                return .init(events: [
                    .bridgeError(code: "unexpected_card_link_request"),
                ])
            }
            guard availability == .ready else {
                return .init(events: [.bridgeError(code: "read_only")])
            }
            return .init(events: [.requestCardLink])

        case let .snapshot(requestID, revision, contentJSON, fallbackMarkdown):
            guard isBridgeReady else {
                return fail(code: "unexpected_snapshot")
            }
            if let latestDocument, revision < latestDocument.revision {
                return .init(
                    events: [.bridgeError(code: "stale_snapshot_revision")],
                    snapshotRequestFailure: .init(
                        requestID: requestID,
                        failure: .bridgeFailed(code: "stale_snapshot_revision")
                    )
                )
            }
            return .init(snapshot: .init(
                requestID: requestID,
                revision: revision,
                contentJSON: contentJSON,
                fallbackMarkdown: fallbackMarkdown
            ))

        case let .compatibilityBlocked(code, details):
            return blockCompatibility(code: code, details: details)

        case let .bridgeError(code):
            if code == "read_only" {
                availability = .readOnly(reason: "read_only")
                return .init(events: [
                    .availabilityChanged(availability),
                    .bridgeError(code: code),
                ])
            }
            return fail(code: code)
        }
    }

    public mutating func failMalformedMessage() -> BlockNoteEditorStateUpdate {
        fail(code: "malformed_message")
    }

    mutating func failBridge(code: String) -> BlockNoteEditorStateUpdate {
        fail(code: code)
    }

    var currentBlockingFailure: BlockNoteEditorFailure? {
        blockingFailure
    }

    var mutationAllowed: Bool {
        isBridgeReady && availability == .ready
    }

    private mutating func blockCompatibility(
        code: String,
        details: String
    ) -> BlockNoteEditorStateUpdate {
        phase = .blocked
        isBridgeReady = false
        availability = .readOnly(reason: code)
        let failure = BlockNoteEditorFailure.compatibilityBlocked(code: code)
        blockingFailure = failure
        return .init(
            events: [
                .availabilityChanged(availability),
                .compatibilityBlocked(code: code, details: details),
            ],
            snapshotFailure: failure
        )
    }

    private mutating func fail(code: String) -> BlockNoteEditorStateUpdate {
        phase = .failed
        isBridgeReady = false
        availability = .failed(code: code)
        let failure = BlockNoteEditorFailure.bridgeFailed(code: code)
        blockingFailure = failure
        return .init(
            events: [
                .availabilityChanged(availability),
                .bridgeError(code: code),
            ],
            snapshotFailure: failure
        )
    }
}

struct BlockNoteBridgeSessionOutput: Equatable, Sendable {
    var commands: [BlockNoteEditorCommand] = []
    var events: [BlockNoteEditorEvent] = []
    var snapshot: BlockNoteSnapshot?
    var snapshotFailure: BlockNoteEditorFailure?
    var snapshotRequestFailure: BlockNoteSnapshotRequestFailure?
}

struct BlockNoteBridgeOutputDispatcher {
    private let submitCommand: (BlockNoteEditorCommand) -> Void
    private let emitEvent: (BlockNoteEditorEvent) -> Void
    private let completeSnapshot: (BlockNoteSnapshot) -> Void
    private let failSnapshot: (BlockNoteSnapshotRequestFailure) -> Void
    private let failSnapshots: (BlockNoteEditorFailure) -> Void

    init(
        submitCommand: @escaping (BlockNoteEditorCommand) -> Void,
        emitEvent: @escaping (BlockNoteEditorEvent) -> Void,
        completeSnapshot: @escaping (BlockNoteSnapshot) -> Void = { _ in },
        failSnapshot: @escaping (BlockNoteSnapshotRequestFailure) -> Void = { _ in },
        failSnapshots: @escaping (BlockNoteEditorFailure) -> Void = { _ in }
    ) {
        self.submitCommand = submitCommand
        self.emitEvent = emitEvent
        self.completeSnapshot = completeSnapshot
        self.failSnapshot = failSnapshot
        self.failSnapshots = failSnapshots
    }

    func dispatch(_ output: BlockNoteBridgeSessionOutput) {
        for command in output.commands {
            submitCommand(command)
        }
        if let snapshot = output.snapshot {
            completeSnapshot(snapshot)
        }
        if let failure = output.snapshotRequestFailure {
            failSnapshot(failure)
        }
        if let failure = output.snapshotFailure {
            failSnapshots(failure)
        }
        for event in output.events {
            emitEvent(event)
        }
    }
}

struct BlockNoteEditorBridgeSession: Sendable {
    private let document: BlockNoteInitialDocument
    private let editable: Bool
    private var runtimeDocumentAdapter: BlockNoteRuntimeDocumentAdapter?
    private var queuedCommands: [BlockNoteEditorCommand] = []
    private(set) var state: BlockNoteEditorState

    init(document: BlockNoteInitialDocument, editable: Bool) {
        self.document = document
        self.editable = editable
        runtimeDocumentAdapter = nil
        state = BlockNoteEditorState(editable: editable)
    }

    mutating func navigationFinished() -> BlockNoteBridgeSessionOutput {
        state.beginInitialization()
        runtimeDocumentAdapter = try? BlockNoteRuntimeDocumentAdapter(
            contentJSON: document.contentJSON,
            displayURLsByMediaReference: document.displayURLsByMediaReference,
            preservesStandardProjection: document.profile == .standard
        )
        return .init(commands: [
            .initialize(
                protocolVersion: BlockNoteEditorProtocol.version,
                documentJSON: runtimeDocumentAdapter?.runtimeDocumentJSON
                    ?? document.contentJSON,
                fallbackMarkdown: document.fallbackMarkdown,
                editable: editable,
                profile: document.profile
            ),
        ])
    }

    mutating func request(_ command: BlockNoteEditorCommand) -> BlockNoteBridgeSessionOutput {
        if case .initialize = command {
            return .init(events: [.bridgeError(code: "reserved_initialize_command")])
        }

        if let failure = state.currentBlockingFailure {
            if command.snapshotRequestID != nil {
                return .init(snapshotFailure: failure)
            }
            return .init()
        }

        if state.isBridgeReady {
            guard !command.isMutation || state.mutationAllowed else {
                return .init(events: [.bridgeError(code: "read_only")])
            }
            return .init(commands: [command])
        }

        queuedCommands.append(command)
        return .init()
    }

    mutating func receive(_ message: BlockNoteEditorMessage) -> BlockNoteBridgeSessionOutput {
        let adaptedMessage: BlockNoteEditorMessage
        do {
            adaptedMessage = try runtimeDocumentAdapter?.adapt(message) ?? message
        } catch {
            return bridgeFailure(code: "merge_runtime_adapter_failed")
        }
        let update = state.receive(adaptedMessage)
        var output = BlockNoteBridgeSessionOutput(
            events: update.events,
            snapshot: update.snapshot,
            snapshotFailure: update.snapshotFailure,
            snapshotRequestFailure: update.snapshotRequestFailure
        )

        if update.snapshotFailure != nil {
            queuedCommands.removeAll()
        }

        if update.becameReady {
            let queued = queuedCommands
            queuedCommands.removeAll(keepingCapacity: true)
            for command in queued {
                if command.isMutation, !state.mutationAllowed {
                    output.events.append(.bridgeError(code: "read_only"))
                } else {
                    output.commands.append(command)
                }
            }
        }

        return output
    }

    mutating func malformedMessage() -> BlockNoteBridgeSessionOutput {
        let update = state.failMalformedMessage()
        queuedCommands.removeAll()
        return .init(
            events: update.events,
            snapshotFailure: update.snapshotFailure
        )
    }

    mutating func bridgeFailure(code: String) -> BlockNoteBridgeSessionOutput {
        let update = state.failBridge(code: code)
        queuedCommands.removeAll()
        return .init(
            events: update.events,
            snapshotFailure: update.snapshotFailure
        )
    }

    mutating func teardown() -> BlockNoteBridgeSessionOutput {
        queuedCommands.removeAll()
        return .init(snapshotFailure: .tornDown)
    }
}

private struct BlockNoteRuntimeDocumentAdapter: Sendable {
    let runtimeDocumentJSON: String
    private let originalsByID: [String: RuntimeBlock]
    private let envelopeMetadata: [String: RuntimeJSONValue]?
    private let preservesStandardProjection: Bool
    private let initialRuntimeImageURLsByID: [String: RuntimeJSONValue]
    private var mappedRuntimeIDs: [String: String] = [:]
    private var usedOutputIDs: Set<String>

    init(
        contentJSON: String?,
        displayURLsByMediaReference: [String: String],
        preservesStandardProjection: Bool
    ) throws {
        guard let contentJSON,
              let data = contentJSON.data(using: .utf8) else {
            throw AdapterError.invalidDocument
        }
        let document = try Self.decodeDocument(from: data)
        let mergeBlocks = document.blocks
        guard !mergeBlocks.isEmpty else { throw AdapterError.invalidDocument }

        var originals: [String: RuntimeBlock] = [:]
        try Self.collectOriginals(mergeBlocks, into: &originals)
        originalsByID = originals
        envelopeMetadata = document.envelopeMetadata
        self.preservesStandardProjection = preservesStandardProjection
        usedOutputIDs = Set(originals.keys)

        let runtimeBlocks = try mergeBlocks.map {
            try Self.runtimeBlock(
                $0,
                displayURLsByMediaReference: displayURLsByMediaReference
            )
        }
        var initialImageURLs: [String: RuntimeJSONValue] = [:]
        Self.collectRuntimeImageURLs(runtimeBlocks, into: &initialImageURLs)
        initialRuntimeImageURLsByID = initialImageURLs
        runtimeDocumentJSON = try Self.encodeDocument(
            blocks: runtimeBlocks,
            envelopeMetadata: document.envelopeMetadata
        )
    }

    static func requiresRuntimeAdaptation(contentJSON: String?) -> Bool {
        guard let contentJSON,
              let sourceData = contentJSON.data(using: .utf8),
              let sourceDocument = try? decodeDocument(from: sourceData),
              sourceDocument.envelopeMetadata != nil,
              !sourceDocument.blocks.isEmpty,
              let adapter = try? BlockNoteRuntimeDocumentAdapter(
                  contentJSON: contentJSON,
                  displayURLsByMediaReference: [:],
                  preservesStandardProjection: false
              ),
              let runtimeData = adapter.runtimeDocumentJSON.data(using: .utf8),
              let runtimeDocument = try? decodeDocument(from: runtimeData),
              runtimeDocument.envelopeMetadata == sourceDocument.envelopeMetadata,
              let addsRuntimeProps = addsRuntimeProps(
                  source: sourceDocument.blocks,
                  runtime: runtimeDocument.blocks
              ) else {
            return false
        }
        return addsRuntimeProps
    }

    private static func addsRuntimeProps(
        source: [RuntimeBlock],
        runtime: [RuntimeBlock]
    ) -> Bool? {
        guard source.count == runtime.count else { return nil }
        for (sourceBlock, runtimeBlock) in zip(source, runtime) {
            guard sourceBlock.id == runtimeBlock.id,
                  sourceBlock.type == runtimeBlock.type,
                  let childAdds = addsRuntimeProps(
                      source: sourceBlock.children,
                      runtime: runtimeBlock.children
                  ) else {
                return nil
            }
            if runtimeBlock.props.contains(where: { key, value in
                sourceBlock.props[key] != value
            }) || childAdds {
                return true
            }
        }
        return false
    }

    mutating func adapt(_ message: BlockNoteEditorMessage) throws -> BlockNoteEditorMessage {
        switch message {
        case let .documentChanged(revision, contentJSON, fallbackMarkdown):
            return .documentChanged(
                revision: revision,
                contentJSON: try mergeDocumentJSON(from: contentJSON),
                fallbackMarkdown: fallbackMarkdown
            )
        case let .snapshot(requestID, revision, contentJSON, fallbackMarkdown):
            return .snapshot(
                requestID: requestID,
                revision: revision,
                contentJSON: try mergeDocumentJSON(from: contentJSON),
                fallbackMarkdown: fallbackMarkdown
            )
        default:
            return message
        }
    }

    private mutating func mergeDocumentJSON(from runtimeJSON: String) throws -> String {
        guard let data = runtimeJSON.data(using: .utf8) else {
            throw AdapterError.invalidDocument
        }
        let runtimeDocument = try Self.decodeDocument(from: data)
        guard runtimeDocument.envelopeMetadata == envelopeMetadata else {
            throw AdapterError.invalidDocument
        }
        let mergeBlocks = try runtimeDocument.blocks.map { try mergeBlock($0) }
        return try Self.encodeDocument(
            blocks: mergeBlocks,
            envelopeMetadata: envelopeMetadata
        )
    }

    private static func decodeDocument(from data: Data) throws -> RuntimeDocument {
        let decoder = JSONDecoder()
        if let blocks = try? decoder.decode([RuntimeBlock].self, from: data) {
            return RuntimeDocument(blocks: blocks, envelopeMetadata: nil)
        }

        let root = try decoder.decode([String: RuntimeJSONValue].self, from: data)
        let allowedKeys: Set<String> = [
            "blocks",
            "content",
            "editor_kind",
            "schema_version",
            "tags",
            "title",
        ]
        guard Set(root.keys).isSubset(of: allowedKeys),
              root["schema_version"] == .number(1),
              root["editor_kind"] == .string("blocknote"),
              case let .array(rawBlocks)? = root["blocks"],
              Self.hasValidOptionalEnvelopeMetadata(root) else {
            throw AdapterError.invalidDocument
        }

        let blockData = try JSONEncoder().encode(rawBlocks)
        let blocks = try decoder.decode([RuntimeBlock].self, from: blockData)
        var metadata = root
        metadata.removeValue(forKey: "blocks")
        return RuntimeDocument(blocks: blocks, envelopeMetadata: metadata)
    }

    private static func hasValidOptionalEnvelopeMetadata(
        _ root: [String: RuntimeJSONValue]
    ) -> Bool {
        for key in ["content", "title"] {
            if let value = root[key], case .string = value {
                continue
            } else if root[key] != nil {
                return false
            }
        }
        if let tags = root["tags"] {
            guard case let .array(values) = tags,
                  values.allSatisfy({ value in
                      if case .string = value { return true }
                      return false
                  }) else {
                return false
            }
        }
        return true
    }

    private static func encodeDocument(
        blocks: [RuntimeBlock],
        envelopeMetadata: [String: RuntimeJSONValue]?
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded: Data
        if var envelopeMetadata {
            let blockData = try encoder.encode(blocks)
            envelopeMetadata["blocks"] = try JSONDecoder().decode(
                RuntimeJSONValue.self,
                from: blockData
            )
            encoded = try encoder.encode(envelopeMetadata)
        } else {
            encoded = try encoder.encode(blocks)
        }
        return String(decoding: encoded, as: UTF8.self)
    }

    private mutating func mergeBlock(_ runtime: RuntimeBlock) throws -> RuntimeBlock {
        let outputID = outputID(for: runtime.id)
        let original = originalsByID[runtime.id]
        let props: [String: RuntimeJSONValue]
        if let original {
            if preservesStandardProjection {
                var projected = original.props
                if let runtimeKeys = Self.runtimePropKeys(for: runtime.type) {
                    for key in runtimeKeys {
                        if let runtimeValue = runtime.props[key] {
                            projected[key] = runtimeValue
                        } else {
                            projected.removeValue(forKey: key)
                        }
                    }
                } else {
                    for (key, runtimeValue) in runtime.props {
                        projected[key] = runtimeValue
                    }
                }
                if runtime.type == "image",
                   original.props["mediaRef"] != nil,
                   runtime.props["url"] != initialRuntimeImageURLsByID[runtime.id] {
                    projected.removeValue(forKey: "mediaRef")
                }
                props = projected
            } else {
                var projected: [String: RuntimeJSONValue] = [:]
                for (key, originalValue) in original.props {
                    if key == "mediaRef" {
                        projected[key] = originalValue
                    } else if let runtimeValue = runtime.props[key] {
                        projected[key] = runtimeValue
                    } else {
                        throw AdapterError.invalidDocument
                    }
                }
                props = projected
            }
        } else {
            props = preservesStandardProjection
                ? runtime.props
                : Self.newBlockProps(runtime)
        }

        let children = try runtime.children.map { try mergeBlock($0) }
        let content: [RuntimeJSONValue]?
        if preservesStandardProjection {
            content = original?.content == nil && runtime.content == nil
                ? nil
                : (runtime.content ?? [])
        } else {
            content = original?.content == nil && runtime.type == "image"
                ? nil
                : (runtime.content ?? [])
        }
        return RuntimeBlock(
            id: outputID,
            type: runtime.type,
            props: props,
            content: content,
            children: children
        )
    }

    private mutating func outputID(for runtimeID: String) -> String {
        if originalsByID[runtimeID] != nil { return runtimeID }
        if let mapped = mappedRuntimeIDs[runtimeID] { return mapped }
        if Self.isServerBlockID(runtimeID), usedOutputIDs.insert(runtimeID).inserted {
            mappedRuntimeIDs[runtimeID] = runtimeID
            return runtimeID
        }

        var generated: String
        repeat {
            generated = "blk_" + UUID().uuidString
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
        } while !usedOutputIDs.insert(generated).inserted
        mappedRuntimeIDs[runtimeID] = generated
        return generated
    }

    private static func runtimeBlock(
        _ merge: RuntimeBlock,
        displayURLsByMediaReference: [String: String]
    ) throws -> RuntimeBlock {
        var props = runtimeDefaults(for: merge.type)
        let runtimeKeys = runtimePropKeys(for: merge.type)
        for (key, value) in merge.props where key != "mediaRef" {
            if runtimeKeys?.contains(key) ?? true {
                props[key] = value
            }
        }
        if merge.type == "image" {
            guard case let .string(mediaReference)? = merge.props["mediaRef"],
                  !mediaReference.isEmpty else {
                throw AdapterError.invalidDocument
            }
            if let displayURL = displayURLsByMediaReference[mediaReference]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !displayURL.isEmpty {
                props["url"] = .string(displayURL)
            }
        } else if merge.props["mediaRef"] != nil {
            throw AdapterError.invalidDocument
        }

        return RuntimeBlock(
            id: merge.id,
            type: merge.type,
            props: props,
            content: merge.type == "image" ? nil : (merge.content ?? []),
            children: try merge.children.map {
                try runtimeBlock(
                    $0,
                    displayURLsByMediaReference: displayURLsByMediaReference
                )
            }
        )
    }

    private static func runtimeDefaults(
        for type: String
    ) -> [String: RuntimeJSONValue] {
        let standard: [String: RuntimeJSONValue] = [
            "backgroundColor": .string("default"),
            "textAlignment": .string("left"),
            "textColor": .string("default"),
        ]
        switch type {
        case "paragraph", "bulletListItem":
            return standard
        case "heading":
            return standard.merging(["isToggleable": .bool(false)]) { _, new in new }
        case "numberedListItem":
            return standard
        case "checkListItem":
            return standard.merging(["checked": .bool(false)]) { _, new in new }
        case "quote":
            return [
                "backgroundColor": .string("default"),
                "textColor": .string("default"),
            ]
        case "codeBlock":
            return ["language": .string("text")]
        case "image":
            return [
                "backgroundColor": .string("default"),
                "caption": .string(""),
                "name": .string(""),
                "showPreview": .bool(true),
                "textAlignment": .string("left"),
                "url": .string(""),
            ]
        default:
            return [:]
        }
    }

    private static func runtimePropKeys(for type: String) -> Set<String>? {
        switch type {
        case "paragraph", "bulletListItem", "numberedListItem":
            return ["backgroundColor", "textAlignment", "textColor"]
        case "heading":
            return [
                "backgroundColor", "isToggleable", "level",
                "textAlignment", "textColor",
            ]
        case "checkListItem":
            return [
                "backgroundColor", "checked", "textAlignment", "textColor",
            ]
        case "quote":
            return ["backgroundColor", "textColor"]
        case "codeBlock":
            return ["language"]
        case "image":
            return [
                "backgroundColor", "caption", "name", "previewWidth",
                "showPreview", "textAlignment", "url",
            ]
        default:
            return nil
        }
    }

    private static func newBlockProps(
        _ runtime: RuntimeBlock
    ) -> [String: RuntimeJSONValue] {
        switch runtime.type {
        case "heading":
            return runtime.props["level"].map { ["level": $0] } ?? [:]
        case "checkListItem":
            return runtime.props["checked"].map { ["checked": $0] } ?? [:]
        default:
            return [:]
        }
    }

    private static func collectOriginals(
        _ blocks: [RuntimeBlock],
        into result: inout [String: RuntimeBlock]
    ) throws {
        for block in blocks {
            guard isPersistedBlockID(block.id), result[block.id] == nil else {
                throw AdapterError.invalidDocument
            }
            result[block.id] = block
            try collectOriginals(block.children, into: &result)
        }
    }

    private static func collectRuntimeImageURLs(
        _ blocks: [RuntimeBlock],
        into result: inout [String: RuntimeJSONValue]
    ) {
        for block in blocks {
            if block.type == "image", let url = block.props["url"] {
                result[block.id] = url
            }
            collectRuntimeImageURLs(block.children, into: &result)
        }
    }

    private static func isServerBlockID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count > 4,
              bytes.starts(with: Array("blk_".utf8)) else {
            return false
        }
        return isPersistedBlockID(value)
    }

    private static func isPersistedBlockID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard !bytes.isEmpty, bytes.count <= 64 else { return false }
        return bytes.allSatisfy { byte in
            (0x30...0x39).contains(byte)
                || (0x41...0x5A).contains(byte)
                || (0x61...0x7A).contains(byte)
                || byte == 0x5F
                || byte == 0x2D
        }
    }

    private enum AdapterError: Error {
        case invalidDocument
    }

    private struct RuntimeDocument: Sendable {
        let blocks: [RuntimeBlock]
        let envelopeMetadata: [String: RuntimeJSONValue]?
    }

    private struct RuntimeBlock: Codable, Equatable, Sendable {
        let id: String
        let type: String
        let props: [String: RuntimeJSONValue]
        let content: [RuntimeJSONValue]?
        let children: [RuntimeBlock]
    }

    private indirect enum RuntimeJSONValue: Codable, Equatable, Sendable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case object([String: RuntimeJSONValue])
        case array([RuntimeJSONValue])
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode(
                [String: RuntimeJSONValue].self
            ) {
                self = .object(value)
            } else if let value = try? container.decode([RuntimeJSONValue].self) {
                self = .array(value)
            } else {
                throw AdapterError.invalidDocument
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .null: try container.encodeNil()
            }
        }
    }
}

public extension BlockNoteInitialDocument {
    static func existingCard(
        contentJSON: String?,
        fallbackMarkdown: String,
        displayURLsByMediaReference: [String: String] = [:]
    ) -> BlockNoteInitialDocument {
        BlockNoteInitialDocument(
            contentJSON: contentJSON,
            fallbackMarkdown: fallbackMarkdown,
            profile: BlockNoteRuntimeDocumentAdapter.requiresRuntimeAdaptation(
                contentJSON: contentJSON
            ) ? .mergeArtifact : .standard,
            displayURLsByMediaReference: displayURLsByMediaReference
        )
    }
}
