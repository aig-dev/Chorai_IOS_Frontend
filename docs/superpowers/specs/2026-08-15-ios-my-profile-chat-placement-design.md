# My Profile Chat Entry Placement Design

> Supersedes the chat-placement decision in `2026-08-14-ios-my-profile-actions-design.md`.

## Goal

Move the My Profile chat shortcut out of every note card and into the profile header's avatar and identity area, matching the placement shown in the supplied Community Profile reference.

## Current Context

`MyProfileView` currently passes `createConversation()` to each shared `UserPostCard`. That renders a chat button in every note's engagement row. The profile header already owns the avatar, username, follower counts, and the existing conversation state and navigation destination.

## Decision

- Add one trailing `send_chat` button to the My Profile header's username row, beside the identity area and above the follower statistics.
- Keep the visual language of Community Profile's header action while giving the target a 44 by 44 point hit area.
- Give the action the stable identifier `my-profile.chat` and the accessible label `Chat`.
- Invoke the existing `createConversation()` method from this header action; do not change its networking, navigation, or error handling behavior.
- Stop passing `onChatTap` from `MyProfileView` into `UserPostCard`, so My Profile note cards no longer render `profile.chat.<card-id>`.
- Leave `UserProfileView` and Community Profile's existing chat behavior unchanged.

## Verification

- Keep the source contract focused on the existing Credits and Home-menu guarantees.
- Update the fixture-driven UI test to assert the real rendered behavior: `my-profile.chat` is visible and at least 44 points in each dimension, while `profile.chat.my-profile-actions-fixture` is absent.
- Re-run the focused CoreFlow test, the two My Profile UI regressions, and both iOS build schemes.

## Scope Boundaries

- The prior Credits removal and the Home-equivalent card menu remain intact.
- No backend endpoint or conversation payload changes are needed.
