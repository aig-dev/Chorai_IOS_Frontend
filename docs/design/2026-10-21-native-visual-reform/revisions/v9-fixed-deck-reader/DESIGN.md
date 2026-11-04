# V9 · Fixed Explore deck and full-page reading

Status: review proposal requested on 2026-10-26. Explore and reader production views are not changed by this proposal. Earlier V1–V8 artifacts remain intact.

## Decisions from the review

The user chose a fixed summary card with tap-through to the full note. Card height must depend on the available screen, never on the note length. Remove the bottom Previous control and Skip/Collect instructions. Make the card larger, leave the surrounding page clear, and reveal gesture meaning while dragging. Reading detail is a document page, not a card inside a page.

The Home body-to-tags gap and editor tools position are separate fidelity corrections to the already approved V6 design. The empty editor must provide a full writing surface and hide the Home tab bar. These corrections are implemented in the actual App and recorded separately.

## Explore proposal

- One stable card rectangle per screen size. Photo, long essay, short note, quotation, checklist, code and reference occupy the same rectangle. Content changes never move its lower edge.
- The card expands into the space previously occupied by Previous and instructions. Keep a small clear gap before the system tab bar; there is no opaque footer covering content and no fade used to conceal overflowing text.
- A bounded preview adapts to the content type: a photo with its authored caption, a text excerpt, a quote, a compact checklist or code sample. The preview is not the full note. The card does not scroll internally. Tap the preview to open the complete document.
- Author, grade, Spark, More, tags and existing engagement actions retain their meanings. The right-hand tier brush stays visible; its color continues to express the card grade, not swipe direction. The Grid remains a separate browsing mode and does not inherit fixed deck heights.
- At rest there is no swipe slogan or Skip/Collect button pair. During a horizontal drag the card follows the finger with a restrained tilt; a small labeled feedback mark appears on the leading side. Left is neutral Skip; right is forest Collect with a bookmark. Avoid red/green full-card flashes that compete with tier colors.
- Below the completion threshold, releasing springs the card back. Beyond it, left advances into recorded history. Right is an explicit collection request; an eventual production implementation must stay on the card until the actual collection succeeds, and show an error without advancing on failure. The proposal only changes in-memory sample state.
- Keep recovery without a persistent bottom button: a small history icon near the feed index opens a native history sheet. Selecting an earlier card revisits it and keeps the unread frontier. Continuing exploration returns to that frontier.
- Respect Reduce Motion by removing the rotational departure and keeping a short state transition. VoiceOver actions and the More menu provide Skip/Collect alternatives without requiring a drag. Large text reduces the amount of preview rather than expanding the card; the full reader remains available.

Alternatives considered: a fixed card with an internally scrolling body would retain more preview text but compete with horizontal gestures; the user explicitly selected summary plus detail. A full-card direction tint would be more conspicuous but confuse grade color and dominate the note; the localized labeled mark is preferred.

## Full-page reader proposal

- A native destination with Back, bookmark and More at the top. Hide the browsing tab bar while reading; Back restores the previous card or Grid position.
- The warm white or dark reading background is the page itself. Remove the rounded enclosing surface, card border and large decorative clearance.
- Use one compact header for actual grade and author metadata. Place the existing small Chora and its corresponding brush as passive header ornament; neither implies growth or earned progress. No rating means no invented Basic badge.
- Put the complete authored body directly on the page, with serif reading type and comfortable margins. Preserve real heading blocks; do not create a separate title field or turn the first paragraph into a title.
- Keep author navigation, Follow and Message available. Keep explicit collection, Spark, Share/Link/Report and ownership-sensitive actions in their existing scopes. The concept may show local demonstration responses but must not imply that an API call succeeded.
- Tags, related-note relationships and engagement belong after the body. Long documents scroll as a single page, with all content reachable; no nested reading card.

An edge-to-edge article header with a full cover was considered, but it would give image notes a different hierarchy and fabricate a cover for text-only notes. The recommended common document structure handles both content types without adding fields.

## Review and validation

Deliver a separate native prototype, paired light/dark captures and a browser review surface. Test card-frame equality across short/long/media samples, drag cancellation, collection/history recovery and full reader navigation. Build and fixture checks are not production, live AI, persistence or deployment validation.

Implementation of the new Explore and reader layouts follows the user's visual review; this document is a proposal, not a declaration that those production screens have already changed.
