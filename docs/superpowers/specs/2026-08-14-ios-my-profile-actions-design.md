# iOS My Profile Card Actions Design

**Date:** 2026-08-14  
**Status:** Implementation-ready

## Goal

Bring the native **My Profile** surface in line with the card interactions on
Home while reclaiming the crowded profile-header space:

1. Remove the credits statistic from My Profile only.
2. Give each owned card the same nine Home actions: Edit, Spark, Merge,
   Public/Private, Share, Link, Root, Remove, and Pin/Unpin.
3. Add the same card-level chat affordance used on community profiles.

## Current State and Root Cause

`MyProfileView` renders credits alongside following and followers, even though
credits are already available from the sidebar and settings. Its cards select
the four-tile `.grid2x2` popup, whereas Home-owned cards use `.grid3x3`.

The larger popup is not sufficient by itself: its Remove, Public/Private, and
Pin/Unpin actions currently post global notifications that only Home handles.
When My Profile is presented over the Home hierarchy, forwarding those events
globally risks a hidden Home view acting as well. My Profile also omits the
`UserPostCard.onChatTap` closure that Community Profile supplies.

## Chosen Design

### Header

Remove the credits statistic and its accessibility element from
`MyProfileView`. Keep credit loading and the shared balance model untouched:
the sidebar and credit screens still use them, and this change is visual scope
only. Following and followers remain tappable and retain their identifiers.

### Owned-card menu

Use `.grid3x3` for every My Profile card. Extend the reusable popup-menu API
with optional local callbacks for Remove, visibility, and pin changes. Its
existing notification behavior remains the default for current callers, so
Home stays unchanged; My Profile supplies local callbacks and owns all three
mutations through its existing `HomeCardsManager`.

Remove opens a native destructive confirmation before calling
`deleteCard(cardId:)`. Visibility and pin mutations call the same
`HomeCardsManager` APIs used by Home, passing the selected card as the
fallback. This preserves the existing optimistic/reload behavior without
adding a second card state source or new network endpoint.

### Chat shortcut

Pass `onChatTap` to `UserPostCard`, matching `UserProfileView`. The callback
uses the existing `NetworkManager.createConversation` flow for the current
profile actor, then navigates to `ChatDetailView` only after a successful
conversation response. The control keeps the existing `send_chat` asset and
gets an explicit VoiceOver identifier.

This intentionally mirrors the Community Profile interaction requested for
the My Profile cards. If the server rejects self-participant conversations,
the existing failure handling keeps the user on the profile rather than
navigating with an invalid conversation ID.

## Error Handling and Accessibility

- Disable duplicate chat and delete requests while each is in flight.
- Preserve the existing `UnauthorizedError` handling for chat failures.
- Surface a concise retryable deletion failure alert.
- Retain 44 pt native action-box tiles and label the added chat button for
  VoiceOver.
- Do not change API hosts, payloads, or persistence.

## Verification Strategy

Use red-green-refactor:

1. Add a focused CoreFlow source-contract test that asserts My Profile has no
   credits surface, uses the Home owner menu layout, supplies local mutation
   callbacks, and wires the community-card chat callback.
2. Run it to observe the expected failure.
3. Implement the smallest SwiftUI and popup-menu changes to make it pass.
4. Run the focused contract suite, build the default `ArcNote` and `ArcNote
   Production` schemes, and inspect the My Profile flow in the simulator.

## Acceptance Criteria

- My Profile shows following and followers but no credit value or Credits
  label.
- The My Profile overflow opens the nine owner-card actions used by Home.
- Remove, Public/Private, and Pin/Unpin act on the My Profile card only, with
  a destructive confirmation for removal.
- Each My Profile card displays the same send-chat affordance as Community
  Profile and opens a chat only after conversation creation succeeds.
- Existing Home menu behavior remains unchanged.
- Focused tests and both iOS build schemes pass.
