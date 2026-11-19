import XCTest
@testable import CoreFlow

@MainActor
final class MergeExecutionMeasurementTests: XCTestCase {
    func testSyntheticLongDocumentMeasuresWorkerAndRemainingSynchronousPersistence() async throws {
        let blocks: [[String: Any]] = (0..<1000).map {
            ["id": "blk_\($0)", "type": "paragraph", "content": [["type": "text", "text": "Synthetic paragraph \($0)"]]]
        }
        let input = try JSONSerialization.data(withJSONObject: ["schemaVersion": "card_doc.v1", "meta": [:], "blocks": blocks])
        let base = makeMergeArtifact()
        let artifact = MergeArtifact(artifactID: base.artifactID, jobID: base.jobID,
            capabilityID: base.capabilityID, outputKind: base.outputKind, document: base.document,
            fragments: base.fragments, metadata: base.metadata, latestRevision: base.latestRevision,
            latestHash: base.latestHash, documentJSON: input,
            presentationHash: base.presentationHash, presentation: base.presentation)
        let worker = MergeArtifactEditorWorker()
        let projection = try await worker.project(cardDocumentJSON: input, displayURLsByMediaReference: [:])
        let suite = "merge-measure-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = UserDefaultsMergeTaskStore(defaults: defaults, keyPrefix: "tasks",
            legacy: UserDefaultsMergeSessionStore(defaults: defaults, keyPrefix: "legacy"))
        var collection = MergeTaskCollection.empty(actorID: "actor_1")
        var record = makeMergeTaskRecord(jobID: "job_1", status: .artifactReady)
        record.snapshot.artifactDraft = MergeArtifactDraftSnapshot(baseRevision: 1, baseDocumentHash: "synthetic",
            documentJSON: input, tags: [], rate: 1, preservationManifest: projection.editable.preservationManifest,
            pendingSave: .init(idempotencyKey: "synthetic", baseRevision: 1, baseDocumentHash: "synthetic", documentJSON: input, tags: []))
        var cleanTimes: [Double] = [], projectTimes: [Double] = [], encodeTimes: [Double] = [], persistenceTimes: [Double] = [], directDecodeTimes: [Double] = []
        for index in 0..<25 {
            var started = ProcessInfo.processInfo.systemUptime
            _ = try await MergeArtifactEditorWorker().cleanDraft(from: artifact)
            let cleanTime = (ProcessInfo.processInfo.systemUptime - started) * 1000
            started = ProcessInfo.processInfo.systemUptime
            _ = try await worker.project(cardDocumentJSON: input, displayURLsByMediaReference: [:])
            let projectTime = (ProcessInfo.processInfo.systemUptime - started) * 1000
            started = ProcessInfo.processInfo.systemUptime
            _ = try await worker.prepareDraft(blockNoteJSON: projection.editable.blockNoteJSON,
                preserving: projection.editable.preservationManifest, displayURLsByMediaReference: [:])
            let encodeTime = (ProcessInfo.processInfo.systemUptime - started) * 1000
            record.updatedAt = Date(timeIntervalSince1970: Double(index))
            collection.tasks["job_1"] = record
            started = ProcessInfo.processInfo.systemUptime
            persistence.save(collection)
            let persistenceTime = (ProcessInfo.processInfo.systemUptime - started) * 1000
            started = ProcessInfo.processInfo.systemUptime
            _ = try MergeArtifactEditorCodec.decode(cardDocumentJSON: input)
            let decodeTime = (ProcessInfo.processInfo.systemUptime - started) * 1000
            if index >= 5 {
                cleanTimes.append(cleanTime); projectTimes.append(projectTime); encodeTimes.append(encodeTime)
                persistenceTimes.append(persistenceTime); directDecodeTimes.append(decodeTime)
            }
        }
        XCTAssertEqual(persistence.collection(actorID: "actor_1"), collection)
        for (name, samples) in [("canonical_clean_worker_cold", cleanTimes), ("project_cached_worker", projectTimes), ("prepare_draft", encodeTimes),
                                ("remaining_sync_persistence", persistenceTimes), ("baseline_direct_clean_decode", directDecodeTimes)] {
            let sorted = samples.sorted()
            print("EXECUTION_METRIC merge_1000_blocks_\(name) bytes=\(input.count) p50_ms=\(sorted[9]) p95_ms=\(sorted[18]) samples=20")
        }
    }
}
