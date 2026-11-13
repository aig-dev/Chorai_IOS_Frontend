import Foundation

public extension Notification.Name {
    static let cardReadSessionDidChange = Notification.Name("chorai.cardReadSessionDidChange")
    static let cardReadInvalidated = Notification.Name("chorai.cardReadInvalidated")
}

/// Main-thread snapshots of results the current session has already read.
public final class RecentCardReads<Value> {
    private let capacity: Int
    private var values: [String: Value] = [:]
    private var recency: [String] = []
    private var observations: [NSObjectProtocol] = []

    public init(capacity: Int = 20) {
        self.capacity = max(capacity, 1)
        let center = NotificationCenter.default
        observations.append(center.addObserver(forName: .cardReadSessionDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.removeAll()
        })
        observations.append(center.addObserver(forName: .cardReadInvalidated, object: nil, queue: .main) { [weak self] event in
            if let id = event.object as? String { self?.remove(id) }
        })
    }

    deinit { observations.forEach(NotificationCenter.default.removeObserver) }

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
