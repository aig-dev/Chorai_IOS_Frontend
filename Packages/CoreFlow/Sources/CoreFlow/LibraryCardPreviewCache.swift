import Foundation

public struct LibraryCardPreviewInput: Equatable, Sendable {
    public let cardID: String
    public let content: String
    public let contentJSON: String?
    private let version: Version

    private enum Version: Equatable, Sendable {
        case hash(String)
        case snapshot(UUID)
    }

    public init(cardID: String, contentHash: String?, snapshotID: UUID, content: String, contentJSON: String?) {
        self.cardID = cardID
        self.content = content
        self.contentJSON = contentJSON
        if let contentHash, !contentHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            version = .hash(contentHash)
        } else {
            version = .snapshot(snapshotID)
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        // Display URLs can change while the document hash is still current.
        lhs.cardID == rhs.cardID && lhs.version == rhs.version
            && lhs.content == rhs.content && lhs.contentJSON == rhs.contentJSON
    }

    fileprivate var estimatedBytes: Int {
        cardID.utf8.count + content.utf8.count + (contentJSON?.utf8.count ?? 0)
    }
}

/// The caller supplies only the current session's authorized card snapshots.
@MainActor
public final class LibraryCardPreviewCache {
    public struct ReadToken: Equatable, Sendable {
        fileprivate let cardID: String
        fileprivate let sessionID: UUID
        fileprivate let invalidationID: UUID?
    }

    private struct Preview: Sendable {
        let value: LibraryCardPresentation
        let bytes: Int
    }

    private struct Entry {
        let input: LibraryCardPreviewInput
        let preview: Preview
    }

    private struct Flight {
        let id = UUID()
        let input: LibraryCardPreviewInput
        let task: Task<Preview?, Never>
    }

    private let entryLimit: Int
    private let byteLimit: Int
    private let parse: @Sendable (LibraryCardPreviewInput) -> LibraryCardPresentation
    private var saved: [String: Entry] = [:]
    private var recency: [String] = []
    private var savedBytes = 0
    private var flights: [String: Flight] = [:]
    private var sessionID = UUID()
    private var invalidations: [String: UUID] = [:]

    public init(
        entryLimit: Int = 40,
        byteLimit: Int = 4 * 1024 * 1024,
        parse: @escaping @Sendable (LibraryCardPreviewInput) -> LibraryCardPresentation = {
            LibraryCardPreviewParser.presentation(content: $0.content, contentJSON: $0.contentJSON)
        }
    ) {
        self.entryLimit = max(1, entryLimit)
        self.byteLimit = max(0, byteLimit)
        self.parse = parse
    }

    public func token(for cardID: String) -> ReadToken {
        ReadToken(cardID: cardID, sessionID: sessionID, invalidationID: invalidations[cardID])
    }

    public func isCurrent(_ token: ReadToken) -> Bool {
        token.sessionID == sessionID && token.invalidationID == invalidations[token.cardID]
    }

    public func read(_ input: LibraryCardPreviewInput, token: ReadToken) async -> LibraryCardPresentation? {
        guard input.cardID == token.cardID, isCurrent(token), !Task.isCancelled else { return nil }
        if let entry = saved[input.cardID] {
            if entry.input == input {
                touch(input.cardID)
                return entry.preview.value
            }
            removeSaved(input.cardID)
        }

        let flight: Flight
        if let pending = flights[input.cardID], pending.input == input {
            flight = pending
        } else {
            flights[input.cardID]?.task.cancel()
            let task = Task.detached(priority: Task.currentPriority) { [parse] () -> Preview? in
                guard !Task.isCancelled else { return nil }
                let result = parse(input)
                return Preview(value: result, bytes: input.estimatedBytes + result.estimatedBytes)
            }
            flight = Flight(input: input, task: task)
            flights[input.cardID] = flight
        }

        let preview = await flight.task.value
        guard isCurrent(token) else { return nil }
        if flights[input.cardID]?.id == flight.id {
            flights.removeValue(forKey: input.cardID)
            if let preview { save(preview, for: input) }
        }
        return Task.isCancelled ? nil : preview?.value
    }

    public func invalidate(cardID: String) {
        invalidations[cardID] = UUID()
        removeSaved(cardID)
        flights.removeValue(forKey: cardID)?.task.cancel()
    }

    public func invalidateAll() {
        sessionID = UUID()
        invalidations.removeAll()
        removeCachedPreviews()
        flights.values.forEach { $0.task.cancel() }
        flights.removeAll()
    }

    public func removeCachedPreviews() {
        saved.removeAll()
        recency.removeAll()
        savedBytes = 0
    }

    private func save(_ preview: Preview, for input: LibraryCardPreviewInput) {
        guard preview.bytes <= byteLimit else { return }
        while saved.count >= entryLimit || savedBytes > byteLimit - preview.bytes {
            guard let oldest = recency.first else { break }
            removeSaved(oldest)
        }
        saved[input.cardID] = Entry(input: input, preview: preview)
        savedBytes += preview.bytes
        touch(input.cardID)
    }

    private func removeSaved(_ cardID: String) {
        if let entry = saved.removeValue(forKey: cardID) {
            savedBytes -= entry.preview.bytes
            recency.removeAll { $0 == cardID }
        }
    }

    private func touch(_ cardID: String) {
        recency.removeAll { $0 == cardID }
        recency.append(cardID)
    }
}
