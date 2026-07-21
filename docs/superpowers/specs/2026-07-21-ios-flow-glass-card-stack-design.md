# iOS Flow Glass Card Stack Design

## Outcome

The iOS Flow screen keeps its current content, Spark action, tags, engagement
controls, navigation, and swipe semantics. Its foreground card gains the dark,
tinted glass quality of the approved reference, while two restrained rear
surfaces create a readable card-stack silhouette. Author avatars render from
both absolute and backend-relative `avatar_url` values instead of falling back
to the placeholder for valid relative paths.

## Scope

This change is limited to `ArcNote/CoreFlow/FlowViews.swift` and focused iOS
presentation tests unless implementation evidence requires a small supporting
view in the same app target.

In scope:

- Canonical resource-URL resolution for Flow author avatars.
- A reusable foreground glass surface and two non-content rear surfaces.
- Stack geometry, border highlights, tint, depth shadows, and accessibility
  fallbacks.
- Focused source-contract, build, and Simulator visual verification.

Out of scope:

- Changes to the Go API, `FlowCard`, or `FlowDeckStore` as data sources.
- Changes to card text, tags, engagement controls, Spark, menus, navigation, or
  swipe decisions.
- Rendering the next cards' private text or metadata through the rear surfaces.
- Broad visual changes outside Flow.

## Avatar root cause and data flow

The Go card contract permits relative avatar paths such as
`/uploads/avatars/pic.png`, and media uploads also produce paths under
`/chorai-assets/...`. `NetworkCoreFlowService` correctly preserves that value
in `FlowAuthor.avatarURL`, but `FlowCardView` currently passes it directly to
`URL(string:)`. Other working avatar views first call
`APIConfiguration.resourceURLString`, which resolves relative paths against the
active Local or Production API environment and preserves absolute HTTP(S)
URLs.

Flow will use the same single resolution path:

1. Trim and reject an empty `card.author.avatarURL`.
2. Pass the non-empty value through `APIConfiguration.resourceURLString`.
3. Construct a `URL` from the resolved value.
4. Render the successful `AsyncImage` as aspect-fill in a circular 32-point
   frame.
5. Keep the quiet person placeholder for nil, invalid, loading, and failed
   states without logging sensitive URLs.

No second avatar field or cached source of truth will be introduced.

## Card-stack composition

`FlowDeckView.loadedDeck` remains the owner of deck composition. It renders one
foreground `FlowCardView` plus at most two decorative backplates based on the
number of available future cards:

- Depth 0: the interactive foreground card at its existing bounds.
- Depth 1: scale `0.972`, horizontal offset `7`, vertical offset `14`.
- Depth 2: scale `0.944`, horizontal offset `14`, vertical offset `28`.

The backplates are drawn rear-most first so their bottom and right edges remain
visible. They contain no card data, accept no hit testing, and are hidden from
accessibility. A deck with one or two available cards renders only the layers
that correspond to real cards; it never implies unavailable content.

Only the foreground card participates in the existing drag gesture. On a
successful dismissal, the current `FlowDeckStore` advance causes the next card
to become the foreground card. Existing Reduce Motion behavior continues to
remove the fly-out animation.

## Glass visual system

The foreground and rear surfaces share the existing 28-point continuous corner
radius and use a dedicated Flow glass-surface primitive. The visual treatment
combines:

- Native `ultraThinMaterial` for environmental blur when transparency is
  allowed.
- A dark violet tint over the material so white text retains current contrast.
- A one-point edge treatment that is brightest at the top-left and quieter at
  the right and bottom, matching the reference's light-catching rim.
- A soft black depth shadow below the foreground card and progressively quieter
  violet edge light on the rear surfaces.
- Slightly lower opacity and contrast at each rear depth so the stack reads as
  depth, not three competing cards.

The effect must remain restrained: card content stays the visual focus, no rear
surface contains decoration, and highlights must not wash out text or controls.
The existing page background remains unchanged and supplies the color sampled
by the material.

When Reduce Transparency is enabled, all surfaces use the existing opaque dark
violet fallback instead of Material. Increased Contrast strengthens the edge
stroke. Rear layers remain visually distinguishable in both modes.

## Interaction and accessibility

- Existing 44-point menu, Spark, engagement, and comment hit areas remain
  unchanged.
- The avatar remains part of the existing author button and does not create a
  second action.
- Rear surfaces use `allowsHitTesting(false)` and
  `accessibilityHidden(true)`.
- Dynamic Type continues to affect foreground content only.
- Swipe thresholds, haptics, interaction locking, failure notices, and card IDs
  remain unchanged.
- A failed avatar request degrades to the placeholder without affecting author
  navigation or card layout.

## Test and verification strategy

Implementation follows a red-green-refactor cycle.

Focused contract tests will first fail while asserting that:

- Flow avatar URLs pass through `APIConfiguration.resourceURLString` before
  `AsyncImage` receives them.
- The loaded deck can render two non-interactive, accessibility-hidden rear
  glass surfaces.
- The foreground surface uses Material and keeps the explicit Reduce
  Transparency fallback.
- Existing body-first content, engagement controls, and swipe wiring remain in
  the isolated `FlowCardView` source.

After the focused tests pass:

1. Run the full CoreFlow package suite.
2. Build both `ArcNote` and `ArcNote Production` for an iOS Simulator.
3. Launch Flow with a Go-backed card whose avatar is a relative path and confirm
   the real image renders.
4. Capture the same dark-mode Flow state used for visual review and compare it
   with the approved reference: one foreground card, two clearly visible rear
   rims, dark violet glass, a fine highlighted edge, and readable content.
5. Verify a swipe advances the deck and keeps all existing actions functional.
6. Repeat the visual check with Reduce Transparency and Increased Contrast.
7. Record comparison evidence in
   `docs/qa/ios-flow-glass-card-stack-design-qa.md`.

## Acceptance criteria

- Valid absolute and relative avatar URLs render the author image in Flow.
- Main plus two rear surfaces are visible when at least three cards are
  available; fewer cards produce only the truthful number of layers.
- The foreground reads as dark tinted glass, with a visible light-catching rim
  and separation from the rear layers at the reference viewport.
- Rear surfaces reinforce depth without showing content or accepting input.
- Existing Flow navigation, Spark, tags, engagement, comments, and left/right
  dismissal behavior remain intact.
- Reduce Motion, Reduce Transparency, Increased Contrast, Dynamic Type, and
  VoiceOver behavior remain usable.
- Focused tests, the full CoreFlow suite, both schemes, and Simulator visual QA
  provide fresh passing evidence.
