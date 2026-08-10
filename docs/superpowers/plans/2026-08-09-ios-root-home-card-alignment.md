# iOS Root Home-Card Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make discovery-path Root cards body-first and Home-aligned, remove their title, add a working top-right overflow menu, and relocate path labels to the footer.

**Architecture:** Keep `DiscoveryPathStore` and its API contract unchanged. `RootView` owns the one currently selected popup card and adapts only reliable `DiscoveryPathCard` fields into the existing `UserCard` menu model. `DiscoveryPathCardView` owns visual card structure; `DiscoveryPathTimeline` supplies both open and overflow callbacks.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, Swift Package Manager, Xcode 16+

## Global Constraints

- iOS 16.0+, iPhone-only.
- Preserve unrelated working-tree changes.
- Keep effective tap targets at least 44 x 44 pt.
- Keep `DiscoveryPathStore`, snapshot ordering, loading, empty, failure, retry, and existing card-tap routing unchanged.
- Do not add a network/API field, guessed public/pin state, or a second navigation source of truth.
- Respect Dynamic Type, Reduce Motion, Reduce Transparency, and VoiceOver.

---

### Task 1: Lock the Root presentation and interaction contract

**Files:**
- Modify: `ArcNoteUITests/ArcNoteUITests.swift:1379-1427`
- Read: `ArcNote/RootView.swift`
- Read: `ArcNote/HomeView.swift`
- Read: `ArcNote/PopupMenuView.swift`

**Interfaces:**
- Consumes: the `--ui-test-discovery-path` fixture, the Root card's visible title, its accessibility controls, and the shared popup overlay.
- Produces: a regression test for titleless Root cards, a top-right menu, a footer path role, and a working popup action.

- [x] **Step 1: Write the failing UI test**

```swift
func testDiscoveryPathFixtureUsesTitlelessCardsWithFooterPathRoles() throws {
    launchDiscoveryPathFixture(mode: "loaded")
    let menu = waitForButton("discovery-path.menu.ast_collected")
    let role = waitFor("discovery-path.role.ast_collected")

    XCTAssertFalse(app.staticTexts["A saved insight"].exists)
    XCTAssertLessThan(menu.frame.minY, role.frame.minY)

    menu.tap()
    waitFor("popup-menu.overlay")
    waitFor("popup-menu.item.view")
}
```

- [x] **Step 2: Run the focused test and verify RED**

Run: `xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=8F00CE99-FEBE-4774-9A07-4BBAF8A0FD1D' -only-testing:ArcNoteUITests/ArcNoteUITests/testDiscoveryPathFixtureUsesTitlelessCardsWithFooterPathRoles`

Expected: failure for the missing `discovery-path.menu.ast_collected` button; it proves the test reaches the real fixture before the UI change.

### Task 2: Add a reliable Root popup-menu adapter

**Files:**
- Modify: `ArcNote/RootView.swift:5-177`
- Test: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: `DiscoveryPathCard.id`, `.content`, `.tags`, `.createdAt`, `.authorActorID`, `.rate`, `AuthManager.shared.currentUser`, and `popupMenu`.
- Produces: `openMenu(_:)` that maps a discovery card to `UserCard` and presents the existing 2-by-2 popup menu.

- [x] **Step 1: Add the selected menu state and modifier**

```swift
@State private var showPopupMenu = false
@State private var menuCard: UserCard?

.popupMenu(
    isPresented: $showPopupMenu,
    layout: .grid2x2,
    cardData: menuCard,
    isOwnCard: menuCard?.isOwner ?? false
)
```

- [x] **Step 2: Adapt only fields known by `DiscoveryPathCard`**

```swift
private func openMenu(_ card: DiscoveryPathCard) {
    let currentActorID = AuthManager.shared.currentUser?.id
    let isOwner = currentActorID != nil
        && card.authorActorID == currentActorID
    menuCard = UserCard(
        id: card.id, title: nil, content: card.content, contentHash: "",
        isPublic: false, tags: card.tags, createdAt: card.createdAt,
        updatedAt: card.createdAt, likeCount: 0, commentCount: nil,
        isLiked: false, isPinned: false, pinnedAt: nil,
        isFavorited: nil, favoriteCount: nil, rate: card.rate,
        ownerActorId: card.authorActorID, isOwner: isOwner
    )
    showPopupMenu = true
}
```

- [x] **Step 3: Thread `openMenu` through the timeline into every card**

```swift
DiscoveryPathTimeline(
    snapshot: snapshot,
    openCard: openCard,
    openMenu: openMenu
)
```

- [x] **Step 4: Run the focused UI test and verify the menu assertions pass**

Run: `xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=8F00CE99-FEBE-4774-9A07-4BBAF8A0FD1D' -only-testing:ArcNoteUITests/ArcNoteUITests/testDiscoveryPathFixtureUsesTitlelessCardsWithFooterPathRoles`

Expected: the test advances past the menu assertion but remains red until the footer role and titleless card are implemented.

### Task 3: Rebuild the Root card around Home's visual hierarchy

**Files:**
- Modify: `ArcNote/RootView.swift:54-380`
- Test: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: the timeline `openMenu` closure, `HTMLTextRenderer`, Home-equivalent card metrics, and `badge`/`badgeColor`.
- Produces: a titleless `DiscoveryPathCardView` with a top-right overflow control and footer path-role capsule.

- [x] **Step 1: Remove the visible Root title while retaining Back navigation**

```swift
private var header: some View {
    HStack {
        Button(action: dismiss.callAsFunction) { /* existing chevron */ }
        Spacer()
    }
    .adaptiveContentGutter()
    .padding(.top, 60)
    .padding(.bottom, 24)
}
```

- [x] **Step 2: Reserve the card header's trailing slot for the menu**

```swift
Button(action: { openMenu(card) }) {
    Image(systemName: "ellipsis")
        .font(.title3)
        .foregroundColor(.white)
        .frame(minWidth: 44, minHeight: 44)
}
.accessibilityLabel("Card menu")
.accessibilityIdentifier("discovery-path.menu.\\(card.id)")
```

- [x] **Step 3: Keep the card body as a separate button instead of nesting the menu button**

```swift
Button(action: action) {
    HTMLTextRenderer(
        htmlContent: card.content,
        maxLines: 3,
        font: .system(size: 14, weight: .regular),
        foregroundColor: .white.opacity(0.9)
    )
}
.buttonStyle(.plain)

ScrollView(.horizontal, showsIndicators: false) {
    // Footer path role and tags stay outside the body button.
}
```

- [x] **Step 4: Remove the title branch and place the path role before tags in the footer**

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 8) {
        pathRoleChip
        ForEach(card.tags, id: \\.self) { tag in
            /* Home-style tag chip */
        }
    }
}
```

- [x] **Step 5: Match the Home card's body-first metrics**

```swift
VStack(alignment: .leading, spacing: 16) {
    // 40-point avatar, 16/12-point metadata, then body and footer.
}
.padding(20)
.clipShape(RoundedRectangle(cornerRadius: 16))
```

- [x] **Step 6: Run the focused Root UI test and discovery-path store tests**

Run: `xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=8F00CE99-FEBE-4774-9A07-4BBAF8A0FD1D' -only-testing:ArcNoteUITests/ArcNoteUITests/testDiscoveryPathFixtureUsesTitlelessCardsWithFooterPathRoles`

Run: `swift test --package-path Packages/CoreFlow --filter DiscoveryPathStoreTests`

Expected: the UI contract and store tests pass with zero failures.

### Task 4: Verify build and native fixture behavior

**Files:**
- Verify: `ArcNote.xcodeproj`
- Verify: `ArcNoteUITests/ArcNoteUITests.swift`
- Verify: `ArcNote/RootView.swift`

**Interfaces:**
- Consumes: both ArcNote schemes and the existing `--ui-test-discovery-path` fixture.
- Produces: build and UI evidence that the visual change preserves navigation, status ordering, and retry behavior.

- [x] **Step 1: Build the local scheme**

Run: `xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -destination 'generic/platform=iOS Simulator' build`

Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 2: Build the production scheme**

Run: `xcodebuild -project ArcNote.xcodeproj -scheme 'ArcNote Production' -destination 'generic/platform=iOS Simulator' build`

Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 3: Run the existing discovery-path fixture tests**

Run: `xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=8F00CE99-FEBE-4774-9A07-4BBAF8A0FD1D' -only-testing:ArcNoteUITests/ArcNoteUITests/testDiscoveryPathFixtureShowsCollectedToOriginOrder -only-testing:ArcNoteUITests/ArcNoteUITests/testDiscoveryPathFixtureShowsNoProvenanceState -only-testing:ArcNoteUITests/ArcNoteUITests/testDiscoveryPathFixtureRetriesTransportFailure`

Expected: all three fixture tests pass; cards retain their collected-to-origin order and empty/failure behavior.

- [x] **Step 4: Inspect the final diff against the design**

Run: `git diff --check && git diff -- ArcNote/RootView.swift ArcNoteUITests/ArcNoteUITests.swift`

Expected: only the requested Root presentation and its regression contract change; no whitespace errors or unrelated edits.
