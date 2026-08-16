import Foundation

public final class MergeTaskSessionPersistence: MergeSessionPersisting {
    public let actorID: String
    public let operationID: String

    private let store: any MergeTaskCollectionPersisting
    private let now: () -> Date
    private var currentJobID: String?

    public init(
        actorID: String,
        operationID: String,
        initialJobID: String? = nil,
        store: any MergeTaskCollectionPersisting,
        now: @escaping () -> Date = Date.init
    ) {
        self.actorID = actorID
        self.operationID = operationID
        self.currentJobID = initialJobID
        self.store = store
        self.now = now
    }

    public func snapshot(actorID: String) -> MergeSessionSnapshot? {
        guard actorID == self.actorID else { return nil }
        let collection = store.collection(actorID: actorID)
        if let pending = collection.pendingCreations[operationID] {
            return pending.snapshot
        }
        if let currentJobID {
            return collection.tasks[currentJobID]?.snapshot
        }
        return nil
    }

    public func save(_ snapshot: MergeSessionSnapshot) {
        guard snapshot.actorID == actorID else { return }

        let savedAt = now()
        let canonicalJobID = snapshot.jobID?.nonEmpty
        store.update(actorID: actorID) { collection in
            let pending = collection.pendingCreations[operationID]
            let current = currentJobID.flatMap { collection.tasks[$0] }

            if let canonicalJobID {
                let existing = collection.tasks[canonicalJobID]
                let createdAt = pending?.createdAt
                    ?? existing?.createdAt
                    ?? current?.createdAt
                    ?? savedAt
                let replacesJobID = pending?.replacesJobID
                collection.pendingCreations[operationID] = nil
                if let replacesJobID {
                    collection.tasks[replacesJobID] = nil
                }
                collection.tasks[canonicalJobID] = MergeTaskRecord(
                    operationID: operationID,
                    snapshot: snapshot,
                    createdAt: createdAt,
                    updatedAt: savedAt,
                    replacesJobID: nil
                )
                currentJobID = canonicalJobID
                return
            }

            let createdAt = pending?.createdAt ?? current?.createdAt ?? savedAt
            collection.pendingCreations[operationID] = MergeTaskRecord(
                operationID: operationID,
                snapshot: snapshot,
                createdAt: createdAt,
                updatedAt: savedAt,
                replacesJobID: pending?.replacesJobID ?? currentJobID
            )
        }
    }

    public func remove(actorID: String) {
        guard actorID == self.actorID else { return }

        store.update(actorID: actorID) { collection in
            let pending = collection.pendingCreations.removeValue(
                forKey: operationID
            )
            if let replacesJobID = pending?.replacesJobID {
                collection.tasks[replacesJobID] = nil
            } else if let currentJobID {
                collection.tasks[currentJobID] = nil
            }
            currentJobID = nil
        }
    }

    public func resumeMetadata(actorID: String) -> MergeResumeMetadata? {
        guard let snapshot = snapshot(actorID: actorID) else { return nil }
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
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
