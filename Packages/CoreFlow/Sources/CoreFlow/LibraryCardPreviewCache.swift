import Foundation

public struct LibraryCardPreviewInput: Equatable, Sendable {
    public let cardID: String
    public let content: String
    public let contentJSON: String?
    public let localScope: NoteStoreScope?
    public var allowsLocalImages: Bool { localScope != nil }
    private let version: Version

    private enum Version: Equatable, Sendable {
        case hash(String)
        case snapshot(UUID)
        case localBody(Int64)
    }

    public init(cardID: String, contentHash: String?, snapshotID: UUID, content: String, contentJSON: String?) {
        self.cardID = cardID
        self.content = content
        self.contentJSON = contentJSON
        localScope = nil
        if let contentHash, !contentHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            version = .hash(contentHash)
        } else {
            version = .snapshot(snapshotID)
        }
    }

    public init(localNoteID: String, scope: NoteStoreScope, bodyRevision: Int64, content: String, contentJSON: String?) {
        cardID = localNoteID
        self.content = content
        self.contentJSON = contentJSON
        localScope = scope
        version = .localBody(bodyRevision)
    }

    // Equality includes the actual strings: display URLs may change without a new document hash.
    fileprivate var key: PreviewKey { PreviewKey(cardID: cardID, localScope: localScope) }
    fileprivate var estimatedBytes: Int {
        cardID.utf8.count + content.utf8.count + (contentJSON?.utf8.count ?? 0)
            + (localScope?.actorID.utf8.count ?? 0) + (localScope?.environmentID.utf8.count ?? 0)
    }
}

private struct PreviewKey: Hashable, Sendable {
    let cardID: String
    let localScope: NoteStoreScope?
}

/// The caller supplies only the current session's authorized snapshots.
@MainActor
public final class LibraryCardPreviewCache {
    public struct ReadToken: Equatable, Sendable {
        fileprivate let key: PreviewKey
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

    private final class Flight {
        let id = UUID()
        let input: LibraryCardPreviewInput
        var operation: Operation?
        var waiters: [UUID: CheckedContinuation<LibraryCardPresentation?, Never>] = [:]
        init(input: LibraryCardPreviewInput) { self.input = input }
    }

    private let entryLimit: Int
    private let byteLimit: Int
    private let parse: @Sendable (LibraryCardPreviewInput) -> LibraryCardPresentation
    private let queue: OperationQueue
    private var saved: [PreviewKey: Entry] = [:]
    private var recency: [PreviewKey] = []
    private var savedBytes = 0
    private var flights: [PreviewKey: [Flight]] = [:]
    private var latestFlight: [PreviewKey: UUID] = [:]
    private var sessionID = UUID()
    private var invalidations: [String: UUID] = [:]

    public init(
        entryLimit: Int = 40,
        byteLimit: Int = 4 * 1024 * 1024,
        maxConcurrentParses: Int = 2,
        parse: @escaping @Sendable (LibraryCardPreviewInput) -> LibraryCardPresentation = {
            LibraryCardPreviewParser.presentation(
                content: $0.content, contentJSON: $0.contentJSON, allowsLocalImages: $0.allowsLocalImages
            )
        }
    ) {
        self.entryLimit = max(1, entryLimit)
        self.byteLimit = max(0, byteLimit)
        self.parse = parse
        queue = OperationQueue()
        queue.name = "Chorai.card-preview"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(1, maxConcurrentParses)
    }

    public func token(for cardID: String, localScope: NoteStoreScope? = nil) -> ReadToken {
        ReadToken(key: PreviewKey(cardID: cardID, localScope: localScope),
                  sessionID: sessionID, invalidationID: invalidations[cardID])
    }

    public func isCurrent(_ token: ReadToken) -> Bool {
        token.sessionID == sessionID && token.invalidationID == invalidations[token.key.cardID]
    }

    public func read(_ input: LibraryCardPreviewInput, token: ReadToken) async -> LibraryCardPresentation? {
        guard input.key == token.key, isCurrent(token), !Task.isCancelled else { return nil }
        if let entry = saved[input.key] {
            if entry.input == input {
                touch(input.key)
                return entry.preview.value
            }
        }
        // Different visible consumers may own different immutable snapshots of
        // the same card. Retire only cancellation/invalidation, not their peers.
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, isCurrent(token) else {
                    continuation.resume(returning: nil)
                    return
                }
                if let flight = flights[input.key]?.first(where: { $0.input == input }) {
                    flight.waiters[waiterID] = continuation
                    return
                }
                let flight = Flight(input: input)
                flight.waiters[waiterID] = continuation
                flights[input.key, default: []].append(flight)
                latestFlight[input.key] = flight.id
                let flightID = flight.id
                let operation = BlockOperation { [parse, weak self] in
                    let value = parse(input)
                    let preview = Preview(value: value, bytes: input.estimatedBytes + value.estimatedBytes)
                    Task { @MainActor [weak self] in
                        self?.finish(input: input, id: flightID, token: token, preview: preview)
                    }
                }
                flight.operation = operation
                queue.addOperation(operation)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(waiterID: waiterID, key: input.key)
            }
        }
    }

    public func invalidate(cardID: String) {
        invalidations[cardID] = UUID()
        for key in Array(saved.keys) where key.cardID == cardID { removeSaved(key) }
        for key in Array(flights.keys) where key.cardID == cardID { retire(key) }
    }

    public func invalidateAll() {
        sessionID = UUID()
        invalidations.removeAll()
        removeCachedPreviews()
        for key in Array(flights.keys) { retire(key) }
    }

    public func removeCachedPreviews() {
        saved.removeAll()
        recency.removeAll()
        savedBytes = 0
    }

    private func finish(input: LibraryCardPreviewInput, id: UUID, token: ReadToken, preview: Preview) {
        guard let flight = flights[input.key]?.first(where: { $0.id == id }) else { return }
        let value: LibraryCardPresentation?
        if isCurrent(token) {
            if latestFlight[input.key] == id { save(preview, for: input) }
            value = preview.value
        } else { value = nil }
        removeFlight(id, key: input.key)
        for waiter in flight.waiters.values { waiter.resume(returning: value) }
    }

    private func cancel(waiterID: UUID, key: PreviewKey) {
        guard let flight = flights[key]?.first(where: { $0.waiters[waiterID] != nil }),
              let waiter = flight.waiters.removeValue(forKey: waiterID) else { return }
        waiter.resume(returning: nil)
        if flight.waiters.isEmpty {
            removeFlight(flight.id, key: key)
            flight.operation?.cancel()
        }
    }

    private func removeFlight(_ id: UUID, key: PreviewKey) {
        flights[key]?.removeAll { $0.id == id }
        if flights[key]?.isEmpty == true {
            flights[key] = nil
            latestFlight[key] = nil
        }
    }

    private func retire(_ key: PreviewKey) {
        guard let retired = flights.removeValue(forKey: key) else { return }
        latestFlight[key] = nil
        // OperationQueue retains running slots until synchronous parsing returns.
        for flight in retired {
            flight.operation?.cancel()
            for waiter in flight.waiters.values { waiter.resume(returning: nil) }
        }
    }

    private func save(_ preview: Preview, for input: LibraryCardPreviewInput) {
        guard preview.bytes <= byteLimit else { return }
        removeSaved(input.key)
        while saved.count >= entryLimit || savedBytes > byteLimit - preview.bytes {
            guard let oldest = recency.first else { break }
            removeSaved(oldest)
        }
        saved[input.key] = Entry(input: input, preview: preview)
        savedBytes += preview.bytes
        touch(input.key)
    }

    private func removeSaved(_ key: PreviewKey) {
        if let entry = saved.removeValue(forKey: key) {
            savedBytes -= entry.preview.bytes
            recency.removeAll { $0 == key }
        }
    }

    private func touch(_ key: PreviewKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
