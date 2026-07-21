# iOS Spark Chain and Flow Card Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep repeated Spark actions in one iOS Spark workspace while appending history nodes and make Spark result cards visually consistent with Flow cards.

**Architecture:** Keep `SparkSessionStore` as the single session state owner. Inject a Spark-scoped popup action into the shared menu, derive the pending rail node from store phase, and align the existing Spark result presentation to the live Flow card tokens and structure without duplicating navigation state.

**Tech Stack:** Swift 5.9, SwiftUI, Combine, XCTest, Swift Package Manager, Xcode 16+

## Global Constraints

- iOS 16.0+, iPhone-only.
- Preserve unrelated working-tree changes.
- Keep effective tap targets at least 44 x 44 pt.
- Respect Dynamic Type, Reduce Motion, Reduce Transparency, and VoiceOver.
- Do not add another Spark chain source of truth or hard-coded API endpoint.

---

### Task 1: Lock the interaction and presentation contracts

**Files:**
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/SparkContinuationSourceContractTests.swift`
- Read: `ArcNote/PopupMenuView.swift`
- Read: `ArcNote/CoreFlow/SparkContinuationViews.swift`

**Interfaces:**
- Consumes: `PopupMenuModifier`, `PopupMenuOverlay`, `SparkContinuationView`, `SparkChainRail`, and `SparkResultCard` source.
- Produces: Regression contracts for scoped Spark continuation, numbered pending nodes, and Flow-aligned result card structure.

- [ ] **Step 1: Write failing source-contract tests**

```swift
XCTAssertTrue(popupSource.contains("let onSpark: (() -> Void)?"))
XCTAssertTrue(continuationSource.contains("onSpark: store.sparkCurrentDeeper"))
XCTAssertTrue(continuationSource.contains("Text(\"\\(pendingDepth + 1)\")"))
XCTAssertFalse(sparkCardSource.contains("result.card.title"))
XCTAssertTrue(sparkCardSource.contains("Button(action: onSparkDeeper)"))
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --package-path Packages/CoreFlow --filter SparkContinuationSourceContractTests`

Expected: failures for the missing scoped popup route, pending number, direct continuation button, and legacy title.

### Task 2: Route continuation within the active session

**Files:**
- Modify: `ArcNote/PopupMenuView.swift`
- Modify: `ArcNote/CoreFlow/SparkContinuationViews.swift`
- Test: `Packages/CoreFlow/Tests/CoreFlowTests/SparkContinuationSourceContractTests.swift`

**Interfaces:**
- Consumes: optional `onSpark: (() -> Void)?` passed through the popup modifier and overlay.
- Produces: `SparkContinuationView` calls `store.sparkCurrentDeeper()` from both direct and menu Spark controls; other screens retain `NavigateToSpark` fallback behavior.

- [ ] **Step 1: Thread the optional scoped action through the popup menu**

```swift
let onSpark: (() -> Void)?

private func sparkCard() {
    isPresented = false
    if let onSpark {
        onSpark()
        return
    }
    // Existing NavigateToSpark notification fallback.
}
```

- [ ] **Step 2: Bind Spark continuation to the current store**

```swift
.popupMenu(
    isPresented: $showPopupMenu,
    layout: menuCardIsOwned ? .grid3x3 : .grid3x2,
    cardData: currentMenuCard,
    isOwnCard: menuCardIsOwned,
    isSparkEnabled: store.phase == .loaded,
    onSpark: store.sparkCurrentDeeper
)
```

- [ ] **Step 3: Render the next numbered node while the trigger is pending**

```swift
ForEach(displayedNodes) { node in
    // Existing committed history-node presentation.
}
Text("\(pendingDepth + 1)")
    .accessibilityIdentifier("spark.chain.pending")
```

- [ ] **Step 4: Run the focused contract test and verify the interaction assertions pass**

Run: `swift test --package-path Packages/CoreFlow --filter SparkContinuationSourceContractTests`

Expected: scoped-route and pending-node tests pass.

### Task 3: Align Spark result cards with Flow cards

**Files:**
- Modify: `ArcNote/CoreFlow/SparkContinuationViews.swift`
- Test: `Packages/CoreFlow/Tests/CoreFlowTests/SparkContinuationSourceContractTests.swift`

**Interfaces:**
- Consumes: `ZenVisualTokens`, `FlowTextPreview`, current Flow header/body/tag/footer metrics.
- Produces: titleless Spark result card with matching header actions, typography, chips, card surface, and engagement icon sizing.

- [ ] **Step 1: Remove the legacy title and match body/tag metrics**

```swift
Text(FlowTextPreview.make(result.card.content))
    .font(.system(size: 17, weight: .regular, design: .rounded))
    .lineSpacing(5)
```

- [ ] **Step 2: Add the native 44-point direct Spark control beside the menu**

```swift
Button(action: onSparkDeeper) {
    Image("menu_spark")
        .resizable()
        .scaledToFit()
        .frame(width: 22, height: 22)
        .frame(width: 44, height: 44)
}
.accessibilityIdentifier("spark.continue.\(result.id)")
```

- [ ] **Step 3: Match Flow engagement metric sizing**

```swift
SparkCount(image: favoriteImage, count: favoriteCount, label: "favorites", iconSize: 24)
SparkCount(image: likeImage, count: likeCount, label: "likes")
SparkCount(image: "comment", count: commentCount, label: "comments")
```

- [ ] **Step 4: Run focused and full CoreFlow tests**

Run: `swift test --package-path Packages/CoreFlow --filter SparkContinuationSourceContractTests`

Run: `swift test --package-path Packages/CoreFlow`

Expected: all tests pass with zero failures.

### Task 4: Build and inspect the native flow

**Files:**
- Verify: `ArcNote.xcodeproj`
- Verify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: local and production Xcode schemes plus existing Spark UI anchors.
- Produces: build evidence and simulator evidence for single-workspace continuation.

- [ ] **Step 1: Build the local scheme**

Run: `xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -destination 'generic/platform=iOS Simulator' build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Build the production scheme**

Run: `xcodebuild -project ArcNote.xcodeproj -scheme 'ArcNote Production' -destination 'generic/platform=iOS Simulator' build`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Inspect the focused simulator flow**

Open a Spark result, invoke direct and popup-menu Spark, confirm the current screen gains node 2 before the source/result content changes, select node 1 and branch again to confirm the old descendant is replaced by pending node 2, force a child-trigger failure to confirm all continuation affordances disable in favor of Retry Spark, and confirm one Back action exits Spark rather than revealing another Spark page.

- [ ] **Step 4: Review the final diff against the design**

Confirm no unrelated file was changed, no Flow working-tree edits were overwritten, and every requirement in the design has direct test or build evidence.
