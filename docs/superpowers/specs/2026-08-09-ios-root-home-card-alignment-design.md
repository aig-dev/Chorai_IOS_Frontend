# iOS Root Home-Card Alignment Design

## Outcome

The discovery-path Root screen presents every path card with the same calm, body-first visual hierarchy as Home. Cards no longer render a title. Each card has a real 44-point overflow control in its upper-right corner, while the path role (Collected, Step n, or Origin) moves to the footer beside the existing tags.

## Options considered

1. Leave the current card surface and add only an ellipsis. This is the smallest change, but it leaves the title-first spacing and badge placement inconsistent with Home.
2. Rebuild the Root card around Home's header/body/tag hierarchy and reuse the existing popup-menu infrastructure with only actions supported by the discovery-path model. **Recommended.** It aligns the requested presentation without inventing missing visibility or pin state.
3. Expand `DiscoveryPathCard` and the network contract to carry every Home-card menu field. This would support the full owner menu, but it broadens a visual adjustment into an API/model change without a product need.

## Interaction and layout

- The Root screen keeps its back control and background, but removes the visible `Discovery Path` header title.
- Each card uses Home-aligned 20-point insets, a 40-point avatar, 16/12-point author and date metadata, body-first content preview, and Home-style tag chips.
- The title is omitted even if the API provides one. The content preview is the card's primary text.
- A trailing 44 by 44-point ellipsis button occupies the header's upper-right slot. It opens the existing popup menu with a `UserCard` assembled from reliable discovery-path fields.
- The menu uses the existing 2 by 2 layout: owners get Spark, Share, Link, and Edit; other authors get Spark, Report, Link, and View. Ownership is true only when a nonempty signed-in actor ID exactly matches `authorActorID`. No guessed public, pin, or background-media state is exposed.
- The path role moves into the footer as the first subdued capsule, before ordinary tags. `Collected` keeps the existing purple emphasis; intermediate steps are neutral; `Origin` keeps its amber emphasis. This preserves scanable path order without competing with the menu control.
- Card taps continue to use the existing View/Edit routing. The card body has its own button while the header overflow and footer remain sibling elements, so the ellipsis and path role retain independent accessibility. The ellipsis adds access to other existing actions; it does not replace card tapping.

## Accessibility and failure behavior

- The overflow control keeps a 44-point target, a clear VoiceOver label, and a stable `discovery-path.menu.<card-id>` identifier.
- Existing loading, empty, failure, retry, timeline order, and card-navigation behavior remain unchanged.
- Dynamic Type remains constrained by the current line limits where needed; title removal gives body text more vertical room.

## Verification

Add a focused source-contract test that proves the Root card has no title rendering, has the top-right menu affordance and accessible identifier, forwards a model to the existing popup menu, and renders the path role in the footer. Run that focused test, the existing discovery-path store tests, both local and production Xcode builds, and the existing discovery-path UI fixture.
