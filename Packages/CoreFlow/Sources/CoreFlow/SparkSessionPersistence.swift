import Foundation

public protocol SparkSessionPersisting {
    func snapshot(actorID: String, rootSourceAssetID: String) throws -> SparkSessionSnapshot?
    func save(_ snapshot: SparkSessionSnapshot) throws
    func remove(actorID: String, rootSourceAssetID: String) throws
}

public enum SparkSessionPersistenceError: Error {
    case invalidRecord
    case writeFailed
    case recordChanged
}

public final class UserDefaultsSparkSessionStore: SparkSessionPersisting {
    private static let recordLock = NSLock()
    private var observed = [String: Data]()
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "chorai.spark.session") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func snapshot(actorID: String, rootSourceAssetID: String) throws -> SparkSessionSnapshot? {
        Self.recordLock.lock(); defer { Self.recordLock.unlock() }
        let storageKey = key(actorID: actorID, rootSourceAssetID: rootSourceAssetID)
        guard let raw = defaults.object(forKey: storageKey) else {
            observed.removeValue(forKey: storageKey)
            return nil
        }
        guard let data = raw as? Data, data.count <= 131_072 else { throw SparkSessionPersistenceError.invalidRecord }
        // Decoding or scope failure is not evidence that no paid request was sent.
        // Keep the original bytes and block a new operation.
        let snapshot = try JSONDecoder().decode(SparkSessionSnapshot.self, from: data)
        guard snapshot.actorID == actorID, snapshot.rootSourceAssetID == rootSourceAssetID else {
            throw SparkSessionPersistenceError.invalidRecord
        }
        try Self.validate(snapshot)
        observed[storageKey] = data
        return snapshot
    }

    public func save(_ snapshot: SparkSessionSnapshot) throws {
        try Self.validate(snapshot)
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 131_072 else { throw SparkSessionPersistenceError.invalidRecord }
        Self.recordLock.lock(); defer { Self.recordLock.unlock() }
        let storageKey = key(actorID: snapshot.actorID, rootSourceAssetID: snapshot.rootSourceAssetID)
        try verifyUnchanged(storageKey)
        defaults.set(data, forKey: storageKey)
        guard defaults.synchronize(), defaults.data(forKey: storageKey) == data else {
            throw SparkSessionPersistenceError.writeFailed
        }
        observed[storageKey] = data
    }

    public func remove(actorID: String, rootSourceAssetID: String) throws {
        Self.recordLock.lock(); defer { Self.recordLock.unlock() }
        let storageKey = key(actorID: actorID, rootSourceAssetID: rootSourceAssetID)
        try verifyUnchanged(storageKey)
        defaults.removeObject(forKey: storageKey)
        guard defaults.synchronize(), defaults.object(forKey: storageKey) == nil else {
            throw SparkSessionPersistenceError.writeFailed
        }
        observed.removeValue(forKey: storageKey)
    }

    // Distinct navigation stacks can hold the same actor/root session. A late
    // callback may only replace the exact bytes that this instance observed.
    private func verifyUnchanged(_ key: String) throws {
        let current = defaults.object(forKey: key)
        guard (current == nil || current is Data), (current as? Data) == observed[key] else {
            throw SparkSessionPersistenceError.recordChanged
        }
    }

    private static func validate(_ value: SparkSessionSnapshot) throws {
        func identity(_ value: String) -> Bool {
            value.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil
        }
        guard identity(value.actorID), identity(value.rootSourceAssetID), value.nodes.count <= 256,
              value.activeActivityID != nil || value.pendingTrigger != nil,
              Set(value.nodes.map(\.activityID)).count == value.nodes.count else {
            throw SparkSessionPersistenceError.invalidRecord
        }
        for node in value.nodes {
            guard identity(node.activityID), identity(node.sourceAssetID), identity(node.rootActivityID),
                  node.visibleIndex >= 0, node.chainDepth >= 0 else { throw SparkSessionPersistenceError.invalidRecord }
            if let parentID = node.parentActivityID {
                guard let parent = value.nodes.first(where: { $0.activityID == parentID }),
                      parent.rootActivityID == node.rootActivityID, node.chainDepth > 0, parent.chainDepth == node.chainDepth - 1 else {
                    throw SparkSessionPersistenceError.invalidRecord
                }
            } else if node.chainDepth != 0 || node.rootActivityID != node.activityID {
                throw SparkSessionPersistenceError.invalidRecord
            }
        }
        if let active = value.activeActivityID, !value.nodes.contains(where: { $0.activityID == active }) {
            throw SparkSessionPersistenceError.invalidRecord
        }
        if let pending = value.pendingTrigger {
            guard identity(pending.sourceAssetID), pending.priorVisibleIndex >= 0,
                  pending.requestKey.uuidString != "00000000-0000-0000-0000-000000000000" else {
                throw SparkSessionPersistenceError.invalidRecord
            }
            if let parent = pending.parentActivityID, !value.nodes.contains(where: { $0.activityID == parent }) {
                throw SparkSessionPersistenceError.invalidRecord
            }
            if let prior = pending.priorActivityID, !value.nodes.contains(where: { $0.activityID == prior }) {
                throw SparkSessionPersistenceError.invalidRecord
            }
            if let id = pending.attemptActivityID, !identity(id) { throw SparkSessionPersistenceError.invalidRecord }
            if let id = pending.committedActivityID {
                guard identity(id), pending.attemptActivityID == nil || pending.attemptActivityID == id else {
                    throw SparkSessionPersistenceError.invalidRecord
                }
            }
        }
    }

    private func key(actorID: String, rootSourceAssetID: String) -> String {
        "\(keyPrefix).\(actorID).\(rootSourceAssetID)"
    }
}
