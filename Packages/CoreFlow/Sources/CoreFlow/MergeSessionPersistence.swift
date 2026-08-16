import Foundation

public struct MergeSessionSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let actorID: String
    public let anchorAssetID: String
    public let anchorPreview: String
    public var createRequest: MergeCreateRequest
    public var selectedCapability: String?
    public var jobID: String?
    public var lastStatus: MergeJobStatus?
    public var artifactID: String?
    public var commitRequest: MergeCommitRequest?
    public var committedAssetID: String?

    public init(
        schemaVersion: Int = MergeSessionSnapshot.currentSchemaVersion,
        actorID: String,
        anchorAssetID: String,
        anchorPreview: String,
        createRequest: MergeCreateRequest,
        selectedCapability: String?,
        jobID: String?,
        lastStatus: MergeJobStatus?,
        artifactID: String?,
        commitRequest: MergeCommitRequest?,
        committedAssetID: String?
    ) {
        self.schemaVersion = schemaVersion
        self.actorID = actorID
        self.anchorAssetID = anchorAssetID
        self.anchorPreview = anchorPreview
        self.createRequest = createRequest
        self.selectedCapability = selectedCapability
        self.jobID = jobID
        self.lastStatus = lastStatus
        self.artifactID = artifactID
        self.commitRequest = commitRequest
        self.committedAssetID = committedAssetID
    }
}

public struct MergeResumeMetadata: Equatable, Sendable {
    public let actorID: String
    public let anchorAssetID: String
    public let anchorPreview: String
    public let sourceCount: Int
    public let jobID: String?
    public let status: MergeJobStatus?
    public let committedAssetID: String?

    public init(
        actorID: String,
        anchorAssetID: String,
        anchorPreview: String,
        sourceCount: Int,
        jobID: String?,
        status: MergeJobStatus?,
        committedAssetID: String?
    ) {
        self.actorID = actorID
        self.anchorAssetID = anchorAssetID
        self.anchorPreview = anchorPreview
        self.sourceCount = sourceCount
        self.jobID = jobID
        self.status = status
        self.committedAssetID = committedAssetID
    }
}

public protocol MergeSessionPersisting {
    func snapshot(actorID: String) -> MergeSessionSnapshot?
    func save(_ snapshot: MergeSessionSnapshot)
    func remove(actorID: String)
    func resumeMetadata(actorID: String) -> MergeResumeMetadata?
}

public extension Notification.Name {
    static let mergeSessionDidChange = Notification.Name(
        "CoreFlow.MergeSessionDidChange"
    )
    static let mergeTaskCollectionDidChange = Notification.Name(
        "CoreFlow.MergeTaskCollectionDidChange"
    )
    static let mergeTaskRecordDidQuarantine = Notification.Name(
        "CoreFlow.MergeTaskRecordDidQuarantine"
    )
}

public final class UserDefaultsMergeSessionStore: MergeSessionPersisting {
    private let defaults: UserDefaults
    private let keyPrefix: String
    private let notificationCenter: NotificationCenter

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "chorai.merge.session",
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
        self.notificationCenter = notificationCenter
    }

    public func snapshot(actorID: String) -> MergeSessionSnapshot? {
        let storageKey = key(actorID: actorID)
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }

        do {
            let value = try JSONDecoder().decode(
                MergeSessionSnapshot.self,
                from: data
            )
            guard
                value.schemaVersion == MergeSessionSnapshot.currentSchemaVersion,
                value.actorID == actorID,
                !value.anchorAssetID.isEmpty,
                value.createRequest.sources.count >= 2
            else {
                defaults.removeObject(forKey: storageKey)
                return nil
            }
            return value
        } catch {
            defaults.removeObject(forKey: storageKey)
            return nil
        }
    }

    public func save(_ snapshot: MergeSessionSnapshot) {
        guard
            snapshot.schemaVersion == MergeSessionSnapshot.currentSchemaVersion,
            !snapshot.actorID.isEmpty,
            let data = try? JSONEncoder().encode(snapshot)
        else {
            return
        }
        defaults.set(data, forKey: key(actorID: snapshot.actorID))
        notificationCenter.post(
            name: .mergeSessionDidChange,
            object: nil,
            userInfo: ["actorID": snapshot.actorID]
        )
    }

    public func remove(actorID: String) {
        defaults.removeObject(forKey: key(actorID: actorID))
        notificationCenter.post(
            name: .mergeSessionDidChange,
            object: nil,
            userInfo: ["actorID": actorID]
        )
    }

    public func resumeMetadata(actorID: String) -> MergeResumeMetadata? {
        guard let snapshot = snapshot(actorID: actorID) else {
            return nil
        }
        return MergeResumeMetadata(
            actorID: snapshot.actorID,
            anchorAssetID: snapshot.anchorAssetID,
            anchorPreview: snapshot.anchorPreview,
            sourceCount: snapshot.createRequest.sources.count,
            jobID: snapshot.jobID,
            status: snapshot.lastStatus,
            committedAssetID: snapshot.committedAssetID
        )
    }

    private func key(actorID: String) -> String {
        "\(keyPrefix).\(actorID)"
    }
}
