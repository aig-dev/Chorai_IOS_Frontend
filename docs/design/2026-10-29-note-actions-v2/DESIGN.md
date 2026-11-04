# Chorai · Note actions and Chat empty state · Review 02

Date: 2026-10-29. Status: independent design proposals, not native implementation.

## Scope and decisions already given by the user

- Explore, Home and Chat keep the approved compact centered header A.
- Spark results use Grid. A result opens the same note detail as ordinary Explore.
- Remove result selection circles and the global Continue action. Each result has a direct Spark action.
- Retain warm white, forest ink, restrained academic gold, tier-specific brushes and the existing Chora mapping.
- Grid omits Chora; full reading detail retains it. No editor engine or content format changes.
- No new service capability, API contract, fake contacts or automatic publication.

## Shared Grid and reading detail

`spark.html` uses one tile renderer for ordinary Explore and Spark results, and one reader renderer for both entry points. The outside-phone comparison switch changes the entry context without substituting another card component.

The current native rated Grid is the reference: grade badge, serif summary, author, bookmark and existing action menu; no new grid-only photograph, avatar or like row. Tier brush remains at the upper-right. The direct Spark button is placed in the existing bottom action row, alongside bookmark and more, to keep the brush visible and give every button a 44pt touch target.

Tap the summary to read the note. Tap the author for the existing author route. Spark and bookmark do not also open the reader.

The reader follows the ordinary native hierarchy: Back / Note / bookmark / more; tier and Chora identity; author with Message and Follow; full content; date, visibility, tags and related notes where present; then like, comment and collection counts. Engagement scrolls with the body. The prototype comment sheet only changes local sample state.

Production reuse targets: `ArcNote/CoreFlow/FlowViews.swift` (`ratedTile`), `ArcNote/DetailView.swift`, `ArcNote/CommentPopupView.swift`, `ArcNote/PopupMenuView.swift`. Do not fork a second Spark-only reader or bypass existing authorization/action stores.

## Direct Spark

Each button supplies its own note ID. From a Spark result or its detail, the next round also retains the current activity as parent; ordinary Explore begins a new root round. Reading, collecting, commenting or liking never changes the Spark source.

Keep the current result set until a new round succeeds. While pending, block repeat starts. Failure keeps the current grid and offers retry; Back returns to the preceding result set. Do not display x/x progress or imply an artificial usage limit. In this HTML proposal, results and errors are offline fixtures.

When wiring the native detail, pass the Spark context through the existing route/action callback. Do not infer the source from the last viewed card, a stale selection, the original root note or a display title.

## Gestures

| Surface | Long press | Swipe left | Swipe right |
| --- | --- | --- | --- |
| Home / My Notes | Existing owner menu | Reveal Remove; tap; confirm move to Trash | Reveal Edit; tap; open existing full-page editor |
| Home / Collections | Existing collection menu | Remove from collection | No edit action |
| Explore swipe deck | Existing note menu on non-control surface | Existing Skip | Existing Collect |
| Explore / Spark Grid | Same note menu as more | Keep vertical Grid browsing | Keep vertical Grid browsing |
| Reader body / editor | Keep text selection and editing | Existing navigation only | Existing navigation only |

The prototype starts long press at about 450ms. Movement cancels it; a clear horizontal intent is required for Home row actions. Tag scrolling and vertical scrolling retain priority. Only one row can stay open; starting another row closes the first. The ellipsis remains an accessible alternative to hidden gestures.

Owner menu retains Edit, Spark, Merge, Share, Link, Root, Public/Private, Pin/Unpin and Remove. Collection menu retains View, Spark, Share, Link, Root and Report. No duplicate, copy, read-later or new ownership power is added.

Destructive confirmation reuses the existing strings: “Remove this note?” / “This note will move to Trash.” / “Remove” / “Cancel”. A full swipe never deletes immediately. Collection removal keeps its current separate semantics and does not delete the author's note.

Native implementation must reuse `OwnedCardActionStore` removal state, permission checks, pending locks and acknowledged result ID. Home currently uses a custom ScrollView/LazyVStack; preserve its approved typography and spacing when introducing a horizontal action container. Do not migrate Home to a visually different list just to obtain gestures. Minimum touch targets remain 44pt. Respect Dynamic Type, Reduce Motion and Reduce Transparency; expose actions to accessibility.

## Chat empty state

Three independent image explorations are stored in `chat-designs/option-1.png` through `option-3.png`, numbered in the order shown to the user. They are visual proposals, not screenshots of the native app. They preserve the approved compact header and tab navigation.

The only proposed CTA is “Explore notes”. It opens the existing Explore tab; users then use the existing Message author or profile Chat action. Native wiring can pass an `onExplore` callback to ChatView. Do not invent a contact picker, online presence, suggested people or an AI assistant conversation.

These images represent a successful load with zero conversations. Fetching, errors and search with no matches must remain separate states; an error must not appear as an empty account. The current search control is not evidence of a working people-search feature.

## Review and verification boundaries

- Original prototypes are preserved; this folder is a new revision.
- App source, package versions, backend and installed app are not changed in this round.
- HTML interaction checks establish only the behavior of these local proposals.
- Chat images compare visual directions. Selection does not establish pixel-perfect iOS materials or completed native implementation.
- Browser screenshots and preservation results are stored under `qa/`.
