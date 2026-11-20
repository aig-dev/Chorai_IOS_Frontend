import Foundation

public extension Notification.Name {
    static let cardReadSessionDidChange = Notification.Name("chorai.cardReadSessionDidChange")
    static let cardReadInvalidated = Notification.Name("chorai.cardReadInvalidated")
}

public enum CardReadInvalidation {
    public static let statusKey = "http_status"
}

/// Main-thread snapshots of results the current session has already read.
@MainActor
public final class RecentCardReads<Value> {
    private let capacity: Int
    private var values: [String: Value] = [:]
    private var recency: [String] = []
    private var observations: [NSObjectProtocol] = []
    private let center: NotificationCenter

    public convenience init(capacity: Int = 20) {
        self.init(capacity: capacity, center: .default)
    }

    init(capacity: Int = 20, center: NotificationCenter) {
        self.capacity = max(capacity, 1)
        self.center = center
        observations.append(center.addObserver(forName: .cardReadSessionDidChange, object: nil, queue: .main) { [weak self] _ in
            // NotificationCenter explicitly delivers on the main operation queue.
            // Preserve synchronous eviction; an asynchronous Task would leave stale reads.
            MainActor.assumeIsolated { self?.removeAll() }
        })
        observations.append(center.addObserver(forName: .cardReadInvalidated, object: nil, queue: .main) { [weak self] event in
            guard let id = event.object as? String else { return }
            MainActor.assumeIsolated { self?.remove(id) }
        })
    }

    isolated deinit { observations.forEach(center.removeObserver) }

    public func value(for cardID: String) -> Value? {
        guard let value = values[cardID] else { return nil }
        touch(cardID)
        return value
    }

    public func insert(_ value: Value, for cardID: String) {
        values[cardID] = value
        touch(cardID)
        if recency.count > capacity { values.removeValue(forKey: recency.removeFirst()) }
    }

    public func remove(_ cardID: String) {
        values.removeValue(forKey: cardID)
        recency.removeAll { $0 == cardID }
    }

    public func removeAll() {
        values.removeAll()
        recency.removeAll()
    }

    private func touch(_ cardID: String) {
        recency.removeAll { $0 == cardID }
        recency.append(cardID)
    }
}
