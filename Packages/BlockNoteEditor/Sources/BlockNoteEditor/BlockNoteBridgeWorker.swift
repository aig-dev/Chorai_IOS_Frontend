import CoreFoundation
import Foundation

/// Copies only recognized bridge fields. Large contentJSON strings stay strings;
/// serialization, validation and stateful adaptation happen on the worker.
enum BlockNoteBridgeEnvelope: Sendable {
    case json(String)
    case fields([String: BlockNoteBridgeValue])
    case invalid

    static func capture(_ body: Any) -> Self {
        if let json = body as? String { return .json(json) }
        guard let object = body as? [String: Any] else { return .invalid }
        let fields = ["type", "protocolVersion", "schemaVersion", "revision", "contentJSON",
                      "fallbackMarkdown", "isFocused", "contentHeight", "requestID", "code", "details"]
        var result = [String: BlockNoteBridgeValue]()
        for key in fields {
            if let value = object[key] { result[key] = .scalar(value) }
        }
        if let raw = object["selectionState"] {
            if let selection = raw as? [String: Any] {
                var values = [String: BlockNoteBridgeValue]()
                if let value = selection["blockType"] { values["blockType"] = .scalar(value) }
                if let formats = selection["formats"] as? [String: Any] {
                    var flags = [String: BlockNoteBridgeValue]()
                    for key in ["bold", "italic", "underline", "strike"] {
                        if let value = formats[key] { flags[key] = .scalar(value) }
                    }
                    values["formats"] = .object(flags)
                } else if selection["formats"] != nil { values["formats"] = .invalid }
                result["selectionState"] = .object(values)
            } else { result["selectionState"] = .invalid }
        }
        return .fields(result)
    }

    /// Raw string bodies conservatively retire an outstanding DOM probe, without
    /// parsing a potentially large message on MainActor. WK normally sends objects.
    var mayContainNaturalFocus: Bool {
        switch self {
        case .json: return true
        case .fields(let fields): return fields["type"] == .string("bodyFocusChanged")
        case .invalid: return false
        }
    }

    var estimatedBytes: Int {
        switch self {
        case .json(let value): return value.utf8.count
        case .fields(let fields): return fields.reduce(0) { $0 + $1.key.utf8.count + $1.value.estimatedBytes }
        case .invalid: return 0
        }
    }

    func decode() throws -> BlockNoteEditorMessage {
        let data: Data
        switch self {
        case .json(let value): data = Data(value.utf8)
        case .fields(let fields): data = try JSONEncoder().encode(fields)
        case .invalid: throw BlockNoteBridgeEncodingError.invalidValue
        }
        return try JSONDecoder().decode(BlockNoteEditorMessage.self, from: data)
    }
}

indirect enum BlockNoteBridgeValue: Encodable, Equatable, Sendable {
    case string(String), integer(Int64), number(Double), bool(Bool), null
    case object([String: BlockNoteBridgeValue]), invalid

    static func scalar(_ value: Any) -> Self {
        if value is NSNull { return .null }
        if let string = value as? String { return .string(string) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            let kind = String(cString: number.objCType)
            if ["c", "s", "i", "l", "q"].contains(kind) { return .integer(number.int64Value) }
            return .number(number.doubleValue)
        }
        return .invalid
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .object(let value): try container.encode(value)
        case .invalid: throw BlockNoteBridgeEncodingError.invalidValue
        }
    }

    var estimatedBytes: Int {
        switch self {
        case .string(let value): return value.utf8.count
        case .object(let values): return values.reduce(0) { $0 + $1.key.utf8.count + $1.value.estimatedBytes }
        default: return 8
        }
    }
}

enum BlockNoteBridgeEncodingError: Error { case invalidValue }

enum BlockNoteBridgeInput: Sendable {
    case navigationFinished
    case message(BlockNoteBridgeEnvelope, focusRevision: Int?)
    case command(BlockNoteEditorCommand)
    case malformedMessage
    case bridgeFailure(String)
    case focusObservation(Int)
    case focusProbe(isFocused: Bool, revision: Int)
    case close

    var estimatedBytes: Int {
        if case .message(let envelope, _) = self { return envelope.estimatedBytes }
        return 0
    }
}

struct BlockNotePreparedCommand: Sendable {
    let command: BlockNoteEditorCommand
    let script: String
}

struct BlockNotePreparedOutput: Sendable {
    let output: BlockNoteBridgeSessionOutput
    let commands: [BlockNotePreparedCommand]
    let isBridgeReady: Bool
    let mutationAllowed: Bool
    let focusProbeRevision: Int?
}

enum BlockNoteBridgeComputeStage: Sendable { case decode, session, encode }

/// The full stateful adapter/session stays together. The legacy Merge path uses
/// this same processor synchronously until its persistence lifetime is migrated.
struct BlockNoteBridgeProcessor: Sendable {
    private var session: BlockNoteEditorBridgeSession
    private var focusRevision = 0

    init(document: BlockNoteInitialDocument, editable: Bool) {
        session = BlockNoteEditorBridgeSession(document: document, editable: editable)
    }

    mutating func apply(_ input: BlockNoteBridgeInput, probe: @Sendable (BlockNoteBridgeComputeStage) -> Void = { _ in }) -> BlockNotePreparedOutput {
        probe(.session)
        var output: BlockNoteBridgeSessionOutput
        var probeRevision: Int?
        switch input {
        case .navigationFinished: output = session.navigationFinished()
        case .message(let envelope, let revision):
            if let revision { focusRevision = max(focusRevision, revision) }
            do {
                probe(.decode)
                let message = try envelope.decode()
                output = session.receive(message)
            } catch { output = session.malformedMessage() }
        case .command(let command): output = session.request(command)
        case .malformedMessage: output = session.malformedMessage()
        case .bridgeFailure(let code): output = session.bridgeFailure(code: code)
        case .focusObservation(let revision):
            focusRevision = max(focusRevision, revision)
            output = .init()
        case .focusProbe(let focused, let revision):
            probeRevision = revision
            output = revision == focusRevision && session.state.mutationAllowed
                ? session.receive(.bodyFocusChanged(isFocused: focused)) : .init()
        case .close: output = session.teardown()
        }
        var commands = [BlockNotePreparedCommand]()
        do {
            for command in output.commands {
                probe(.encode)
                let data = try JSONEncoder().encode(command)
                let json = String(decoding: data, as: UTF8.self)
                commands.append(.init(command: command, script: "window.\(BlockNoteEditorProtocol.javaScriptBridgeName).receiveCommand(\(json));"))
            }
        } catch {
            commands = []
            output = session.bridgeFailure(code: "command_encoding_failed")
        }
        return .init(output: output, commands: commands,
                     isBridgeReady: session.state.isBridgeReady,
                     mutationAllowed: session.state.mutationAllowed,
                     focusProbeRevision: probeRevision)
    }
}

actor BlockNoteBridgeWorker {
    private var processor: BlockNoteBridgeProcessor?
    private let probe: @Sendable (BlockNoteBridgeComputeStage) -> Void
    private let beforeApply: (@Sendable (BlockNoteBridgeInput) async -> Void)?

    init(document: BlockNoteInitialDocument, editable: Bool,
         probe: @escaping @Sendable (BlockNoteBridgeComputeStage) -> Void = { _ in },
         beforeApply: (@Sendable (BlockNoteBridgeInput) async -> Void)? = nil) {
        processor = .init(document: document, editable: editable)
        self.probe = probe
        self.beforeApply = beforeApply
    }

    func apply(_ input: BlockNoteBridgeInput) async -> BlockNotePreparedOutput {
        await beforeApply?(input)
        guard processor != nil else {
            return .init(output: .init(), commands: [], isBridgeReady: false, mutationAllowed: false, focusProbeRevision: nil)
        }
        let output = processor!.apply(input, probe: probe)
        if case .close = input { processor = nil }
        return output
    }
}
