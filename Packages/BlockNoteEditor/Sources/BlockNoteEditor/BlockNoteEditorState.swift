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
    case heightChanged(Double)
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

        case let .heightChanged(contentHeight):
            guard contentHeight.isFinite, contentHeight >= 0 else {
                return .init()
            }
            self.contentHeight = contentHeight
            return .init(events: [.heightChanged(contentHeight)])

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
    private var queuedCommands: [BlockNoteEditorCommand] = []
    private(set) var state: BlockNoteEditorState

    init(document: BlockNoteInitialDocument, editable: Bool) {
        self.document = document
        self.editable = editable
        state = BlockNoteEditorState(editable: editable)
    }

    mutating func navigationFinished() -> BlockNoteBridgeSessionOutput {
        state.beginInitialization()
        return .init(commands: [
            .initialize(
                protocolVersion: BlockNoteEditorProtocol.version,
                documentJSON: document.contentJSON,
                fallbackMarkdown: document.fallbackMarkdown,
                editable: editable
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
        let update = state.receive(message)
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
