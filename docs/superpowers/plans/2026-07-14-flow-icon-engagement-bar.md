# Flow Icon Engagement Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the iOS Explore/Flow card's large `Skip`, `Save`, and `Spark` text controls with the compact icon layout selected by the user while preserving all product actions.

**Architecture:** Keep the change inside the existing SwiftUI Flow presentation. `FlowCardView` owns header and footer chrome, the existing `CommentButton` opens comments, and `FlowDeckStore` continues to own save/dismiss behavior. UI automation verifies spatial placement and interaction semantics against stable accessibility identifiers.

**Tech Stack:** Swift 5, SwiftUI, XCTest/XCUITest, existing iOS asset catalog.

## Global Constraints

- Match the supplied footer reference: Save/favorite on the left; Like and Comment on the right.
- No visible `Skip`, `Save`, or `Spark` text labels or filled action capsules.
- Skip remains available by left swipe; Spark remains available as an icon in the card header.
- Reuse existing icon assets and API behavior.
- Do not modify the Go backend or web frontend.

---

### Task 1: Lock the Flow Card Chrome Contract

**Files:**
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: `flow.visible-card.id`, `flow.card.<id>`, and existing Flow automation anchors.
- Produces: `testFlowUsesCompactIconChromeAndSwipeOnlyDismissal()` regression coverage.

- [ ] **Step 1: Write the failing UI test**

Add a focused test that launches Flow, resolves the current card ID, waits for `flow.favorite.<id>`, `flow.like.<id>`, `flow.comment.<id>`, and `flow.spark.<id>`, then asserts:

```swift
XCTAssertFalse(app.buttons["flow.skip.\(cardID)"].exists)
XCTAssertLessThan(save.frame.midX, like.frame.midX)
XCTAssertLessThan(like.frame.midX, comment.frame.midX)
XCTAssertLessThan(spark.frame.midY, save.frame.midY)
```

Finally swipe `flow.card.<id>` left and assert `flow.visible-card.id` changes.

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testFlowUsesCompactIconChromeAndSwipeOnlyDismissal
```

Expected: FAIL because `flow.comment.<id>` does not exist and `flow.skip.<id>` is still visible.

- [ ] **Step 3: Keep the failing output as the regression baseline**

Confirm the failure is caused by the old Flow chrome, not launch, authentication, backend, or fixture setup.

### Task 2: Implement the Compact Icon Chrome

**Files:**
- Modify: `ArcNote/CoreFlow/FlowViews.swift`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: `FlowCard.favoriteCount`, `likeCount`, `commentCount`, `isFavorited`, `isLiked`; `onToggleFavorite`, `onSave`, `onSpark`, `onDismiss`, and `onToggleLike` closures.
- Produces: icon-only `flow.favorite.<id>`, `flow.like.<id>`, `flow.comment.<id>`, and `flow.spark.<id>` controls; swipe-only dismiss behavior.

- [ ] **Step 1: Move Spark into the card header**

Place an icon-only `Button(action: onSpark)` beside the overflow button using `Image("menu_spark")`, a 22-point icon, and a 44-point hit target. Preserve `.accessibilityLabel("Spark")` and `.accessibilityIdentifier("flow.spark.\(card.id)")`.

- [ ] **Step 2: Replace both lower rows with one footer**

Render a single `HStack` with Save/favorite at the leading edge and Like plus Comment at the trailing edge. Use existing raster assets and counts; keep a minimum 44-point hit target without a visible background.

The icon calls `FlowDeckStore.toggleFavoriteCurrent` so it updates gray/red state and count without advancing the deck. Both swipe directions call `dismissCurrent`; neither direction mutates favorite state.

- [ ] **Step 3: Delete obsolete text-button code**

Remove the `Skip` button, the lower `Spark` button, and the `flowActionButton` helper. Keep `onDismiss` for the existing drag resolver and remove environment state used only by the deleted text layout.

- [ ] **Step 4: Update old UI journeys**

Replace automation taps on `flow.skip.<id>` with `flow.card.<id>.swipeLeft()` so onboarding and Spark-result discovery exercise the intended dismiss gesture.

- [ ] **Step 5: Run the focused UI test to verify GREEN**

Run the Task 1 command again.

Expected: PASS with the compact icon ordering and swipe-only dismissal.

### Task 3: Remove Flow Save/Undo Semantics

**Files:**
- Modify: `Packages/CoreFlow/Sources/CoreFlow/CoreFlowModels.swift`
- Modify: `Packages/CoreFlow/Sources/CoreFlow/FlowDeckStore.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/FlowDeckStoreTests.swift`
- Modify: `ArcNote/CoreFlow/FlowViews.swift`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Retains: `FlowDeckStore.toggleFavoriteCurrent()` and Favorite failure rollback.
- Removes: `saveCurrent()`, `undoLastSave()`, `expireUndo(assetID:)`, `undoAssetID`, and `flow.undo`.
- Changes: both `FlowSwipeDecision` directions advance without favorite mutation.

- [ ] **Step 1: Verify the right-swipe regression test fails because favorite state changes**
- [ ] **Step 2: Delete Flow-only save and undo state from `FlowDeckStore`**
- [ ] **Step 3: Route both swipe directions through `dismissCurrent` and remove the Undo notice UI**
- [ ] **Step 4: Replace obsolete save/undo unit tests with swipe/dismiss invariants**
- [ ] **Step 5: Run CoreFlow tests, focused XCUITests, and an iOS simulator build**

### Task 4: Verify Existing Behavior and Visual Fidelity

**Files:**
- Create: `design-qa.md`

**Interfaces:**
- Consumes: supplied footer reference and a simulator screenshot of the implemented Flow card.
- Produces: fresh build/test evidence and `design-qa.md` with `final result: passed` or an explicit blocker.

- [ ] **Step 1: Run focused regressions**

Run the compact chrome test plus existing Flow swipe, Like, Spark, and onboarding tests affected by removed Skip automation.

- [ ] **Step 2: Build the app**

Run:

```bash
xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Capture and compare**

Open the supplied reference and the simulator screenshot together. Compare icon assets, left/right grouping, baseline alignment, spacing, opacity, hit-area side effects, and the absence of text buttons.

- [ ] **Step 4: Record design QA**

Write `design-qa.md` with source path, implementation screenshot path, viewport/device, comparison evidence, findings, iteration history, and exact `final result`.

- [ ] **Step 5: Review the final diff**

Confirm only iOS Flow chrome, affected tests, and required design/plan/QA documentation changed.
