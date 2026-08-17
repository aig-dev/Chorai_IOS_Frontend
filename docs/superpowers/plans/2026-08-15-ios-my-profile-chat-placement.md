# My Profile Chat Entry Placement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Place the My Profile chat shortcut in the profile header and remove it from individual note cards.

**Architecture:** `MyProfileView` already owns the conversation state and `createConversation()` action. The header will call that action directly; omitting the optional `onChatTap` callback from its `UserPostCard` construction prevents the shared card from rendering a chat control. `UserProfileView` remains unchanged.

**Tech Stack:** SwiftUI, XCTest UI tests, Swift Package Manager.

## Global Constraints

- Target iOS 16+ and iPhone layouts.
- Preserve Community Profile behavior and the existing Home-equivalent My Profile menu.
- Use a 44 by 44 point minimum touch target for the header action.
- Do not create a branch, commit, or alter unrelated working-tree changes.

---

### Task 1: Relocate the My Profile Chat Shortcut

**Files:**
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`
- Modify: `ArcNote/MyProfileView.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/MyProfileActionsSourceContractTests.swift`

**Interfaces:**
- Consumes: `MyProfileView.createConversation() -> Void` and `UserPostCard(onChatTap: (() -> Void)?)`.
- Produces: Header button `my-profile.chat`; no `profile.chat.<card-id>` control in My Profile cards.

- [x] **Step 1: Write the failing UI assertion**

```swift
let chat = waitForButton("my-profile.chat")
XCTAssertGreaterThanOrEqual(chat.frame.width, 44)
XCTAssertGreaterThanOrEqual(chat.frame.height, 44)
XCTAssertFalse(app.buttons["profile.chat.my-profile-actions-fixture"].exists)
```

- [x] **Step 2: Run the focused UI test to verify the expected failure**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter MyProfileActionsSourceContractTests
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' -only-testing:ArcNoteUITests/ArcNoteUITests/testMyProfileHeaderExposesChatShortcutWhileCardsKeepHomeActions
```

Expected: the UI test fails because the header button does not exist and the card button is still present.

- [x] **Step 3: Implement the minimal header action**

```swift
Button(action: createConversation) {
    Image("send_chat")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 24, height: 24)
        .frame(width: 44, height: 44)
}
.accessibilityIdentifier("my-profile.chat")
```

Remove the `onChatTap` argument from only the `UserPostCard` created in `MyProfileView`.

- [x] **Step 4: Run the focused tests to verify the implementation passes**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter MyProfileActionsSourceContractTests
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' -only-testing:ArcNoteUITests/ArcNoteUITests/testSidebarShowsCreditWhileMyProfileOmitsIt -only-testing:ArcNoteUITests/ArcNoteUITests/testMyProfileHeaderExposesChatShortcutWhileCardsKeepHomeActions
```

Expected: one CoreFlow source contract and two UI tests pass.

- [x] **Step 5: Build both iOS schemes and check the diff**

Run:

```bash
xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote -destination 'generic/platform=iOS Simulator'
xcodebuild build -project ArcNote.xcodeproj -scheme 'ArcNote Production' -destination 'generic/platform=iOS Simulator'
git diff --check
```

Expected: both builds succeed and the diff check emits no output.
