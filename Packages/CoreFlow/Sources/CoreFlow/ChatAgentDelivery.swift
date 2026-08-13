import Foundation

public struct ChatConversationEvent: Equatable, Sendable {
    public let name: String
    public let id: String?
    public let data: Data

    public init(name: String, id: String?, data: Data) {
        self.name = name
        self.id = id
        self.data = data
    }
}

public struct ChatConversationEventCursor: Equatable, Sendable {
    private var value: UInt64?

    public init() {}

    public var lastEventID: String? {
        value.map(String.init)
    }

    public mutating func advance(to eventID: UInt64) {
        value = max(value ?? 0, eventID)
    }

    public mutating func advance(to rawEventID: String) {
        guard let eventID = UInt64(
            rawEventID.trimmingCharacters(in: .whitespacesAndNewlines)
        ) else { return }
        advance(to: eventID)
    }
}

/// Incrementally decodes Server-Sent Events without assuming network chunks
/// align to either UTF-8 scalar or SSE frame boundaries.
public struct ChatServerSentEventParser: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ chunk: Data) -> [ChatConversationEvent] {
        buffer.append(chunk)

        var events: [ChatConversationEvent] = []
        while let delimiter = firstFrameDelimiter() {
            let frame = buffer.subdata(in: buffer.startIndex..<delimiter.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<delimiter.upperBound)
            if let event = Self.parseFrame(frame) {
                events.append(event)
            }
        }
        return events
    }

    private func firstFrameDelimiter() -> Range<Data.Index>? {
        let lineFeed = buffer.range(of: Data([0x0A, 0x0A]))
        let carriageReturnLineFeed = buffer.range(
            of: Data([0x0D, 0x0A, 0x0D, 0x0A])
        )

        switch (lineFeed, carriageReturnLineFeed) {
        case let (lhs?, rhs?):
            return lhs.lowerBound < rhs.lowerBound ? lhs : rhs
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private static func parseFrame(_ data: Data) -> ChatConversationEvent? {
        let text = String(decoding: data, as: UTF8.self)
        var name = "message"
        var id: String?
        var dataLines: [String] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if line.last == "\r" {
                line.removeLast()
            }
            guard !line.isEmpty, !line.hasPrefix(":") else { continue }

            let field: String
            var value: String
            if let separator = line.firstIndex(of: ":") {
                field = String(line[..<separator])
                value = String(line[line.index(after: separator)...])
                if value.first == " " {
                    value.removeFirst()
                }
            } else {
                field = line
                value = ""
            }

            switch field {
            case "event":
                name = value
            case "id":
                id = value
            case "data":
                dataLines.append(value)
            default:
                continue
            }
        }

        guard !dataLines.isEmpty else { return nil }
        return ChatConversationEvent(
            name: name,
            id: id,
            data: Data(dataLines.joined(separator: "\n").utf8)
        )
    }
}

public enum ChatAgentDeliveryState: Equatable, Sendable {
    case idle
    case thinking
    case failed(message: String)
}

public struct ChatAgentDeliveryUpdate: Equatable, Sendable {
    public let state: ChatAgentDeliveryState
    public let shouldRefreshMessages: Bool

    public init(
        state: ChatAgentDeliveryState,
        shouldRefreshMessages: Bool
    ) {
        self.state = state
        self.shouldRefreshMessages = shouldRefreshMessages
    }
}

public enum ChatAgentDeliveryReducer {
    private struct ResponseReadyPayload: Decodable {
        let status: String
    }

    public static func reduce(
        event: ChatConversationEvent
    ) -> ChatAgentDeliveryUpdate? {
        switch event.name {
        case "agent.thinking":
            return ChatAgentDeliveryUpdate(
                state: .thinking,
                shouldRefreshMessages: false
            )
        case "agent.response_ready":
            guard
                let payload = try? JSONDecoder().decode(
                    ResponseReadyPayload.self,
                    from: event.data
                )
            else {
                return failedUpdate()
            }

            switch payload.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "succeeded":
                return ChatAgentDeliveryUpdate(
                    state: .idle,
                    shouldRefreshMessages: true
                )
            case "failed":
                return failedUpdate()
            default:
                return failedUpdate()
            }
        default:
            return nil
        }
    }

    private static func failedUpdate() -> ChatAgentDeliveryUpdate {
        ChatAgentDeliveryUpdate(
            state: .failed(
                message: "Chora couldn't reply. Please try again."
            ),
            shouldRefreshMessages: false
        )
    }
}
