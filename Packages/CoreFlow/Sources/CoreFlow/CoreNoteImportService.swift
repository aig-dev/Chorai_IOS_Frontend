import Foundation

public protocol CoreNoteImportServing: Sendable {
    func enqueue(
        files: [NoteImportFile],
        clientRequestID: String
    ) async throws -> NoteImportReceipt
    func jobs(limit: Int) async throws -> [NoteImportJobSummary]
    func job(id: String) async throws -> NoteImportJobDetail
    func cancel(id: String) async throws
}

public protocol NoteImportRequestIDPersisting: Sendable {
    func load(actorID: String) -> String?
    func save(_ requestID: String, actorID: String)
    func clear(actorID: String)
}

public protocol NoteImportSleeping: Sendable {
    func sleep(nanoseconds: UInt64) async throws
}

public struct SystemNoteImportSleeper: NoteImportSleeping {
    public init() {}

    public func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

public final class UserDefaultsNoteImportRequestIDStore: NoteImportRequestIDPersisting, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String
    private let lock = NSLock()

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "chorai.note-import.request"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func load(actorID: String) -> String? {
        lock.withLock { defaults.string(forKey: key(actorID: actorID)) }
    }

    public func save(_ requestID: String, actorID: String) {
        lock.withLock { defaults.set(requestID, forKey: key(actorID: actorID)) }
    }

    public func clear(actorID: String) {
        lock.withLock { defaults.removeObject(forKey: key(actorID: actorID)) }
    }

    private func key(actorID: String) -> String {
        "\(keyPrefix).\(actorID)"
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
