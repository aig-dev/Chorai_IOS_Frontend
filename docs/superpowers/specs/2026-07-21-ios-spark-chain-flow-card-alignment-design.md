# iOS Spark Chain and Flow Card Alignment Design

## Outcome

Continuing Spark from a result stays inside the current Spark workspace. The header immediately gains a pending sequential history node, then the same source strip and result deck update when the child activity resolves. Selecting an earlier node replays that activity in place.

Spark result cards use the current Flow card presentation language while retaining Spark-specific context and gestures.

## Interaction architecture

`SparkSessionStore` remains the only owner of the active activity, chain, source card, result deck, and loading phase. `SparkContinuationView` routes both its direct Spark control and its scoped popup-menu Spark action to `store.sparkCurrentDeeper()`. The shared popup menu retains its existing global navigation fallback everywhere outside the Spark workspace.

The chain rail derives its pending position from the active activity depth. When continuing from an ancestor, it temporarily renders only the prefix through that ancestor, then places the disabled loading node where the canonical child will land. The server response replaces it with the canonical activity node before the source strip and result deck change; a failure restores the prior branch.

## Card presentation

Spark result cards match the current Flow card conventions:

- 28-point continuous card radius, shared fill and border tokens, and 22-point inset.
- Author row with 44-point menu and direct Spark controls.
- Body-first presentation with no legacy title.
- Rounded 17-point body typography, matching tag chips, and optically balanced engagement icons.
- Spark bucket remains a quiet eyebrow because it explains why the result was generated.
- Existing left/right/up gestures, Reduce Motion, Reduce Transparency, Dynamic Type, VoiceOver actions, and loading lock remain intact.

## Failure behavior

A failed child trigger restores the prior node, visible card, and source through the existing store rollback. The pending rail node disappears, direct/menu/VoiceOver continuation actions stay unavailable, and the explicit Retry Spark control owns recovery. The popup-menu fallback still opens a new root Spark screen when invoked outside a Spark workspace.

## Verification

Source-contract tests protect the scoped menu route, direct continuation control, pending numbered node, and Flow-aligned card presentation. Existing CoreFlow lifecycle tests continue to prove canonical child appends, rollback, and ancestor replay. Both local and production schemes must build; the focused live UI flow should confirm one-page continuation and back-navigation depth.
