# Flow Icon Engagement Bar Design

## Status

Approved visual target supplied by the user; implementation follows the attached Explore footer reference.

## Context

The current iOS Flow card renders engagement counts in one row and then adds a second row of large `Skip`, `Save`, and `Spark` text buttons. This duplicates actions, consumes vertical space, and does not match the compact card footer used by the product reference.

The existing iOS asset catalog already contains the exact visual language shown in the reference: `favorite`/`favorite_active`, `like`/`like_active`, `comment`, and `menu_spark`.

## Design

- Remove the visible `Skip`, `Save`, and `Spark` text-button row.
- Render one compact footer row inside the card:
  - left: favorite/Save icon and `favoriteCount`;
  - right: Like icon and `likeCount`, followed by Comment icon and `commentCount`.
- Keep each icon/count pair visually transparent, with no capsule or filled button background.
- Move Spark to a compact icon-only control beside the existing overflow menu in the card header.
- Remove the visible Skip control. Left swipe remains the only direct dismiss gesture.
- Preserve 44-point interactive hit areas and descriptive VoiceOver labels even though visible text labels are removed.

## Interaction Semantics

- Tapping Favorite toggles the current card in place: inactive is gray, active uses the red `favorite_active` asset, and the count updates immediately.
- A failed Favorite mutation restores the prior icon and count and surfaces an inline error.
- Like continues to toggle in place and preserves optimistic/error behavior.
- Comment opens the existing comment popup for the current card.
- Spark invokes the existing Spark route without changing its API or state flow.
- Left and right swipes both advance the deck without mutating favorite state.
- Favorite state is changed only by tapping the Favorite icon.
- Flow has no Saved/Undo notice, undo timer, or undo retry state.

## Compatibility

- Keep `flow.favorite.<card-id>`, `flow.spark.<card-id>`, and `flow.like.<card-id>` automation identifiers on their icon controls.
- Add `flow.comment.<card-id>` for the comment icon.
- Remove `flow.skip.<card-id>` because no visible Skip control remains.
- Remove `flow.undo`; Flow no longer exposes an undo action.
- Update UI journeys that used `flow.skip` to swipe the card left instead.

## Non-goals

- No backend, API contract, or web frontend changes.
- No redesign of the card body, navigation shell, Spark results, or comment popup.
- No new icon assets.

## Validation

- A focused XCUITest verifies the footer ordering, Spark header placement, absence of a Skip control, red Favorite activation without advancing the card, and the left-swipe dismissal path.
- Existing Flow like, swipe, Spark, and onboarding UI tests remain compatible.
- A focused right-swipe test verifies that the card advances without changing favorite state or exposing Undo.
- Build the iOS app for the available simulator.
- Capture the rendered Flow card and compare its footer region with the supplied reference.
