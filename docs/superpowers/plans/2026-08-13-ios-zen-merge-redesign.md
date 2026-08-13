# iOS Zen Merge Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the original Zen iPhone Merge composition, align it with Merge v2, and make Home, Favorite, and Merge render the canonical backend rate palette consistently.

**Architecture:** `MergeSessionStore` remains the sole lifecycle authority. CoreFlow gains testable card-response and rate-style value contracts; existing Home card primitives own the shared SwiftUI rate treatment; the Merge projection composes those primitives and presents the exact server artifact in one centered glass review panel.

**Tech Stack:** Swift 5.9, SwiftUI, Combine, Swift Package Manager, XCTest/XCUITest, Xcode 26.2 simulator tooling.

## Global Constraints

- Work directly on `main`, as explicitly requested; do not create a branch or worktree.
- Support iOS 16+ and iPhone only.
- Do not modify Web, Go backend, or unrelated Auth/Blocked Actors files.
- Preserve `MergeSessionStore` as the only Merge lifecycle state machine.
- Persist no artifact title, tags, route, surprise kind, or user-selected rate.
- The review panel has exactly two user actions: `Discard` and `Save`.
- Canonical rate mapping is `1 = neutral`, `2 = #00FF66`, `3 = #0371FF`, `4 = #9627D2`, `5 = #D97800`, `6 = #FF5E00`; all other values are neutral.
- Use no new third-party dependency.
- Every behavior change starts with a failing test and a witnessed expected failure.
- Stage and commit only files belonging to this feature; preserve unrelated working-tree changes.

---

### Task 1: Canonical Card Response and Rate Semantics

**Files:**
- Create: `Packages/CoreFlow/Sources/CoreFlow/CardResponseModels.swift`
- Create: `Packages/CoreFlow/Sources/CoreFlow/LibraryCardRateStyle.swift`
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/CardResponseModelsTests.swift`
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/LibraryCardRateStyleTests.swift`
- Modify: `ArcNote/NetworkModels.swift`
- Modify: `ArcNote/CoreFlow/MergeLifecycleViews.swift`

**Interfaces:**
- Produces: `public struct CardResponseData: Codable, Sendable`, `public struct CardResponseEnvelope: Codable, Sendable`, and internal compatibility aliases `CreateCardData` / `CardResponse` in the app target.
- Produces: `public enum LibraryCardRateStyle: Equatable, Sendable` with `init(rate: Int)` and `accentHex: String?`.
- Consumes: current Go `CardDTO` keys, including `note_document_version_id`, `content_json`, `background_media_ref`, and `rate`.

- [ ] **Step 1: Write a failing response-decoding test**

Add a literal full `CardDTO` fixture and decode it through the production envelope:

```swift
func testCardResponseDecodesCurrentCardDTOForMergePresentation() throws {
    let response = try JSONDecoder().decode(
        CardResponseEnvelope.self,
        from: Data(Self.rateFiveCardJSON.utf8)
    )

    XCTAssertEqual(response.data.id, "ast_rate_5")
    XCTAssertEqual(response.data.noteDocumentVersionID, "ver_rate_5")
    XCTAssertEqual(response.data.contentJSON, #"{"type":"doc"}"#)
    XCTAssertEqual(response.data.backgroundMediaRef, "/chorai-assets/rate-5.png")
    XCTAssertEqual(response.data.favoriteCount, 12)
    XCTAssertEqual(response.data.rate, 5)
    XCTAssertEqual(response.data.author?.id, "act_author")
}
```

- [ ] **Step 2: Run the decoding test and verify RED**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardResponseModelsTests
```

Expected: compilation fails because `CardResponseEnvelope` does not exist.

- [ ] **Step 3: Implement the current response contract**

Create public CoreFlow response values that decode the current backend keys and default only genuinely legacy omissions (`rate` to `1`, counts/booleans to neutral values). Replace the duplicate app structs with aliases:

```swift
typealias CreateCardData = CardResponseData
typealias CardResponse = CardResponseEnvelope
```

Update `MergeCandidateStore.loadAnchor()` to pass `response.data.rate`, author metadata, `contentJSON`, and `backgroundMediaRef`; remove the hard-coded `rate: 0`.

- [ ] **Step 4: Run the decoding test and verify GREEN**

Run the same filtered test. Expected: PASS.

- [ ] **Step 5: Write a failing canonical rate-style table test**

```swift
func testCanonicalBackendRatesMapToLibraryAccents() {
    let cases: [(Int, LibraryCardRateStyle, String?)] = [
        (1, .neutral, nil),
        (2, .green, "#00FF66"),
        (3, .blue, "#0371FF"),
        (4, .purple, "#9627D2"),
        (5, .amber, "#D97800"),
        (6, .orangeRed, "#FF5E00"),
        (0, .neutral, nil),
        (7, .neutral, nil),
        (243, .neutral, nil),
    ]

    for (rate, style, accent) in cases {
        XCTAssertEqual(LibraryCardRateStyle(rate: rate), style)
        XCTAssertEqual(LibraryCardRateStyle(rate: rate).accentHex, accent)
    }
}
```

- [ ] **Step 6: Run the rate test and verify RED**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter LibraryCardRateStyleTests
```

Expected: compilation fails because `LibraryCardRateStyle` does not exist.

- [ ] **Step 7: Implement the pure rate value and verify GREEN**

Implement only the six semantic cases and literal hex values. Run both Task 1 test classes and the complete CoreFlow test suite.

- [ ] **Step 8: Commit Task 1**

```bash
git add Packages/CoreFlow/Sources/CoreFlow/CardResponseModels.swift Packages/CoreFlow/Sources/CoreFlow/LibraryCardRateStyle.swift Packages/CoreFlow/Tests/CoreFlowTests/CardResponseModelsTests.swift Packages/CoreFlow/Tests/CoreFlowTests/LibraryCardRateStyleTests.swift ArcNote/NetworkModels.swift ArcNote/CoreFlow/MergeLifecycleViews.swift
git commit -m "fix(ios): honor canonical card rate contract"
```

### Task 2: One Shared Library Card Rate Surface

**Files:**
- Modify: `ArcNote/HomeView.swift`
- Modify: `ArcNote/MergeView.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/LibraryCardPreviewSourceContractTests.swift`

**Interfaces:**
- Consumes: `LibraryCardRateStyle(rate:)` from Task 1.
- Produces: `LibraryCardBackgroundSurface(backgroundMediaRef:rate:fallback:)` applying one neutral glass base plus a restrained canonical ambient glow and border reflection.
- Produces: Home, Favorite, and Merge call sites that pass their real backend `rate` to the shared surface.

- [ ] **Step 1: Write a failing shared-surface contract test**

Extend the existing library-card integration contract. The break it catches is reintroducing a separate visual rate algorithm in one surface:

```swift
func testEveryLibrarySurfaceConsumesCanonicalRateStyle() throws {
    let home = try source(at: "ArcNote/HomeView.swift")
    let merge = try source(at: "ArcNote/MergeView.swift")

    XCTAssertGreaterThanOrEqual(
        home.components(separatedBy: "rate:").count - 1,
        3
    )
    XCTAssertTrue(home.contains("LibraryCardRateStyle(rate: rate)"))
    XCTAssertTrue(merge.contains("rate: card.rate"))
    XCTAssertFalse(home.contains("backgroundImageForRate"))
    XCTAssertFalse(merge.contains("backgroundImageForRate"))
    for legacyRange in ["rate >= 3 && rate <= 8", "rate >= 9 && rate <= 26", "rate > 242"] {
        XCTAssertFalse(home.contains(legacyRange))
        XCTAssertFalse(merge.contains(legacyRange))
    }
}
```

- [ ] **Step 2: Run the focused contract test and verify RED**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter LibraryCardPreviewSourceContractTests
```

Expected: FAIL because the shared surface currently has no `rate` input and old `backgroundImageForRate` functions remain.

- [ ] **Step 3: Add canonical SwiftUI rate treatment**

Add a `LibraryCardRateAccent` inside the existing shared background surface. Convert each CoreFlow tier to a SwiftUI `Color`, render a low-opacity top-centered radial glow and one-pixel border reflection, and render no accent for neutral/unknown values. Keep custom background media and readability veil as the protagonist.

- [ ] **Step 4: Migrate all three library presentations and Merge**

Pass `card.rate`/`rate` at the Notes, Favorite, colored-note, and Merge call sites. Remove `backgroundImageForRate` and old `<3`, `3...8`, `9...26`, `27...80`, `81...242`, `>242` branching. Fix the Favorite menu conversion from `rate: 0` to `rate: favorite.rate`.

- [ ] **Step 5: Verify GREEN and build the app target**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter 'LibraryCardPreviewSourceContractTests|LibraryCardRateStyleTests'
xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -configuration Debug -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' build
```

Expected: tests PASS and `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit Task 2**

```bash
git add ArcNote/HomeView.swift ArcNote/MergeView.swift Packages/CoreFlow/Tests/CoreFlowTests/LibraryCardPreviewSourceContractTests.swift
git commit -m "refactor(ios): share library card rate surface"
```

### Task 3: Zen Merge Selection Surface

**Files:**
- Modify: `ArcNote/CoreFlow/MergeLifecycleViews.swift`
- Modify: `ArcNote/MergeView.swift`
- Modify: `ArcNote/ArcNoteApp.swift`
- Replace: `Packages/CoreFlow/Tests/CoreFlowTests/MergeSelectionPresentationSourceContractTests.swift`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Produces: one centered `Merge` header, fixed anchor, divider, search, direct-tap candidates, and one safe-area-aware `Merge N cards` pill.
- Produces: selected-card border/checkmark and a deterministic Debug visual fixture containing neutral, green, purple, orange-red, and custom-background examples.

- [ ] **Step 1: Write a failing UI behavior test**

Launch `--ui-test-merge-selection` and assert:

```swift
XCTAssertFalse(app.descendants(matching: .any)["merge.selection.action-bar"].exists)
XCTAssertEqual(waitForButton("merge.action").label, "Merge 2 cards")
XCTAssertGreaterThanOrEqual(waitForButton("merge.action").frame.width, window.frame.width - 40)
XCTAssertTrue(waitFor("merge.card.merge-fixture-candidate").value as? String == "selected")
```

Tap the candidate and verify the action becomes disabled with `Merge 1 card`; tap again and verify it becomes enabled without a second confirmation control.

- [ ] **Step 2: Run the UI test and verify RED**

Run:

```bash
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' -only-testing:ArcNoteUITests/ArcNoteUITests/testMergeSelectionFixtureUsesOneZenMergeAction
```

Expected: FAIL because the rejected `Selected notes` bar exists and the action is not a wide count-bearing pill.

- [ ] **Step 3: Restore the original selection hierarchy**

Remove `MergeSelectionActionBar`. Remove the header merge icon. Use one wide capsule labeled with the selected total, placed with a bottom safe-area inset so the list cannot hide beneath it. Keep the anchor selected implicitly and add a compact selected checkmark to candidates.

- [ ] **Step 4: Update the visual fixture and verify GREEN**

Use rates `1`, `2`, `4`, and `6`. Use an existing bundled image asset as the fixture's deterministic custom `backgroundMediaRef` input; do not add test-only behavior to production resolvers. Re-run the focused UI test and capture `merge-selection`.

- [ ] **Step 5: Commit Task 3**

```bash
git add ArcNote/ArcNoteApp.swift ArcNote/CoreFlow/MergeLifecycleViews.swift ArcNote/MergeView.swift ArcNoteUITests/ArcNoteUITests.swift Packages/CoreFlow/Tests/CoreFlowTests/MergeSelectionPresentationSourceContractTests.swift
git commit -m "fix(ios): restore zen merge selection"
```

### Task 4: Merge v2 Centered Artifact Review

**Files:**
- Modify: `Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/MergeSessionStoreArtifactTests.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/MergeSessionStoreCommitTests.swift`
- Modify: `ArcNote/CoreFlow/MergeLifecycleViews.swift`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Produces: `discardArtifact()` that cancels an uncommitted ready job and returns to selection after success.
- Produces: recoverable artifact action errors that preserve the artifact and allow `Discard`/`Save` to be retried in place.
- Produces: one centered `Merge preview` glass panel rendering the exact titleless `MergeArtifact.document`, with only `merge.discard` and `merge.commit` actions.

- [ ] **Step 1: Write failing lifecycle tests**

Add these concrete behavior tests:

```swift
func testDiscardReadyArtifactReturnsDirectlyToFreshSelection() async {
    let service = MockCoreMergeService()
    let persistence = InMemoryMergeSessionPersistence()
    let store = await readyStore(service: service, persistence: persistence)
    await service.enqueueCancel(.success(makeMergeJob(status: .cancelled)))

    store.discardArtifact()
    await waitForMergeStore { store.phase == .selection }

    XCTAssertNil(persistence.snapshot(actorID: "actor_1"))
    XCTAssertNil(store.job)
    XCTAssertNil(store.artifact)
    XCTAssertEqual(store.selectedSources.map(\.assetID), ["ast_anchor"])
}

func testCommitFailureKeepsArtifactVisibleAndRetryable() async {
    let service = MockCoreMergeService()
    let persistence = InMemoryMergeSessionPersistence()
    let store = await readyStore(service: service, persistence: persistence, keys: ["commit-stable"])
    let expectedArtifact = store.artifact
    await service.enqueueCommit(.failure(.offline))

    store.commit()
    await waitForMergeStore { store.artifactActionError == .offline }

    XCTAssertEqual(store.phase, .ready)
    XCTAssertEqual(store.artifact, expectedArtifact)
    XCTAssertNotNil(store.activeSnapshot?.commitRequest)
}
```

- [ ] **Step 2: Run focused lifecycle tests and verify RED**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter 'MergeSessionStoreArtifactTests|MergeSessionStoreCommitTests'
```

Expected: compilation/failure because `discardArtifact()` and recoverable artifact-action state do not exist.

- [ ] **Step 3: Implement minimal lifecycle support and verify GREEN**

Keep generic `cancel()` behavior unchanged for navigation abandonment. Add only the artifact-specific discard intent and action-error state. Clear the error before each action; preserve the artifact on failure; on successful discard reset to selection without an intermediate terminal screen. Re-run the focused tests.

- [ ] **Step 4: Write a failing artifact-panel UI test**

Launch the deterministic fixture in `artifact` mode and use these assertions:

```swift
let panel = waitFor("merge.artifact.panel")
XCTAssertEqual(panel.label, "Merge preview")
XCTAssertTrue(waitFor("merge.artifact.body").exists)
XCTAssertEqual(app.buttons.matching(identifier: "merge.discard").count, 1)
XCTAssertEqual(app.buttons.matching(identifier: "merge.commit").count, 1)
for forbidden in ["New Insight", "Uncommon", "Add tag", "Close"] {
    XCTAssertFalse(app.descendants(matching: .any)[forbidden].exists)
}
```

Launch `artifact-long` mode and assert both actions are hittable and fully within the window:

```swift
for action in [waitForButton("merge.discard"), waitForButton("merge.commit")] {
    XCTAssertTrue(action.isHittable)
    XCTAssertLessThanOrEqual(action.frame.maxY, app.windows.firstMatch.frame.maxY)
}
```

- [ ] **Step 5: Run the panel UI test and verify RED**

Run the two focused XCUITests on iPhone 17 Pro. Expected: FAIL because the current artifact is a full-page card with icon-only actions.

- [ ] **Step 6: Implement the centered glass artifact panel**

Dim and disable the selection surface beneath the panel. Render `Merge preview`, `N sources → 1 card`, the titleless block document, inline error text, and exactly two text actions. Keep the same panel visible during commit with progress inside Save. Direct success to canonical detail through the existing completion task.

- [ ] **Step 7: Update the live Merge smoke test and verify GREEN**

Replace the old confirmation-dialog cancellation flow with one tap on `merge.discard`, and keep the backend assertion that the job reaches `CANCELLED`. Re-run lifecycle tests and focused fixture UI tests.

- [ ] **Step 8: Commit Task 4**

```bash
git add Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift Packages/CoreFlow/Tests/CoreFlowTests/MergeSessionStoreArtifactTests.swift Packages/CoreFlow/Tests/CoreFlowTests/MergeSessionStoreCommitTests.swift ArcNote/CoreFlow/MergeLifecycleViews.swift ArcNoteUITests/ArcNoteUITests.swift
git commit -m "feat(ios): present merge v2 artifact review"
```

### Task 5: Full Verification and Simulator Visual QA

**Files:**
- Create: `docs/qa/ios-zen-merge-redesign-qa.md`
- Create screenshots under: `docs/qa/assets/ios-zen-merge-redesign/`
- Modify only if verification finds a real defect: feature files from Tasks 1–4, with a new failing regression test first.

**Interfaces:**
- Consumes: deterministic selection/artifact fixture modes and production Merge v2 smoke path.
- Produces: repository-retained visual evidence and a requirement-by-requirement QA record.

- [ ] **Step 1: Run complete automated suites**

```bash
swift test --package-path Packages/CoreFlow
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' -only-testing:ArcNoteUITests/ArcNoteUITests/testMergeSelectionFixtureUsesOneZenMergeAction -only-testing:ArcNoteUITests/ArcNoteUITests/testMergeArtifactFixtureUsesCenteredTwoActionPreview -only-testing:ArcNoteUITests/ArcNoteUITests/testMergeLongArtifactKeepsActionsReachable
```

Expected: all tests PASS.

- [ ] **Step 2: Build both production configurations**

```bash
xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -configuration Debug -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' build
xcodebuild -project ArcNote.xcodeproj -scheme 'ArcNote Production' -configuration Debug-Production -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' build
```

Expected: both commands end with `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Capture normal-device visuals**

Boot/install/launch the Debug app on iPhone 17 Pro with selection, artifact, and long-artifact fixture arguments. Capture PNGs with `xcrun simctl io 43E6164C-1F4B-47E4-9B65-D154C7281A56 screenshot ...` after each state.

- [ ] **Step 4: Capture compact and accessibility visuals**

Run selection and artifact fixtures on `Chorai iPhone SE 3 QA`. Capture compact screenshots. On iPhone 17 Pro enable Reduce Transparency (or Increased Contrast if simulator preference automation is more reliable), relaunch, and capture one accessibility screenshot; restore the setting afterward.

- [ ] **Step 5: Inspect every screenshot at original resolution**

Use visual inspection to verify no clipping, overlap, hidden actions, false rate tiers, unreadable custom background, oversized chrome, or redundant action. If a defect is found, add a failing regression test, fix it, and repeat affected checks.

- [ ] **Step 6: Write the QA record and run the completion audit**

Record simulator/device, commands, screenshots, rate examples, accessibility setting, and outcome. Audit every requirement in the design spec against source, test, build, runtime, and screenshot evidence.

- [ ] **Step 7: Commit QA evidence**

```bash
git add docs/qa/ios-zen-merge-redesign-qa.md docs/qa/assets/ios-zen-merge-redesign
git commit -m "test(ios): verify zen merge visuals"
```
