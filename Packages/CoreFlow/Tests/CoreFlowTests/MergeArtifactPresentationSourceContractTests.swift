import Foundation
import XCTest

final class MergeArtifactPresentationSourceContractTests: XCTestCase {
    func testArtifactLifecycleUsesOneInPlaceEditorSurface() throws {
        let lifecycle = try source(
            at: "ArcNote/CoreFlow/MergeLifecycleViews.swift"
        )
        let surface = try source(
            at: "ArcNote/CoreFlow/MergeArtifactEditorSurface.swift"
        )

        XCTAssertTrue(lifecycle.contains("private var isArtifactPresentation"))
        XCTAssertTrue(lifecycle.contains("MergeArtifactEditorSurface("))
        XCTAssertFalse(lifecycle.contains("MergeArtifactReviewPanel("))
        XCTAssertTrue(surface.contains("BlockNoteCardEditor("))
        XCTAssertTrue(surface.contains("CardEditorTagRow("))
        XCTAssertTrue(surface.contains("CardLevelMaterial("))
        XCTAssertTrue(surface.contains(#"Text("New Insight")"#))
        XCTAssertTrue(surface.contains(#""Discard""#))
        XCTAssertTrue(surface.contains(#""Accept""#))
        XCTAssertTrue(surface.contains(#"accessibilityLabel("Back")"#))

        for identifier in [
            "screen.merge.artifact",
            "merge.artifact.back",
            "merge.artifact.level",
            "merge.artifact.editor",
            "merge.artifact.tags",
            "merge.artifact.add-tag",
            "merge.artifact.sync-state",
            "merge.artifact.discard",
            "merge.artifact.accept",
        ] {
            XCTAssertTrue(
                surface.contains(#""\#(identifier)""#),
                "Missing accessibility identifier \(identifier)"
            )
        }

        XCTAssertFalse(surface.contains(#"Text("Preview")"#))
        XCTAssertFalse(surface.contains(#"Text("Edit")"#))
        XCTAssertFalse(surface.contains("Picker("))
        XCTAssertFalse(surface.contains("MergeArtifactBlockView"))
        XCTAssertFalse(surface.contains("struct MergeArtifactTag"))
        XCTAssertFalse(surface.contains("Circle().fill"))
    }

    func testDraftControllerSnapshotsFlushesAndUsesExistingCommitPath() throws {
        let controller = try source(
            at: "ArcNote/CoreFlow/MergeArtifactDraftController.swift"
        )

        XCTAssertTrue(controller.contains("requestSnapshot()"))
        XCTAssertTrue(controller.contains("MergeArtifactEditorCodec"))
        XCTAssertTrue(controller.contains("codec.encode("))
        XCTAssertTrue(controller.contains("store.updateArtifactDraft("))
        XCTAssertTrue(controller.contains("store.updateArtifactTags("))
        XCTAssertTrue(controller.contains("try await store.flushArtifactDraft()"))
        XCTAssertTrue(controller.contains("store.commit()"))
        XCTAssertTrue(controller.contains("store.resolveArtifactConflict("))
        XCTAssertFalse(
            controller.contains("jobID"),
            "The draft controller must not own Merge job identity"
        )
    }

    func testArtifactSurfaceHasExactlyTwoMutationActions() throws {
        let surface = try source(
            at: "ArcNote/CoreFlow/MergeArtifactEditorSurface.swift"
        )

        XCTAssertEqual(
            surface.components(separatedBy: "MergeArtifactMutationButton(").count - 1,
            2
        )
        XCTAssertTrue(surface.contains("controller.discard()"))
        XCTAssertTrue(surface.contains("controller.accept()"))
        XCTAssertFalse(surface.contains(#"Text("Save")"#))
        XCTAssertFalse(surface.contains(#"Text("Close")"#))
    }

    func testAcceptFinalizesPendingTagBeforeSnapshotAndFlush() throws {
        let controller = try source(
            at: "ArcNote/CoreFlow/MergeArtifactDraftController.swift"
        )
        let acceptStart = try XCTUnwrap(
            controller.range(of: "func accept()")
        )
        let acceptEnd = try XCTUnwrap(
            controller.range(
                of: "func resolveConflict(",
                range: acceptStart.upperBound..<controller.endIndex
            )
        )
        let accept = controller[
            acceptStart.lowerBound..<acceptEnd.lowerBound
        ]
        let completeTag = try XCTUnwrap(accept.range(of: "completeTag()"))
        let snapshot = try XCTUnwrap(
            accept.range(of: "persistCurrentSnapshot()")
        )
        let flush = try XCTUnwrap(
            accept.range(of: "store.flushArtifactDraft()")
        )

        XCTAssertLessThan(completeTag.lowerBound, snapshot.lowerBound)
        XCTAssertLessThan(snapshot.lowerBound, flush.lowerBound)
    }

    func testMutationBoundaryLocksBodyAndConfirmsDiscard() throws {
        let surface = try source(
            at: "ArcNote/CoreFlow/MergeArtifactEditorSurface.swift"
        )
        let controller = try source(
            at: "ArcNote/CoreFlow/MergeArtifactDraftController.swift"
        )

        XCTAssertTrue(surface.contains(".allowsHitTesting(controller.canEdit)"))
        XCTAssertTrue(surface.contains(".confirmationDialog("))
        XCTAssertTrue(surface.contains(#"Button("Discard", role: .destructive)"#))
        XCTAssertTrue(surface.contains("controller.discard()"))
        let changeStart = try XCTUnwrap(
            controller.range(of: "fileprivate func documentDidChange(")
        )
        let changeEnd = try XCTUnwrap(
            controller.range(
                of: "private func persistCurrentSnapshot()",
                range: changeStart.upperBound..<controller.endIndex
            )
        )
        let documentChange = controller[
            changeStart.lowerBound..<changeEnd.lowerBound
        ]
        XCTAssertTrue(documentChange.contains("guard canEdit else { return }"))
    }

    private func source(at path: String) throws -> String {
        let url = Self.repositoryRoot.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("Missing production source: \(path)")
            return ""
        }
        return try String(
            contentsOf: url,
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
