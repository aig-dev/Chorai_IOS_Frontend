# Design QA — Flow Icon Engagement Bar

## Evidence

- Source visual truth: `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-892927b0-00a3-4964-8130-0f81ce5a0132.png`
- Implementation screenshot: `/tmp/FlowIconFinalAttachments-20260714-1711/A16C1C86-1F62-4403-9A0B-EF9831C9CE15.png`
- Active Favorite screenshot: `/tmp/FlowFavoriteActiveAttachments-20260714/45ED3810-FE91-4AB2-9E17-A9A088CDB373.png`
- Side-by-side comparison: `/tmp/chorai-flow-footer-comparison-final.png`
- Viewport: iPhone 17 Pro portrait, 1206 × 2622 px at 3×
- State: Flow card loaded; Favorite and Like inactive; engagement counts are zero

## Comparison history

1. The first pass placed the footer controls too high and gave the inactive Favorite icon too much contrast.
2. The footer was moved 18 points lower while preserving 44-point hit targets, and the inactive Favorite icon opacity was reduced.
3. The post-fix screenshot was captured from the focused XCUITest and compared directly with the source crop.

## Required fidelity surfaces

- Typography: numeric counts match the compact, secondary footer treatment.
- Spacing and layout rhythm: Favorite is isolated on the left; Like and Comment are grouped on the right near the card edge.
- Colors and tokens: inactive controls use the existing secondary foreground treatment; selected-state assets remain unchanged.
- Assets: the existing `favorite`, `like`, and `comment` image assets are used without raster scaling artifacts.
- Copy and content: the large `Skip`, `Save`, and `Spark` labels are absent from the footer.
- Interaction and accessibility: Favorite, Like, Comment, and Spark retain 44-point button targets, accessibility labels, and stable UI-test identifiers. Left and right swipes only advance the deck; neither changes Favorite state.
- Selected state: tapping Favorite keeps the current card visible, immediately swaps to the existing red `favorite_active` asset, increments the count, and exposes accessibility value `true`.
- Undo removal: Flow no longer exposes Saved/Undo notices, timers, retry actions, or restoration state. Favorite and Unfavorite are controlled exclusively through the Favorite icon.

## Findings

- P0: none.
- P1: none.
- P2: none after the footer-position and inactive-opacity adjustment.
- P3: the reference crop uses a brighter card border than the live screen. This is an existing card-surface token outside the requested footer-control change and was not modified.
- Console errors: not applicable to this native iOS screen.

final result: passed
