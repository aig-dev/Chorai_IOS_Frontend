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
        XCTAssertFalse(
            source.contains("canRemove:"),
            "Editor links are display-only"
        )
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
        let privacy = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func togglePrivacy()")
        )
        XCTAssertTrue(
            privacy.contains(
                "updateMetadata(isPublic: !editingStore.draft.isPublic)"
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

        for signature in [
            "func addOntologyLink()",
            "func performPersistedCardAction(",
        ] {
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
    }

    func testCardActionsUseSharedFixedGridWithoutPersistenceOrBackgroundRemoval() throws {
        let source = try Self.newNoteSource()
        let grid = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "ArcNote/CardEditor/CardEditorActionBox.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("saveActionTitle: \"Retry\""))
        XCTAssertTrue(source.contains("onOpenCardActions: cardActionsHandler"))
        XCTAssertTrue(source.contains("CardEditorActionBox("))
        XCTAssertFalse(source.contains(".accessibilityHidden(showCardActions)"))
        XCTAssertFalse(source.contains(".confirmationDialog("))
        XCTAssertFalse(source.contains(".popupMenu("))
        XCTAssertFalse(source.contains("layout: .grid3x3"))
        XCTAssertFalse(source.contains("Remove Background"))
        XCTAssertFalse(source.contains("cardEditorRemoveBackgroundButton"))

        for wiring in [
            "onBackground: { showBackgroundPicker = true }",
            "onSpark: { performPersistedCardAction(.notification(\"NavigateToSpark\")) }",
            "onMerge: { performPersistedCardAction(.notification(\"NavigateToMerge\")) }",
            "onShare: { performPersistedCardAction(.notification(\"ShowCardShare\")) }",
            "onLink: addOntologyLink",
            "onRoot: { performPersistedCardAction(.notification(\"NavigateToRoot\")) }",
            "onRemove: { showRemoveCardConfirmation = true }",
            "onTogglePin: { performPersistedCardAction(.togglePin) }",
        ] {
            XCTAssertTrue(
                source.contains(wiring),
                "Card Actions must preserve its lazy-persist route: \(wiring)"
            )
        }

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
        XCTAssertTrue(
            grid.contains(
                "closeAccessibilityIdentifier: \"cardEditorActionsClose\""
            )
        )
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

        let expectedRows: [[(identifier: String, action: String)]] = [
            [
                (
                    identifier: "\"cardEditorBackgroundButton\"",
                    action: "dismissThenPerform(onBackground)"
                ),
                (
                    identifier: "\"cardEditorActionSpark\"",
                    action: "dismissThenPerform(onSpark)"
                ),
                (
                    identifier: "\"cardEditorActionMerge\"",
                    action: "dismissThenPerform(onMerge)"
                ),
            ],
            [
                (
                    identifier: "\"cardEditorActionShare\"",
                    action: "dismissThenPerform(onShare)"
                ),
                (
                    identifier: "\"cardEditorActionLink\"",
                    action: "dismissThenPerform(onLink)"
                ),
            ],
            [
                (
                    identifier: "\"cardEditorActionRoot\"",
                    action: "dismissThenPerform(onRoot)"
                ),
                (
                    identifier: "\"cardEditorActionRemove\"",
                    action: "dismissThenPerform(onRemove)"
                ),
                (
                    identifier: "\"cardEditorActionPin\"",
                    action: "dismissThenPerform(onTogglePin)"
                ),
            ],
        ]
        let expectedEmptyTileCounts = [0, 1, 0]
        let actionGridBlocks = Self.bracedBlocks(
            in: grid,
            signature: "VStack(spacing: 15)"
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
            1
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

            var expectedMarkers = expectedTiles.flatMap {
                [$0.identifier, $0.action]
            }
            if rowIndex == 1 {
                expectedMarkers.insert("ActionBoxEmptyTile()", at: 0)
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
                Self.occurrenceCount(identifier, in: grid),
                1,
                "Editor action identifiers must be globally unique: \(identifier)"
            )
        }
        XCTAssertEqual(
            Self.occurrenceCount("dismissThenPerform(on", in: grid),
            8,
            "Every editor action tile must dismiss before dispatching its injected action"
        )
    }

    func testIDScopedCardActionsPersistLazilyAndRetryTheirExactIntent() throws {
        let source = try Self.newNoteSource()
        XCTAssertTrue(source.contains("enum CardEditorPersistedAction"))
        XCTAssertTrue(source.contains("case notification(String)"))
        XCTAssertTrue(source.contains("case togglePin"))
        XCTAssertTrue(source.contains("case persistedAction(CardEditorPersistedAction)"))
        XCTAssertFalse(source.contains("case openCardActions"))

        let action = try XCTUnwrap(
            Self.functionBody(
                in: source,
                signature: "func performPersistedCardAction("
            )
        )
        let snapshot = try XCTUnwrap(action.range(of: "applyCurrentSnapshot()"))
        let recovery = try XCTUnwrap(
            action.range(of: "recoverFailedDraftOperationIfNeeded()")
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
        XCTAssertTrue(action.contains("retryAction = .persistedAction(action)"))

        let retry = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func retryCurrentFailure()")
        )
        XCTAssertTrue(retry.contains("case let .persistedAction(action)"))
        XCTAssertTrue(retry.contains("performPersistedCardAction(action)"))

        for notification in [
            "ShowCardShare",
            "NavigateToSpark",
            "NavigateToMerge",
            "NavigateToRoot",
        ] {
            XCTAssertTrue(
                source.contains(
                    "performPersistedCardAction(.notification(\"\(notification)\"))"
                )
            )
        }
        XCTAssertTrue(source.contains("performPersistedCardAction(.togglePin)"))

        XCTAssertTrue(source.contains("func togglePinnedCard()"))
        XCTAssertTrue(source.contains("NetworkManager.shared.pinCard(cardId: cardID)"))
        XCTAssertTrue(source.contains("NetworkManager.shared.unpinCard(cardId: cardID)"))
        XCTAssertTrue(source.contains("func removeCanonicalCard()"))
        XCTAssertTrue(source.contains("NetworkManager.shared.deleteCard(id: cardID)"))
        XCTAssertTrue(source.contains(#"userInfo: ["cardId": cardID]"#))

        let removal = try XCTUnwrap(
            Self.functionBody(in: source, signature: "func removeCanonicalCard()")
        )
        let localDismiss = try XCTUnwrap(
            removal.range(of: "guard let cardID = editingStore.cardID else")
        )
        let delete = try XCTUnwrap(
            removal.range(of: "NetworkManager.shared.deleteCard(id: cardID)")
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
