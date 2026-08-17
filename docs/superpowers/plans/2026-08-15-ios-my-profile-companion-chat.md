# My Profile Companion Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the My Profile header chat shortcut create or open the conversation with the user's bound My Companion rather than attempting a self-conversation.

**Architecture:** `NetworkChoraProfileService` already validates the human-to-active-agent relationship and produces a `ChoraIdentity`. A small injected chat router will resolve that identity, send its `agentActorID` to the existing conversation endpoint, and return the conversation plus companion presentation data to `MyProfileView`. A DEBUG fixture will run the same router with a deterministic human/companion pair, allowing the UI test to prove that the requested conversation is keyed by the companion actor.

**Tech Stack:** SwiftUI, Combine, Swift concurrency, CoreFlow, XCTest UI tests.

## Global Constraints

- Target iOS 16+ and iPhone layouts.
- Preserve Community Profile chat behavior, the header shortcut placement, and the Home-equivalent My Profile menu.
- Reuse `CoreChoraProfileServing.identity(humanActorID:)` instead of independently selecting an agent ID.
- Keep the 44 by 44 point `my-profile.chat` target.
- Do not create a branch, commit, or alter unrelated working-tree changes.

---

### Task 1: Cover Companion Routing Through the Existing UI Fixture

**Files:**
- Modify: `ArcNoteUITests/ArcNoteUITests.swift:2112-2147`
- Modify: `ArcNote/ArcNoteApp.swift:528-564`

**Interfaces:**
- Consumes: `MyProfileView` test initializer hooks for a `MyCompanionChatRouting` implementation and a `ChatDetailFetching` implementation.
- Produces: UI assertion that tapping `my-profile.chat` loads conversation ID `conversation_with_act_agent_fixture`.

- [x] **Step 1: Write the failing UI assertion**

```swift
chat.tap()
XCTAssertEqual(
    waitFor("chat.detail.conversation-id", timeout: 10).label,
    "conversation_with_act_agent_fixture"
)
```

- [x] **Step 2: Run the focused test to verify the expected failure**

Run:

```bash
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' -only-testing:ArcNoteUITests/ArcNoteUITests/testMyProfileHeaderExposesChatShortcutWhileCardsKeepHomeActions
```

Expected: FAIL because the fixture has no authenticated human actor and the current implementation attempts to target that human actor directly.

- [x] **Step 3: Add a deterministic fixture seam**

```swift
let chatRouter = NetworkMyCompanionChatRouter(
    profileService: ChoraProfileFixtureService(mode: .loaded),
    conversationCreator: MyProfileFixtureConversationCreator()
)

MyProfileView(
    cardsManager: cardsManager,
    loadsDataOnAppear: false,
    companionChatRouter: chatRouter,
    chatDetailFetcher: chatDetailService
)
```

The fixture identity must map `act_my_profile_fixture` to `act_agent_fixture`; its conversation creator must derive the returned conversation ID from the received participant actor ID.

- [x] **Step 4: Re-run the focused UI test to verify the fixture remains deterministic**

Run the Step 2 command again.

Expected: still FAIL until the production router and `MyProfileView` use the fixture seam.

### Task 2: Route the Header Action to the Bound Companion

**Files:**
- Modify: `ArcNote/MyProfileView.swift:1-449`

**Interfaces:**
- Consumes: `CoreChoraProfileServing.identity(humanActorID:) async throws -> ChoraIdentity`.
- Produces: `MyCompanionChatRouting.openConversation(humanActorID:) async throws -> MyCompanionChatDestination` and `MyCompanionConversationCreating.createConversation(participantActorID:) async throws -> CreateConversationData`.

- [x] **Step 1: Define the route contracts and network adapters**

```swift
struct MyCompanionChatDestination: Equatable {
    let conversationID: String
    let companionName: String
    let companionAvatarURL: String?
}

@MainActor
protocol MyCompanionChatRouting {
    func openConversation(
        humanActorID: String
    ) async throws -> MyCompanionChatDestination
}
```

`NetworkMyCompanionChatRouter` must call `identity(humanActorID:)`, reject an identity whose human and agent IDs match, and pass only `identity.agentActorID` to `MyCompanionConversationCreating`.

- [x] **Step 2: Replace the self-targeting action**

```swift
Task { @MainActor in
    let destination = try await companionChatRouter.openConversation(
        humanActorID: humanActorID
    )
    chatDestination = destination
    navigateToChat = true
}
```

Use `chatDestination.companionName` and `chatDestination.companionAvatarURL` when constructing `ChatDetailView`; preserve the existing unauthorized notification for a failed conversation POST.

- [x] **Step 3: Run the focused UI test to verify Companion routing**

Run the Task 1 test command.

Expected: PASS and the visible chat destination is loaded with `conversation_with_act_agent_fixture`, not a conversation ID containing `act_my_profile_fixture`.

### Task 3: Verify the iOS Targets

**Files:**
- Verify: `ArcNote/MyProfileView.swift`
- Verify: `ArcNote/ArcNoteApp.swift`
- Verify: `ArcNoteUITests/ArcNoteUITests.swift`

- [x] **Step 1: Run the focused UI test and adjacent regression test**

```bash
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' -only-testing:ArcNoteUITests/ArcNoteUITests/testMyProfileHeaderExposesChatShortcutWhileCardsKeepHomeActions -only-testing:ArcNoteUITests/ArcNoteUITests/testChatUsesBrandFallbackAvatarForBackendDefaultAvatar
```

Expected: both tests pass.

- [x] **Step 2: Build both app schemes and check the patch**

```bash
xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote -destination 'generic/platform=iOS Simulator'
xcodebuild build -project ArcNote.xcodeproj -scheme 'ArcNote Production' -destination 'generic/platform=iOS Simulator'
git diff --check
```

Expected: both builds succeed and the whitespace check emits no output.

## Self-Review

- Spec coverage: Task 2 changes only the My Profile header target from the human actor to the validated active Companion actor; Task 1 proves the selected participant at the UI boundary; Task 3 checks the user-facing regression surface and both build schemes.
- Placeholder scan: no TBD/TODO or generic testing steps remain.
- Type consistency: the `MyCompanionChatRouting` output is the same destination consumed by `MyProfileView` and rendered by `ChatDetailView`.
