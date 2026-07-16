# Card Editor design QA

## Comparison target

- Source visual truth:
  - Reported bottom-overlap and Close-icon mismatch: `/Users/luffylu/.codex/attachments/b67cdfbd-5205-4787-8538-d54c40f0b059/image-1.png`
  - Requested mainstream Action Box alignment: `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-2702f55f-cc5d-4122-8ad8-d00ecbe57b45.png`
  - View Card metadata styling: `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-39c2fe64-c184-436a-a5a6-3547b7c6ae3f.png`
  - Previous literal-HTML failure: `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-5ceed2ac-45e2-45b1-86de-fd5c75f0daef.png`
- Final live implementation:
  - Mainstream View Card Action Box: `/tmp/ChoraiActionBoxFinalLiveAttachments-1622/718AD5E7-E7B7-4724-BA6C-06180FFEFCB3.png`
  - Editor Action Box, default text: `/tmp/ChoraiActionBoxFinalLiveAttachments-1622/6E42A10B-C040-4DFF-BAAB-0931E5834C9E.png`
  - Editor Action Box, Accessibility XXXL: `/tmp/ChoraiActionBoxFinalLiveAttachments-1622/9BAA80AF-A36A-4E20-A0F3-69284112820C.png`
  - Background replacement staged: `/tmp/ChoraiActionBoxLiveReviewFixFinalAttachments/9532A3E4-47D7-48E3-AE49-63BD1A69FF8A.png`
  - Compact 375-point viewport: `/tmp/ChoraiActionBoxCompact375Attachments/9C7ABE68-A730-48D7-9076-8121E60F4A9D.png`
  - Short 350-point safe-area fixture: `/tmp/ChoraiActionBoxShortViewport5Attachments/6B12667A-2AF9-445C-A26F-D0B3BD5A7C33.png`
- Primary viewport: iPhone 17, 402 x 874 points, 1206 x 2622 pixels, iOS 26.2 Simulator.
- Responsive viewport: iPhone SE (3rd generation), 375 x 667 points, 750 x 1334 pixels.
- State: dark theme; real Go-backed cards; default and Accessibility XXXL text sizes.

## Combined comparison evidence

`docs/qa/card-editor-action-box-comparison.png` places the reference and final implementation in one visual input, in this order:

1. top left: the reported bottom overlap and Close-icon mismatch;
2. top right: the corrected mainstream View Card 3 x 3 Action Box;
3. bottom left: the corrected editor Action Box at default text size;
4. bottom right: the corrected editor Action Box at Accessibility XXXL.

The live captures use the same device and shared Action Box surface, with 90 x 90 point standard tiles, symbols, color treatment, corner radius, and backdrop-dismiss behavior. The editor substitutes `Background` for `Edit`, fills rows from the leading edge as 3 + 3 + 2, and keeps privacy as a direct control beside More.

## Findings

No actionable P0, P1, or P2 visual or interaction mismatch remains.

- Action Box structure: the editor uses the shared square/glass 3 x 3 Action Box instead of a native vertical confirmation dialog.
- Fixed editor placement:
  - row 1: `Background`, `Spark`, `Merge`;
  - row 2: `Share`, `Link`, `Root`;
  - row 3: `Remove`, `Pin` or `Unpin`, left aligned.
- Shared bottom inset: three-row Action Boxes reserve at least 16 points above and below the grid, so the final row no longer touches the rounded border.
- Dismissal: the visual Close button is removed from mainstream and editor Action Boxes; tapping outside the surface dismisses the menu, while VoiceOver Escape remains available.
- Background copy and behavior: exactly one `Background` action is shown for both add and replace. There is no `Remove Background` action.
- Privacy placement: `Make Public` / `Make Private` remains a direct 44-point control immediately beside More and is not duplicated in Card Actions.
- Link behavior: related links remain display-only in editor metadata. New links are initiated by Card Actions or the existing `@` shortcut, which continue into the same link flow.
- Standard geometry: the 402-point View Card and editor captures both retain the mainstream 90 x 90 point tile metric.
- Compact geometry: tile size adapts only when the available width or safe-area height cannot contain the top/bottom inset, three rows, and two 15-point gaps. The 375-point portrait fixture and a 350-point short-height fixture keep all actions inside the surface without overlap; label scaling keeps `Background` complete instead of truncated.
- Keyboard geometry: opening editor Card Actions dismisses the body keyboard first, while the shared overlay ignores the transient keyboard safe area and resigns first responder as a fallback. The physical viewport therefore remains available to the three-row grid throughout presentation.
- Shared two-row geometry: 2 x 2 menus retain vertically centered four-tile bounds in the square after Close removal.
- Accessibility: the shared overlay declares `.isModal`, supports the accessibility Escape action, posts `.screenChanged` when entering and leaving, and keeps underlying controls non-hittable while visible. Editor and mainstream backdrop-dismiss -> reopen journeys both pass.
- Accessibility XXXL: all eight actions remain enabled, hittable, separated, and inside the surface without turning into a vertical sheet or requiring scrolling.
- Rendering and metadata: literal `<p>` markup stays out of the editor, and tag/link presentation continues to reuse the View Card components.

## Interaction and persistence evidence

- Final completion gate: `/tmp/ChoraiActionBoxFinalVerification-20260716-1630.xcresult` — 8 tests passed, 0 failed in 265.071 seconds across standard, adaptive, short-height, keyboard, backdrop hit testing, shared 2 x 2, real mainstream 3 x 3, and Accessibility XXXL states.
- Latest focused live result bundle: `/tmp/ChoraiActionBoxFinalLive-20260716-1621.xcresult` — 3 tests passed, 0 failed in 145.914 seconds. It covers mainstream 3 x 3 bottom clearance and backdrop dismissal, editor 3 + 3 + 2 ordering, and Accessibility XXXL.
- Latest deterministic geometry bundles:
  - `/tmp/ChoraiActionBoxInteractionGreen-20260716-1606.xcresult` — editor ordering and backdrop dismissal passed, 2 tests;
  - `/tmp/ChoraiActionBoxGeometryGreen-20260716-1607.xcresult` — standard, compact, keyboard, short-height, and shared 2 x 2 geometry passed, 4 tests.
- Current CoreFlow package regression: 373 tests passed, 0 failed.
- Final live result bundle: `/tmp/ChoraiActionBoxLiveReviewFixFinal.xcresult` — 6 tests passed, 0 failed in 279.164 seconds.
- Responsive fixtures:
  - `/tmp/ChoraiActionBoxCompact375.xcresult` — compact 375-point portrait passed;
  - `/tmp/ChoraiActionBoxShortViewport5.xcresult` — short-height safe-area fixture passed;
  - `/tmp/ChoraiActionBoxDeterministicFinal0ba0c9a.xcresult` — historical pre-dismissal-change coverage for standard, compact 375-point, and short-height containment.
- Review-fix fixtures:
  - `/tmp/ChoraiActionBoxReviewFixesFocusedUI.xcresult` — keyboard-open editor presentation and frozen 2 x 2 centering passed, 2 tests with 0 failures;
  - `/tmp/ChoraiActionBoxBackgroundReplacementStrict.xcresult` — Go-backed Background add then replace passed with the persisted replacement ref required to differ from the first ref;
  - `/tmp/ChoraiActionBoxLegacyHTMLStrict.xcresult` — legacy paragraph and strong markup hydrate without exposing literal tags;
  - `/tmp/ChoraiActionBoxKeyboardStandard90.xcresult` — keyboard-open presentation restores the standard 90 x 90 point tiles before interaction;
  - `/tmp/ChoraiActionBoxFinalLiveRegression.xcresult` — new-draft Card Actions remains lazy and mainstream public/private plus Pin/Unpin behavior remains intact, 2 tests with 0 failures.
- Focused source contracts: 31 tests passed, 0 failed.
- BlockNote bridge/resources: 40 tests passed, 0 failed, including the bundled `@` trigger-to-native-link wiring.
- Covered journeys:
  - default eight-button 3 + 3 + 2 grid, exact descendants, leading alignment, single Background, and no Remove Background;
  - Accessibility XXXL geometry and hit targets;
  - Background upload, staged state, save, reload, replacement route, and a distinct persisted Go replacement ref;
  - opening Card Actions on a new draft without creating a server card;
  - staging Background plus public state before the first save;
  - mainstream backdrop-dismiss -> reopen, public/private, and Pin/Unpin mutations.

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
7. The shared three-row header could shift legacy 2 x 2 menus down by 30 points.
   - Fix: reserve the header only for three-row layouts and keep 2 x 2 content centered beneath an independent Close layer.
8. A visible keyboard could temporarily reduce three-row layout height below its 44-point hit-target floor.
   - Fix: dismiss the editor keyboard before presentation and make shared overlay geometry independent of the keyboard safe area.
9. The three-row surface spent its vertical budget on a Close header, leaving the last row against the border.
   - Fix: remove the visual Close control and budget explicit 16-point top and bottom content insets.
10. The editor inserted an empty tile before `Share`, producing a centered 3 + 2 + 3 arrangement instead of natural row filling.
   - Fix: remove the placeholder and render `Background/Spark/Merge`, `Share/Link/Root`, then left-aligned `Remove/Pin`.

## Implementation checklist

- [x] Remove literal legacy HTML markup while preserving rich-text semantics.
- [x] Place privacy directly beside More.
- [x] Keep editor links display-only and initiate creation from Card Actions or `@`.
- [x] Reuse View Card tag/link presentation.
- [x] Match the mainstream 3 x 3 Action Box surface and 90-point standard geometry.
- [x] Show one stable `Background` action with no removal action.
- [x] Verify default and Accessibility XXXL states against the mainstream reference in one combined comparison.
- [x] Verify 375-point width and short safe-area height without overlap or truncation.
- [x] Verify editor and mainstream backdrop-dismiss -> reopen accessibility/touch recovery.
- [x] Verify Background add/replace routing and new-draft lazy-save behavior against Go.
- [x] Preserve centered 2 x 2 mainstream menus after removing the shared Close control.
- [x] Keep at least 16 points of visible bottom clearance on three-row Action Boxes.
- [x] Fill editor actions from the leading edge as 3 + 3 + 2.
- [x] Verify keyboard-open Card Actions restores full-height geometry before interaction.

final result: passed
