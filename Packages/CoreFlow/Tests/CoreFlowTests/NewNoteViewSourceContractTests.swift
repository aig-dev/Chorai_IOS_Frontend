import Foundation
import XCTest

final class NewNoteViewSourceContractTests: XCTestCase {
    func testProductionRouteUsesStableBlockNoteSessionWithoutLegacyEditor() throws {
        let source = try Self.newNoteSource()

        XCTAssertTrue(source.contains("import BlockNoteEditor"))
        XCTAssertTrue(source.contains("struct CardEditorSeed: Identifiable"))
        XCTAssertTrue(source.contains("struct CardEditorSessionView: View"))
        XCTAssertTrue(source.contains("@StateObject private var bodyModel"))
        XCTAssertTrue(source.contains(".id(seed.id)"))
        XCTAssertFalse(source.contains(".id(editingStore.cardID"))
        XCTAssertTrue(source.contains(".navigationBarBackButtonHidden(true)"))
        XCTAssertTrue(source.contains(".interactiveDismissDisabled()"))
        XCTAssertFalse(source.contains(#"Text("Card editor")"#))
        XCTAssertTrue(source.contains(".font(.system(size: 17, weight: .semibold))"))

        for retired in [
            "import MarkupEditor",
            "MarkupDelegate",
            "MarkupEditorView",
            "topNavigationBar",
            ".frame(height: 200)",
            "autoSaveNote",
            "titleFromHTML",
            "extractTags",
        ] {
            XCTAssertFalse(
                source.contains(retired),
                "Retired editor path must be absent: \(retired)"
            )
        }
    }

    func testNewSeedIsCanonicalAndExistingSeedIsCreatedOnlyAfterHydration() throws {
        let source = try Self.newNoteSource()
        let newSeed = try XCTUnwrap(
            Self.functionBody(in: source, signature: "static func newNote()")
        )

        XCTAssertTrue(newSeed.contains("contentJSON: nil"))
        XCTAssertTrue(newSeed.contains("fallbackMarkdown: \"\""))
        XCTAssertTrue(newSeed.contains("revision: 0"))
        XCTAssertTrue(newSeed.contains("isNew: true"))
        XCTAssertTrue(newSeed.contains("initialFocus: true"))

        let hydration = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func hydrateExistingCard(")
        )
        let storeHydration = try XCTUnwrap(
            hydration.range(of: "editingStore.hydrate(")
        )
        let seedCreation = try XCTUnwrap(
            hydration.range(of: "editorSeed = CardEditorSeed(")
        )
        XCTAssertLessThan(storeHydration.lowerBound, seedCreation.lowerBound)
        XCTAssertTrue(hydration.contains("title: card.title"))
        XCTAssertTrue(hydration.contains("isNew: false"))
        XCTAssertTrue(hydration.contains("initialFocus: false"))
    }

    func testBackSavesOneExactSnapshotAndDismissesOnlyExactCleanCommit() throws {
        let source = try Self.newNoteSource()
        let back = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func handleBack()")
        )
        XCTAssertTrue(back.contains("bodyModel.compatibilityNotice != nil"))
        XCTAssertFalse(
            back.contains("!editingStore.isDirty"),
            "A possibly delayed bridge event must not bypass the exact snapshot"
        )
        XCTAssertTrue(back.contains("saveCurrentSnapshot(thenDismiss: true)"))

        let save = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func saveCurrentSnapshot(thenDismiss: Bool)"
            )
        )
        let snapshot = try XCTUnwrap(save.range(of: "applyCurrentSnapshot()"))
        let untouched = try XCTUnwrap(
            save.range(of: "isUntouchedNewSnapshot(snapshot)")
        )
        let persist = try XCTUnwrap(save.range(of: "editingStore.save()"))
        XCTAssertLessThan(snapshot.lowerBound, untouched.lowerBound)
        XCTAssertLessThan(untouched.lowerBound, persist.lowerBound)
        XCTAssertLessThan(snapshot.lowerBound, persist.lowerBound)
        XCTAssertTrue(
            save.contains("editingStore.lastCommittedBodyRevision == snapshot.revision")
        )
        XCTAssertTrue(save.contains("editingStore.bodyRevision == snapshot.revision"))
        XCTAssertTrue(save.contains("bodyModel.revision == snapshot.revision"))
        XCTAssertTrue(save.contains("!editingStore.isDirty"))
        XCTAssertFalse(save.contains("updateDraft("))

        let untouchedCheck = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func isUntouchedNewSnapshot(_ snapshot: BlockNoteSnapshot)"
            )
        )
        XCTAssertTrue(
            untouchedCheck.contains("snapshot.revision == seed.revision"),
            "Image-only documents can have empty fallback Markdown; only the initial revision is untouched"
        )

        let apply = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func applyCurrentSnapshot()")
        )
        let blur = try XCTUnwrap(apply.range(of: "bodyModel.dismissKeyboard()"))
        let request = try XCTUnwrap(
            apply.range(of: "bodyModel.requestSnapshot()")
        )
        let storeApply = try XCTUnwrap(
            apply.range(of: "editingStore.applyBodyRevision(")
        )
        XCTAssertLessThan(blur.lowerBound, request.lowerBound)
        XCTAssertLessThan(request.lowerBound, storeApply.lowerBound)
        XCTAssertFalse(apply.contains("updateDraft("))
    }

    func testFatalBridgeFailureRequiresExplicitDiscardConfirmationToClose() throws {
        let source = try Self.newNoteSource()
        let back = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func handleBack()")
        )

        XCTAssertTrue(back.contains("bodyModel.bridgeFailureNotice != nil"))
        XCTAssertTrue(back.contains("showCloseWithoutSavingConfirmation = true"))
        XCTAssertTrue(source.contains(#""Close without saving?""#))
        XCTAssertTrue(source.contains(#"Button("Keep Editing", role: .cancel)"#))
        XCTAssertTrue(source.contains(#"Button("Close", role: .destructive"#))
        XCTAssertTrue(source.contains(#".accessibilityIdentifier("cardEditorDiscardAndClose")"#))
    }

    func testMetadataPreservesHiddenTitleAndNeverExtractsBodyHashtags() throws {
        let source = try Self.newNoteSource()
        let metadata = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func updateMetadata(")
        )

        XCTAssertTrue(metadata.contains("title: editingStore.draft.title"))
        XCTAssertTrue(metadata.contains("content: editingStore.draft.content"))
        XCTAssertTrue(metadata.contains("contentJSON: editingStore.draft.contentJSON"))
        XCTAssertTrue(metadata.contains("editorAtmosphere: editingStore.draft.editorAtmosphere"))
        XCTAssertFalse(source.contains("prefix(50)"))
        XCTAssertFalse(source.contains("#(["))
        XCTAssertFalse(source.contains("replacingOccurrences(of: \"#"))
    }

    func testOntologyLinkPersistsSnapshotBeforeSelectionAndMutatesOnlyAfterReturn() throws {
        let source = try Self.newNoteSource()
        let add = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func addOntologyLink()")
        )
        let snapshot = try XCTUnwrap(
            add.range(of: "applyCurrentSnapshot()")
        )
        let persist = try XCTUnwrap(
            add.range(of: "editingStore.ensurePersisted()")
        )
        let picker = try XCTUnwrap(
            add.range(of: "mode: .selectionOnly")
        )
        XCTAssertLessThan(snapshot.lowerBound, persist.lowerBound)
        XCTAssertLessThan(persist.lowerBound, picker.lowerBound)
        XCTAssertFalse(add.contains("createLink("))

        let selection = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func handleSelectedLink(")
        )
        XCTAssertTrue(selection.contains("guard let sourceID = pendingOntologyLinkSourceID"))
        XCTAssertTrue(selection.contains("editingStore.cardID == sourceID"))
        XCTAssertTrue(selection.contains("editingStore.createLink(link)"))
        XCTAssertTrue(selection.contains("guard didCreate else"))
        XCTAssertFalse(source.contains("adoptAlreadyCreatedLink"))
        XCTAssertFalse(selection.contains("replaceLinks("))
        XCTAssertTrue(source.contains("canRemove: link.sourceCardID == cardID"))
    }

    func testCardLinkBridgeRequestRoutesToExistingOntologyLinkFlow() throws {
        let source = try Self.newNoteSource()
        let router = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func requestCardLink()")
        )
        XCTAssertTrue(router.contains("onRequestCardLink()"))
        XCTAssertFalse(router.contains("onRequestInlineLink()"))

        XCTAssertTrue(
            source.contains("onRequestCardLink: router.requestCardLink")
        )
        let configuration = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func configureNativeActions()"
            )
        )
        XCTAssertTrue(
            configuration.contains("nativeActionRouter.onRequestCardLink = {")
        )
        XCTAssertTrue(configuration.contains("addOntologyLink()"))
    }

    func testBackgroundStagesWithoutSavingAndInlineImageInsertsOnlyAfterUpload() throws {
        let source = try Self.newNoteSource()
        let background = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func handleSelectedBackgroundPhoto("
            )
        )
        XCTAssertTrue(background.contains("editingStore.stageBackground("))
        XCTAssertFalse(background.contains("editingStore.save()"))
        XCTAssertFalse(background.contains("insertImage("))

        let inlineImage = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func handleSelectedInlineImage("
            )
        )
        let upload = try XCTUnwrap(
            inlineImage.range(of: "editingStore.uploadInlineImage(")
        )
        let insert = try XCTUnwrap(
            inlineImage.range(of: "bodyModel.insertImage(")
        )
        XCTAssertLessThan(upload.lowerBound, insert.lowerBound)
        XCTAssertFalse(inlineImage[..<upload.lowerBound].contains("insertImage("))
    }

    func testNativeInlineLinkAndSeparatePhotoPickersStayOutsideBridge() throws {
        let source = try Self.newNoteSource()

        XCTAssertTrue(source.contains("CardEditorInlineLinkSheet {"))
        XCTAssertTrue(source.contains("bodyModel.insertLink("))
        XCTAssertTrue(source.contains("selectedBackgroundPhoto"))
        XCTAssertTrue(source.contains("selectedInlineImagePhoto"))
        XCTAssertTrue(source.contains("showBackgroundPicker"))
        XCTAssertTrue(source.contains("showInlineImagePicker"))
        XCTAssertFalse(source.contains("backgroundMediaRef:" + " bodyModel"))
    }

    func testRetryDispatchKeepsSaveAndCanonicalMutationFailuresDistinct() throws {
        let source = try Self.newNoteSource()
        XCTAssertTrue(source.contains("enum CardEditorRetryAction"))
        XCTAssertTrue(source.contains("onSave: retryHandler"))
        XCTAssertTrue(source.contains("guard retryAction != nil else { return nil }"))

        let retry = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func retryCurrentFailure()")
        )
        XCTAssertTrue(retry.contains("case let .save(thenDismiss)"))
        XCTAssertTrue(retry.contains("saveCurrentSnapshot(thenDismiss: thenDismiss)"))
        XCTAssertTrue(retry.contains("case .store"))
        XCTAssertTrue(retry.contains("editingStore.retry()"))

        let recovery = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func recoverFailedDraftOperationIfNeeded()"
            )
        )
        let reconcileRelationshipFailure = try XCTUnwrap(
            recovery.range(
                of: "editingStore.reconcileFailedRelationshipMutation()"
            )
        )
        XCTAssertFalse(source.contains("discardFailedRelationshipMutation"))
        XCTAssertTrue(recovery.contains("case .creatingLink, .deletingLink"))
        XCTAssertTrue(
            recovery.contains(
                "return await editingStore.reconcileFailedRelationshipMutation()"
            )
        )
        XCTAssertTrue(recovery.contains("editingStore.failureStage != nil"))
        XCTAssertFalse(
            recovery.contains("case .creatingCard, .updatingCard"),
            "Background and link failures also need their frozen retry operation"
        )
        let exactRetry = try XCTUnwrap(
            recovery.range(of: "editingStore.retry()")
        )
        let latestSave = try XCTUnwrap(
            recovery.range(of: "editingStore.save()")
        )
        XCTAssertLessThan(
            reconcileRelationshipFailure.lowerBound,
            exactRetry.lowerBound,
            "Back and prerequisite actions must canonicalize failed relationships before retrying required draft or background writes"
        )
        XCTAssertLessThan(exactRetry.lowerBound, latestSave.lowerBound)
        XCTAssertTrue(recovery.contains("editingStore.failureStage == nil"))
        XCTAssertTrue(recovery.contains("editingStore.cardID != nil"))
        XCTAssertTrue(recovery.contains("editingStore.isDirty"))

        let save = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func saveCurrentSnapshot(thenDismiss: Bool)"
            )
        )
        XCTAssertLessThan(
            try XCTUnwrap(
                save.range(of: "recoverFailedDraftOperationIfNeeded()")
            ).lowerBound,
            try XCTUnwrap(save.range(of: "editingStore.save()")).lowerBound
        )

        for signature in ["func addOntologyLink()", "func openCardActions()"] {
            let action = try XCTUnwrap(
                Self.functionBody(in: source, signature: signature)
            )
            XCTAssertLessThan(
                try XCTUnwrap(
                    action.range(of: "recoverFailedDraftOperationIfNeeded()")
                ).lowerBound,
                try XCTUnwrap(
                    action.range(of: "editingStore.ensurePersisted()")
                ).lowerBound
            )
        }

        let selection = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func handleSelectedLink(")
        )
        XCTAssertTrue(selection.contains("retryAction = .store"))

        let backgroundRemoval = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func removeBackground()")
        )
        XCTAssertTrue(backgroundRemoval.contains("retryAction = .store"))
    }

    func testNativeCardActionsPersistExactSnapshotWithoutLegacyMutationBypasses() throws {
        let source = try Self.newNoteSource()
        XCTAssertTrue(source.contains("saveActionTitle: \"Retry\""))
        XCTAssertTrue(source.contains("onOpenCardActions: cardActionsHandler"))
        XCTAssertTrue(source.contains(".confirmationDialog("))
        XCTAssertFalse(source.contains(".popupMenu("))
        XCTAssertFalse(source.contains("layout: .grid3x3"))

        let actions = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func openCardActions()")
        )
        let snapshot = try XCTUnwrap(
            actions.range(of: "applyCurrentSnapshot()")
        )
        let persist = try XCTUnwrap(
            actions.range(of: "editingStore.ensurePersisted()")
        )
        let notify = try XCTUnwrap(
            actions[persist.upperBound...].range(of: "notifyCreationIfNeeded()")
        )
        let present = try XCTUnwrap(
            actions.range(of: "showCardActions = true")
        )
        XCTAssertLessThan(snapshot.lowerBound, persist.lowerBound)
        XCTAssertLessThan(persist.lowerBound, notify.lowerBound)
        XCTAssertLessThan(notify.lowerBound, present.lowerBound)

        XCTAssertTrue(source.contains("func togglePinnedCard()"))
        XCTAssertTrue(source.contains("NetworkManager.shared.pinCard(cardId: cardID)"))
        XCTAssertTrue(source.contains("NetworkManager.shared.unpinCard(cardId: cardID)"))
        XCTAssertTrue(source.contains("func removeCanonicalCard()"))
        XCTAssertTrue(source.contains("NetworkManager.shared.deleteCard(id: cardID)"))
        for notification in [
            "ShowCardShare",
            "NavigateToSpark",
            "NavigateToMerge",
            "NavigateToRoot",
        ] {
            XCTAssertTrue(source.contains(#"postCardAction("\#(notification)")"#))
        }
        XCTAssertTrue(source.contains(#"userInfo: ["cardId": cardID]"#))
    }

    func testAppProjectRetiresLegacyMarkupEditorDependency() throws {
        let project = try String(
            contentsOf: Self.repositoryRoot
                .appendingPathComponent("ArcNote.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertFalse(project.contains("MarkupEditor"))
        XCTAssertFalse(project.contains("Packages/MarkdownEditor"))
    }

    private static func newNoteSource() throws -> String {
        try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("ArcNote/NewNoteView.swift"),
            encoding: .utf8
        )
    }

    private static func functionBody(
        in source: String,
        signature: String
    ) -> Substring? {
        guard let signatureRange = source.range(of: signature),
              let openingBrace = source[signatureRange.lowerBound...]
                .firstIndex(of: "{") else {
            return nil
        }

        var depth = 0
        var index = openingBrace
        var isInString = false
        var isEscaped = false
        while index < source.endIndex {
            let character = source[index]
            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
            } else if character == "\"" {
                isInString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return source[openingBrace...index]
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
