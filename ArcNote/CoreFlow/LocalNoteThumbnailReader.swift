import Combine
import CoreFlow
import UIKit

/// Owns verified local image work, independently of any one visible row.
@MainActor
final class LocalNoteThumbnailReader: ObservableObject {
    static let shared = LocalNoteThumbnailReader(library: LocalNotesController.shared.library, currentScope: {
        let auth = AuthManager.shared
        let scope = LocalNotesController.shared.library.scope
        return auth.canOpenLocalNotes && auth.currentNoteScope == scope ? scope : nil
    })

    @Published private(set) var invalidationGeneration: UInt64 = 0
    private struct Key: Hashable {
        let identity: NoteThumbnailIdentity
        let pixels: Int
    }
    private struct Cached {
        let image: UIImage
        let bytes: Int
    }
    private final class Flight {
        let id = UUID()
        let key: Key
        let epoch: UInt64
        var waiters: [UUID: CheckedContinuation<UIImage, Error>] = [:]
        var task: Task<Void, Never>?
        init(key: Key, epoch: UInt64) { self.key = key; self.epoch = epoch }
    }

    private let library: NoteLibraryStore
    private let currentScope: @MainActor () -> NoteStoreScope?
    private let load: @MainActor (NoteThumbnailIdentity) async throws -> Data
    private let prepare: @Sendable (Data, CGSize) -> UIImage?
    private let entryLimit: Int
    private let byteLimit: Int
    private let concurrency: Int
    private var epoch: UInt64 = 0
    private var cached: [Key: Cached] = [:]
    private var recency: [Key] = []
    private var cachedBytes = 0
    private var flights: [Key: Flight] = [:]
    private var queued: [Flight] = []
    // Retired tasks stay here until their actual load/prepare work returns.
    private var running = Set<UUID>()
    private var subscriptions = Set<AnyCancellable>()

    init(
        library: NoteLibraryStore,
        currentScope: @escaping @MainActor () -> NoteStoreScope?,
        entryLimit: Int = 40,
        byteLimit: Int = 16 * 1024 * 1024,
        maxConcurrentPreparations: Int = 2,
        notifications: NotificationCenter = .default,
        load: (@MainActor (NoteThumbnailIdentity) async throws -> Data)? = nil,
        prepare: @escaping @Sendable (Data, CGSize) -> UIImage? = { data, size in
            UIImage(data: data)?.preparingThumbnail(of: size)
        }
    ) {
        self.library = library; self.currentScope = currentScope
        self.load = load ?? { try await library.thumbnailData(for: $0) }
        self.prepare = prepare
        self.entryLimit = max(0, entryLimit); self.byteLimit = max(0, byteLimit)
        concurrency = max(1, maxConcurrentPreparations)
        library.changes.sink { [weak self] change in
            guard let self else { return }
            switch change {
            case .background: break
            case .reset: self.invalidateAll()
            case .updated: self.invalidateObsoleteImages()
            }
        }.store(in: &subscriptions)
        notifications.publisher(for: .cardReadSessionDidChange).sink { [weak self] _ in
            self?.invalidateAll()
        }.store(in: &subscriptions)
        notifications.publisher(for: UIApplication.didReceiveMemoryWarningNotification).sink { [weak self] _ in
            self?.removeCachedImages()
        }.store(in: &subscriptions)
    }

    func allows(_ scope: NoteStoreScope) -> Bool { currentScope() == scope && library.scope == scope }

    func image(source: NoteThumbnailSource, cardID: String, scope: NoteStoreScope,
               bodyRevision: Int64, pixelSize: Int) async throws -> UIImage {
        try Task.checkCancellation()
        guard allows(scope) else { throw NoteLocalStoreError.invalidScope }
        guard (1...4096).contains(pixelSize) else { throw NoteLocalStoreError.invalidAttachment }
        let expectedEpoch = epoch
        let identity = try await library.thumbnailIdentity(source: source, identifier: cardID, scope: scope, bodyRevision: bodyRevision)
        try validate(identity, epoch: expectedEpoch)
        try Task.checkCancellation()
        let key = Key(identity: identity, pixels: pixelSize)
        if let value = cached[key] { touch(key); return value.image }
        let consumer = UUID()
        let image: UIImage = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                if let flight = flights[key] {
                    flight.waiters[consumer] = continuation
                } else {
                    let flight = Flight(key: key, epoch: expectedEpoch)
                    flight.waiters[consumer] = continuation
                    flights[key] = flight; queued.append(flight)
                    startQueuedWork()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(consumer: consumer, key: key) }
        }
        try Task.checkCancellation()
        try validate(identity, epoch: expectedEpoch)
        return image
    }

    private func validate(_ identity: NoteThumbnailIdentity, epoch expected: UInt64) throws {
        guard allows(identity.scope) else { throw NoteLocalStoreError.invalidScope }
        guard epoch == expected, library.isCurrentThumbnail(identity) else { throw NoteLocalStoreError.staleGeneration }
    }

    private func startQueuedWork() {
        while running.count < concurrency, !queued.isEmpty {
            let flight = queued.removeFirst()
            guard flights[flight.key]?.id == flight.id else { continue }
            running.insert(flight.id)
            flight.task = Task { [weak self] in
                guard let self else { return }
                let result: Result<UIImage, Error>
                do {
                    try self.validate(flight.key.identity, epoch: flight.epoch)
                    let data = try await self.load(flight.key.identity)
                    try Task.checkCancellation()
                    let prepare = self.prepare
                    let size = CGSize(width: flight.key.pixels, height: flight.key.pixels)
                    // Await real completion even when the last consumer retires. Otherwise
                    // cancellation could start more decodes than the concurrency limit.
                    let image = await Task.detached(priority: .userInitiated) {
                        autoreleasepool { prepare(data, size) }
                    }.value
                    try Task.checkCancellation()
                    try self.validate(flight.key.identity, epoch: flight.epoch)
                    guard let image else { throw NoteLocalStoreError.invalidAttachment }
                    result = .success(image)
                } catch { result = .failure(error) }
                self.finish(flight, result: result)
            }
        }
    }

    private func finish(_ flight: Flight, result: Result<UIImage, Error>) {
        running.remove(flight.id)
        flight.task = nil
        if flights[flight.key]?.id == flight.id {
            flights.removeValue(forKey: flight.key)
            if case .success(let image) = result { retain(image, for: flight.key) }
            let waiters = flight.waiters.values
            flight.waiters.removeAll()
            for waiter in waiters { waiter.resume(with: result) }
        }
        startQueuedWork()
    }

    private func cancel(consumer: UUID, key: Key) {
        guard let flight = flights[key], let waiter = flight.waiters.removeValue(forKey: consumer) else { return }
        waiter.resume(throwing: CancellationError())
        if flight.waiters.isEmpty { retire(flight, error: CancellationError()) }
    }

    private func retire(_ flight: Flight, error: Error) {
        guard flights[flight.key]?.id == flight.id else { return }
        flights.removeValue(forKey: flight.key)
        queued.removeAll { $0.id == flight.id }
        flight.task?.cancel()
        let waiters = flight.waiters.values
        flight.waiters.removeAll()
        for waiter in waiters { waiter.resume(throwing: error) }
    }

    private func invalidateAll() {
        epoch &+= 1
        removeCachedImages()
        for flight in Array(flights.values) { retire(flight, error: NoteLocalStoreError.staleGeneration) }
        invalidationGeneration &+= 1
    }

    private func invalidateObsoleteImages() {
        let obsolete = cached.keys.filter { !library.isCurrentThumbnail($0.identity) }
        let pending = flights.values.filter { !library.isCurrentThumbnail($0.key.identity) }
        for key in obsolete { remove(key) }
        for flight in pending { retire(flight, error: NoteLocalStoreError.staleGeneration) }
        if !obsolete.isEmpty || !pending.isEmpty { invalidationGeneration &+= 1 }
    }

    private func retain(_ image: UIImage, for key: Key) {
        guard let bitmap = image.cgImage, entryLimit > 0 else { return }
        let (bytes, overflow) = bitmap.bytesPerRow.multipliedReportingOverflow(by: bitmap.height)
        guard !overflow, bytes <= byteLimit else { return }
        remove(key)
        while cached.count >= entryLimit || cachedBytes > byteLimit - bytes {
            guard let oldest = recency.first else { break }
            remove(oldest)
        }
        cached[key] = Cached(image: image, bytes: bytes); cachedBytes += bytes; touch(key)
    }
    private func touch(_ key: Key) { recency.removeAll { $0 == key }; recency.append(key) }
    private func remove(_ key: Key) {
        if let value = cached.removeValue(forKey: key) { cachedBytes -= value.bytes }
        recency.removeAll { $0 == key }
    }
    private func removeCachedImages() { cached.removeAll(); recency.removeAll(); cachedBytes = 0 }
}
