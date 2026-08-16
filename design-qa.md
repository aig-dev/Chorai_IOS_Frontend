# Background multi-merge rail design QA

## Comparison target

- Source visual truth: `docs/qa/assets/ios-background-multi-merge/source-right-edge-rail.png` (durable copy of `/var/folders/68/tx0676vs5rzgc9tfrkp_5ccc0000gn/T/codex-clipboard-a2ce44f1-32b4-4efb-bbe9-e96f05e48568.png`).
- Context only, not fidelity targets:
  - `docs/qa/assets/ios-background-multi-merge/source-legacy-weaving-context.png`
  - `docs/qa/assets/ios-background-multi-merge/source-legacy-empty-error-context.png`
- Primary implementation: `docs/qa/assets/ios-background-multi-merge/iphone17pro-final-working-normal-frame-a.png`.
- Responsive implementation: `docs/qa/assets/ios-background-multi-merge/iphonese3-final-expanded-numbered-3.png`.
- Primary viewport: iPhone 17 Pro, iOS 26.2 (23C54), 402 x 874 points, 1206 x 2622 pixels, 3x density, dark appearance.
- Short viewport: iPhone SE (3rd generation), iOS 26.2, 375 x 667 points, 750 x 1334 pixels, 2x density, dark appearance.
- State: a global right-edge Merge task rail over ordinary app content; Working, Complete, Failed, Recovering, collapsed count 3, expanded numbered 3, Preview open/closed, Reduce Motion, and Reduce Transparency were reviewed.

## Normalization and combined evidence

- Source pixels: 90 x 72. The source crop has no trustworthy point-density metadata.
- Focused implementation pixels: 225 x 180, cropped from the original 1206 x 2622 screenshot at the native 3x simulator density.
- Normalized implementation pixels: 90 x 72, downsampled from 225 x 180 with Lanczos filtering (0.4 scale). This aligns the visible 44-point shell and `menu_merge` mark to the source crop without claiming that the source itself was captured at a known density.
- Full-view plus focused comparison: `docs/qa/assets/ios-background-multi-merge/comparison-source-vs-final.png` (1040 x 1080). Top left is the 90 x 72 source crop; top right is the 90 x 72 normalized implementation; bottom left is the complete iPhone 17 Pro viewport; bottom right is the native focused crop.
- Focused originals:
  - `docs/qa/assets/ios-background-multi-merge/iphone17pro-final-working-focused-225x180.png`
  - `docs/qa/assets/ios-background-multi-merge/iphone17pro-final-working-focused-normalized-90x72.png`
- Implementation contact sheet: `docs/qa/assets/ios-background-multi-merge/implementation-state-contact-sheet.png` (1200 x 1600). Row-major order: Working A/B, Complete A/B; Failed, Recovering, collapsed 3, expanded 3; Reduce Motion A/B, Reduce Transparency, Preview open; Preview closed, SE collapsed, SE expanded, focused Working detail.
- P2 comparison history: `docs/qa/assets/ios-background-multi-merge/comparison-p2-before-after.png` (1080 x 1360). Left to right: original misplaced rail, right-edge-aligned rail with displaced expanded glyphs, final aligned rail with centered glyphs.

All source, implementation, combined-comparison, contact-sheet, and history images above were opened at original resolution before this decision. The source-to-final combined image was itself opened and judged; separate screenshots were not treated as a side-by-side comparison.

## Findings

No actionable P0, P1, or P2 finding remains.

- Fonts and typography: the rail has no visible semantic words. The only visible copy is the numeric collapsed count and newest-first `1`, `2`, `3` markers, rendered in compact system rounded bold styles. At 3x and 2x they remain crisp, centered, and untruncated. Semantic state text remains in accessibility values rather than leaking into the visual rail.
- Spacing and layout: the single-task control is 44 x 44 points. The automated frame assertion places its trailing edge at 25 +/- 2 points on both the iPhone 17 Pro and the short iPhone SE. Expanded controls use 8-point vertical spacing and cap the visible list at four 44-point rows before scrolling. The final SE captures have no clipping, safe-area collision, overlap, or unusable control.
- Colors and tokens: the shell retains the product's dark violet glass treatment and subtle border/elevation. Working uses the violet activity ring, Complete a green static check, Failed a red warning, and Recovering an amber warning. Failure wins the aggregate collapsed state. Actual Reduce Transparency produces an opaque high-contrast shell without losing the asset or status mark.
- Image and icon asset fidelity: the implementation uses the existing `menu_merge` asset from `ArcNote/Assets.xcassets/pop/menu_merge.imageset/merge.png`. The source and normalized implementation show the same stepped white mark and yellow accent. No custom SVG, CSS drawing, emoji, or text-glyph substitute was introduced.
- Copy and content: the rail remains numeric-only in every visible state. `Weaving`, `Preview`, and status words do not appear as rail copy. The underlying QA fixture labels are route anchors, not rail content.
- States and interaction: Working and Committing rotate; Complete is static; Failed and Recovering use static warning shapes. Collapsed count 3 expands to newest-first numbered controls. Preview open has no duplicate rail, while closing Preview retains one Complete rail. The live journey then commits, removes the rail, and opens the canonical Card.
- Animation: focused Working A/B crops differ (`PSNR 21.695092`, `mse_avg 440.12`), proving rotation. Complete A/B and actual Reduce Motion Working A/B are pixel-identical in the same crop (`PSNR inf`, `mse_avg 0.00`).
- Accessibility: the collapsed button exposes `Merge task` or `Merge tasks`, value `count, state`, and a destination-specific hint. Expanded tasks expose number, source count, semantic state, and destination hint. UI tests verify exactly one accessible rail, button semantics, hit testing, and at least 44 x 44-point frames. Complete uses a check; Failed/Recovering use warning shapes in addition to color. Actual Reduce Motion and Reduce Transparency settings were changed at the simulator system level, the app was relaunched, and both settings were restored and read back.
- Responsive behavior: all three expanded items remain fully visible on the 375 x 667-point SE viewport, with badges top-trailing and state glyphs centered. No persistent app control is pushed offscreen.

## Intentional adaptation

The source crop is a tightly clipped, edge-anchored rectangular context, while the approved iOS design uses a 44-point circular floating control with a 25-point trailing inset. This is an intentional platform and hit-target adaptation, not a pixel clone. Fidelity is judged on the real `menu_merge` asset, dark-violet shell language, right-side hierarchy, state semantics, and compact numeric presentation.

## Comparison history

1. P2 — the first iPhone 17 Pro capture placed the rail 95.5 points from the right edge and vertically near the fixture content.
   - Before evidence: `iphone17pro-working-normal-frame-a.png` and `iphone17pro-expanded-numbered-3.png`.
   - Regression first: `testMergeTaskRailPinsSingleControlToRightEdge` failed with a 95.5-point measured trailing gap against 25 +/- 2 points.
   - Fix: align `MergeTaskRailShellOverlay` to `.topTrailing` within its full-size portal.
   - Post-fix evidence: `iphone17pro-after-working-normal-frame-a.png`; the frame test passed on iPhone 17 Pro and iPhone SE.
2. P2 — after the placement fix, expanded Complete and Failed glyphs inherited the badge's top-trailing alignment and were visibly displaced.
   - Before evidence: `iphone17pro-after-expanded-numbered-3.png`.
   - Regression first: centered-pixel checks failed with Complete center 0 and Failed center 91 while badges remained present.
   - Fix: give `MergeTaskStateGlyph` an explicit 44 x 44 centered frame; badge alignment remained top-trailing.
   - Post-fix evidence: `iphone17pro-final-expanded-numbered-3.png`; final counts were Complete center 406, Failed center 1028, Complete badge 1211, Failed badge 1381.
3. Final comparison — placement, glyph centering, count badges, state colors, source asset, motion, accessibility settings, Preview ownership, and SE resilience all passed. No later visual fix was made after the final comparison.

## Verification note

The live relaunch test exposed a stale immediate assertion while capturing Preview evidence: two clean runs probed `screen.merge.loaded` only 0.451-0.472 seconds after tapping Merge, before the asynchronous dismissal completed. Both jobs progressed without backend errors. The existing two-phase product behavior (`adopt`, yield, dismiss) predated this task, and the same exact test had already passed once. The test-only contract now waits up to five seconds for dismissal; the focused green run observed the rail at 0.819 seconds and the first synchronized missing-screen probe at 0.835 seconds, then completed relaunch, Preview, commit, and canonical-card navigation. Production lifecycle code was not changed for this synchronization correction.

## Open questions and follow-up polish

- P3: simulator PNG evidence validates sRGB screenshot output, but wide-color P3 gamut and physical OLED appearance were not independently hardware-verified. This does not block the approved dark-violet and semantic-state treatment.

## Implementation checklist

- [x] Reuse the real `menu_merge` asset.
- [x] Keep visible rail copy numeric-only and semantic state text accessibility-only.
- [x] Verify one 44 x 44-point control for one task and numbered expansion for multiple tasks.
- [x] Verify at most four visible task controls before scrolling.
- [x] Verify Working motion, Complete static treatment, warning states, and failure precedence.
- [x] Verify actual Reduce Motion and Reduce Transparency behavior and restore both settings.
- [x] Verify VoiceOver labels, values, hints, semantic shapes, and hit targets.
- [x] Verify a single global owner, Preview suppression, Preview-close retention, discard removal, and commit navigation.
- [x] Verify iPhone 17 Pro and short iPhone SE layouts.
- [x] Open and judge normalized, full-view, contact-sheet, and before/after comparison evidence.

final result: passed
