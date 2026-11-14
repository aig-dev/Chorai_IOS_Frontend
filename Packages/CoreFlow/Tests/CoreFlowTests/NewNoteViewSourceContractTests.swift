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
            Self.functionBody(in: source, signature: "func loadExistingCard()")
        )
        let storeHydration = try XCTUnwrap(
            hydration.range(of: "editingStore.hydrate(")
        )
        let seedCreation = try XCTUnwrap(
            hydration.range(of: "editorSeed = CardEditorSeed(")
        )
        XCTAssertLessThan(storeHydration.lowerBound, seedCreation.lowerBound)
        XCTAssertTrue(hydration.contains("title: note.body.title"))
        XCTAssertTrue(
            hydration.contains("document: BlockNoteInitialDocument.existingCard("),
            "Existing cards must select the lossless runtime profile from their document shape"
        )
        XCTAssertTrue(hydration.contains("contentJSON: note.body.contentJSON"))
        XCTAssertTrue(hydration.contains("fallbackMarkdown: note.body.content"))
        XCTAssertTrue(hydration.contains("isNew: false"))
        XCTAssertTrue(hydration.contains("initialFocus: false"))
    }

    func testLeadingSaveStaysOpenAndBackChecksTheLatestLocalCommit() throws {
        let source = try Self.newNoteSource()
        let leading = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func handleLeadingControl()")
        )
        XCTAssertTrue(leading.contains("case .save, .retry:"))
        XCTAssertTrue(leading.contains("saveCurrentSnapshot()"))
        XCTAssertTrue(leading.contains("case .back:"))
        XCTAssertTrue(leading.contains("verifyCurrentSnapshotAndDismiss()"))
        XCTAssertFalse(leading.contains("showCloudVersionConfirmation"))

        let save = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func saveCurrentSnapshot()")
        )
        XCTAssertTrue(save.contains("completeTagEntry()"))
        XCTAssertTrue(save.contains("applyCurrentSnapshot()"))
        XCTAssertTrue(save.contains("editingStore.save()"))
        XCTAssertTrue(save.contains("classifyCommit("))
        XCTAssertFalse(save.contains("dismiss()"))
        XCTAssertFalse(save.contains("thenDismiss"))

        let close = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func verifyCurrentSnapshotAndDismiss()"
            )
        )
        XCTAssertTrue(close.contains("completeTagEntry()"))
        XCTAssertTrue(close.contains("applyCurrentSnapshot()"))
        XCTAssertTrue(close.contains("isUntouchedNewSnapshot(snapshot)"))
        XCTAssertTrue(Self.containsInOrder([
            "await persistLocalDraft()",
            "snapshotMatchesCommittedBaseline(snapshot)",
            "dismiss()",
        ], in: String(close)))
    }

    func testLeadingStateUsesMeaningfulDraftAndPendingInlineTag() throws {
        let source = try Self.newNoteSource()
        XCTAssertTrue(source.contains("var hasPendingInlineTagCandidate: Bool"))
        XCTAssertTrue(source.contains("CardEditingTag.appending("))
        XCTAssertTrue(source.contains("var hasPendingCommit: Bool"))
        XCTAssertTrue(source.contains("editingStore.cardID != nil"))
        XCTAssertTrue(source.contains("editingStore.isDirty"))
        XCTAssertTrue(source.contains("isUntouchedNewDraft"))
        XCTAssertTrue(source.contains("backgroundIntent == .unchanged"))
        XCTAssertFalse(source.contains("@State private var hasUnsavedChanges"))
    }

    func testEmptyStructuredNewNoteDoesNotBecomePendingFromRevisionAlone() throws {
        let source = try Self.newNoteSource()
        let untouchedDraft = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "var isUntouchedNewDraft: Bool"
            )
        )
        XCTAssertTrue(
            untouchedDraft.contains("!editingStore.draft.hasMeaningfulContent")
        )
        XCTAssertFalse(untouchedDraft.contains("bodyRevision == seed.revision"))

        let pendingCommit = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "var hasPendingCommit: Bool"
            )
        )
        XCTAssertTrue(
            pendingCommit.contains(
                "if editingStore.cardID == nil, isUntouchedNewDraft { return false }"
            )
        )

        let untouchedSnapshot = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func isUntouchedNewSnapshot("
            )
        )
        XCTAssertTrue(untouchedSnapshot.contains("CardEditingDraft("))
        XCTAssertTrue(
            untouchedSnapshot.contains("!snapshotDraft.hasMeaningfulContent")
        )
        XCTAssertFalse(
            untouchedSnapshot.contains("snapshot.revision == seed.revision")
        )
    }

    func testFatalBridgeFailureRequiresExplicitDiscardConfirmationToClose() throws {
        let source = try Self.newNoteSource()
        let leading = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func handleLeadingControl()")
        )

        XCTAssertTrue(leading.contains("case .bridgeFailed:"))
        XCTAssertTrue(
            leading.contains("showCloseWithoutSavingConfirmation = true")
        )
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

    func testTagEntryIsSessionOwnedAndNeverUsesAnAlert() throws {
        let source = try Self.newNoteSource()

        XCTAssertTrue(source.contains("@State private var isAddingTag = false"))
        XCTAssertTrue(source.contains("@State private var tagInput = \"\""))
        XCTAssertTrue(source.contains("isAddingTag: isAddingTag"))
        XCTAssertTrue(source.contains("tagInput: $tagInput"))
        XCTAssertTrue(source.contains("onBeginTag: beginTagEntry"))
        XCTAssertTrue(source.contains("onCompleteTag: completeTagEntry"))
        XCTAssertTrue(source.contains("CardEditingTag.appending("))
        XCTAssertFalse(source.contains(".alert(\"Add Tag\""))
        XCTAssertFalse(source.contains("showTagEditor"))
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
        XCTAssertTrue(
            source.contains("canRemove: true"),
            "Every canonical related-note edge should expose inline unlink"
        )
        let remove = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func removeOntologyLink(_ item: CardEditorLinkItem)"
            )
        )
        XCTAssertTrue(remove.contains("cardID == item.sourceCardID"))
        XCTAssertTrue(remove.contains("|| cardID == item.targetCardID"))
        XCTAssertTrue(remove.contains("editingStore.deleteLink(link)"))
        XCTAssertFalse(remove.contains("links.remove"))
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

    func testBackgroundStagesWithoutSaving() throws {
        let source = try Self.newNoteSource()
        let privacy = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func togglePrivacy()")
        )
        XCTAssertTrue(
            privacy.contains(
                "NetworkManager.shared.updateCardVisibility(cardId: serverID, isPublic: value)"
            )
        )
        XCTAssertFalse(privacy.contains("editingStore.save()"))
        XCTAssertFalse(privacy.contains("editingStore.ensurePersisted()"))

        let background = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func handleSelectedBackgroundPhoto("
            )
        )
        XCTAssertTrue(background.contains("editingStore.stageBackground("))
        XCTAssertFalse(background.contains("editingStore.save()"))
        XCTAssertFalse(background.contains("insertImage("))
    }

    func testInlineImagePhotoAndCameraShareOneGuardedUploadThenInsertPipeline() throws {
        let source = try Self.newNoteSource()

        let photo = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func handleSelectedInlineImagePhoto("
            )
        )
        XCTAssertTrue(photo.contains("beginInlineImageProcessing"))
        XCTAssertTrue(photo.contains("cardEditingImage("))

        let camera = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func handleCapturedInlineImage("
            )
        )
        XCTAssertTrue(camera.contains("beginInlineImageProcessing"))
        XCTAssertTrue(camera.contains("capturedCardEditingImage("))

        let inlineImage = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func beginInlineImageProcessing("
            )
        )
        XCTAssertTrue(
            inlineImage.contains(
                "guard !isProcessingInlineImage else { return }"
            )
        )
        XCTAssertTrue(inlineImage.contains("isProcessingInlineImage = true"))
        XCTAssertTrue(
            inlineImage.contains("defer { isProcessingInlineImage = false }")
        )
        let upload = try XCTUnwrap(
            inlineImage.range(of: "editingStore.uploadInlineImage(")
        )
        let insert = try XCTUnwrap(
            inlineImage.range(of: "bodyModel.insertImage(")
        )
        XCTAssertLessThan(upload.lowerBound, insert.lowerBound)
        XCTAssertFalse(inlineImage[..<upload.lowerBound].contains("insertImage("))
        XCTAssertTrue(
            inlineImage.contains(
                "Couldn't insert that image. Your draft is unchanged."
            )
        )

        let cameraImage = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func capturedCardEditingImage("
            )
        )
        XCTAssertTrue(cameraImage.contains("jpegData(compressionQuality: 0.9)"))
        XCTAssertTrue(cameraImage.contains("filename: \"inline-camera.jpg\""))
        XCTAssertTrue(cameraImage.contains("mimeType: \"image/jpeg\""))
    }

    func testNativeInlineLinkAndSeparateImageSourceRoutesStayOutsideBridge() throws {
        let source = try Self.newNoteSource()

        XCTAssertTrue(source.contains("CardEditorInlineLinkSheet {"))
        XCTAssertTrue(source.contains("bodyModel.insertLink("))
        XCTAssertTrue(source.contains("selectedBackgroundPhoto"))
        XCTAssertTrue(source.contains("selectedInlineImagePhoto"))
        XCTAssertTrue(source.contains("showBackgroundPicker"))
        XCTAssertTrue(source.contains("showInlineImageSourceDialog"))
        XCTAssertTrue(source.contains("showInlineImagePhotoPicker"))
        XCTAssertTrue(source.contains("showInlineImageCamera"))
        XCTAssertTrue(source.contains("showCameraSettingsAlert"))
        XCTAssertTrue(source.contains("isProcessingInlineImage"))
        XCTAssertTrue(source.contains(".cardEditorInlineImageSourceDialog("))
        XCTAssertTrue(
            source.contains(
                ".fullScreenCover(isPresented: $showInlineImageCamera)"
            )
        )
        XCTAssertFalse(source.contains("@State private var showInlineImagePicker"))
        XCTAssertFalse(source.contains("backgroundMediaRef:" + " bodyModel"))
    }

    func testInlineImageCameraUsesNativePermissionFlowAndDeclaresPrivacyReasons() throws {
        let source = try Self.newNoteSource()
        XCTAssertTrue(source.contains("import AVFoundation"))
        XCTAssertTrue(source.contains("import UIKit"))
        XCTAssertTrue(
            source.contains(
                "UIImagePickerController.isSourceTypeAvailable(.camera)"
            )
        )

        let request = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func requestInlineImageCamera()"
            )
        )
        XCTAssertTrue(
            request.contains(
                "AVCaptureDevice.authorizationStatus(for: .video)"
            )
        )
        XCTAssertTrue(request.contains("AVCaptureDevice.requestAccess(for: .video)"))
        XCTAssertTrue(request.contains("case .authorized"))
        XCTAssertTrue(request.contains("case .notDetermined"))
        XCTAssertTrue(request.contains("case .denied, .restricted"))
        XCTAssertTrue(
            request.contains("Camera isn't available on this device.")
        )

        let settings = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func openCameraSettings()"
            )
        )
        XCTAssertTrue(settings.contains("UIApplication.openSettingsURLString"))
        XCTAssertTrue(settings.contains("UIApplication.shared.open("))

        let infoData = try Data(
            contentsOf: Self.repositoryRoot
                .appendingPathComponent("ArcNote/Info.plist")
        )
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: infoData,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        XCTAssertEqual(
            info["NSCameraUsageDescription"] as? String,
            "Chorai uses your camera when you choose to take a photo for a note."
        )
        XCTAssertEqual(
            info["NSPhotoLibraryUsageDescription"] as? String,
            "Chorai uses your photo library when you choose profile and note images."
        )
    }

    func testOnlyCommitFailureOwnsTheLeadingRetryState() throws {
        let source = try Self.newNoteSource()
        let save = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func saveCurrentSnapshot()")
        )

        XCTAssertTrue(source.contains("@State private var hasSaveFailure = false"))
        XCTAssertTrue(save.contains("hasSaveFailure = true"))
        XCTAssertFalse(source.contains("CardEditorRetryAction"))
        XCTAssertFalse(source.contains("retryCurrentFailure"))

        for signature in [
            "func addOntologyLink()",
            "func handleSelectedLink(",
            "func performPersistedCardAction(",
        ] {
            let action = try XCTUnwrap(
                Self.functionBody(in: source, signature: signature)
            )
            XCTAssertFalse(
                action.contains("hasSaveFailure = true"),
                "Contextual action failures must be retried from their origin: \(signature)"
            )
        }
    }

    func testModalEditorActionsFinishInlineTagEntryFirst() throws {
        let source = try Self.newNoteSource()
        for signature in [
            "func openCardActions()",
            "func presentInlineImageSourceOptions()",
            "func presentInlineLinkSheet()",
        ] {
            let action = try XCTUnwrap(
                Self.functionBody(in: source, signature: signature)
            )
            XCTAssertTrue(
                action.contains("completeTagEntry()"),
                "Modal action must finish inline tag entry: \(signature)"
            )
        }
    }

    func testSaveBindsSnapshotBaselineBeforeFrozenRecoveryAndPersistence() throws {
        let source = try Self.newNoteSource()
        let save = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func saveCurrentSnapshot()")
        )
        let snapshot = try XCTUnwrap(save.range(of: "applyCurrentSnapshot()"))
        let baseline = try XCTUnwrap(
            save.range(of: "let baseline = try commitBaseline(matching: snapshot)")
        )
        let recovery = try XCTUnwrap(
            save.range(of: "recoverFrozenFailedOperationIfNeeded()")
        )
        let exactCheck = try XCTUnwrap(
            save.range(of: "!commitBaselineMatchesCurrent(baseline)")
        )
        let persist = try XCTUnwrap(save.range(of: "editingStore.save()"))

        XCTAssertLessThan(snapshot.lowerBound, baseline.lowerBound)
        XCTAssertLessThan(baseline.lowerBound, recovery.lowerBound)
        XCTAssertLessThan(recovery.lowerBound, exactCheck.lowerBound)
        XCTAssertLessThan(exactCheck.lowerBound, persist.lowerBound)
        XCTAssertEqual(
            Self.occurrenceCount(
                "await ",
                in: String(save[exactCheck.lowerBound..<persist.lowerBound])
            ),
            1,
            "Only the bound save call may suspend after the final exact check"
        )
        XCTAssertTrue(source.contains("struct CardEditorCommitBaseline"))
        XCTAssertTrue(source.contains("let draft: CardEditingDraft"))
        XCTAssertTrue(source.contains("let bodyRevision: Int"))
        XCTAssertTrue(source.contains("let editorRevision: Int"))
        XCTAssertTrue(
            source.contains("let backgroundIntent: CardEditingBackgroundIntent")
        )
    }

    func testCommitEquivalenceIsScopedToCommittedStateAndBootstrapRebase() throws {
        let source = try Self.newNoteSource()
        let snapshotMatch = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func snapshotMatchesCommittedBaseline("
            )
        )
        let baseline = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "struct CardEditorCommitBaseline: Equatable"
            )
        )
        let storeSource = try Self.cardEditingStoreSource()
        let dirty = try XCTUnwrap(
            Self.functionBody(
                in: storeSource,
                signature: "var isDraftDirty: Bool"
            )
        )
        let applyBodyRevision = try XCTUnwrap(
            Self.functionBody(
                in: storeSource,
                signature: "func applyBodyRevision("
            )
        )
        let persist = try XCTUnwrap(
            Self.functionBody(
                in: storeSource,
                signature: "func persistDraft("
            )
        )

        XCTAssertTrue(
            snapshotMatch.contains(
                "editingStore.draft.isCommitEquivalent(to: committedDraft)"
            )
        )
        XCTAssertFalse(baseline.contains("static func =="))
        XCTAssertFalse(baseline.contains("isCommitEquivalent(to:"))
        XCTAssertTrue(
            dirty.contains("draft.isCommitEquivalent(to: lastCommittedDraft)")
        )
        XCTAssertTrue(
            applyBodyRevision.contains("cardID != nil")
        )
        XCTAssertTrue(
            applyBodyRevision.contains("activeOperationID == nil")
        )
        XCTAssertTrue(
            applyBodyRevision.contains("&& !hasUncertainDraftWrite")
        )
        XCTAssertTrue(
            applyBodyRevision.contains(
                "failureContext?.stage == .creatingCard"
            )
        )
        XCTAssertTrue(
            applyBodyRevision.contains(
                "failureContext?.stage == .updatingCard"
            )
        )
        XCTAssertTrue(
            applyBodyRevision.contains("nextDraft.isCommitEquivalent(to: $0)")
        )
        XCTAssertTrue(
            applyBodyRevision.contains("lastCommittedBodyRevision = revision")
        )
        XCTAssertEqual(
            source.components(separatedBy: "isCommitEquivalent(to:").count - 1,
            1
        )
        XCTAssertEqual(
            storeSource.components(
                separatedBy: "isCommitEquivalent(to:"
            ).count - 1,
            2
        )
        XCTAssertTrue(
            persist.contains(
                "if draft == request, bodyRevision == requestRevision"
            )
        )
        XCTAssertFalse(persist.contains("draft.isCommitEquivalent(to: request)"))
    }

    func testFrozenRecoveryNeverAutoSavesTheCurrentDraft() throws {
        let source = try Self.newNoteSource()
        let recovery = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func recoverFrozenFailedOperationIfNeeded()"
            )
        )

        XCTAssertTrue(
            recovery.contains("editingStore.reconcileFailedRelationshipMutation()")
        )
        XCTAssertTrue(recovery.contains("editingStore.retry()"))
        XCTAssertFalse(recovery.contains("editingStore.save()"))
        XCTAssertFalse(source.contains("recoverFailedDraftOperationIfNeeded"))
    }

    func testNewerChangesOutrankFailureAndStaleSnapshotsStayPending() throws {
        let source = try Self.newNoteSource()
        let classify = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func classifyCommit(")
        )
        let exactSuccess = try XCTUnwrap(
            classify.range(of: "if didSave, exactRevision, !editingStore.isDirty")
        )
        let newer = try XCTUnwrap(
            classify.range(of: "!commitBaselineMatchesCurrent(baseline)")
        )
        let failure = try XCTUnwrap(classify.range(of: "editingStore.failureStage"))
        XCTAssertLessThan(exactSuccess.lowerBound, newer.lowerBound)
        XCTAssertLessThan(newer.lowerBound, failure.lowerBound)

        let leading = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "var leadingControlState: CardEditorLeadingControlState"
            )
        )
        XCTAssertTrue(leading.contains("hasCorrelatedSaveFailure"))

        let correlation = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "var hasCorrelatedSaveFailure: Bool"
            )
        )
        XCTAssertTrue(correlation.contains("failedCommitBaseline"))
        XCTAssertTrue(correlation.contains("currentCommitBaseline"))

        let pending = try XCTUnwrap(
            Self.functionBody(in: source, signature: "var hasPendingCommit: Bool")
        )
        XCTAssertTrue(pending.contains("hasUncommittedEditorRevision"))

        for signature in [
            "func saveCurrentSnapshot()",
            "func verifyCurrentSnapshotAndDismiss()",
        ] {
            let action = try XCTUnwrap(
                Self.functionBody(in: source, signature: signature)
            )
            XCTAssertTrue(action.contains("catch CardEditorSessionError.staleSnapshot"))
        }
    }

    func testFailedFrozenBaselineRemainsCorrelatedWhenNewerBaselineCannotRun() throws {
        let source = try Self.newNoteSource()
        let save = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func saveCurrentSnapshot()")
        )
        let priorFailure = try XCTUnwrap(
            save.range(of: "let priorFailedBaseline = failedCommitBaseline")
        )
        let recovery = try XCTUnwrap(
            save.range(of: "recoverFrozenFailedOperationIfNeeded()")
        )
        let recoveryFailure = try XCTUnwrap(save.range(of: "if !didRecover"))
        let preserveFailure = try XCTUnwrap(
            save.range(of: "failureBaseline = priorFailedBaseline")
        )
        let persist = try XCTUnwrap(save.range(of: "editingStore.save()"))

        XCTAssertLessThan(priorFailure.lowerBound, recovery.lowerBound)
        XCTAssertLessThan(recovery.lowerBound, recoveryFailure.lowerBound)
        XCTAssertLessThan(recoveryFailure.lowerBound, preserveFailure.lowerBound)
        XCTAssertLessThan(preserveFailure.lowerBound, persist.lowerBound)
        XCTAssertFalse(
            save[..<recovery.lowerBound].contains("clearSaveFailure()"),
            "Starting B must not erase the failed A baseline before retrying A"
        )
        XCTAssertTrue(save.contains("priorFailedBaseline == baseline"))
        XCTAssertTrue(save.contains("outcome = .pendingNewerChanges"))
        XCTAssertTrue(save.contains("if let failureBaseline"))
        XCTAssertTrue(save.contains("failureBaseline = baseline"))
        XCTAssertTrue(source.contains("var editingStoreHasFailure: Bool"))
    }

    func testMetadataHidesCommitFailureWithoutForgettingFrozenBaseline() throws {
        let source = try Self.newNoteSource()
        let hide = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func hideSaveFailure()")
        )
        let resolve = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func resolveSaveFailure()")
        )
        let metadata = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func updateMetadata(")
        )
        let save = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func saveCurrentSnapshot()")
        )

        XCTAssertTrue(hide.contains("hasSaveFailure = false"))
        XCTAssertFalse(hide.contains("failedCommitBaseline = nil"))
        XCTAssertTrue(resolve.contains("hideSaveFailure()"))
        XCTAssertTrue(resolve.contains("failedCommitBaseline = nil"))
        XCTAssertTrue(metadata.contains("hideSaveFailure()"))
        XCTAssertFalse(metadata.contains("resolveSaveFailure()"))
        XCTAssertTrue(save.contains("let priorFailedBaseline = failedCommitBaseline"))
        XCTAssertTrue(save.contains("failedCommitBaseline = failureBaseline"))
        XCTAssertTrue(save.contains("hideSaveFailure()"))
    }

    func testStagedBackgroundHidesCommitFailureAcrossEveryLoadOutcome() throws {
        let source = try Self.newNoteSource()
        let handler = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func handleSelectedBackgroundPhoto("
            )
        )
        let hide = try XCTUnwrap(handler.range(of: "hideSaveFailure()"))
        let task = try XCTUnwrap(handler.range(of: "Task {"))
        let stage = try XCTUnwrap(handler.range(of: "editingStore.stageBackground(image)"))

        XCTAssertLessThan(hide.lowerBound, task.lowerBound)
        XCTAssertLessThan(task.lowerBound, stage.lowerBound)
        XCTAssertGreaterThanOrEqual(
            Self.occurrenceCount("hideSaveFailure()", in: String(handler)),
            4,
            "Selection, invalid image, staged B, and load failure must retain A"
        )
        XCTAssertFalse(handler.contains("resolveSaveFailure()"))
    }

    func testBodyImageHidesCommitFailureAcrossProcessingOutcomes() throws {
        let source = try Self.newNoteSource()
        let processing = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func beginInlineImageProcessing("
            )
        )
        let hide = try XCTUnwrap(processing.range(of: "hideSaveFailure()"))
        let task = try XCTUnwrap(processing.range(of: "Task {"))
        let insert = try XCTUnwrap(processing.range(of: "bodyModel.insertImage("))

        XCTAssertLessThan(hide.lowerBound, task.lowerBound)
        XCTAssertLessThan(task.lowerBound, insert.lowerBound)
        XCTAssertGreaterThanOrEqual(
            Self.occurrenceCount("hideSaveFailure()", in: String(processing)),
            3,
            "Processing start, inserted B, and upload failure must retain A"
        )
        XCTAssertFalse(processing.contains("resolveSaveFailure()"))
    }

    func testContextualLaunchesHideFailureUntilFrozenRecoveryIsResolved() throws {
        let source = try Self.newNoteSource()
        for signature in [
            "func addOntologyLink()",
            "func performPersistedCardAction(",
        ] {
            let action = try XCTUnwrap(
                Self.functionBody(in: source, signature: signature)
            )
            let hide = try XCTUnwrap(action.range(of: "hideSaveFailure()"))
            let recover = try XCTUnwrap(
                action.range(of: "recoverFrozenFailedOperationIfNeeded()")
            )
            let persist = try XCTUnwrap(
                action.range(of: "editingStore.ensurePersisted()")
            )
            let resolve = try XCTUnwrap(
                action.range(of: "resolveSaveFailure()")
            )
            XCTAssertLessThan(hide.lowerBound, recover.lowerBound)
            XCTAssertLessThan(recover.lowerBound, persist.lowerBound)
            XCTAssertLessThan(persist.lowerBound, resolve.lowerBound)
        }

        for signature in [
            "func presentInlineImageSourceOptions()",
            "func presentInlineLinkSheet()",
            "func openCardActions()",
            "func togglePinnedCard()",
            "func removeCanonicalCard()",
        ] {
            let action = try XCTUnwrap(
                Self.functionBody(in: source, signature: signature)
            )
            XCTAssertTrue(
                action.contains("hideSaveFailure()"),
                "Context launch must hide but retain frozen A: \(signature)"
            )
        }
    }

    func testDelayedBackgroundLoadingParticipatesInBusyState() throws {
        let source = try Self.newNoteSource()
        XCTAssertTrue(
            source.contains("@State private var isLoadingBackgroundPhoto = false")
        )
        let busy = try XCTUnwrap(
            Self.functionBody(in: source, signature: "var isBusy: Bool")
        )
        XCTAssertTrue(busy.contains("isLoadingBackgroundPhoto"))

        let handler = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func handleSelectedBackgroundPhoto("
            )
        )
        let start = try XCTUnwrap(
            handler.range(of: "isLoadingBackgroundPhoto = true")
        )
        let task = try XCTUnwrap(handler.range(of: "Task {"))
        let finish = try XCTUnwrap(
            handler.range(of: "isLoadingBackgroundPhoto = false")
        )
        XCTAssertLessThan(start.lowerBound, task.lowerBound)
        XCTAssertLessThan(task.lowerBound, finish.lowerBound)
    }

    func testCardActionsKeepFixedBackgroundTileAndStageContextualMutations() throws {
        let source = try Self.newNoteSource()
        let grid = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "ArcNote/CardEditor/CardEditorActionBox.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("saveActionTitle:"))
        XCTAssertTrue(source.contains("onOpenCardActions: cardActionsHandler"))
        XCTAssertTrue(source.contains("CardEditorActionBox("))
        XCTAssertFalse(source.contains(".accessibilityHidden(showCardActions)"))
        XCTAssertFalse(source.contains(".popupMenu("))
        XCTAssertFalse(source.contains("layout: .grid3x3"))
        XCTAssertTrue(source.contains(".cardEditorBackgroundActionDialog("))
        XCTAssertTrue(source.contains("editingStore.stageBackgroundRemoval()"))
        XCTAssertTrue(source.contains("editingStore.restoreBackground()"))
        XCTAssertTrue(source.contains("editingStore.canRestoreBackground"))
        XCTAssertFalse(source.contains("editingStore.removeBackground()"))

        for wiring in [
            "onBackground: presentBackgroundActions",
            "onShare: { performPersistedCardAction(.notification(\"ShowCardShare\")) }",
            "onLink: addOntologyLink",
            "onRemove: { showRemoveCardConfirmation = true }",
            "onTogglePin: { performPersistedCardAction(.togglePin) }",
        ] {
            XCTAssertTrue(
                source.contains(wiring),
                "Card Actions must preserve its lazy-persist route: \(wiring)"
            )
        }
        XCTAssertTrue(source.contains(".navigation(CardNavigationRoute.spark)"))
        XCTAssertTrue(source.contains(".navigation(CardNavigationRoute.merge)"))
        XCTAssertTrue(source.contains(".root(cardID: $0, type: nil)"))

        let presentation = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func presentBackgroundActions()"
            )
        )
        XCTAssertTrue(presentation.contains("completeTagEntry()"))
        XCTAssertTrue(presentation.contains("backgroundIntent == .unchanged"))
        XCTAssertTrue(presentation.contains("backgroundMediaRef == nil"))
        XCTAssertTrue(presentation.contains("showBackgroundPicker = true"))
        XCTAssertTrue(presentation.contains("showBackgroundActions = true"))
        XCTAssertFalse(presentation.contains("editingStore.save()"))
        XCTAssertFalse(presentation.contains("editingStore.ensurePersisted()"))

        let handler = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func handleBackgroundAction("
            )
        )
        for expected in [
            "showBackgroundPicker = true",
            "editingStore.stageBackgroundRemoval()",
            "editingStore.restoreBackground()",
        ] {
            XCTAssertTrue(handler.contains(expected))
        }
        XCTAssertTrue(
            handler.contains("guard editingStore.restoreBackground() else")
        )
        XCTAssertTrue(
            handler.contains("Retry the pending background change before restoring.")
        )
        XCTAssertEqual(
            Self.occurrenceCount("hideSaveFailure()", in: String(handler)),
            3
        )
        for forbidden in [
            "editingStore.save()",
            "editingStore.ensurePersisted()",
            "editingStore.stageBackground(",
            "editingStore.removeBackground()",
            "resolveSaveFailure()",
            "Task {",
            "NetworkManager",
            "URLSession",
            "service.",
        ] {
            XCTAssertFalse(
                handler.contains(forbidden),
                "Background actions must remain local-only: \(forbidden)"
            )
        }

        let preview = try XCTUnwrap(
            Self.functionBody(in: source, signature: "var editorBackground:")
        )
        XCTAssertTrue(
            preview.contains(
                """
                case let .replace(image):
                            return .local(image.data)
                        case .remove:
                            return .none
                        case .unchanged:
                """
            )
        )
        XCTAssertTrue(
            preview.contains(
                """
                case .unchanged:
                            guard let mediaRef = editingStore.backgroundMediaRef,
                                  let url = URL(
                                      string: APIConfiguration.resourceURLString(mediaRef)
                                  ) else {
                                return .none
                            }
                            return .remote(url)
                """
            )
        )
        XCTAssertFalse(preview.contains("pendingBackground"))

        let actions = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func openCardActions()")
        )
        XCTAssertTrue(actions.contains("guard bodyModel.canSave, !isBusy else { return }"))
        let dismissKeyboard = try XCTUnwrap(
            actions.range(of: "bodyModel.dismissKeyboard()")
        )
        let presentActions = try XCTUnwrap(
            actions.range(of: "showCardActions = true")
        )
        XCTAssertLessThan(
            dismissKeyboard.lowerBound,
            presentActions.lowerBound,
            "The editor must restore full viewport height before presenting Card Actions"
        )
        for forbidden in [
            "Task {",
            "applyCurrentSnapshot()",
            "recoverFailedDraftOperationIfNeeded()",
            "editingStore.ensurePersisted()",
            "editingStore.save()",
            "notifyCreationIfNeeded()",
        ] {
            XCTAssertFalse(
                actions.contains(forbidden),
                "Opening Card Actions must be presentation-only: \(forbidden)"
            )
        }

        XCTAssertTrue(grid.contains("ActionBoxOverlay("))
        XCTAssertTrue(
            grid.contains(
                "accessibilityIdentifier: \"cardEditorActionsOverlay\""
            )
        )
        XCTAssertFalse(grid.contains("closeAccessibilityIdentifier"))
        XCTAssertFalse(grid.contains("cardEditorActionsClose"))
        XCTAssertEqual(
            Self.occurrenceCount(
                ".accessibilityIdentifier(\"cardEditorActionGrid\")",
                in: grid
            ),
            1
        )
        XCTAssertEqual(
            Self.occurrenceCount("text: \"Background\"", in: grid),
            1
        )
        XCTAssertTrue(grid.contains("role: .destructive"))
        XCTAssertFalse(grid.contains("Remove Background"))
        XCTAssertFalse(grid.contains("cardEditorRemoveBackgroundButton"))

        XCTAssertEqual(
            Self.occurrenceCount(
                "private func dismissThenPerform(",
                in: grid
            ),
            1
        )
        let dismissHelper = try XCTUnwrap(
            Self.functionBody(
                in: grid,
                signature: "private func dismissThenPerform("
            )
        )
        let dismissHelperSource = String(dismissHelper)
        XCTAssertEqual(
            Self.occurrenceCount(
                "isPresented = false",
                in: dismissHelperSource
            ),
            1
        )
        XCTAssertEqual(
            Self.occurrenceCount(
                "DispatchQueue.main.async",
                in: dismissHelperSource
            ),
            1
        )
        XCTAssertEqual(
            Self.occurrenceCount("action()", in: dismissHelperSource),
            1
        )
        let dismissPresentation = try XCTUnwrap(
            dismissHelperSource.range(of: "isPresented = false")
        )
        let asyncDispatch = try XCTUnwrap(
            dismissHelperSource.range(of: "DispatchQueue.main.async")
        )
        XCTAssertLessThan(
            dismissPresentation.lowerBound,
            asyncDispatch.lowerBound,
            "The overlay must dismiss before scheduling its action"
        )
        let asyncClosures = Self.bracedBlocks(
            in: dismissHelperSource,
            signature: "DispatchQueue.main.async"
        )
        XCTAssertEqual(asyncClosures.count, 1)
        let asyncClosure = try XCTUnwrap(asyncClosures.first)
        XCTAssertEqual(
            Self.occurrenceCount("action()", in: String(asyncClosure)),
            1,
            "The injected action must execute inside the async closure"
        )
        XCTAssertFalse(
            asyncClosure.contains("isPresented = false"),
            "Dismissal must not be deferred into the async closure"
        )

        XCTAssertTrue(source.contains("menuActions: nativeMenuActions"))
        XCTAssertTrue(grid.contains("struct CardEditorNativeMenuButton: UIViewRepresentable"))
        XCTAssertTrue(grid.contains("actions.prepare()"))
        XCTAssertTrue(grid.contains("bodyModel.perform(.undo)"))
        XCTAssertTrue(grid.contains("bodyModel.perform(.redo)"))
        XCTAssertTrue(source.contains("spark: { performPersistedCardAction(.navigation(CardNavigationRoute.spark)) }"))
        XCTAssertTrue(source.contains("merge: { performPersistedCardAction(.navigation(CardNavigationRoute.merge)) }"))
        for identifier in [
            "cardEditorBackgroundButton", "cardEditorActionSpark", "cardEditorActionMerge",
            "cardEditorActionShare", "cardEditorActionLink", "cardEditorActionRoot",
            "cardEditorActionRemove", "cardEditorActionPin",
        ] {
            XCTAssertEqual(Self.occurrenceCount("\"\(identifier)\"", in: grid), 1,
                           "Menu and legacy fixture share one canonical identifier")
        }

        let expectedRows: [[(identifier: String, action: String)]] = [
            [
                (
                    identifier: "CardEditorActionIdentity.background",
                    action: "dismissThenPerform(onBackground)"
                ),
                (
                    identifier: "CardEditorActionIdentity.spark",
                    action: "dismissThenPerform(onSpark)"
                ),
                (
                    identifier: "CardEditorActionIdentity.merge",
                    action: "dismissThenPerform(onMerge)"
                ),
            ],
            [
                (
                    identifier: "CardEditorActionIdentity.share",
                    action: "dismissThenPerform(onShare)"
                ),
                (
                    identifier: "CardEditorActionIdentity.link",
                    action: "dismissThenPerform(onLink)"
                ),
                (
                    identifier: "CardEditorActionIdentity.root",
                    action: "dismissThenPerform(onRoot)"
                ),
            ],
            [
                (
                    identifier: "CardEditorActionIdentity.remove",
                    action: "dismissThenPerform(onRemove)"
                ),
                (
                    identifier: "CardEditorActionIdentity.pin",
                    action: "dismissThenPerform(onTogglePin)"
                ),
            ],
        ]
        let expectedEmptyTileCounts = [0, 0, 0]
        let actionGridBlocks = Self.bracedBlocks(
            in: grid,
            signature: "VStack(alignment: .leading, spacing: 15)"
        )
        XCTAssertEqual(actionGridBlocks.count, 1)
        let actionGrid = try XCTUnwrap(actionGridBlocks.first)
        let actionGridContainment =
            ".accessibilityElement(children: .contain)"
        let actionGridIdentifier =
            ".accessibilityIdentifier(\"cardEditorActionGrid\")"
        XCTAssertEqual(
            Self.occurrenceCount(actionGridContainment, in: grid),
            1
        )
        let actionGridContainmentRange = try XCTUnwrap(
            grid.range(
                of: actionGridContainment,
                range: actionGrid.endIndex..<grid.endIndex
            )
        )
        XCTAssertTrue(
            grid[actionGrid.endIndex..<actionGridContainmentRange.lowerBound]
                .allSatisfy { $0.isWhitespace },
            "The action-grid VStack must directly contain its accessibility children"
        )
        let actionGridIdentifierRange = try XCTUnwrap(
            grid.range(
                of: actionGridIdentifier,
                range: actionGridContainmentRange.upperBound..<grid.endIndex
            )
        )
        let containmentEnd = actionGridContainmentRange.upperBound
        let identifierStart = actionGridIdentifierRange.lowerBound
        let containmentToIdentifier = containmentEnd..<identifierStart
        XCTAssertTrue(
            grid[containmentToIdentifier]
                .allSatisfy { $0.isWhitespace },
            "cardEditorActionGrid must follow the VStack containment modifier"
        )
        XCTAssertEqual(
            Self.occurrenceCount("ActionBoxTile(", in: String(actionGrid)),
            8
        )
        XCTAssertEqual(
            Self.occurrenceCount(
                "ActionBoxEmptyTile()",
                in: String(actionGrid)
            ),
            0
        )
        let rows = Self.bracedBlocks(
            in: String(actionGrid),
            signature: "HStack(spacing: 15)"
        )

        XCTAssertEqual(rows.count, 3)
        guard rows.count == 3 else { return }

        for rowIndex in rows.indices {
            let row = String(rows[rowIndex])
            let expectedTiles = expectedRows[rowIndex]
            let tileBlocks = Self.bracedCallBlocks(
                in: row,
                signature: "ActionBoxTile("
            )
            XCTAssertEqual(
                tileBlocks.count,
                expectedTiles.count,
                "Unexpected tile count in editor action row \(rowIndex + 1)"
            )
            XCTAssertEqual(
                Self.occurrenceCount("ActionBoxEmptyTile()", in: row),
                expectedEmptyTileCounts[rowIndex],
                "Unexpected empty-tile count in editor action row \(rowIndex + 1)"
            )

            let expectedMarkers = expectedTiles.flatMap {
                [$0.identifier, $0.action]
            }
            XCTAssertTrue(
                Self.containsInOrder(expectedMarkers, in: row),
                "Unexpected tile or action order in editor action row \(rowIndex + 1)"
            )

            guard tileBlocks.count == expectedTiles.count else { continue }
            for tileIndex in tileBlocks.indices {
                let tile = String(tileBlocks[tileIndex])
                let expectedTile = expectedTiles[tileIndex]
                XCTAssertEqual(
                    Self.occurrenceCount(expectedTile.identifier, in: tile),
                    1,
                    "Unexpected action identifier in row \(rowIndex + 1), tile \(tileIndex + 1)"
                )
                XCTAssertEqual(
                    Self.occurrenceCount("dismissThenPerform(", in: tile),
                    1,
                    "Each action closure must call dismissThenPerform exactly once"
                )
                XCTAssertEqual(
                    Self.occurrenceCount("text: \"Background\"", in: tile),
                    rowIndex == 0 && tileIndex == 0 ? 1 : 0,
                    "Background must belong only to the first action tile"
                )
                XCTAssertTrue(
                    Self.containsInOrder(
                        [expectedTile.identifier, expectedTile.action],
                        in: tile
                    ),
                    "Unexpected action closure in row \(rowIndex + 1), tile \(tileIndex + 1)"
                )
            }
        }

        let tileIdentifiers = expectedRows.flatMap { row in
            row.map { $0.identifier }
        }
        for identifier in tileIdentifiers {
            XCTAssertEqual(
                Self.occurrenceCount(identifier, in: String(actionGrid)),
                1,
                "Each exclusive legacy fixture action remains unique: \(identifier)"
            )
        }
        XCTAssertEqual(
            Self.occurrenceCount("dismissThenPerform(on", in: grid),
            8,
            "Every editor action tile must dismiss before dispatching its injected action"
        )
    }

    func testIDScopedCardActionsPersistLazilyAndRecoverTheirExactStoreIntent() throws {
        let source = try Self.newNoteSource()
        XCTAssertTrue(source.contains("enum CardEditorPersistedAction"))
        XCTAssertTrue(
            source.contains(
                "case navigation((String) -> CardNavigationRoute)"
            )
        )
        XCTAssertTrue(source.contains("case notification(String)"))
        XCTAssertTrue(source.contains("case togglePin"))
        XCTAssertFalse(source.contains("case persistedAction(CardEditorPersistedAction)"))
        XCTAssertFalse(source.contains("case openCardActions"))

        let action = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func performPersistedCardAction("
            )
        )
        let snapshot = try XCTUnwrap(action.range(of: "applyCurrentSnapshot()"))
        let recovery = try XCTUnwrap(
            action.range(of: "recoverFrozenFailedOperationIfNeeded()")
        )
        let persist = try XCTUnwrap(
            action.range(of: "editingStore.ensurePersisted()")
        )
        let notify = try XCTUnwrap(action.range(of: "notifyCreationIfNeeded()"))
        let execute = try XCTUnwrap(
            action.range(of: "executePersistedCardAction(action)")
        )
        XCTAssertLessThan(snapshot.lowerBound, recovery.lowerBound)
        XCTAssertLessThan(recovery.lowerBound, persist.lowerBound)
        XCTAssertLessThan(persist.lowerBound, notify.lowerBound)
        XCTAssertLessThan(notify.lowerBound, execute.lowerBound)
        XCTAssertFalse(action.contains("hasSaveFailure = true"))
        XCTAssertFalse(source.contains("retryCurrentFailure"))

        XCTAssertTrue(
            source.contains(
                "performPersistedCardAction(.notification(\"ShowCardShare\"))"
            )
        )
        XCTAssertTrue(source.contains("navigateCard(route(cardID))"))
        XCTAssertFalse(source.contains(".notification(\"NavigateTo"))
        XCTAssertTrue(source.contains("performPersistedCardAction(.togglePin)"))

        XCTAssertTrue(source.contains("func togglePinnedCard()"))
        XCTAssertTrue(source.contains("NetworkManager.shared.pinCard(cardId: cardID)"))
        XCTAssertTrue(source.contains("NetworkManager.shared.unpinCard(cardId: cardID)"))
        XCTAssertTrue(source.contains("func removeCanonicalCard()"))
        XCTAssertTrue(source.contains("localNotes.setLifecycle(identifier: cardID, lifecycle: .trashed)"))
        XCTAssertTrue(source.contains(#"userInfo: ["cardId": cardID]"#))

        let removal = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func removeCanonicalCard()")
        )
        let localDismiss = try XCTUnwrap(
            removal.range(of: "guard let cardID = editingStore.cardID else")
        )
        let delete = try XCTUnwrap(
            removal.range(of: "localNotes.setLifecycle(identifier: cardID, lifecycle: .trashed)")
        )
        XCTAssertLessThan(localDismiss.lowerBound, delete.lowerBound)
        XCTAssertTrue(removal.contains("dismiss()"))
        XCTAssertFalse(removal.contains("ensurePersisted()"))
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

    private static func cardEditingStoreSource() throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Packages/CoreFlow/Sources/CoreFlow/CardEditingStore.swift"
            ),
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

    private static func bracedBlocks(
        in source: String,
        signature: String
    ) -> [Substring] {
        var blocks: [Substring] = []
        var lowerBound = source.startIndex

        while lowerBound < source.endIndex,
              let signatureRange = source.range(
                  of: signature,
                  range: lowerBound..<source.endIndex
              ),
              let openingBrace = source[signatureRange.upperBound...]
                  .firstIndex(of: "{") {
            guard let block = bracedBlock(
                in: source,
                openingBrace: openingBrace
            ) else {
                break
            }
            blocks.append(block)
            lowerBound = block.endIndex
        }

        return blocks
    }

    private static func bracedCallBlocks(
        in source: String,
        signature: String
    ) -> [Substring] {
        var blocks: [Substring] = []
        var lowerBound = source.startIndex

        while lowerBound < source.endIndex,
              let signatureRange = source.range(
                  of: signature,
                  range: lowerBound..<source.endIndex
              ),
              let openingBrace = source[signatureRange.upperBound...]
                  .firstIndex(of: "{") {
            guard let closure = bracedBlock(
                in: source,
                openingBrace: openingBrace
            ) else {
                break
            }
            blocks.append(source[signatureRange.lowerBound..<closure.endIndex])
            lowerBound = closure.endIndex
        }

        return blocks
    }

    private static func bracedBlock(
        in source: String,
        openingBrace: String.Index
    ) -> Substring? {
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

    private static func occurrenceCount(
        _ needle: String,
        in source: String
    ) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    private static func containsInOrder(
        _ markers: [String],
        in source: String
    ) -> Bool {
        var lowerBound = source.startIndex
        for marker in markers {
            guard let range = source.range(
                of: marker,
                range: lowerBound..<source.endIndex
            ) else {
                return false
            }
            lowerBound = range.upperBound
        }
        return true
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
