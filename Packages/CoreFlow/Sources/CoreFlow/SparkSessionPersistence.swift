import Foundation

public protocol SparkSessionPersisting {
    func snapshot(
        actorID: String,
        rootSourceAssetID: String
    ) -> SparkSessionSnapshot?

    func save(_ snapshot: SparkSessionSnapshot)

    func remove(
        actorID: String,
        rootSourceAssetID: String
    )
}

public final class UserDefaultsSparkSessionStore: SparkSessionPersisting {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "chorai.spark.session"
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func snapshot(
        actorID: String,
        rootSourceAssetID: String
    ) -> SparkSessionSnapshot? {
        let storageKey = key(
            actorID: actorID,
            rootSourceAssetID: rootSourceAssetID
        )
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(
                SparkSessionSnapshot.self,
                from: data
            )
        } catch {
            defaults.removeObject(forKey: storageKey)
            return nil
        }
    }

    public func save(_ snapshot: SparkSessionSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(
            data,
            forKey: key(
                actorID: snapshot.actorID,
                rootSourceAssetID: snapshot.rootSourceAssetID
            )
        )
    }

    public func remove(
        actorID: String,
        rootSourceAssetID: String
    ) {
        defaults.removeObject(
            forKey: key(
                actorID: actorID,
                rootSourceAssetID: rootSourceAssetID
            )
        )
    }

    private func key(
        actorID: String,
        rootSourceAssetID: String
    ) -> String {
        "\(keyPrefix).\(actorID).\(rootSourceAssetID)"
    }
}
