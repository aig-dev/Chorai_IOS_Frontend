# Card Editor design QA

## Comparison target

- Source visual truth:
  - Requested mainstream Action Box alignment: `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-2702f55f-cc5d-4122-8ad8-d00ecbe57b45.png`
  - View Card metadata styling: `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-39c2fe64-c184-436a-a5a6-3547b7c6ae3f.png`
  - Previous literal-HTML failure: `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-5ceed2ac-45e2-45b1-86de-fd5c75f0daef.png`
- Final live implementation:
  - Mainstream View Card Action Box: `/tmp/ChoraiActionBoxLiveFinalReady3Attachments/022917F1-BD42-4A4F-8A50-BF0395AC7302.png`
  - Editor Action Box, default text: `/tmp/ChoraiActionBoxLiveFinalReady3Attachments/CBFC9C3C-2631-4459-B5AC-685CD0FB19F5.png`
  - Editor Action Box, Accessibility XXXL: `/tmp/ChoraiActionBoxLiveFinalReady3Attachments/ADDB2D14-5E1C-4D82-9020-26C79890D222.png`
  - Background staged before save: `/tmp/ChoraiActionBoxLiveFinalReady3Attachments/16CA2A66-F1F9-4165-9904-252923C25B95.png`
- Viewport: iPhone 17, 402 x 874 points, 1206 x 2622 pixels, iOS 26.2 Simulator.
- State: dark theme; real Go-backed cards; default and Accessibility XXXL text sizes.

## Combined comparison evidence

`docs/qa/card-editor-action-box-comparison.png` places the reference and implementation in one visual input, in this order:

1. top left: the reported native vertical Card Actions mismatch;
2. top right: the product's mainstream View Card 3 x 3 Action Box;
3. bottom left: the final editor Action Box at default text size;
4. bottom right: the final editor Action Box at Accessibility XXXL.

The two live default captures use the same device, viewport, shared Action Box surface, tile geometry, symbols, color treatment, corner radius, and close control. The editor intentionally substitutes `Background` for `Edit`, keeps the middle-left slot empty, and keeps privacy as a direct control beside More.

## Findings

No actionable P0, P1, or P2 visual or interaction mismatch remains.

- Action Box structure: the editor now uses the shared square/glass 3 x 3 Action Box instead of a native vertical confirmation dialog.
- Fixed editor placement:
  - row 1: `Background`, `Spark`, `Merge`;
  - row 2: empty, `Share`, `Link`;
  - row 3: `Root`, `Remove`, `Pin` or `Unpin`.
- Background copy and behavior: exactly one `Background` action is shown for both add and replace. There is no `Remove Background` action.
- Privacy placement: `Make Public` / `Make Private` remains a direct 44-point control immediately beside More and is not duplicated in Card Actions.
- Link behavior: related links remain display-only in editor metadata. New links are initiated by Card Actions or the existing `@` shortcut, which continue into the same link flow.
- Responsive geometry: default and Accessibility XXXL captures keep all eight semantic actions and Close inside the surface with no hit-target overlap. At XXXL, `Background` wraps to two lines while every action remains enabled and hittable; the fixed grid does not become a vertical sheet or require scrolling.
- Rendering and metadata: the earlier legacy-HTML, tag-capsule, and related-link alignment fixes remain unchanged. Literal `<p>` markup stays out of the editor, and tag/link presentation continues to reuse the View Card components.

## Interaction and persistence evidence

- Final live result bundle: `/tmp/ChoraiActionBoxLiveFinalReady3.xcresult` — 6 tests passed, 0 failed.
- Covered journeys:
  - default eight-button grid, exact order, single Background, and no Remove Background;
  - Accessibility XXXL geometry and hit targets;
  - Background image upload, staged state, save, reload, and Go persistence;
  - opening Card Actions on a new draft without creating a server card;
  - staging Background plus public state before the first save;
  - mainstream public/private and Pin/Unpin mutations.
- Deterministic close regression: opening, closing, and immediately reopening the Action Box succeeds. Closing the Action Box also restores Back and save interactions.

## Comparison history

1. Earlier P1: raw `<p>` and `</p>` markup appeared in editor content.
   - Fix: recognize legacy HTML when canonical JSON is absent and hydrate it through the BlockNote parser.
2. Earlier P1: Make Public and Add Background both lived inside Card Actions.
   - Fix: keep privacy beside More and move Background into Card Actions.
3. Earlier P2: editor tags and related links did not align with View Card.
   - Fix: reuse the View Card capsule and related-row components.
4. Current P1: editor Card Actions used a tall native list instead of the product's mainstream Action Box.
   - Fix: share the Action Box surface and render the accepted fixed editor grid with one Background action.
5. Current interaction regression found during QA: after Close, editor buttons could remain unresponsive.
   - Fix: remove the stateful accessibility hiding modifier from the underlying editor and rely on the full-screen Action Box backdrop to block touches while presented.

## Implementation checklist

- [x] Remove literal legacy HTML markup while preserving rich-text semantics.
- [x] Place privacy directly beside More.
- [x] Keep editor links display-only and initiate creation from Card Actions or `@`.
- [x] Reuse View Card tag/link presentation.
- [x] Match the mainstream 3 x 3 Action Box surface and geometry.
- [x] Show one stable `Background` action with no removal action.
- [x] Verify default and Accessibility XXXL states against the mainstream reference in one combined comparison.
- [x] Verify Background persistence and new-draft lazy-save behavior against Go.

final result: passed
