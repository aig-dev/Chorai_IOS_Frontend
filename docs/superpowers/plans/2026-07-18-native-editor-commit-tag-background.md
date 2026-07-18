# Native Editor Commit, Inline Tag, and Background Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make native tag entry inline, make the upper-left control the editor's only explicit save/exit affordance, and make background replacement/removal reversible and staged until that control saves.

**Architecture:** Keep `CardEditorSessionView` as the interaction orchestrator and `CardEditingStore` as the revision/persistence truth. Expose shared tag normalization and a three-state background intent from CoreFlow, render a semantic leading control in `CardEditorShell`, and keep all native dialogs, focus, exact snapshots, and error presentation outside the embedded BlockNote body.

**Tech Stack:** Swift 6, SwiftUI, PhotosUI, CoreFlow Swift Package, BlockNoteEditor/WKWebView snapshot bridge, XCTest, XCUITest, Xcode 26, iOS 26.2 simulator.

## Global Constraints

- Native iOS only; do not modify `chorai_web_frontend` or expose the embedded editor as a browser surface.
- Tag entry is a native single-line field in the existing tag row; it must not show the body formatting bar.
- Return, focus loss, Save, Back, or another modal action finishes tag entry synchronously.
- Empty, whitespace-only, hash-only, duplicate, and over-limit tag candidates create nothing and do not dirty the draft.
- The upper-left control is the only Save/Retry/Back affordance; there is no editor-body Save button.
- Save never dismisses. Exact clean success turns the checkmark into Back; a second explicit tap exits.
- Back never silently persists. It verifies an exact snapshot and refuses to exit when it discovers unsaved content.
- Newer edits arriving during a captured save remain dirty and keep the checkmark; they are not reported as a failed save.
- Background selection remains photo-library-only; no camera route is added for backgrounds.
- Background replace/remove/restore mutate local intent and preview only until the upper-left checkmark saves.
- Link and pin network semantics stay unchanged. Their failures keep contextual messages and are retried by repeating the originating action, not by restoring a standalone Save button.
- Preserve stable create request IDs, exact frozen retry payloads, revision checks, compatibility mode, bridge-failure discard confirmation, Dynamic Type, and 44-point interactive targets.
- Authoritative simulator: `Chorai iPhone SE 3 QA`, iOS 26.2, UDID `86CD9628-7C27-4799-B237-3EEC82E7E9B5`.

---

## File Map

- Create `Packages/CoreFlow/Tests/CoreFlowTests/CardEditingTagTests.swift`: unit-test shared candidate/list normalization.
- Modify `Packages/CoreFlow/Sources/CoreFlow/CardEditingModels.swift`: expose `CardEditingTag` and `CardEditingBackgroundIntent`.
- Modify `Packages/CoreFlow/Sources/CoreFlow/CardEditingStore.swift`: replace replacement-only pending state with staged replace/remove intent and revision-safe retry clearing.
- Modify `Packages/CoreFlow/Tests/CoreFlowTests/CardEditingStoreTests.swift`: cover staged removal, restore, replacement, failure, retry, hydrate, and newer-intent preservation.
- Modify `ArcNote/CardEditor/CardMetadataPresentation.swift`: expose one shared compact tag-capsule surface modifier.
- Modify `ArcNote/CardEditor/CardEditorMetadataRows.swift`: render the Add Tag capsule or inline native `TextField` in the same location.
- Modify `ArcNote/CardEditor/CardEditorShell.swift`: accept parent-owned tag entry state, render a semantic leading control, remove inline Save, and make the DEBUG fixture exercise production components.
- Create `ArcNote/CardEditor/CardEditorBackgroundActions.swift`: own native replace/remove/restore confirmation-dialog presentation.
- Modify `ArcNote.xcodeproj/project.pbxproj`: add `CardEditorBackgroundActions.swift` to the CardEditor group and ArcNote Sources.
- Modify `ArcNote/NewNoteView.swift`: orchestrate tag completion, meaningful dirty state, exact save/close, staged background actions, and recoverable messages.
- Modify `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift`: protect shared inline-tag, semantic-leading-control, fixture, and background-dialog source boundaries.
- Modify `Packages/CoreFlow/Tests/CoreFlowTests/NewNoteViewSourceContractTests.swift`: replace auto-save-on-Back and no-remove contracts with exact two-step commit and staged background contracts.
- Modify `ArcNoteUITests/ArcNoteUITests.swift`: exercise inline tag completion, leading state transitions, retry behavior, add/replace/remove/restore background journeys, and the new two-tap save/close helper.

### Task 1: Shared Tag Normalization

**Files:**

- Create: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditingTagTests.swift`
- Modify: `Packages/CoreFlow/Sources/CoreFlow/CardEditingModels.swift:13-96`

**Interfaces:**

- Consumes: `String`, `[String]`, and the existing ten-tag rule.
- Produces: `CardEditingTag.maximumCount`, `CardEditingTag.normalized(_:)`, `CardEditingTag.normalize(_:)`, and `CardEditingTag.appending(_:to:)` for Tasks 3 and 5.

- [ ] **Step 1: Write failing shared tag tests**

Create `CardEditingTagTests.swift`:

```swift
import XCTest
@testable import CoreFlow

final class CardEditingTagTests: XCTestCase {
    func testNormalizedCandidateTrimsAndRemovesLeadingHashes() {
        XCTAssertEqual(CardEditingTag.normalized("  ##  idea  "), "idea")
        XCTAssertEqual(CardEditingTag.normalized("research"), "research")
        XCTAssertNil(CardEditingTag.normalized("  \n "))
        XCTAssertNil(CardEditingTag.normalized(" ###  "))
    }

    func testNormalizeDeduplicatesInOrderAndCapsAtTen() {
        let values = [
            "#one", " one ", "two", "three", "four", "five", "six",
            "seven", "eight", "nine", "ten", "eleven",
        ]

        XCTAssertEqual(
            CardEditingTag.normalize(values),
            ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        )
    }

    func testAppendingReturnsOnlyARealNewCandidate() {
        XCTAssertEqual(
            CardEditingTag.appending(" ## work ", to: ["idea"]),
            ["idea", "work"]
        )
        XCTAssertNil(CardEditingTag.appending("#idea", to: ["idea"]))
        XCTAssertNil(CardEditingTag.appending("###", to: ["idea"]))
        XCTAssertNil(
            CardEditingTag.appending(
                "eleven",
                to: (1...CardEditingTag.maximumCount).map(String.init)
            )
        )
    }

    func testDraftUsesTheSharedListNormalizer() {
        let draft = CardEditingDraft(
            title: nil,
            content: "Body",
            tags: ["## idea ", "idea", "work"],
            isPublic: false
        )

        XCTAssertEqual(draft.tags, ["idea", "work"])
    }
}
```

- [ ] **Step 2: Run the tests and verify the shared API is missing**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditingTagTests
```

Expected: compilation FAIL with `cannot find 'CardEditingTag' in scope`.

- [ ] **Step 3: Expose one normalization implementation and route drafts through it**

Add above `CardEditingDraft` in `CardEditingModels.swift`:

```swift
public enum CardEditingTag {
    public static let maximumCount = 10

    public static func normalized(_ value: String) -> String? {
        let tag = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^#+\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? nil : tag
    }

    public static func normalize(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            guard let tag = normalized(value), seen.insert(tag).inserted else {
                continue
            }
            result.append(tag)
            if result.count == maximumCount { break }
        }
        return result
    }

    public static func appending(
        _ candidate: String,
        to values: [String]
    ) -> [String]? {
        let current = normalize(values)
        guard current.count < maximumCount,
              let tag = normalized(candidate),
              !current.contains(tag) else {
            return nil
        }
        return current + [tag]
    }
}
```

Change the draft initializer to:

```swift
self.tags = CardEditingTag.normalize(tags)
```

Delete the old private `CardEditingDraft.normalize(_:)` method completely.

- [ ] **Step 4: Run focused and existing tag persistence tests**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditingTagTests
swift test --package-path Packages/CoreFlow --filter CardEditingStoreTests.testMetadataUpdateNormalizesTagsWithoutChangingStructuredDocument
swift test --package-path Packages/CoreFlow --filter CardEditingStoreTests.testMetadataRetryPersistsNormalizedTagsAndLatestUpdate
```

Expected: all PASS.

- [ ] **Step 5: Commit the shared rule**

```bash
git add Packages/CoreFlow/Sources/CoreFlow/CardEditingModels.swift Packages/CoreFlow/Tests/CoreFlowTests/CardEditingTagTests.swift
git commit -m "refactor(editor): share tag normalization"
```

### Task 2: Staged Background Intent and Exact Retry

**Files:**

- Modify: `Packages/CoreFlow/Sources/CoreFlow/CardEditingModels.swift:159-177`
- Modify: `Packages/CoreFlow/Sources/CoreFlow/CardEditingStore.swift:6-43,76-110,174-205,239-256,347-431,534-585`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditingStoreTests.swift:62-122,631-760,1450-1626`

**Interfaces:**

- Consumes: `CardEditingImage`, committed `backgroundMediaRef`, and existing `CoreCardEditingServing.replaceBackground/removeBackground` operations.
- Produces: `CardEditingBackgroundIntent`, `CardEditingStore.backgroundIntent`, `stageBackground(_:)`, `stageBackgroundRemoval()`, and `restoreBackground()` for Tasks 5 and 6.

- [ ] **Step 1: Add failing intent, removal, restore, and retry tests**

Add these tests to `CardEditingStoreTests`:

```swift
func testStageBackgroundRemovalDefersDeleteUntilSave() async {
    let service = MockCardEditingService()
    service.removeBackgroundResults = [.success(())]
    let store = CardEditingStore(
        cardID: "ast_1",
        draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
        backgroundMediaRef: "med_existing",
        links: [],
        service: service
    )

    store.stageBackgroundRemoval()

    XCTAssertEqual(store.backgroundIntent, .remove)
    XCTAssertTrue(store.isDirty)
    XCTAssertTrue(service.removeBackgroundRequests.isEmpty)

    XCTAssertTrue(await store.save())
    XCTAssertEqual(service.removeBackgroundRequests, ["ast_1"])
    XCTAssertNil(store.backgroundMediaRef)
    XCTAssertEqual(store.backgroundIntent, .unchanged)
    XCTAssertFalse(store.isDirty)
}

func testRemovalWithoutCommittedBackgroundCancelsLocalReplacement() {
    let service = MockCardEditingService()
    let store = CardEditingStore(
        cardID: "ast_1",
        draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
        backgroundMediaRef: nil,
        links: [],
        service: service
    )
    XCTAssertTrue(store.stageBackground(validImage))

    store.stageBackgroundRemoval()

    XCTAssertEqual(store.backgroundIntent, .unchanged)
    XCTAssertFalse(store.isDirty)
    XCTAssertTrue(service.events.isEmpty)
}

func testRestoreClearsStagedMutationAndKeepsCommittedReference() {
    let service = MockCardEditingService()
    let store = CardEditingStore(
        cardID: "ast_1",
        draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
        backgroundMediaRef: "med_existing",
        links: [],
        service: service
    )
    store.stageBackgroundRemoval()

    store.restoreBackground()

    XCTAssertEqual(store.backgroundIntent, .unchanged)
    XCTAssertEqual(store.backgroundMediaRef, "med_existing")
    XCTAssertFalse(store.isDirty)
    XCTAssertTrue(service.events.isEmpty)
}

func testReplacementSupersedesStagedRemoval() {
    let service = MockCardEditingService()
    let store = CardEditingStore(
        cardID: "ast_1",
        draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
        backgroundMediaRef: "med_existing",
        links: [],
        service: service
    )
    store.stageBackgroundRemoval()

    XCTAssertTrue(store.stageBackground(validImage))

    XCTAssertEqual(store.backgroundIntent, .replace(validImage))
    XCTAssertEqual(store.backgroundMediaRef, "med_existing")
    XCTAssertTrue(service.events.isEmpty)
}

func testRemovalFailureKeepsCommittedReferenceAndRemovalIntent() async {
    let service = MockCardEditingService()
    service.removeBackgroundResults = [
        .failure(.transport(code: "remove_failed")),
        .success(()),
    ]
    let store = CardEditingStore(
        cardID: "ast_1",
        draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
        backgroundMediaRef: "med_existing",
        links: [],
        service: service
    )
    store.stageBackgroundRemoval()

    XCTAssertFalse(await store.save())
    XCTAssertEqual(store.backgroundMediaRef, "med_existing")
    XCTAssertEqual(store.backgroundIntent, .remove)
    XCTAssertEqual(store.failureStage, .removingBackground)

    XCTAssertTrue(await store.retry())
    XCTAssertNil(store.backgroundMediaRef)
    XCTAssertEqual(store.backgroundIntent, .unchanged)
}

func testRestoreAfterFailedRemovalAbandonsOnlyBackgroundRetry() async {
    let service = MockCardEditingService()
    service.removeBackgroundResults = [
        .failure(.transport(code: "remove_failed")),
    ]
    let store = CardEditingStore(
        cardID: "ast_1",
        draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
        backgroundMediaRef: "med_existing",
        links: [],
        service: service
    )
    store.stageBackgroundRemoval()
    XCTAssertFalse(await store.save())

    store.restoreBackground()

    XCTAssertEqual(store.backgroundIntent, .unchanged)
    XCTAssertEqual(store.backgroundMediaRef, "med_existing")
    XCTAssertNil(store.failureStage)
    XCTAssertEqual(store.phase, .ready)
    XCTAssertFalse(store.isDirty)
    XCTAssertEqual(service.removeBackgroundRequests, ["ast_1"])
}

func testRemovalRetryPreservesNewerReplacementIntent() async {
    let replacement = CardEditingImage(
        data: Data("replacement".utf8),
        filename: "replacement.png",
        mimeType: "image/png"
    )
    let service = MockCardEditingService()
    service.removeBackgroundResults = [
        .failure(.transport(code: "remove_failed")),
        .success(()),
    ]
    let store = CardEditingStore(
        cardID: "ast_1",
        draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
        backgroundMediaRef: "med_existing",
        links: [],
        service: service
    )
    store.stageBackgroundRemoval()
    XCTAssertFalse(await store.save())
    XCTAssertTrue(store.stageBackground(replacement))

    XCTAssertFalse(await store.retry())

    XCTAssertNil(store.backgroundMediaRef)
    XCTAssertEqual(store.backgroundIntent, .replace(replacement))
    XCTAssertTrue(store.isDirty)
}
```

- [ ] **Step 2: Run the new background tests and verify the staged API is missing**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditingStoreTests.testStageBackgroundRemovalDefersDeleteUntilSave
```

Expected: compilation FAIL because `backgroundIntent` and `stageBackgroundRemoval()` do not exist.

- [ ] **Step 3: Add the intent model and replace pending replacement storage**

Add after `CardEditingImage` in `CardEditingModels.swift`:

```swift
public enum CardEditingBackgroundIntent: Equatable, Sendable {
    case unchanged
    case replace(CardEditingImage)
    case remove
}
```

In `CardEditingStore`, replace `pendingBackground` with:

```swift
@Published public private(set) var backgroundIntent:
    CardEditingBackgroundIntent = .unchanged

public var pendingBackground: CardEditingImage? {
    guard case let .replace(image) = backgroundIntent else { return nil }
    return image
}
```

`pendingBackground` remains a read-only computed compatibility view while the native consumer is migrated in Task 6; it is no longer independent storage and cannot represent removal.

Replace dirty computation with:

```swift
public var isDirty: Bool {
    isDraftDirty || backgroundIntent != .unchanged
}
```

Replace `stageBackground(_:)` and the public immediate `removeBackground()` with:

```swift
@discardableResult
public func stageBackground(_ image: CardEditingImage) -> Bool {
    guard image.isValidBackground else {
        if !isBusy {
            fail(with: .invalidDraft(code: "invalid_background_image"))
        }
        return false
    }
    backgroundIntent = .replace(image)
    if !isBusy, failureContext?.retryOperation == nil {
        clearFailure()
        phase = .ready
    }
    return true
}

public func stageBackgroundRemoval() {
    guard backgroundMediaRef != nil else {
        restoreBackground()
        return
    }
    backgroundIntent = .remove
    if !isBusy, failureContext?.retryOperation == nil {
        clearFailure()
        phase = .ready
    }
}

public func restoreBackground() {
    backgroundIntent = .unchanged
    if failureStage == .replacingBackground || failureStage == .removingBackground {
        clearFailure()
    }
    if !isBusy, failureContext == nil {
        phase = .ready
    }
}
```

In `save()` and `retryDraft(_:)`, replace the `pendingBackground` branches with:

```swift
if backgroundIntent != .unchanged {
    guard await persistBackgroundIntent() else { return false }
}
```

Replace `persistPendingBackground()` with:

```swift
private func persistBackgroundIntent() async -> Bool {
    let intent = backgroundIntent
    guard let cardID else {
        fail(with: .transport(code: "card_id_missing"))
        return false
    }
    switch intent {
    case .unchanged:
        return true
    case let .replace(image):
        return await persistBackground(
            cardID: cardID,
            image: image,
            capturedIntent: intent
        )
    case .remove:
        return await persistBackgroundRemoval(
            cardID: cardID,
            capturedIntent: intent
        )
    }
}
```

Change replacement persistence to clear only the captured intent:

```swift
private func persistBackground(
    cardID: String,
    image: CardEditingImage,
    capturedIntent: CardEditingBackgroundIntent
) async -> Bool {
    phase = .updatingBackground
    do {
        let mediaRef = try await service.replaceBackground(
            cardID: cardID,
            image: image
        )
        backgroundMediaRef = mediaRef
        if backgroundIntent == capturedIntent {
            backgroundIntent = .unchanged
        }
        clearFailure()
        phase = .ready
        return true
    } catch {
        fail(
            with: Self.mapError(error),
            stage: .replacingBackground,
            retryOperation: .replaceBackground(cardID: cardID, image: image)
        )
        return false
    }
}
```

Change removal persistence symmetrically:

```swift
private func persistBackgroundRemoval(
    cardID: String,
    capturedIntent: CardEditingBackgroundIntent
) async -> Bool {
    phase = .updatingBackground
    do {
        try await service.removeBackground(cardID: cardID)
        backgroundMediaRef = nil
        if backgroundIntent == capturedIntent {
            backgroundIntent = .unchanged
        }
        clearFailure()
        phase = .ready
        return true
    } catch {
        fail(
            with: Self.mapError(error),
            stage: .removingBackground,
            retryOperation: .removeBackground(cardID: cardID)
        )
        return false
    }
}
```

Make exact retry use captured intents without clearing newer intent:

```swift
private func retryBackground(cardID: String, image: CardEditingImage) async -> Bool {
    guard let operationID = beginOperation() else { return false }
    defer { endOperation(operationID) }
    clearFailure()
    guard await persistBackground(
        cardID: cardID,
        image: image,
        capturedIntent: .replace(image)
    ) else {
        return false
    }
    phase = .ready
    return !isDirty
}

private func retryBackgroundRemoval(cardID: String) async -> Bool {
    guard let operationID = beginOperation() else { return false }
    defer { endOperation(operationID) }
    clearFailure()
    guard await persistBackgroundRemoval(
        cardID: cardID,
        capturedIntent: .remove
    ) else {
        return false
    }
    phase = .ready
    return !isDirty
}
```

In `hydrate`, leave `backgroundIntent` untouched and replace the existing replacement-only failure branch with:

```swift
if let failureContext,
   backgroundIntent != .unchanged,
   failureContext.stage == .replacingBackground
        || failureContext.stage == .removingBackground {
    phase = .failed(failureContext.error)
} else {
    clearFailure()
    phase = .ready
}
```

- [ ] **Step 4: Migrate existing replacement assertions to the intent model**

In `CardEditingStoreTests.swift`, make these exact assertion substitutions:

```swift
XCTAssertEqual(store.pendingBackground, validImage)
```

becomes:

```swift
XCTAssertEqual(store.backgroundIntent, .replace(validImage))
```

and:

```swift
XCTAssertNil(store.pendingBackground)
```

becomes:

```swift
XCTAssertEqual(store.backgroundIntent, .unchanged)
```

Delete the superseded `testRemoveBackgroundFromUnsavedCardClearsOnlyStagedPreview` and `testRemoveBackgroundFailureKeepsCommittedRefUntilRetrySucceeds` methods after adding their staged replacements from Step 1; do not keep duplicate test names or any call to the retired async `removeBackground()` API.

- [ ] **Step 5: Run the entire store suite**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditingStoreTests
```

Expected: PASS, including captured replacement/removal retry and hydrate concurrency tests.

- [ ] **Step 6: Commit staged background semantics**

```bash
git add Packages/CoreFlow/Sources/CoreFlow/CardEditingModels.swift Packages/CoreFlow/Sources/CoreFlow/CardEditingStore.swift Packages/CoreFlow/Tests/CoreFlowTests/CardEditingStoreTests.swift
git commit -m "feat(editor): stage background removal intent"
```

### Task 3: Inline Native Tag Entry

**Files:**

- Modify: `ArcNote/CardEditor/CardMetadataPresentation.swift:3-46`
- Modify: `ArcNote/CardEditor/CardEditorMetadataRows.swift:22-71`
- Modify: `ArcNote/CardEditor/CardEditorShell.swift:8-58,72-79,249-520`
- Modify: `ArcNote/NewNoteView.swift:219-220,275-293,377-390,621-628`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift:304-380`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/NewNoteViewSourceContractTests.swift:137-150`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift:377-389`

**Interfaces:**

- Consumes: Task 1's `CardEditingTag.appending(_:to:)` and existing metadata update callback.
- Produces: session-owned `isAddingTag`/`tagInput`, `beginTagEntry()`, `completeTagEntry()`, and a shared production/fixture inline field for Task 5.

- [ ] **Step 1: Replace old source contracts with failing inline-entry contracts**

Add to `CardEditorShellSourceContractTests`:

```swift
func testTagRowReplacesAddCapsuleWithFocusedInlineField() throws {
    let metadata = try source(
        at: "ArcNote/CardEditor/CardEditorMetadataRows.swift"
    )
    let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")

    XCTAssertTrue(metadata.contains("let isAddingTag: Bool"))
    XCTAssertTrue(metadata.contains("@Binding var tagInput: String"))
    XCTAssertTrue(metadata.contains("@FocusState private var isTagInputFocused"))
    XCTAssertTrue(metadata.contains("if isAddingTag"))
    XCTAssertTrue(metadata.contains("TextField(\"Tag\", text: $tagInput)"))
    XCTAssertTrue(metadata.contains(".submitLabel(.done)"))
    XCTAssertTrue(metadata.contains(".onSubmit(onCompleteTag)"))
    XCTAssertTrue(metadata.contains("guard !isFocused, isAddingTag else { return }"))
    XCTAssertTrue(metadata.contains(".accessibilityIdentifier(\"cardEditorTagInput\")"))
    XCTAssertTrue(metadata.contains(".accessibilityIdentifier(\"cardEditorAddTag\")"))
    XCTAssertTrue(metadata.contains("cardMetadataTagCapsuleStyle"))
    XCTAssertTrue(shell.contains("TapGesture().onEnded"))
    XCTAssertTrue(shell.contains("guard isAddingTag else { return }"))
    XCTAssertTrue(shell.contains("onCompleteTag()"))
    XCTAssertFalse(shell.contains("CardEditorNativeTagInputFixture"))
    XCTAssertFalse(shell.contains("cardEditorNativeTagInput"))
}
```

Add to `NewNoteViewSourceContractTests`:

```swift
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
```

Delete the old source assertions that require `leadingSystemImage: "plus"` unconditionally; require it only in the `else` branch that renders Add Tag.

- [ ] **Step 2: Run source contracts and verify they fail against alert-based entry**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests.testTagRowReplacesAddCapsuleWithFocusedInlineField
swift test --package-path Packages/CoreFlow --filter NewNoteViewSourceContractTests.testTagEntryIsSessionOwnedAndNeverUsesAnAlert
```

Expected: both FAIL because the row has no field/focus state and production still presents an alert.

- [ ] **Step 3: Share the compact capsule surface**

In `CardMetadataPresentation.swift`, replace the private width constant and repeated final styling with:

```swift
let cardMetadataMaximumReadableTagWidth: CGFloat = 280

struct CardMetadataTagCapsuleStyle: ViewModifier {
    let maximumWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: maximumWidth)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(red: 0.2, green: 0.1, blue: 0.3))
            )
    }
}

extension View {
    func cardMetadataTagCapsuleStyle(
        maximumWidth: CGFloat = cardMetadataMaximumReadableTagWidth
    ) -> some View {
        modifier(CardMetadataTagCapsuleStyle(maximumWidth: maximumWidth))
    }
}
```

Apply `.cardMetadataTagCapsuleStyle()` to the existing capsule `HStack` after removing its duplicated foreground, padding, frame, and background modifiers.

- [ ] **Step 4: Replace `CardEditorTagRow` with the inline-field variant**

Use this complete `CardEditorTagRow` implementation:

```swift
struct CardEditorTagRow: View {
    let tags: [String]
    let isEditable: Bool
    let isAddingTag: Bool
    @Binding var tagInput: String
    let onBeginTag: () -> Void
    let onCompleteTag: () -> Void
    let onRemove: (String) -> Void

    @FocusState private var isTagInputFocused: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        onRemove(tag)
                    } label: {
                        CardMetadataTagCapsule(
                            tag: tag,
                            showsRemoveIndicator: true
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .disabled(!isEditable)
                    .accessibilityLabel(
                        isEditable ? "Remove tag \(tag)" : "Tag \(tag)"
                    )
                    .accessibilityIdentifier(
                        "cardEditorTag.\(accessibilityComponent(tag))"
                    )
                }

                if isAddingTag {
                    TextField("Tag", text: $tagInput)
                        .font(.system(size: 12, weight: .medium))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isTagInputFocused)
                        .onSubmit(onCompleteTag)
                        .onChange(of: isTagInputFocused) { isFocused in
                            guard !isFocused, isAddingTag else { return }
                            onCompleteTag()
                        }
                        .frame(width: 96)
                        .cardMetadataTagCapsuleStyle(maximumWidth: 120)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Tag")
                        .accessibilityIdentifier("cardEditorTagInput")
                        .onAppear {
                            DispatchQueue.main.async {
                                isTagInputFocused = true
                            }
                        }
                } else {
                    Button(action: onBeginTag) {
                        CardMetadataTagCapsule(
                            tag: "Tag",
                            showsRemoveIndicator: false,
                            leadingSystemImage: "plus"
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .disabled(
                        !isEditable || tags.count >= CardEditingTag.maximumCount
                    )
                    .accessibilityLabel("Add Tag")
                    .accessibilityHint("Adds a tag to this note")
                    .accessibilityIdentifier("cardEditorAddTag")
                }
            }
            .padding(.horizontal, 1)
        }
    }
}
```

Add `import CoreFlow` to `CardEditorMetadataRows.swift`.

- [ ] **Step 5: Thread parent-owned state through shell, production, and fixture**

Change the shell API from `onAddTag: () -> Void` to:

```swift
let isAddingTag: Bool
@Binding var tagInput: String
let onBeginTag: () -> Void
let onCompleteTag: () -> Void
```

Add the corresponding initializer inputs and assignments:

```swift
isAddingTag: Bool,
tagInput: Binding<String>,
onBeginTag: @escaping () -> Void,
onCompleteTag: @escaping () -> Void,
```

```swift
self.isAddingTag = isAddingTag
_tagInput = tagInput
self.onBeginTag = onBeginTag
self.onCompleteTag = onCompleteTag
```

Pass those values into `CardEditorTagRow`. In `CardEditorSessionView`, replace `showTagEditor` with:

```swift
@State private var isAddingTag = false
@State private var tagInput = ""
```

Remove the complete Add Tag alert. Add:

```swift
private func beginTagEntry() {
    guard bodyModel.canMutate, !isBusy else { return }
    bodyModel.dismissKeyboard()
    tagInput = ""
    isAddingTag = true
}

private func completeTagEntry() {
    guard isAddingTag else { return }
    let candidate = tagInput
    isAddingTag = false
    tagInput = ""
    guard let tags = CardEditingTag.appending(
        candidate,
        to: editingStore.draft.tags
    ) else {
        return
    }
    updateMetadata(tags: tags)
}
```

Wire `isAddingTag`, `$tagInput`, `beginTagEntry`, and `completeTagEntry` into `CardEditorShell`.

Attach this simultaneous gesture to the `CardEditorBackground` body surface—not to the entire shell, where it could consume the Add Tag tap—so tapping the writing area always commits an active tag before body focus changes:

```swift
.simultaneousGesture(
    TapGesture().onEnded {
        guard isAddingTag else { return }
        onCompleteTag()
    }
)
```

In the DEBUG fixture, delete `isAddingTag` sheet state and `CardEditorNativeTagInputFixture`; use the same shell bindings and normalize fixture tags with `CardEditingTag.appending(_:to:)`. Add `import CoreFlow` to `CardEditorShell.swift` because the fixture now uses the shared rule.

- [ ] **Step 6: Run source tests and a failing-then-passing native UI interaction**

Replace `testNativeTagInputDoesNotShowBodyFormattingBar` with:

```swift
func testInlineTagEntryCommitsOnReturnWithoutBodyFormattingBar() {
    launchCardEditorFixture(mode: "empty")

    waitForButton("cardEditorAddTag").tap()
    let input = waitFor("cardEditorTagInput")
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
    XCTAssertFalse(app.descendants(matching: .any)["cardEditorFormattingBar"].exists)
    XCTAssertFalse(app.buttons["cardEditorAddTag"].exists)

    input.typeText("## native-tag\n")

    waitForMissing("cardEditorTagInput")
    XCTAssertTrue(waitFor("cardEditorTag.native-tag").exists)
    XCTAssertTrue(waitForButton("cardEditorAddTag").exists)
}

func testInlineTagEntryCommitsOnFocusLossAndRejectsBlankInput() {
    launchCardEditorFixture(mode: "empty")

    waitForButton("cardEditorAddTag").tap()
    waitFor("cardEditorTagInput").typeText("focus-tag")
    let body = waitFor("cardEditorBodyWebView")
    body.coordinate(
        withNormalizedOffset: CGVector(dx: 0.25, dy: 0.08)
    ).tap()
    XCTAssertTrue(waitFor("cardEditorTag.focus-tag").exists)

    let tags = app.descendants(matching: .any).matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "cardEditorTag.")
    )
    let countBeforeBlank = tags.count
    waitForButton("cardEditorAddTag").tap()
    waitFor("cardEditorTagInput").typeText("### ")
    body.coordinate(
        withNormalizedOffset: CGVector(dx: 0.25, dy: 0.08)
    ).tap()
    XCTAssertEqual(tags.count, countBeforeBlank)
    XCTAssertTrue(waitForButton("cardEditorAddTag").exists)
}
```

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests.testTagRowReplacesAddCapsuleWithFocusedInlineField
swift test --package-path Packages/CoreFlow --filter NewNoteViewSourceContractTests.testTagEntryIsSessionOwnedAndNeverUsesAnAlert
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-editor-tag-tests -parallel-testing-enabled NO -only-testing:ArcNoteUITests/ArcNoteUITests/testInlineTagEntryCommitsOnReturnWithoutBodyFormattingBar -only-testing:ArcNoteUITests/ArcNoteUITests/testInlineTagEntryCommitsOnFocusLossAndRejectsBlankInput
```

Expected: source and UI tests PASS.

- [ ] **Step 7: Commit inline tag entry**

```bash
git add ArcNote/CardEditor/CardMetadataPresentation.swift ArcNote/CardEditor/CardEditorMetadataRows.swift ArcNote/CardEditor/CardEditorShell.swift ArcNote/NewNoteView.swift Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift Packages/CoreFlow/Tests/CoreFlowTests/NewNoteViewSourceContractTests.swift ArcNoteUITests/ArcNoteUITests.swift
git commit -m "feat(editor): edit tags inline"
```

### Task 4: Semantic Upper-Left Control

**Files:**

- Modify: `ArcNote/CardEditor/CardEditorShell.swift:4-58,87-119,132-202,249-390`
- Modify: `ArcNote/NewNoteView.swift:275-293,420-423,485-498`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift:181-204,643-701`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift:19-65,161-229,418-460,585-596,5085-5093`

**Interfaces:**

- Consumes: session-derived semantic state supplied by Task 5.
- Produces: `CardEditorLeadingControlState` and `CardEditorShell.leadingControlState/onLeadingControl`, with stable accessibility identifier `cardEditorLeadingAction`.

- [ ] **Step 1: Write a failing semantic-control source contract**

Add to `CardEditorShellSourceContractTests`:

```swift
func testShellUsesOneSemanticLeadingControlWithoutInlineSave() throws {
    let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")

    for state in ["case back", "case save", "case saving", "case retry", "case readOnly", "case bridgeFailed"] {
        XCTAssertTrue(shell.contains(state), "Missing leading state: \(state)")
    }
    XCTAssertTrue(shell.contains("let leadingControlState: CardEditorLeadingControlState"))
    XCTAssertTrue(shell.contains("let onLeadingControl: () -> Void"))
    XCTAssertTrue(shell.contains("? \"checkmark\""))
    XCTAssertTrue(shell.contains("ProgressView()"))
    XCTAssertTrue(shell.contains("\"Close note\""))
    XCTAssertTrue(shell.contains("\"Save note\""))
    XCTAssertTrue(shell.contains("\"Retry saving note\""))
    XCTAssertTrue(shell.contains(".accessibilityIdentifier(\"cardEditorLeadingAction\")"))
    XCTAssertFalse(shell.contains("inlineSaveAction"))
    XCTAssertFalse(shell.contains("cardEditorSave"))
    XCTAssertFalse(shell.contains("saveActionTitle"))
    XCTAssertFalse(shell.contains("let onSave:"))
}
```

- [ ] **Step 2: Run the source contract and verify the old Back/inline Save split fails**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests.testShellUsesOneSemanticLeadingControlWithoutInlineSave
```

Expected: FAIL because the shell still declares `onBack`, optional `onSave`, and `inlineSaveAction`.

- [ ] **Step 3: Define and render the semantic leading control**

Add near the top of `CardEditorShell.swift`:

```swift
enum CardEditorLeadingControlState: Equatable {
    case back
    case save
    case saving
    case retry
    case readOnly
    case bridgeFailed

    var accessibilityLabel: String {
        switch self {
        case .back, .readOnly, .bridgeFailed:
            return "Close note"
        case .save:
            return "Save note"
        case .saving:
            return "Saving note"
        case .retry:
            return "Retry saving note"
        }
    }
}
```

Replace shell inputs `isSaving`, `saveActionTitle`, `onBack`, and `onSave` with:

```swift
let leadingControlState: CardEditorLeadingControlState
let onLeadingControl: () -> Void
```

Delete `inlineSaveAction` and its conditional call. Change `CardEditorFloatingControls` to accept the same state/action and render:

```swift
Button(action: onLeadingControl) {
    Group {
        if leadingControlState == .saving {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        } else {
            Image(
                systemName: leadingControlState == .save
                    || leadingControlState == .retry
                    ? "checkmark"
                    : "chevron.left"
            )
            .font(.system(size: 17, weight: .semibold))
        }
    }
    .frame(width: 44, height: 44)
    .background(controlBackground)
    .clipShape(Circle())
    .contentShape(Circle())
}
.buttonStyle(.plain)
.foregroundStyle(.white)
.frame(maxWidth: .infinity, alignment: .leading)
.disabled(leadingControlState == .saving)
.accessibilityLabel(leadingControlState.accessibilityLabel)
.accessibilityIdentifier("cardEditorLeadingAction")
.accessibilitySortPriority(3)
```

Keep this task independently buildable by adapting the production shell call before Task 5 introduces meaningful dirty state:

```swift
leadingControlState: isSaving
    ? .saving
    : (retryHandler == nil ? .back : .retry),
onLeadingControl: retryHandler ?? handleBack,
```

This adapter preserves the existing lifecycle for one commit while removing the body Save button. Task 5 replaces it with `leadingControlState` and `handleLeadingControl` derived from real session state.

- [ ] **Step 4: Make the DEBUG fixture model real clean/dirty transitions**

Extend `CardEditorShellFixtureActionRouter` with:

```swift
@Published var hasPendingChanges = false

func markDirty() {
    hasPendingChanges = true
}

func markSaved() {
    hasPendingChanges = false
}
```

Call `actionRouter.markDirty()` from the fixture's BlockNote `onDocumentChanged`, tag add/remove, privacy toggle, and background mutation closures. Derive fixture state as `.readOnly` for blocked mode, `.bridgeFailed` for bridge-failure mode, `.save` when `hasPendingChanges`, otherwise `.back`. The fixture leading action calls `markSaved()` for `.save/.retry` and remains a no-op for `.back/.readOnly/.bridgeFailed`.

- [ ] **Step 5: Update fixture UI tests to assert the same control changes in place**

Add:

```swift
func testCardEditorLeadingControlChangesFromBackToSaveAndBack() {
    launchCardEditorFixture(mode: "empty")

    let leading = waitForButton("cardEditorLeadingAction")
    XCTAssertEqual(leading.label, "Close note")
    waitForButton("cardEditorPrivacyButton").tap()
    waitForLabel("cardEditorLeadingAction", expected: "Save note")

    leading.tap()

    waitForLabel("cardEditorLeadingAction", expected: "Close note")
    XCTAssertFalse(app.descendants(matching: .any)["cardEditorSave"].exists)
}
```

Replace all fixture references to `cardEditorFloatingBack` with `cardEditorLeadingAction`. Replace fixture assertions for `cardEditorSave` with the expected leading label for the mode. Change `launchCardEditorFixture` to wait for enabled `cardEditorLeadingAction` instead of `cardEditorSave`.

- [ ] **Step 6: Run shell contracts and focused fixture tests**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-editor-leading-tests -parallel-testing-enabled NO -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorLeadingControlChangesFromBackToSaveAndBack -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorShellCompatibilityBlockIsReadOnlyAndCannotSave -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorBridgeFailureFallbackRetriesIntoFreshWebView
```

Expected: PASS; no `cardEditorSave` element exists.

- [ ] **Step 7: Commit the semantic shell control**

```bash
git add ArcNote/CardEditor/CardEditorShell.swift ArcNote/NewNoteView.swift Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift ArcNoteUITests/ArcNoteUITests.swift
git commit -m "feat(editor): unify save and back control"
```

### Task 5: Exact Save-Then-Exit Session State

**Files:**

- Modify: `ArcNote/NewNoteView.swift:233-235,275-293,403-467,485-600,621-636,638-695,845-988,1001-1006`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/NewNoteViewSourceContractTests.swift:63-121,375-462`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift:3604-3650,3652-3705,3929-4002,5686-5767`

**Interfaces:**

- Consumes: Task 1 tag candidate API, Task 2 store dirty/background intent, Task 3 tag completion, Task 4 semantic leading state, and the existing exact BlockNote snapshot bridge.
- Produces: `leadingControlState`, `handleLeadingControl()`, `saveCurrentSnapshot()`, `verifyCurrentSnapshotAndDismiss()`, and two-step UI-test helpers.

- [ ] **Step 1: Replace auto-save-on-Back contracts with failing two-step contracts**

Replace `testBackSavesOneExactSnapshotAndDismissesOnlyExactCleanCommit` with:

```swift
func testLeadingSaveCommitsWithoutDismissAndBackOnlyVerifiesCleanSnapshot() throws {
    let source = try Self.newNoteSource()
    let leading = try XCTUnwrap(
        Self.functionBody(in: source, signature: "func handleLeadingControl()")
    )
    XCTAssertTrue(leading.contains("case .save, .retry:"))
    XCTAssertTrue(leading.contains("saveCurrentSnapshot()"))
    XCTAssertTrue(leading.contains("case .back:"))
    XCTAssertTrue(leading.contains("verifyCurrentSnapshotAndDismiss()"))

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
    XCTAssertTrue(close.contains("snapshotMatchesCommittedBaseline(snapshot)"))
    XCTAssertTrue(close.contains("dismiss()"))
    XCTAssertFalse(close.contains("editingStore.save()"))
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
```

Replace the old retry-dispatch contract with:

```swift
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
```

- [ ] **Step 2: Run the new contracts and verify the old `thenDismiss` flow fails**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter NewNoteViewSourceContractTests.testLeadingSaveCommitsWithoutDismissAndBackOnlyVerifiesCleanSnapshot
swift test --package-path Packages/CoreFlow --filter NewNoteViewSourceContractTests.testLeadingStateUsesMeaningfulDraftAndPendingInlineTag
swift test --package-path Packages/CoreFlow --filter NewNoteViewSourceContractTests.testOnlyCommitFailureOwnsTheLeadingRetryState
swift test --package-path Packages/CoreFlow --filter NewNoteViewSourceContractTests.testModalEditorActionsFinishInlineTagEntryFirst
```

Expected: FAIL because production still calls `saveCurrentSnapshot(thenDismiss: true)` from Back.

- [ ] **Step 3: Derive semantic state without a parallel dirty flag**

Replace `retryAction` with:

```swift
@State private var hasSaveFailure = false
```

Add:

```swift
private var hasPendingInlineTagCandidate: Bool {
    isAddingTag
        && CardEditingTag.appending(
            tagInput,
            to: editingStore.draft.tags
        ) != nil
}

private var isUntouchedNewDraft: Bool {
    editingStore.cardID == nil
        && seed.isNew
        && editingStore.bodyRevision == seed.revision
        && editingStore.draft.content
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && editingStore.draft.tags.isEmpty
        && editingStore.draft.isPublic == seed.initialIsPublic
        && editingStore.backgroundIntent == .unchanged
        && editingStore.backgroundMediaRef == nil
}

private var hasPendingCommit: Bool {
    if hasPendingInlineTagCandidate { return true }
    if editingStore.cardID != nil { return editingStore.isDirty }
    return !isUntouchedNewDraft
}

private var leadingControlState: CardEditorLeadingControlState {
    if isSaving { return .saving }
    if bodyModel.compatibilityNotice != nil { return .readOnly }
    if bodyModel.bridgeFailureNotice != nil { return .bridgeFailed }
    if hasSaveFailure { return .retry }
    return hasPendingCommit ? .save : .back
}
```

Wire `leadingControlState` and `handleLeadingControl` into `CardEditorShell`.

- [ ] **Step 4: Split leading dispatch, save, and close verification**

Add:

```swift
private enum CardEditorCommitOutcome {
    case clean
    case pendingNewerChanges
    case failed
}
```

Implement dispatch:

```swift
private func handleLeadingControl() {
    guard !isBusy else { return }
    switch leadingControlState {
    case .save, .retry:
        saveCurrentSnapshot()
    case .back:
        verifyCurrentSnapshotAndDismiss()
    case .readOnly:
        dismiss()
    case .bridgeFailed:
        showCloseWithoutSavingConfirmation = true
    case .saving:
        break
    }
}
```

Replace `saveCurrentSnapshot(thenDismiss:)` with:

```swift
private func saveCurrentSnapshot() {
    guard !isSaving else { return }
    completeTagEntry()
    isSaving = true
    hasSaveFailure = false
    saveMessage = nil

    Task {
        defer { isSaving = false }
        do {
            let snapshot = try await applyCurrentSnapshot()
            let didRecover = await recoverFailedDraftOperationIfNeeded()
            let didSave = didRecover ? await editingStore.save() : false
            notifyCreationIfNeeded()

            switch classifyCommit(snapshot: snapshot, didSave: didSave) {
            case .clean:
                saveMessage = nil
                hasSaveFailure = false
            case .pendingNewerChanges:
                saveMessage = nil
                hasSaveFailure = false
            case .failed:
                saveMessage = "Couldn't save this note. Retry when ready."
                hasSaveFailure = true
            }
        } catch CardEditorBodyError.compatibilityBlocked {
            dismiss()
        } catch {
            saveMessage = "Couldn't take a safe editor snapshot. Retry."
            hasSaveFailure = true
        }
    }
}
```

Add exact classification:

```swift
private func classifyCommit(
    snapshot: BlockNoteSnapshot,
    didSave: Bool
) -> CardEditorCommitOutcome {
    let exactRevision = editingStore.lastCommittedBodyRevision == snapshot.revision
        && editingStore.bodyRevision == snapshot.revision
        && bodyModel.revision == snapshot.revision
    if didSave, exactRevision, !editingStore.isDirty {
        return .clean
    }
    if editingStore.failureStage == nil,
       editingStore.phase == .ready,
       (editingStore.isDirty || !exactRevision) {
        return .pendingNewerChanges
    }
    return .failed
}
```

Implement clean verification without persistence:

```swift
private func verifyCurrentSnapshotAndDismiss() {
    guard !isSaving else { return }
    completeTagEntry()
    isSaving = true

    Task {
        defer { isSaving = false }
        do {
            let snapshot = try await applyCurrentSnapshot()
            if isUntouchedNewSnapshot(snapshot)
                || snapshotMatchesCommittedBaseline(snapshot) {
                dismiss()
            } else {
                hasSaveFailure = false
                saveMessage = nil
            }
        } catch CardEditorBodyError.compatibilityBlocked {
            dismiss()
        } catch {
            showCloseWithoutSavingConfirmation = true
        }
    }
}

private func snapshotMatchesCommittedBaseline(
    _ snapshot: BlockNoteSnapshot
) -> Bool {
    guard editingStore.cardID != nil,
          let committedDraft = editingStore.lastCommittedDraft,
          let committedRevision = editingStore.lastCommittedBodyRevision else {
        return false
    }
    return !editingStore.isDirty
        && editingStore.draft == committedDraft
        && committedRevision == snapshot.revision
        && editingStore.bodyRevision == snapshot.revision
        && bodyModel.revision == snapshot.revision
}
```

Update `isUntouchedNewSnapshot` to require `editingStore.cardID == nil` and `backgroundIntent == .unchanged`.

Call `completeTagEntry()` before `openCardActions()` and `presentInlineImageSourceOptions()` dismiss the body keyboard. Replace the direct inline-link router assignment with:

```swift
nativeActionRouter.onRequestInlineLink = presentInlineLinkSheet
```

and add:

```swift
private func presentInlineLinkSheet() {
    completeTagEntry()
    bodyModel.dismissKeyboard()
    showInlineLinkSheet = true
}
```

- [ ] **Step 5: Remove contextual actions from the retired global retry channel**

Delete `retryHandler`, `retryCurrentFailure`, and `CardEditorRetryAction`. For link, pin, and persisted-action failures, keep the existing `saveMessage` text but remove every assignment to `.addLink`, `.persistedAction`, and `.store`. Repeating the originating Link/Pin/action route continues through `recoverFailedDraftOperationIfNeeded()` and the store's exact failure context.

Whenever a new metadata/background/body-image action intentionally supersedes a displayed save error, set `hasSaveFailure = false`; do not add a second dirty boolean.

- [ ] **Step 6: Update two-step UI helpers and authenticated journeys**

Add helpers:

```swift
private func saveCardEditor(
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let leading = waitForButton("cardEditorLeadingAction", file: file, line: line)
    XCTAssertTrue(
        ["Save note", "Retry saving note"].contains(leading.label),
        "Expected a commit action, got \(leading.label)",
        file: file,
        line: line
    )
    leading.tap()
    waitForLabel(
        "cardEditorLeadingAction",
        expected: "Close note",
        timeout: 30,
        file: file,
        line: line
    )
}

private func closeNewNoteEditor(
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let leading = waitForButton("cardEditorLeadingAction", file: file, line: line)
    if leading.label != "Close note" {
        saveCardEditor(file: file, line: line)
    }
    waitForButton("cardEditorLeadingAction", file: file, line: line).tap()
    waitForMissing("cardEditorContent", timeout: 30, file: file, line: line)
}
```

Update `testCardEditorSavePersistsNormalizedTagsToGo` to use inline `cardEditorTagInput`, Return submission, `saveCardEditor()`, assert the editor still exists with leading label “Close note”, then tap Back and verify persistence.

Update `testNewCardCreateResponseLossRetryReusesCanonicalCard` so the first `cardEditorLeadingAction` tap fails and remains labeled “Retry saving note”; the retry tap succeeds but stays in the editor labeled “Close note”; a final tap dismisses.

Update `testCardEditorLinkFailureKeepsCanonicalRelationshipList` to assert the leading control remains “Close note” for a contextual link failure, then close normally. Replace every production `cardEditorFloatingBack` and `cardEditorSave` reference with the semantic leading control and appropriate label assertion.

- [ ] **Step 7: Run contracts, store race tests, and focused real UI save journeys**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter NewNoteViewSourceContractTests
swift test --package-path Packages/CoreFlow --filter CardEditingStoreTests.testSaveResponseForOlderRevisionDoesNotClearNewerDirtyDraft
swift test --package-path Packages/CoreFlow --filter CardEditingStoreTests.testOverlappingSaveIsRejectedWhileFirstSaveIsInFlight
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-editor-commit-tests -parallel-testing-enabled NO -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorLeadingControlChangesFromBackToSaveAndBack -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorSavePersistsNormalizedTagsToGo -only-testing:ArcNoteUITests/ArcNoteUITests/testNewCardCreateResponseLossRetryReusesCanonicalCard -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorLinkFailureKeepsCanonicalRelationshipList
```

Expected: PASS. Smoke-dependent tests may skip only when the local Go session is unavailable; they must be rerun in Task 7 with the stack running.

- [ ] **Step 8: Commit two-step session semantics**

```bash
git add ArcNote/NewNoteView.swift Packages/CoreFlow/Tests/CoreFlowTests/NewNoteViewSourceContractTests.swift ArcNoteUITests/ArcNoteUITests.swift
git commit -m "feat(editor): save before explicit exit"
```

### Task 6: Contextual Background Replace, Remove, and Restore

**Files:**

- Create: `ArcNote/CardEditor/CardEditorBackgroundActions.swift`
- Modify: `ArcNote.xcodeproj/project.pbxproj`
- Modify: `ArcNote/CardEditor/CardEditorShell.swift:249-450`
- Modify: `ArcNote/NewNoteView.swift:221-222,275-369,430-467,747-767`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift:5-15,90-118`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/NewNoteViewSourceContractTests.swift:208-230,293-314,464-560`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift:4004-4173`

**Interfaces:**

- Consumes: Task 2's background intent/staging API and Task 5's leading dirty state.
- Produces: `CardEditorBackgroundActionContext`, `CardEditorBackgroundAction`, and `cardEditorBackgroundActionDialog(...)` for production and fixture.

- [ ] **Step 1: Write failing source contracts for contextual staging**

Add to `CardEditorShellSourceContractTests`:

```swift
func testBackgroundActionsUseNativeContextualDialog() throws {
    let actions = try source(
        at: "ArcNote/CardEditor/CardEditorBackgroundActions.swift"
    )
    let project = try source(at: "ArcNote.xcodeproj/project.pbxproj")

    XCTAssertTrue(actions.contains("enum CardEditorBackgroundActionContext"))
    XCTAssertTrue(actions.contains("case visible(canRestoreOriginal: Bool)"))
    XCTAssertTrue(actions.contains("case removed"))
    XCTAssertTrue(actions.contains("case choosePhoto"))
    XCTAssertTrue(actions.contains("case remove"))
    XCTAssertTrue(actions.contains("case restore"))
    XCTAssertTrue(actions.contains(".confirmationDialog("))
    XCTAssertTrue(actions.contains("cardEditorReplaceBackgroundButton"))
    XCTAssertTrue(actions.contains("cardEditorRemoveBackgroundButton"))
    XCTAssertTrue(actions.contains("cardEditorRestoreBackgroundButton"))
    XCTAssertTrue(project.contains("/* CardEditorBackgroundActions.swift in Sources */"))
}
```

Replace `testCardActionsUseSharedFixedGridWithoutPersistenceOrBackgroundRemoval` with:

```swift
func testCardActionsKeepFixedBackgroundTileAndStageContextualMutations() throws {
    let source = try Self.newNoteSource()
    let grid = try String(
        contentsOf: Self.repositoryRoot.appendingPathComponent(
            "ArcNote/CardEditor/CardEditorActionBox.swift"
        ),
        encoding: .utf8
    )

    XCTAssertTrue(source.contains("onBackground: presentBackgroundActions"))
    XCTAssertTrue(source.contains(".cardEditorBackgroundActionDialog("))
    XCTAssertTrue(source.contains("editingStore.stageBackgroundRemoval()"))
    XCTAssertTrue(source.contains("editingStore.restoreBackground()"))
    XCTAssertFalse(source.contains("editingStore.removeBackground()"))
    XCTAssertEqual(Self.occurrenceCount("text: \"Background\"", in: grid), 1)
    XCTAssertFalse(grid.contains("Remove Background"))

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

    let preview = try XCTUnwrap(
        Self.functionBody(in: source, signature: "var editorBackground:")
    )
    XCTAssertTrue(preview.contains("case let .replace(image)"))
    XCTAssertTrue(preview.contains("case .remove"))
    XCTAssertTrue(preview.contains("case .unchanged"))
}
```

- [ ] **Step 2: Run the contracts and verify the actions file is absent**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests.testBackgroundActionsUseNativeContextualDialog
```

Expected: FAIL because `CardEditorBackgroundActions.swift` does not exist.

- [ ] **Step 3: Create the background action dialog component**

Create `CardEditorBackgroundActions.swift`:

```swift
import SwiftUI

enum CardEditorBackgroundActionContext: Equatable {
    case visible(canRestoreOriginal: Bool)
    case removed
}

enum CardEditorBackgroundAction: Equatable {
    case choosePhoto
    case remove
    case restore
}

private struct CardEditorBackgroundActionDialog: ViewModifier {
    @Binding var isPresented: Bool
    let context: CardEditorBackgroundActionContext
    let onSelect: (CardEditorBackgroundAction) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Background",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            switch context {
            case let .visible(canRestoreOriginal):
                Button("Replace Background") {
                    onSelect(.choosePhoto)
                }
                .accessibilityIdentifier("cardEditorReplaceBackgroundButton")

                if canRestoreOriginal {
                    Button("Restore Original Background") {
                        onSelect(.restore)
                    }
                    .accessibilityIdentifier("cardEditorRestoreBackgroundButton")
                }

                Button("Remove Background", role: .destructive) {
                    onSelect(.remove)
                }
                .accessibilityIdentifier("cardEditorRemoveBackgroundButton")

            case .removed:
                Button("Choose New Background") {
                    onSelect(.choosePhoto)
                }
                .accessibilityIdentifier("cardEditorReplaceBackgroundButton")

                Button("Restore Background") {
                    onSelect(.restore)
                }
                .accessibilityIdentifier("cardEditorRestoreBackgroundButton")
            }

            Button("Cancel", role: .cancel) {}
        }
    }
}

extension View {
    func cardEditorBackgroundActionDialog(
        isPresented: Binding<Bool>,
        context: CardEditorBackgroundActionContext,
        onSelect: @escaping (CardEditorBackgroundAction) -> Void
    ) -> some View {
        modifier(
            CardEditorBackgroundActionDialog(
                isPresented: isPresented,
                context: context,
                onSelect: onSelect
            )
        )
    }
}
```

Add these exact PBX objects beside the existing CardEditor entries:

```text
C0DEF3002F8000010000001C /* CardEditorBackgroundActions.swift in Sources */ = {isa = PBXBuildFile; fileRef = C0DEF3002F8000010000002C /* CardEditorBackgroundActions.swift */; };
C0DEF3002F8000010000002C /* CardEditorBackgroundActions.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CardEditorBackgroundActions.swift; sourceTree = "<group>"; };
```

Add this child to the `C0DEF3002F80000100000001 /* CardEditor */` group:

```text
C0DEF3002F8000010000002C /* CardEditorBackgroundActions.swift */,
```

Add this build file to `1B48AE2D2E30967F0090CF86 /* Sources */`:

```text
C0DEF3002F8000010000001C /* CardEditorBackgroundActions.swift in Sources */,
```

Add `"CardEditorBackgroundActions.swift"` to `cardEditorFiles` in the source contract.

- [ ] **Step 4: Route production preview and actions through background intent**

Add state:

```swift
@State private var showBackgroundActions = false
```

Add context and presentation:

```swift
private var backgroundActionContext: CardEditorBackgroundActionContext {
    switch editingStore.backgroundIntent {
    case .unchanged:
        return .visible(canRestoreOriginal: false)
    case .replace:
        return .visible(canRestoreOriginal: editingStore.backgroundMediaRef != nil)
    case .remove:
        return .removed
    }
}

private func presentBackgroundActions() {
    guard !isBusy else { return }
    completeTagEntry()
    bodyModel.dismissKeyboard()
    if editingStore.backgroundIntent == .unchanged,
       editingStore.backgroundMediaRef == nil {
        showBackgroundPicker = true
    } else {
        showBackgroundActions = true
    }
}

private func handleBackgroundAction(_ action: CardEditorBackgroundAction) {
    switch action {
    case .choosePhoto:
        showBackgroundPicker = true
    case .remove:
        editingStore.stageBackgroundRemoval()
        saveMessage = nil
        hasSaveFailure = false
    case .restore:
        editingStore.restoreBackground()
        saveMessage = nil
        hasSaveFailure = false
    }
}
```

Change the Action Box callback to `onBackground: presentBackgroundActions` and attach:

```swift
.cardEditorBackgroundActionDialog(
    isPresented: $showBackgroundActions,
    context: backgroundActionContext,
    onSelect: handleBackgroundAction
)
```

Replace `editorBackground` with:

```swift
private var editorBackground: CardEditorBackgroundSource {
    switch editingStore.backgroundIntent {
    case let .replace(image):
        return .local(image.data)
    case .remove:
        return .none
    case .unchanged:
        guard let mediaRef = editingStore.backgroundMediaRef,
              let url = URL(
                  string: APIConfiguration.resourceURLString(mediaRef)
              ) else {
            return .none
        }
        return .remote(url)
    }
}
```

The existing photo handler continues to call `stageBackground(image)` and never saves directly.

- [ ] **Step 5: Exercise the same dialog in the native DEBUG fixture**

For fixture mode `background`, add:

```swift
@State private var showBackgroundActions = false
@State private var isFixtureBackgroundRemoved = false

private var fixtureBackgroundActionContext: CardEditorBackgroundActionContext {
    isFixtureBackgroundRemoved
        ? .removed
        : .visible(canRestoreOriginal: false)
}

private func presentFixtureBackgroundActions() {
    if background == .none, mode != .background {
        background = .local(Self.fixtureBackgroundData)
        actionRouter.markDirty()
    } else {
        showBackgroundActions = true
    }
}

private func handleFixtureBackgroundAction(
    _ action: CardEditorBackgroundAction
) {
    switch action {
    case .choosePhoto:
        background = .local(Self.fixtureBackgroundData)
        isFixtureBackgroundRemoved = false
        actionRouter.markDirty()
    case .remove:
        background = .none
        isFixtureBackgroundRemoved = true
        actionRouter.markDirty()
    case .restore:
        background = .local(Self.fixtureBackgroundData)
        isFixtureBackgroundRemoved = false
        actionRouter.markSaved()
    }
}
```

Wire `onBackground: presentFixtureBackgroundActions` and attach:

```swift
.cardEditorBackgroundActionDialog(
    isPresented: $showBackgroundActions,
    context: fixtureBackgroundActionContext,
    onSelect: handleFixtureBackgroundAction
)
```

Add a fixture UI test:

```swift
func testCardEditorBackgroundDialogRemovesAndRestoresLocally() {
    launchCardEditorFixture(mode: "background")
    waitForButton("cardEditorMoreButton").tap()
    waitForEditorCardAction("cardEditorBackgroundButton", requireHittable: true).tap()

    let remove = waitForButton("cardEditorRemoveBackgroundButton")
    XCTAssertTrue(waitForButton("cardEditorReplaceBackgroundButton").exists)
    remove.tap()
    waitForLabel("cardEditorLeadingAction", expected: "Save note")

    waitForButton("cardEditorMoreButton").tap()
    waitForEditorCardAction("cardEditorBackgroundButton", requireHittable: true).tap()
    XCTAssertTrue(waitForButton("cardEditorRestoreBackgroundButton").exists)
    waitForButton("cardEditorRestoreBackgroundButton").tap()
    waitForLabel("cardEditorLeadingAction", expected: "Close note")

    waitForButton("cardEditorMoreButton").tap()
    waitForEditorCardAction("cardEditorBackgroundButton", requireHittable: true).tap()
    app.buttons["Cancel"].tap()
    waitForLabel("cardEditorLeadingAction", expected: "Close note")
}
```

- [ ] **Step 6: Run contracts, fixture dialog, and store staging tests**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests
swift test --package-path Packages/CoreFlow --filter NewNoteViewSourceContractTests
swift test --package-path Packages/CoreFlow --filter CardEditingStoreTests.testStageBackgroundRemovalDefersDeleteUntilSave
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-editor-background-fixture -parallel-testing-enabled NO -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorBackgroundDialogRemovesAndRestoresLocally
```

Expected: PASS.

- [ ] **Step 7: Commit contextual background management**

```bash
git add ArcNote/CardEditor/CardEditorBackgroundActions.swift ArcNote.xcodeproj/project.pbxproj ArcNote/CardEditor/CardEditorShell.swift ArcNote/NewNoteView.swift Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift Packages/CoreFlow/Tests/CoreFlowTests/NewNoteViewSourceContractTests.swift ArcNoteUITests/ArcNoteUITests.swift
git commit -m "feat(editor): manage staged backgrounds"
```

### Task 7: Authenticated Persistence Journeys and Native Simulator Acceptance

**Files:**

- Modify: `ArcNoteUITests/ArcNoteUITests.swift:3604-3650,3929-4002,4004-4173,5761-5767,6118-6202`

**Interfaces:**

- Consumes: all prior production behavior and the existing local Go smoke helpers/photo-picker helper.
- Produces: authoritative end-to-end evidence for inline tags, two-step save/exit, background add/replace/remove/restore, and retry.

- [ ] **Step 1: Rewrite the authenticated tag journey for inline entry and explicit save**

In `testCardEditorSavePersistsNormalizedTagsToGo`, replace the two alert blocks with:

```swift
waitForEnabledButton("cardEditorAddTag", timeout: 20).tap()
let tagInput = waitFor("cardEditorTagInput")
tagInput.typeText("## editortag ")
waitForLabel("cardEditorLeadingAction", expected: "Save note")
saveCardEditor()
XCTAssertTrue(waitFor("cardEditorTag.editortag").exists)
XCTAssertTrue(exists("cardEditorContent", timeout: 2))

waitForEnabledButton("cardEditorAddTag", timeout: 20).tap()
waitFor("cardEditorTagInput").typeText("#editortag\n")
XCTAssertEqual(
    app.descendants(matching: .any)
        .matching(identifier: "cardEditorTag.editortag").count,
    1
)

XCTAssertEqual(waitForButton("cardEditorLeadingAction").label, "Close note")
waitForButton("cardEditorLeadingAction").tap()
waitForMissing("cardEditorContent", timeout: 30)
```

Keep the existing server assertion that `editortag` appears exactly once in `tags`, never in body content, and structured JSON remains present.

- [ ] **Step 2: Extend the background smoke journey through add, replace, restore, and remove**

Replace the body of `testCardEditorBackgroundUploadPersistsToGo` after opening the editor with this sequence, retaining its session/card setup and cleanup:

```swift
let initialBackground = revealEditorBackgroundButton()
XCTAssertEqual(editorActionButtons().count, 8)
initialBackground.tap()
try selectFirstPhotoFromImagePicker()
XCTAssertNil(
    try fetchSmokeCard(id: cardID, token: session.token).backgroundMediaRef,
    "A selected background must remain local before Save"
)
waitForLabel("cardEditorLeadingAction", expected: "Save note")
saveCardEditor()
waitForSmokeCardState(
    id: cardID,
    token: session.token
) { !($0.backgroundMediaRef ?? "").isEmpty }
let firstBackgroundRef = try XCTUnwrap(
    fetchSmokeCard(id: cardID, token: session.token).backgroundMediaRef
)
waitForButton("cardEditorLeadingAction").tap()
waitFor("card.home.\(cardID)", timeout: 30).tap()
waitFor("cardEditorContent", timeout: 20)

let replaceBackground = revealEditorBackgroundButton()
XCTAssertEqual(editorActionButtons().count, 8)
replaceBackground.tap()
XCTAssertTrue(waitForButton("cardEditorReplaceBackgroundButton").exists)
XCTAssertTrue(waitForButton("cardEditorRemoveBackgroundButton").exists)
waitForButton("cardEditorReplaceBackgroundButton").tap()
try selectFirstPhotoFromImagePicker()
XCTAssertEqual(
    try fetchSmokeCard(id: cardID, token: session.token).backgroundMediaRef,
    firstBackgroundRef,
    "Replacement must remain local before Save"
)
saveCardEditor()
waitForSmokeCardState(id: cardID, token: session.token) {
    guard let ref = $0.backgroundMediaRef else { return false }
    return !ref.isEmpty && ref != firstBackgroundRef
}
let replacementRef = try XCTUnwrap(
    fetchSmokeCard(id: cardID, token: session.token).backgroundMediaRef
)
waitForButton("cardEditorLeadingAction").tap()
waitFor("card.home.\(cardID)", timeout: 30).tap()
waitFor("cardEditorContent", timeout: 20)

let removeBackground = revealEditorBackgroundButton()
XCTAssertEqual(editorActionButtons().count, 8)
removeBackground.tap()
waitForButton("cardEditorRemoveBackgroundButton").tap()
waitForLabel("cardEditorLeadingAction", expected: "Save note")
XCTAssertEqual(
    try fetchSmokeCard(id: cardID, token: session.token).backgroundMediaRef,
    replacementRef,
    "Removal must remain local before Save"
)
let stagedRemovalBackground = revealEditorBackgroundButton()
XCTAssertEqual(editorActionButtons().count, 8)
stagedRemovalBackground.tap()
XCTAssertTrue(waitForButton("cardEditorRestoreBackgroundButton").exists)
waitForButton("cardEditorRestoreBackgroundButton").tap()
waitForLabel("cardEditorLeadingAction", expected: "Close note")

let finalRemovalBackground = revealEditorBackgroundButton()
XCTAssertEqual(editorActionButtons().count, 8)
finalRemovalBackground.tap()
waitForButton("cardEditorRemoveBackgroundButton").tap()
saveCardEditor()
waitForSmokeCardState(id: cardID, token: session.token) {
    $0.backgroundMediaRef == nil
}
waitForButton("cardEditorLeadingAction").tap()
waitForMissing("cardEditorContent", timeout: 30)
```

Replace, Remove, and Restore belong only to the native confirmation dialog, never the fixed eight-item grid.

- [ ] **Step 3: Run the local backend stack and the focused authenticated UI suite**

In a separate terminal, run:

```bash
cd /Users/luffylu/Documents/Chorai/Chorai_Go/chorai-go
make run-stack
```

Expected: Go API and required local services become healthy; keep the process running.

Then run:

```bash
cd /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-editor-acceptance -parallel-testing-enabled NO -only-testing:ArcNoteUITests/ArcNoteUITests/testInlineTagEntryCommitsOnReturnWithoutBodyFormattingBar -only-testing:ArcNoteUITests/ArcNoteUITests/testInlineTagEntryCommitsOnFocusLossAndRejectsBlankInput -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorLeadingControlChangesFromBackToSaveAndBack -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorSavePersistsNormalizedTagsToGo -only-testing:ArcNoteUITests/ArcNoteUITests/testNewCardCreateResponseLossRetryReusesCanonicalCard -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorBackgroundDialogRemovesAndRestoresLocally -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorBackgroundUploadPersistsToGo
```

Expected: all seven tests PASS. If the simulator photo library is empty, preload one image and rerun; the background persistence test may not be accepted as a skip.

- [ ] **Step 4: Run package regression and build the native app**

Run:

```bash
swift test --package-path Packages/CoreFlow
xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote -configuration Debug -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-editor-final-build CODE_SIGNING_ALLOWED=NO
```

Expected: CoreFlow tests PASS and Xcode reports `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Install and launch the native editor fixture for visual inspection**

Run:

```bash
xcrun simctl bootstatus 86CD9628-7C27-4799-B237-3EEC82E7E9B5 -b
xcrun simctl install 86CD9628-7C27-4799-B237-3EEC82E7E9B5 /tmp/chorai-editor-final-build/Build/Products/Debug-iphonesimulator/ArcNote.app
SIMCTL_CHILD_CHORAI_CARD_EDITOR_FIXTURE_MODE=background xcrun simctl launch --terminate-running-process 86CD9628-7C27-4799-B237-3EEC82E7E9B5 com.michen.arcnote --ui-test-card-editor-shell
open -a Simulator
xcrun simctl io 86CD9628-7C27-4799-B237-3EEC82E7E9B5 screenshot /tmp/chorai-native-editor-commit-tag-background.png
```

Expected: the Simulator shows the native ArcNote editor, not Safari. Manually verify Add Tag transforms in place, Return and tap-out completion work, the checkmark becomes Back after saving, and existing background opens Replace/Remove/Restore actions.

- [ ] **Step 6: Inspect the final diff and commit UI acceptance updates**

Run:

```bash
git diff --check
git status --short
git diff --stat HEAD~6..HEAD
```

Expected: no whitespace errors and only scoped editor, CoreFlow, test, project, spec, and plan files changed.

Commit any remaining Task 7 test/helper edits:

```bash
git add ArcNoteUITests/ArcNoteUITests.swift
git commit -m "test(editor): cover unified native interactions"
```

Do not create an empty commit when Task 7 produced no uncommitted test changes.
