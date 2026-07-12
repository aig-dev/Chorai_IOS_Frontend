import Foundation

public protocol CoreNotionSourceServing: Sendable {
    func status() async throws -> NotionConnectionStatus
    func authorizationURL(client: NotionClient) async throws -> URL
    func pages(query: String?) async throws -> [NotionPage]
    func enqueue(pageIDs: [String]) async throws -> NotionImportReceipt
    func job(id: String) async throws -> NotionImportJob
    func disconnect() async throws
}

public protocol NotionSourceSleeping: Sendable {
    func sleep(for interval: TimeInterval) async throws
}

public struct SystemNotionSourceSleeper: NotionSourceSleeping {
    public init() {}

    public func sleep(for interval: TimeInterval) async throws {
        let nanoseconds = UInt64(max(0, interval) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

public protocol NotionSourceClock: Sendable {
    func now() -> Date
}

public struct SystemNotionSourceClock: NotionSourceClock {
    public init() {}
    public func now() -> Date { Date() }
}
