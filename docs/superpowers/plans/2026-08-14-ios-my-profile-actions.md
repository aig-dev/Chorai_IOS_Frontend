# iOS My Profile Card Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Remove the crowded credits item from My Profile, give its owned cards the Home action set, and add the Community Profile chat shortcut.

**Architecture:** MyProfileView remains the owner of profile/card state. The reusable popup menu receives optional local mutation callbacks so its Home notification fallback stays backward compatible while My Profile handles its own mutations without broadcasting into a hidden Home view. Chat reuses the existing Community Profile conversation-creation flow.

**Tech Stack:** Swift 5.9+, SwiftUI, Combine, XCTest source-contract tests, XCUITest, Swift Package Manager, Xcode, iOS 16.0+

## Global Constraints

- Work only in Chorai_IOS_Frontend; do not modify Web or Go.
- Do not create or switch branches; preserve unrelated worktree changes.
- Keep UserProfileManager credit data because sidebar and settings still use it; remove only My Profile's visual/statistical credit surface.
- Reuse HomeCardsManager for delete, visibility, and pin mutations.
- Keep popup-menu notification behavior as the default for existing callers.
- Do not add API endpoints, hard-coded API hosts, or a second card-state source.
- Follow red-green-refactor and keep My Profile controls accessible.

---

## File Map

- Packages/CoreFlow/Tests/CoreFlowTests/MyProfileActionsSourceContractTests.swift
  - Locks the layout and callback integration requirements without importing the Xcode app target.
- ArcNoteUITests/ArcNoteUITests.swift
  - Verifies the My Profile fixture no longer exposes credits.
- ArcNote/PopupMenuView.swift
  - Adds optional local callbacks for owner-card mutations while retaining the existing notification fallback.
- ArcNote/MyProfileView.swift
  - Removes the credit stat, supplies the Home owner-menu layout/actions, owns removal confirmation/error state, and creates chats from card shortcuts.

### Task 1: Lock the intended My Profile composition with failing tests

**Files:**
- Create: Packages/CoreFlow/Tests/CoreFlowTests/MyProfileActionsSourceContractTests.swift
- Modify: ArcNoteUITests/ArcNoteUITests.swift:2077-2104

**Interfaces:**
- Consumes: MyProfileView, PopupMenuView, and the existing --ui-test-profile-credit-surfaces fixture.
- Produces: test coverage for no credits, the owner menu layout, local callback hooks, and the card-level chat callback.

- [ ] **Step 1: Write the failing source-contract test**

Create Packages/CoreFlow/Tests/CoreFlowTests/MyProfileActionsSourceContractTests.swift:

~~~swift
import Foundation
import XCTest

final class MyProfileActionsSourceContractTests: XCTestCase {
    func testMyProfileUsesHomeOwnerActionsAndCommunityChatShortcut() throws {
        let profile = try source(at: "ArcNote/MyProfileView.swift")
        let popupMenu = try source(at: "ArcNote/PopupMenuView.swift")

        XCTAssertFalse(profile.contains("my-profile.credit-balance"))
        XCTAssertFalse(profile.contains("Text(\"Credits\")"))
        XCTAssertTrue(profile.contains("popupMenuLayout = .grid3x3"))
        XCTAssertTrue(profile.contains("onChatTap: {"))
        XCTAssertTrue(profile.contains("createConversation()"))
        XCTAssertTrue(profile.contains("onDelete: requestCardDeletion"))
        XCTAssertTrue(
            profile.contains("onToggleVisibility: toggleCardVisibility")
        )
        XCTAssertTrue(profile.contains("onTogglePin: toggleCardPin"))

        XCTAssertTrue(popupMenu.contains("onDelete: (() -> Void)?"))
        XCTAssertTrue(
            popupMenu.contains("onToggleVisibility: ((UserCard) -> Void)?")
        )
        XCTAssertTrue(popupMenu.contains("onTogglePin: ((UserCard) -> Void)?"))
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
~~~

- [ ] **Step 2: Change the credit fixture expectation to the desired UI**

Rename testSidebarAndMyProfileShareSingleCreditBalanceFixture to testSidebarShowsCreditWhileMyProfileOmitsIt. Keep the existing sidebar assertions, then replace the My Profile credit assertion with:

~~~swift
tap("side-menu.profile")
waitFor("profile.primary-surface")
XCTAssertFalse(exists("my-profile.credit-balance", timeout: 2))
XCTAssertEqual(
    app.staticTexts.matching(
        NSPredicate(format: "label == %@", "Credits")
    ).count,
    0
)
~~~

- [ ] **Step 3: Run the focused tests and verify RED**

Run:

~~~bash
swift test --package-path Packages/CoreFlow \
  --filter MyProfileActionsSourceContractTests
~~~

Expected: FAIL because My Profile still renders credits, uses .grid2x2, has no chat callback, and the popup API exposes no local mutation callbacks.

Run the UI test on an installed iPhone simulator (substitute the actual available device name):

~~~bash
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testSidebarShowsCreditWhileMyProfileOmitsIt
~~~

Expected: FAIL because my-profile.credit-balance still exists.

### Task 2: Make popup mutation actions locally routable

**Files:**
- Modify: ArcNote/PopupMenuView.swift:214-380,640-662

**Interfaces:**
- Consumes: existing PopupMenuModifier and PopupMenuOverlay action methods.
- Produces: optional callbacks with these exact signatures:

~~~swift
let onDelete: (() -> Void)?
let onToggleVisibility: ((UserCard) -> Void)?
let onTogglePin: ((UserCard) -> Void)?
~~~

- [ ] **Step 1: Thread callbacks through the popup API**

Add the three optional properties to PopupMenuModifier and PopupMenuOverlay; accept them in both initializers; and forward them from View.popupMenu with nil defaults:

~~~swift
func popupMenu(
    isPresented: Binding<Bool>,
    layout: PopupMenuLayout = .grid2x2,
    cardData: UserCard? = nil,
    isOwnCard: Bool = false,
    isSparkEnabled: Bool = true,
    onSpark: (() -> Void)? = nil,
    onDelete: (() -> Void)? = nil,
    onToggleVisibility: ((UserCard) -> Void)? = nil,
    onTogglePin: ((UserCard) -> Void)? = nil,
    onRouteDismissed: @escaping (CardNavigationDismissal) -> Void = { _ in },
    onRoutePresentationChanged: @escaping (Bool) -> Void = { _ in }
) -> some View
~~~

- [ ] **Step 2: Prefer callbacks but preserve current defaults**

In PopupMenuOverlay, make the three action methods use a supplied callback first and otherwise retain the existing NotificationCenter posts:

~~~swift
private func deleteCard() {
    if let onDelete {
        onDelete()
    } else {
        NotificationCenter.default.post(
            name: NSNotification.Name("DeleteCard"), object: nil
        )
    }
    isPresented = false
}

private func toggleCardVisibility() {
    guard let card = cardData else { return }
    if let onToggleVisibility {
        onToggleVisibility(card)
    } else {
        NotificationCenter.default.post(
            name: NSNotification.Name("ToggleCardVisibility"),
            object: nil,
            userInfo: ["cardId": card.id, "isPublic": card.isPublic]
        )
    }
    isPresented = false
}
~~~

Apply the same onTogglePin-or-notification pattern to toggleCardPin(). Do not change the layout, labels, routes, or existing Home call site.

- [ ] **Step 3: Run the focused source-contract test and verify it is still RED**

Run the Task 1 Swift Package command. Expected: it now fails only on the My Profile assertions; this proves the popup API is present before the owning screen is changed.

### Task 3: Align My Profile with owned Home cards and community chat

**Files:**
- Modify: ArcNote/MyProfileView.swift:1-315

**Interfaces:**
- Consumes: HomeCardsManager.deleteCard, toggleCardVisibility, toggleCardPin; NetworkManager.createConversation; UserPostCard.
- Produces: local owner-card mutations and a ChatDetailView route.

- [ ] **Step 1: Remove the credit stat and select the owner-card grid**

Delete the third statistics HStack that displays creditTotal, the Credits label, and my-profile.credit-balance. In the UserPostCard.onShowMenu closure, change:

~~~swift
popupMenuLayout = .grid2x2
~~~

to:

~~~swift
popupMenuLayout = .grid3x3
~~~

- [ ] **Step 2: Add chat state and reuse the existing conversation flow**

Import Combine, then add state for navigateToChat, conversationId, isCreatingConversation, and Set<AnyCancellable>. Pass this exact card callback:

~~~swift
onChatTap: {
    createConversation()
},
~~~

Add a navigationDestination for ChatDetailView and copy the existing UserProfileView.createConversation() lifecycle, using the current profile actor ID with the signed-in actor ID as fallback. Keep the in-flight guard, main-thread delivery, and unauthorized notification behavior.

- [ ] **Step 3: Add local owner-card mutation state and callbacks**

Add cardToDelete, showDeleteConfirmation, isDeletingCard, and deleteErrorMessage state. Pass the local actions through the popup:

~~~swift
.popupMenu(
    isPresented: $showPopupMenu,
    layout: popupMenuLayout,
    cardData: currentMenuCardData,
    isOwnCard: true,
    onDelete: requestCardDeletion,
    onToggleVisibility: toggleCardVisibility,
    onTogglePin: toggleCardPin
)
~~~

Implement the functions by delegating to cardsManager. requestCardDeletion sets the selected card and opens a destructive native confirmation dialog; the confirm action calls deleteCard(cardId:), clears state on success, and sets a retryable alert message on failure. Both mutation functions pass the incoming card as fallbackCard so they do not depend on a stale list reload.

- [ ] **Step 4: Add native confirmation and failure surfaces**

Attach a destructive confirmationDialog to My Profile that is bound to showDeleteConfirmation, labels the destructive button Remove, disables it while isDeletingCard is true, and calls the deletion helper. Attach an alert bound to deleteErrorMessage != nil with one OK action that clears the message. Give the confirmation and buttons stable my-profile.delete.* accessibility identifiers where SwiftUI permits them.

- [ ] **Step 5: Run the source contract and UI test and verify GREEN**

Run the two Task 1 commands again. Expected: both PASS.

### Task 4: Build and inspect the shipped interaction

**Files:**
- No source changes expected.

- [ ] **Step 1: Run focused CoreFlow tests**

~~~bash
swift test --package-path Packages/CoreFlow \
  --filter MyProfileActionsSourceContractTests
~~~

- [ ] **Step 2: Build both requested app configurations**

~~~bash
xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote \
  -destination 'generic/platform=iOS Simulator'
xcodebuild build -project ArcNote.xcodeproj -scheme 'ArcNote Production' \
  -destination 'generic/platform=iOS Simulator'
~~~

- [ ] **Step 3: Inspect My Profile on a simulator**

Open My Profile and verify:

1. Header statistics contain only following and followers.
2. An owned card menu shows the complete 3 x 3 Home action grid.
3. Public/Private and Pin/Unpin refresh the card state, and Remove asks for confirmation before deletion.
4. The send-chat icon is visible, tappable, and creates/navigates only after a successful conversation response.
5. Home's same card menu still works after returning to Home.

- [ ] **Step 4: Review the diff and retain only scope-aligned changes**

~~~bash
git diff --check
git diff -- ArcNote/MyProfileView.swift ArcNote/PopupMenuView.swift \
  ArcNoteUITests/ArcNoteUITests.swift \
  Packages/CoreFlow/Tests/CoreFlowTests/MyProfileActionsSourceContractTests.swift
git status --short
~~~

Do not stage or commit unless the user explicitly requests it.

