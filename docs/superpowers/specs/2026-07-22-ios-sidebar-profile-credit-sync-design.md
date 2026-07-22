# iOS Sidebar Profile and Credit Sync Design

**Date:** 2026-07-22
**Status:** Approved direction; written specification pending review

## Goal

Bring the iOS sidebar header into line with Personal Profile and the current
credit semantics:

1. The sidebar avatar and cover use the current user's profile media.
2. No following or follower content is visible before the drawer surface
   reaches it during the opening animation.
3. Every value labelled `SYN` is the ordinary `credit` balance only and never
   includes `premium_credit`.

The scope is the native iOS app. The matching view is
`ArcNote/SideMenuView.swift`; the similarly named web sidebar is not part of
this change.

## Current State and Root Cause

`SideMenuView` already observes `UserProfileManager.shared`, but only the
avatar reads `userProfile.avatar`. Its cover is the bundled `side_bg` image,
so it cannot reflect a background changed in Personal Profile.

The drawer stays mounted while closed and is moved left by exactly
`adaptiveLayout.drawerWidth`. SwiftUI frames constrain layout but do not clip
descendant drawing. The following/follower row can therefore draw beyond the
nominal drawer width and remain visible at the screen edge before the rest of
the drawer arrives.

`UserProfileManager.creditTotal` currently adds every returned tier. Both
`SideMenuView` and `MyProfileView` label that sum as `SYN`, which incorrectly
includes `premium_credit`.

## Chosen Design

### Profile media

The sidebar header will render both media values from the same
`UserProfileManager.userProfile` object used by Personal Profile:

- Resolve `background` with `APIConfiguration.resourceURLString` and render it
  as an aspect-fill `AsyncImage` over the full header area.
- Keep `side_bg` as the fallback when the profile has no usable background or
  remote loading fails.
- Resolve `avatar` through the same profile resource path and keep the bundled
  `avatar` image as its fallback.
- Retain a restrained dark/gradient overlay so variable user media does not
  reduce the username and balance contrast.

Opening the sidebar continues to call `fetchCurrentUserProfile()`. Because
`SideMenuView` observes the shared manager, media saved by Personal Profile is
also reflected immediately from the shared in-memory value and refreshed from
the server on the next open.

### Drawer composition and animation

The dimming scrim remains a sibling behind the drawer. The complete drawer
surface—including cover, avatar, profile statistics, navigation, and glass
background—remains in one moving container.

Modifier order is significant:

1. Lay out that container at `adaptiveLayout.drawerWidth`.
2. Clip descendant drawing to that width.
3. Apply the open/closed horizontal offset to the clipped result.

This fixes the layer boundary itself. It does not delay or fade the statistics,
so all content continues to move as one coherent surface and reduced-motion
behavior remains predictable.

### SYN balance semantics

Expose a clearly named `synBalance` computed value from
`UserProfileManager`. It filters balances to `credit_tier == "credit"` and
sums only those entries. `premium_credit` and unknown future tiers are ignored.

Both native views that render a value labelled `SYN`—`SideMenuView` and
`MyProfileView`—will use `synBalance`. This prevents the two profile surfaces
from drifting while leaving the invitation/credit screens free to display
ordinary and premium balances separately.

## Loading and Failure Behavior

- Existing profile media may stay visible while a refresh is in flight.
- The existing `--` loading treatment remains for profile statistics and SYN.
- If profile media is absent or fails to load, bundled fallbacks are shown.
- If the balance request fails, the last in-memory balance remains available;
  the existing request error behavior is unchanged.
- No new network endpoints, persistence, or premium-credit transformations are
  introduced.

## Verification Strategy

Implementation follows a red-green-refactor cycle.

1. Add a failing contract/unit test proving that `SYN` selects only `credit`
   when `credit` and `premium_credit` coexist.
2. Add a failing sidebar source/presentation contract proving that the cover
   reads the current profile background and that the fixed-width moving drawer
   clips descendant drawing before offsetting.
3. Make the smallest production changes that satisfy those tests.
4. Run the focused CoreFlow/source-contract tests and the iOS build.
5. Launch the relevant simulator flow and visually inspect the closed,
   opening, and fully open states against the supplied screenshot.

The implementation must not modify or stage the unrelated changes currently in
`CommentPopupView.swift`, `CoreShellViews.swift`, or existing UI-test work.

## Acceptance Criteria

- A changed Personal Profile avatar appears in the sidebar without a separate
  sidebar-specific setting.
- A changed Personal Profile background appears as the sidebar cover, with the
  bundled cover used only as fallback.
- Following/follower content never appears outside the moving drawer during
  opening or closing.
- With `credit = 12` and `premium_credit = 4`, every native `SYN` label displays
  `12`, not `16`.
- Existing sidebar destinations, tap handling, unread indicator, and adaptive
  drawer width continue to work.
- Focused tests and the iOS build pass, and the animation is visually checked
  on a simulator.
