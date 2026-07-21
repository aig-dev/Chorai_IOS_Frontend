# iOS Spark Footer Interactions Design

## Goal

Make the Spark result card follow the Flow card's interaction hierarchy: the card body opens detail, the bottom-left favorite control changes favorite state in place, and Spark continuation remains an explicit header or popup-menu action.

## Interaction model

- Remove the bottom-center upward Spark cue.
- Remove upward-drag Spark continuation and its card-level accessibility action.
- Keep the top-right Continue Spark button and popup-menu Spark action; both continue the active same-page chain.
- Restrict the detail tap and horizontal browse gesture to the card content region, excluding the engagement footer.
- Turn the bottom-left favorite metric into a 44-point button with the same active icon, count, accessibility value, and placement as Flow.
- Favorite and unfavorite optimistically in place. A successful favorite retains the active Spark activity as discovery context and does not open detail or advance the deck.
- Match Flow's browsing rule: either horizontal swipe advances, and neither direction silently favorites. Favorite state changes only through the visible footer control.
- Remove the saved/undo overlay and its hidden save-and-advance state. Failure feedback is an inline text notice below the card.

## State and failure behavior

`SparkSessionStore` owns the optimistic footer mutation. It replaces only the current `SparkResult.card`, locks duplicate mutations, persists the optimistic state, and rolls the exact result back on API failure. Favorite uses `sparkActivityID`; unfavorite uses the existing unfavorite endpoint. A success callback delivers the saved asset ID directly to onboarding telemetry without creating visual notice state.

The persisted `didShowUpwardCue` field remains for snapshot compatibility, but the UI no longer consumes it.

## Accessibility and visual constraints

- Favorite has a minimum 44 x 44 hit target, `Favorite`/`Unfavorite` label, Boolean accessibility value, and stable `spark.favorite.<card-id>` identifier.
- The footer sits outside the detail tap region, preventing gesture fall-through.
- No favorite or Spark control overlaps the like/comment metrics.
- The visual treatment reuses the Flow card's icon sizes, spacing, subdued footer color, and bottom alignment.
