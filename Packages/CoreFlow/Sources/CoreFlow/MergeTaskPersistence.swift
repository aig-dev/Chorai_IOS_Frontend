import Foundation

public struct MergeTaskRecord: Codable, Equatable, Sendable, Identifiable {
    public let operationID: String
    public var snapshot: MergeSessionSnapshot
    public let createdAt: Date
    public var updatedAt: Date
    public var replacesJobID: String?
    public var id: String { snapshot.jobID ?? operationID }

    public init(
        operationID: String,
        snapshot: MergeSessionSnapshot,
        createdAt: Date,
        updatedAt: Date,
        replacesJobID: String?
    ) {
        self.operationID = operationID
        self.snapshot = snapshot
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.replacesJobID = replacesJobID
    }
}

public struct MergeTaskCollection: Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    public let actorID: String
    public var pendingCreations: [String: MergeTaskRecord]
    public var tasks: [String: MergeTaskRecord]

    public init(
        schemaVersion: Int = MergeTaskCollection.currentSchemaVersion,
        actorID: String,
        pendingCreations: [String: MergeTaskRecord],
        tasks: [String: MergeTaskRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.actorID = actorID
        self.pendingCreations = pendingCreations
        self.tasks = tasks
    }

    public static func empty(actorID: String) -> Self {
        Self(
            schemaVersion: currentSchemaVersion,
            actorID: actorID,
            pendingCreations: [:],
            tasks: [:]
        )
    }
}

public protocol MergeTaskCollectionPersisting {
    func collection(actorID: String) -> MergeTaskCollection
    func save(_ collection: MergeTaskCollection)
    func update(
        actorID: String,
        _ mutation: (inout MergeTaskCollection) -> Void
    )
    func remove(actorID: String)
}

struct MergeTaskCollectionEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let actorID: String
    var pendingCreations: [String: Data]
    var tasks: [String: Data]
    var quarantinedRecords: [String: Data]
}

public final class UserDefaultsMergeTaskStore: MergeTaskCollectionPersisting {
    private let defaults: UserDefaults
    private let keyPrefix: String
    private let legacy: any MergeSessionPersisting
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private let lock = NSRecursiveLock()

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "chorai.merge.tasks",
        legacy: any MergeSessionPersisting = UserDefaultsMergeSessionStore(),
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
        self.legacy = legacy
        self.notificationCenter = notificationCenter
        self.now = now
    }

    public func collection(actorID: String) -> MergeTaskCollection {
        lock.lock()
        defer { lock.unlock() }

        if let current = decodeCollection(actorID: actorID) {
            return current
        }
        guard let snapshot = legacy.snapshot(actorID: actorID) else {
            return .empty(actorID: actorID)
        }
        let migrated = migratedCollection(from: snapshot, now: now())
        save(migrated)
        guard decodeCollection(actorID: actorID) == migrated else {
            return migrated
        }
        legacy.remove(actorID: actorID)
        return migrated
    }

    public func save(_ collection: MergeTaskCollection) {
        lock.lock()
        defer { lock.unlock() }

        guard write(collection) else { return }
        postCollectionDidChange(actorID: collection.actorID)
    }

    public func update(
        actorID: String,
        _ mutation: (inout MergeTaskCollection) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        var current = collection(actorID: actorID)
        mutation(&current)
        guard write(current) else { return }
        postCollectionDidChange(actorID: actorID)
    }

    public func remove(actorID: String) {
        lock.lock()
        defer { lock.unlock() }

        defaults.removeObject(forKey: storageKey(actorID: actorID))
        postCollectionDidChange(actorID: actorID)
    }

    func storageKey(actorID: String) -> String {
        "\(keyPrefix).\(actorID)"
    }

    private func decodeCollection(actorID: String) -> MergeTaskCollection? {
        let key = storageKey(actorID: actorID)
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let envelope = try? JSONDecoder().decode(
            MergeTaskCollectionEnvelope.self,
            from: data
        ), envelope.schemaVersion == MergeTaskCollection.currentSchemaVersion,
           envelope.actorID == actorID
        else {
            defaults.removeObject(forKey: key)
            return nil
        }

        var repaired = envelope
        var pending: [String: MergeTaskRecord] = [:]
        var tasks: [String: MergeTaskRecord] = [:]
        var quarantined: [(String, String)] = []

        decodeRecords(
            repaired.pendingCreations,
            prefix: "pending",
            actorID: actorID,
            isPending: true,
            into: &pending,
            envelope: &repaired,
            quarantined: &quarantined
        )
        decodeRecords(
            repaired.tasks,
            prefix: "tasks",
            actorID: actorID,
            isPending: false,
            into: &tasks,
            envelope: &repaired,
            quarantined: &quarantined
        )

        if !quarantined.isEmpty, let repairedData = try? JSONEncoder().encode(repaired) {
            defaults.set(repairedData, forKey: key)
            for (_, recordKey) in quarantined {
                logQuarantine(actorID: actorID, recordKey: recordKey)
                notificationCenter.post(
                    name: .mergeTaskRecordDidQuarantine,
                    object: nil,
                    userInfo: ["actorID": actorID, "recordKey": recordKey]
                )
            }
            postCollectionDidChange(actorID: actorID)
        }

        return MergeTaskCollection(
            actorID: actorID,
            pendingCreations: pending,
            tasks: tasks
        )
    }

    private func decodeRecords(
        _ encodedRecords: [String: Data],
        prefix: String,
        actorID: String,
        isPending: Bool,
        into records: inout [String: MergeTaskRecord],
        envelope: inout MergeTaskCollectionEnvelope,
        quarantined: inout [(String, String)]
    ) {
        for (key, data) in encodedRecords {
            guard let record = try? JSONDecoder().decode(MergeTaskRecord.self, from: data),
                  isValid(record, key: key, actorID: actorID, isPending: isPending)
            else {
                let quarantinedKey = "\(prefix):\(key)"
                envelope.quarantinedRecords[quarantinedKey] = data
                if isPending {
                    envelope.pendingCreations.removeValue(forKey: key)
                } else {
                    envelope.tasks.removeValue(forKey: key)
                }
                quarantined.append((quarantinedKey, key))
                continue
            }
            records[key] = record
        }
    }

    private func migratedCollection(
        from snapshot: MergeSessionSnapshot,
        now: Date
    ) -> MergeTaskCollection {
        let record = MergeTaskRecord(
            operationID: snapshot.createRequest.idempotencyKey,
            snapshot: snapshot,
            createdAt: now,
            updatedAt: now,
            replacesJobID: nil
        )
        var collection = MergeTaskCollection.empty(actorID: snapshot.actorID)
        if let jobID = snapshot.jobID, !jobID.isEmpty {
            collection.tasks[jobID] = record
        } else {
            collection.pendingCreations[record.operationID] = record
        }
        return collection
    }

    private func write(_ collection: MergeTaskCollection) -> Bool {
        guard isValid(collection),
              let envelope = makeEnvelope(collection),
              let data = try? JSONEncoder().encode(envelope)
        else {
            return false
        }
        defaults.set(data, forKey: storageKey(actorID: collection.actorID))
        return true
    }

    private func makeEnvelope(
        _ collection: MergeTaskCollection
    ) -> MergeTaskCollectionEnvelope? {
        var pending: [String: Data] = [:]
        var tasks: [String: Data] = [:]
        for (key, record) in collection.pendingCreations {
            guard let data = try? JSONEncoder().encode(record) else { return nil }
            pending[key] = data
        }
        for (key, record) in collection.tasks {
            guard let data = try? JSONEncoder().encode(record) else { return nil }
            tasks[key] = data
        }
        return MergeTaskCollectionEnvelope(
            schemaVersion: collection.schemaVersion,
            actorID: collection.actorID,
            pendingCreations: pending,
            tasks: tasks,
            quarantinedRecords: retainedQuarantinedRecords(
                actorID: collection.actorID
            )
        )
    }

    private func retainedQuarantinedRecords(actorID: String) -> [String: Data] {
        guard let data = defaults.data(forKey: storageKey(actorID: actorID)),
              let envelope = try? JSONDecoder().decode(
                  MergeTaskCollectionEnvelope.self,
                  from: data
              ), envelope.schemaVersion == MergeTaskCollection.currentSchemaVersion,
                 envelope.actorID == actorID
        else {
            return [:]
        }
        return envelope.quarantinedRecords
    }

    private func isValid(_ collection: MergeTaskCollection) -> Bool {
        guard collection.schemaVersion == MergeTaskCollection.currentSchemaVersion,
              !collection.actorID.isEmpty
        else {
            return false
        }
        return collection.pendingCreations.allSatisfy {
            isValid($0.value, key: $0.key, actorID: collection.actorID, isPending: true)
        } && collection.tasks.allSatisfy {
            isValid($0.value, key: $0.key, actorID: collection.actorID, isPending: false)
        }
    }

    private func isValid(
        _ record: MergeTaskRecord,
        key: String,
        actorID: String,
        isPending: Bool
    ) -> Bool {
        let snapshot = record.snapshot
        let sourceAssetIDs = snapshot.createRequest.sources.map(\.assetID)
        guard !record.operationID.isEmpty,
              snapshot.schemaVersion == MergeSessionSnapshot.currentSchemaVersion,
              snapshot.actorID == actorID,
              !snapshot.anchorAssetID.isEmpty,
              (2...8).contains(sourceAssetIDs.count),
              !sourceAssetIDs.contains(where: \.isEmpty),
              Set(sourceAssetIDs).count == sourceAssetIDs.count
        else {
            return false
        }
        if isPending {
            return snapshot.jobID == nil && key == record.operationID
        }
        guard let jobID = snapshot.jobID, !jobID.isEmpty else { return false }
        return key == jobID
    }

    private func postCollectionDidChange(actorID: String) {
        notificationCenter.post(
            name: .mergeTaskCollectionDidChange,
            object: nil,
            userInfo: ["actorID": actorID]
        )
    }

    private func logQuarantine(actorID: String, recordKey: String) {
        NSLog("Merge task record quarantined actorID=%@ recordKey=%@", actorID, recordKey)
    }
}
