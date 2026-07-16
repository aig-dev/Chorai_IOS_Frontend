# Card Editor design QA

## Comparison target

- Source visual truth:
  - Requested mainstream Action Box alignment: `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-2702f55f-cc5d-4122-8ad8-d00ecbe57b45.png`
  - View Card metadata styling: `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-39c2fe64-c184-436a-a5a6-3547b7c6ae3f.png`
  - Previous literal-HTML failure: `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-5ceed2ac-45e2-45b1-86de-fd5c75f0daef.png`
- Final live implementation:
  - Mainstream View Card Action Box: `/tmp/ChoraiActionBoxLiveReviewFixFinalAttachments/F7EC4C2D-93AC-44D6-B4DC-35B2783CE743.png`
  - Editor Action Box, default text: `/tmp/ChoraiActionBoxLiveReviewFixFinalAttachments/AACF05A4-D0A3-4A5E-8BE2-AF9833219459.png`
  - Editor Action Box, Accessibility XXXL: `/tmp/ChoraiActionBoxLiveReviewFixFinalAttachments/F75422E0-41F9-4B99-8668-005ED596E9EB.png`
  - Background replacement staged: `/tmp/ChoraiActionBoxLiveReviewFixFinalAttachments/9532A3E4-47D7-48E3-AE49-63BD1A69FF8A.png`
  - Compact 375-point viewport: `/tmp/ChoraiActionBoxCompact375Attachments/9C7ABE68-A730-48D7-9076-8121E60F4A9D.png`
  - Short 350-point safe-area fixture: `/tmp/ChoraiActionBoxShortViewport5Attachments/6B12667A-2AF9-445C-A26F-D0B3BD5A7C33.png`
- Primary viewport: iPhone 17, 402 x 874 points, 1206 x 2622 pixels, iOS 26.2 Simulator.
- Responsive viewport: iPhone SE (3rd generation), 375 x 667 points, 750 x 1334 pixels.
- State: dark theme; real Go-backed cards; default and Accessibility XXXL text sizes.

## Combined comparison evidence

`docs/qa/card-editor-action-box-comparison.png` places the reference and final implementation in one visual input, in this order:

1. top left: the reported native vertical Card Actions mismatch;
2. top right: the product's mainstream View Card 3 x 3 Action Box;
3. bottom left: the final editor Action Box at default text size;
4. bottom right: the final editor Action Box at Accessibility XXXL.

The two live default captures use the same device, shared Action Box surface, 90 x 90 point standard tiles, symbols, color treatment, corner radius, and Close treatment. The editor intentionally substitutes `Background` for `Edit`, keeps the middle-left slot empty, and keeps privacy as a direct control beside More.

## Findings

No actionable P0, P1, or P2 visual or interaction mismatch remains.

- Action Box structure: the editor uses the shared square/glass 3 x 3 Action Box instead of a native vertical confirmation dialog.
- Fixed editor placement:
  - row 1: `Background`, `Spark`, `Merge`;
  - row 2: empty, `Share`, `Link`;
  - row 3: `Root`, `Remove`, `Pin` or `Unpin`.
- Background copy and behavior: exactly one `Background` action is shown for both add and replace. There is no `Remove Background` action.
- Privacy placement: `Make Public` / `Make Private` remains a direct 44-point control immediately beside More and is not duplicated in Card Actions.
- Link behavior: related links remain display-only in editor metadata. New links are initiated by Card Actions or the existing `@` shortcut, which continue into the same link flow.
- Standard geometry: the 402-point View Card and editor captures both retain the mainstream 90 x 90 point tile metric.
- Compact geometry: tile size adapts only when the available width or safe-area height cannot contain the 60-point header, three rows, and two 15-point gaps. The 375-point portrait fixture and a 350-point short-height fixture keep all actions and Close inside the surface without overlap; label scaling keeps `Background` complete instead of truncated.
- Accessibility: the shared overlay declares `.isModal`, posts `.screenChanged` when entering and leaving, and keeps the underlying controls non-hittable while visible without dynamically destroying their accessibility subtree. Editor and mainstream Close -> reopen journeys both pass.
- Accessibility XXXL: all eight actions and Close remain enabled, hittable, separated, and inside the surface without turning into a vertical sheet or requiring scrolling.
- Rendering and metadata: literal `<p>` markup stays out of the editor, and tag/link presentation continues to reuse the View Card components.

## Interaction and persistence evidence

- Final live result bundle: `/tmp/ChoraiActionBoxLiveReviewFixFinal.xcresult` — 6 tests passed, 0 failed in 279.164 seconds.
- Responsive fixtures:
  - `/tmp/ChoraiActionBoxCompact375.xcresult` — compact 375-point portrait passed;
  - `/tmp/ChoraiActionBoxShortViewport5.xcresult` — short-height safe-area fixture passed;
  - `/tmp/ChoraiActionBoxReviewFixGeometryAndReopen.xcresult` — standard geometry and editor Close -> reopen passed.
- Focused source contracts: 31 tests passed, 0 failed.
- Covered journeys:
  - default eight-button grid, exact real grid descendants, order, single Background, and no Remove Background;
  - Accessibility XXXL geometry and hit targets;
  - Background upload, staged state, save, reload, replacement route, and Go persistence;
  - opening Card Actions on a new draft without creating a server card;
  - staging Background plus public state before the first save;
  - mainstream Close -> reopen, public/private, and Pin/Unpin mutations.

## Comparison history

1. Raw `<p>` and `</p>` markup appeared in editor content.
   - Fix: recognize legacy HTML when canonical JSON is absent and hydrate it through the BlockNote parser.
2. Make Public and Add Background both lived inside Card Actions.
   - Fix: keep privacy beside More and move the one stable Background action into Card Actions.
3. Editor tags and related links did not align with View Card.
   - Fix: reuse the View Card capsule and related-row components.
4. Editor Card Actions used a tall native list instead of the product's mainstream Action Box.
   - Fix: share the Action Box surface and render the accepted fixed editor grid.
5. The first shared-grid pass reduced every product tile to 84 points and still risked Close overlap on compact widths.
   - Fix: restore 90-point standard tiles, reserve a 60-point header, and adapt only below the available width/height threshold.
6. Stateful accessibility hiding could leave controls unavailable after Close.
   - Fix: put modal semantics on the stable shared overlay and refresh accessibility focus with `.screenChanged`.

## Implementation checklist

- [x] Remove literal legacy HTML markup while preserving rich-text semantics.
- [x] Place privacy directly beside More.
- [x] Keep editor links display-only and initiate creation from Card Actions or `@`.
- [x] Reuse View Card tag/link presentation.
- [x] Match the mainstream 3 x 3 Action Box surface and 90-point standard geometry.
- [x] Show one stable `Background` action with no removal action.
- [x] Verify default and Accessibility XXXL states against the mainstream reference in one combined comparison.
- [x] Verify 375-point width and short safe-area height without overlap or truncation.
- [x] Verify editor and mainstream Close -> reopen accessibility/touch recovery.
- [x] Verify Background add/replace routing and new-draft lazy-save behavior against Go.

final result: passed
