import Foundation

public indirect enum MergeJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: MergeJSONValue])
    case array([MergeJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: MergeJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([MergeJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Merge JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var textValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value.rounded() == value
                ? String(Int(value))
                : String(value)
        case .bool(let value):
            return String(value)
        case .array(let values):
            let text = values.compactMap(\.textValue).joined(separator: " ")
            return text.isEmpty ? nil : text
        case .object(let values):
            for key in ["text", "label", "title", "name", "summary", "content"] {
                if let text = values[key]?.textValue, !text.isEmpty {
                    return text
                }
            }
            return nil
        case .null:
            return nil
        }
    }
}

public struct MergeSource: Codable, Equatable, Identifiable, Sendable {
    public var id: String { assetID }
    public let assetID: String
    public let versionID: String?
    public let preview: String

    public init(assetID: String, versionID: String?, preview: String) {
        self.assetID = assetID
        self.versionID = versionID
        self.preview = preview
    }
}

public enum MergeSourceOrdering {
    public static func ordered(
        anchor: MergeSource,
        companions: [MergeSource]
    ) -> [MergeSource] {
        var seen = Set([anchor.assetID])
        return [anchor] + companions.filter { seen.insert($0.assetID).inserted }
    }
}

public enum MergeCapabilityOutputKind: Codable, Equatable, Sendable {
    case document
    case blockFragment
    case unknown(String)

    public init(serverValue: String) {
        switch serverValue {
        case "document": self = .document
        case "block_fragment": self = .blockFragment
        default: self = .unknown(serverValue)
        }
    }

    public var serverValue: String {
        switch self {
        case .document: return "document"
        case .blockFragment: return "block_fragment"
        case .unknown(let value): return value
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(serverValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(serverValue)
    }
}

public struct MergeCapability: Codable, Equatable, Identifiable, Sendable {
    public var id: String { capabilityID }
    public let capabilityID: String
    public let displayName: String
    public let outputKind: MergeCapabilityOutputKind
    public let blockExport: Bool
    public let slotCommit: Bool
    public let isEnabled: Bool
    public let rolloutStage: String

    public init(
        capabilityID: String,
        displayName: String,
        outputKind: MergeCapabilityOutputKind,
        blockExport: Bool,
        slotCommit: Bool,
        isEnabled: Bool,
        rolloutStage: String
    ) {
        self.capabilityID = capabilityID
        self.displayName = displayName
        self.outputKind = outputKind
        self.blockExport = blockExport
        self.slotCommit = slotCommit
        self.isEnabled = isEnabled
        self.rolloutStage = rolloutStage
    }
}

public enum MergeJobStatus: Codable, Equatable, Sendable {
    case created
    case snapshotReady
    case planned
    case generating
    case artifactReady
    case committing
    case committedCard
    case committedBlock
    case failed
    case cancelled
    case unknown(String)

    public init(serverValue: String) {
        switch serverValue {
        case "CREATED": self = .created
        case "PREPARING": self = .snapshotReady
        case "SNAPSHOT_READY": self = .snapshotReady
        case "PLANNED": self = .planned
        case "GENERATING": self = .generating
        case "ARTIFACT_READY": self = .artifactReady
        case "COMMITTING": self = .committing
        case "COMMITTED", "COMMITTED_CARD": self = .committedCard
        case "COMMITTED_BLOCK": self = .committedBlock
        case "FAILED": self = .failed
        case "CANCELLED": self = .cancelled
        default: self = .unknown(serverValue)
        }
    }

    public var serverValue: String {
        switch self {
        case .created: return "CREATED"
        case .snapshotReady: return "PREPARING"
        case .planned: return "PLANNED"
        case .generating: return "GENERATING"
        case .artifactReady: return "ARTIFACT_READY"
        case .committing: return "COMMITTING"
        case .committedCard: return "COMMITTED"
        case .committedBlock: return "COMMITTED_BLOCK"
        case .failed: return "FAILED"
        case .cancelled: return "CANCELLED"
        case .unknown(let value): return value
        }
    }

    public var isRunning: Bool {
        switch self {
        case .created, .snapshotReady, .planned, .generating:
            return true
        default:
            return false
        }
    }

    public var isReady: Bool { self == .artifactReady }
    public var isCommitting: Bool { self == .committing }

    public var isTerminal: Bool {
        switch self {
        case .committedCard, .committedBlock, .failed, .cancelled:
            return true
        default:
            return false
        }
    }

    public var canCancel: Bool {
        switch self {
        case .created, .snapshotReady, .planned, .generating, .artifactReady:
            return true
        default:
            return false
        }
    }

    public var canCommit: Bool { self == .artifactReady }

    public init(from decoder: Decoder) throws {
        self.init(serverValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(serverValue)
    }
}

public struct MergeCommitSummary: Codable, Equatable, Sendable {
    public let commitID: String
    public let status: String
    public let targetType: String

    public init(commitID: String, status: String, targetType: String) {
        self.commitID = commitID
        self.status = status
        self.targetType = targetType
    }
}

public struct MergeJob: Codable, Equatable, Identifiable, Sendable {
    public var id: String { jobID }
    public let jobID: String
    public let status: MergeJobStatus
    public let capability: String
    public let selectedCapability: String?
    public let planScore: Double?
    public let artifactID: String?
    public let latestCommit: MergeCommitSummary?
    public let failureStage: String?
    public let errorCode: String?
    public let failureReason: String?

    public init(
        jobID: String,
        status: MergeJobStatus,
        capability: String,
        selectedCapability: String?,
        planScore: Double?,
        artifactID: String?,
        latestCommit: MergeCommitSummary?,
        failureStage: String?,
        errorCode: String?,
        failureReason: String?
    ) {
        self.jobID = jobID
        self.status = status
        self.capability = capability
        self.selectedCapability = selectedCapability
        self.planScore = planScore
        self.artifactID = artifactID
        self.latestCommit = latestCommit
        self.failureStage = failureStage
        self.errorCode = errorCode
        self.failureReason = failureReason
    }
}

public struct MergeInline: Codable, Equatable, Sendable {
    public let type: String?
    public let text: String?
    public let properties: [String: MergeJSONValue]

    public init(
        type: String?,
        text: String?,
        properties: [String: MergeJSONValue]
    ) {
        self.type = type
        self.text = text
        self.properties = properties
    }

    public var plainText: String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        for key in ["text", "label", "title", "name", "summary", "content"] {
            if let value = properties[key]?.textValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

public struct MergeBlock: Codable, Equatable, Sendable {
    public let id: String?
    public let type: String
    public let content: [MergeInline]
    public let properties: [String: MergeJSONValue]
    public let children: [MergeBlock]

    public init(
        id: String?,
        type: String,
        content: [MergeInline],
        properties: [String: MergeJSONValue],
        children: [MergeBlock]
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.properties = properties
        self.children = children
    }

    public var plainTextLines: [String] {
        textLines(depth: 0)
    }

    private func textLines(depth: Int) -> [String] {
        let ownText = resolvedOwnText()
        let indent = String(repeating: "  ", count: depth)
        var lines: [String] = []

        if let ownText {
            switch type.lowercased() {
            case "list_item", "bullet", "bullet_item":
                lines.append("\(indent)• \(ownText)")
            case "ordered_item", "numbered_item":
                lines.append("\(indent)\(ownText)")
            case "quote", "blockquote":
                lines.append("\(indent)“\(ownText)”")
            default:
                lines.append("\(indent)\(ownText)")
            }
        }

        let childDepth: Int
        switch type.lowercased() {
        case "bullet_list", "ordered_list", "list":
            childDepth = depth
        default:
            childDepth = ownText == nil ? depth : depth + 1
        }
        lines.append(contentsOf: children.flatMap { $0.textLines(depth: childDepth) })
        return lines
    }

    private func resolvedOwnText() -> String? {
        let inlineText = content.compactMap(\.plainText).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !inlineText.isEmpty {
            return inlineText
        }
        for key in ["text", "label", "title", "name", "summary", "content"] {
            if let value = properties[key]?.textValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

public struct MergeDocument: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let title: String?
    public let subtitle: String?
    public let blocks: [MergeBlock]
    public let metadata: [String: MergeJSONValue]

    public init(
        schemaVersion: String,
        title: String?,
        subtitle: String?,
        blocks: [MergeBlock],
        metadata: [String: MergeJSONValue]
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.subtitle = subtitle
        self.blocks = blocks
        self.metadata = metadata
    }

    public var plainText: String {
        blocks
            .map { $0.plainTextLines.joined(separator: "\n") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

public struct MergeFragment: Codable, Equatable, Identifiable, Sendable {
    public var id: String { fragmentID }
    public let fragmentID: String
    public let schemaVersion: String
    public let blocks: [MergeBlock]
    public let insertMode: String?
    public let metadata: [String: MergeJSONValue]

    public init(
        fragmentID: String,
        schemaVersion: String,
        blocks: [MergeBlock],
        insertMode: String?,
        metadata: [String: MergeJSONValue]
    ) {
        self.fragmentID = fragmentID
        self.schemaVersion = schemaVersion
        self.blocks = blocks
        self.insertMode = insertMode
        self.metadata = metadata
    }
}

public struct MergeArtifactPresentation: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let tags: [String]
    public let rate: Int

    public init(schemaVersion: String, tags: [String], rate: Int) {
        self.schemaVersion = schemaVersion
        self.tags = tags
        self.rate = rate
    }
}

public struct MergeArtifactSaveRequest: Equatable, Sendable {
    public let baseRevision: Int
    public let baseHash: String
    public let idempotencyKey: String
    public let documentJSON: Data
    public let tags: [String]

    public init(
        baseRevision: Int,
        baseHash: String,
        idempotencyKey: String,
        documentJSON: Data,
        tags: [String]
    ) {
        self.baseRevision = baseRevision
        self.baseHash = baseHash
        self.idempotencyKey = idempotencyKey
        self.documentJSON = documentJSON
        self.tags = tags
    }
}

public struct MergeArtifactSaveResult: Equatable, Sendable {
    public let artifactID: String
    public let revision: Int
    public let documentHash: String
    public let presentationHash: String
    public let presentation: MergeArtifactPresentation

    public init(
        artifactID: String,
        revision: Int,
        documentHash: String,
        presentationHash: String,
        presentation: MergeArtifactPresentation
    ) {
        self.artifactID = artifactID
        self.revision = revision
        self.documentHash = documentHash
        self.presentationHash = presentationHash
        self.presentation = presentation
    }
}

public struct MergeArtifact: Codable, Equatable, Identifiable, Sendable {
    public var id: String { artifactID }
    public let artifactID: String
    public let jobID: String
    public let capabilityID: String
    public let outputKind: MergeCapabilityOutputKind
    public let document: MergeDocument
    public let fragments: [MergeFragment]
    public let metadata: [String: MergeJSONValue]
    public let latestRevision: Int
    public let latestHash: String
    public let documentJSON: Data
    public let presentationHash: String
    public let presentation: MergeArtifactPresentation

    public init(
        artifactID: String,
        jobID: String,
        capabilityID: String,
        outputKind: MergeCapabilityOutputKind,
        document: MergeDocument,
        fragments: [MergeFragment],
        metadata: [String: MergeJSONValue],
        latestRevision: Int = 1,
        latestHash: String = "",
        documentJSON: Data = Data(),
        presentationHash: String = "",
        presentation: MergeArtifactPresentation = MergeArtifactPresentation(
            schemaVersion: "merge_artifact_presentation.v1",
            tags: [],
            rate: 1
        )
    ) {
        self.artifactID = artifactID
        self.jobID = jobID
        self.capabilityID = capabilityID
        self.outputKind = outputKind
        self.document = document
        self.fragments = fragments
        self.metadata = metadata
        self.latestRevision = latestRevision
        self.latestHash = latestHash
        self.documentJSON = documentJSON
        self.presentationHash = presentationHash
        self.presentation = presentation
    }
}

public struct MergeCreateRequest: Codable, Equatable, Sendable {
    public let sources: [MergeSource]
    public let capability: String
    public let idempotencyKey: String
    public let context: [String: MergeJSONValue]

    public init(
        sources: [MergeSource],
        capability: String,
        idempotencyKey: String,
        context: [String: MergeJSONValue]
    ) {
        self.sources = sources
        self.capability = capability
        self.idempotencyKey = idempotencyKey
        self.context = context
    }
}

public struct MergeCommitTarget: Codable, Equatable, Sendable {
    public let targetType: String
    public let spaceID: String?
    public let titleOverride: String?

    public static func newCard(
        spaceID: String?,
        titleOverride: String?
    ) -> MergeCommitTarget {
        MergeCommitTarget(
            targetType: "new_card",
            spaceID: spaceID,
            titleOverride: titleOverride
        )
    }

    private init(targetType: String, spaceID: String?, titleOverride: String?) {
        self.targetType = targetType
        self.spaceID = spaceID
        self.titleOverride = titleOverride
    }
}

public struct MergeCommitRequest: Codable, Equatable, Sendable {
    public let idempotencyKey: String
    public let target: MergeCommitTarget

    public init(idempotencyKey: String, target: MergeCommitTarget) {
        self.idempotencyKey = idempotencyKey
        self.target = target
    }
}

public struct MergeCommitResult: Codable, Equatable, Identifiable, Sendable {
    public var id: String { commitID }
    public let commitID: String
    public let status: String
    public let targetType: String
    public let assetID: String?
    public let versionID: String?
    public let activityID: String?
    public let logID: String?
    public let errorCode: String?
    public let backgroundMediaReference: String?

    public init(
        commitID: String,
        status: String,
        targetType: String,
        assetID: String?,
        versionID: String?,
        activityID: String?,
        logID: String?,
        errorCode: String?,
        backgroundMediaReference: String?
    ) {
        self.commitID = commitID
        self.status = status
        self.targetType = targetType
        self.assetID = assetID
        self.versionID = versionID
        self.activityID = activityID
        self.logID = logID
        self.errorCode = errorCode
        self.backgroundMediaReference = backgroundMediaReference
    }
}

public enum CoreMergeError: Error, Equatable, Sendable {
    case unauthorized
    case forbidden
    case notFound
    case validation(code: String?)
    case conflict(code: String?)
    case unavailable(code: String?)
    case offline
    case timeout
    case interrupted
    case artifactNotReady
    case cancelled
    case decoding
    case server(code: String?)
    case unknown(code: String?)
}
