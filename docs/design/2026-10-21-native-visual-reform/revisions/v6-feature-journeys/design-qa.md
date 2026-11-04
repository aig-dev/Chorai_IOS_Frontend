# Design QA · Chorai Feature Journeys V6

**Source visual truth:** `../v5-explore-grid/screenshots/flow-light.png`, `flow-dark.png`, the selected V5 warm-white / forest / modest gold theme. These are the visual language reference; V5 has no corresponding full Spark or Merge flow. This is a new-flow extension, not a claim of pixel identity with an old screen.

**Rendered implementation:** 40 V6 native screenshots; `feature-journeys-preview.png` (browser); `screenshots/atlas-mobile.png` (mobile browser).

**Viewport and normalization:** native source and implementation 1206×2622 pixels = 402×874 points at 3×. `qa/native-material-comparison.png` puts V5 and V6 light/dark together in one image, each normalized to 402×874, no device chrome added. Browser default 1280×720; full page 1280×1165. Mobile 390×844, document width 390, no horizontal page overflow. Temporary browser viewport reset after QA.

## Findings and comparison history

- **P2, fixed — Conflict explanation below the first viewport.** Initial V6 conflict screen displayed disabled Accept while its explanation and recovery choices appeared after the long body. Evidence: `qa/before-conflict-visibility.png`, fourth panel. Moved the sync/conflict panel above the body. Recaptured both light/dark ready, sync-error and conflict states; updated comparison visibly shows Reload / Keep before the body. `qa/native-material-comparison.png`, right column, is the post-fix evidence.
- **P2, fixed — Claimed screenshot clickability without hotspots.** Added 23 hotspots mapped to actual visible controls or relevant content regions; states without hotspots hide the marker control and explicitly direct users to the adjacent actions. Browser clicks verified results → reader → results and Merge selection → selected → progress → background.
- **P2, fixed — Mobile transitions left the new screen offscreen.** State/flow changes now reveal the visual stage below 600px. Browser at 390×844: background → ready moved stage top to approximately 0, document width stayed 390. Evidence: `screenshots/atlas-mobile.png`.
- **P2, fixed — Light-only images announced as dark.** Alt text now describes the actual image and states that dark is pending. Browser checked Report while dark selected: alt is “浅色原生原型截图；深色待补”; visible notice agrees.

## Required fidelity surfaces

- **Fonts and typography:** native system serif for content / display, system UI type for controls. Compared at 402pt normalization. Same roles as selected V5; no separate title field was added to the editor. Native long content scrolls; no clipped persistent action label observed. Browser Chinese uses platform sans with serif display title.
- **Spacing and rhythm:** content margins 22pt in journeys, source/task groups separated, primary action dock in safe area. New flow density differs intentionally from single-card Explore. TextEditor remains within scrolling content; fixed Accept/Discard is outside via safeAreaInset. Actual edit/close/conflict tests passed.
- **Color tokens:** inherited `forestGold` theme. Warm-white light surfaces, ink-green content, muted gold markers; charcoal dark surfaces and pale forest foreground. No full gold or green content backgrounds. Semantic error copy explains blocked actions.
- **Image fidelity:** V5 image/photo content reused unchanged. All phone content in the browser comes from actual simulator captures; no CSS-built imitation of native controls. Offline edition resizes captures to 804×1748 and stores lossless WebP; native originals remain in PNG.
- **Copy / content:** explicit local sample indicators, source ownership, saved vs collected distinction, Accept as the local note insertion boundary, and real-service gaps. Review-only Preview state controls are separated from user workflow. Screens without new visuals show source evidence text rather than invented production captures.

Focused inspection used the full 402pt native panels for source strips, body text, action docks and conflict controls; a separate crop was unnecessary at this readable scale. The browser proof was also opened and checked in full, including lower actions and footer.

## Tested interactions and limitations

Eight distinct new native journey tests passed, plus 54 model checks. Browser navigation, hotspots, state menu, overview, themes, source-only nodes, mobile reveal and inline offline image loading checked. Inspected browser console logs contained no errors or warnings.

Not a full accessibility certification, Dynamic Type matrix, live backend test or production rich-text migration. Comments/author and several service states are deliberately source-only; Share/Link/Report remain light-only V5 images. These are disclosed coverage gaps, not newly completed surfaces.

**Implementation checklist:** fixed all four P2s; recaptured changed states; verified UI tests; preserved prior manifests; included offline package and clear source boundaries.

final result: passed
