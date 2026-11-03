# Welcome motion review · 2026-11-04

Source: `Screen Recording iPhone 17 Pro 2026-11-04 at 00.46.40.mp4`, captured by the parent agent through Device Hub. `welcome-motion.mp4` is a byte-for-byte copy. Runtime: approximately 40 seconds.

The contact sheets sample selected transition windows at requested 0.1-second intervals. This is a visual sequence audit, not a frame-rate, performance, sound, or haptic measurement. Requested sample timestamps are shown below each thumbnail.

## Observations

- First to second intro around 3.4–3.9 seconds: outgoing artwork travels upward; incoming artwork comes from below. Final composition settles without persistent overlap or clipping.
- Second to third intro around 10.8–11.3 seconds: direction remains consistent. The background changes to forest green while the primary button retains its bottom position.
- Third to second intro around 16.4–16.8 seconds and second to first around 28.0–28.3 seconds: direction reverses correctly. Artwork is clipped only while passing through the dedicated viewport boundary; the settled content remains visible.
- Two rapid Next presses around 33.0 seconds advance to the third intro. By the later sampled frames the third intro is settled, with no stuck state or lingering artwork from the first two pages.
- The header crossfade briefly places two text strings over one another. This is visible near requested timestamps 3.50, 28.00, and 33.00 seconds. It is a short-lived visual refinement issue, not a navigation failure. A fade-out / replace / fade-in sequence, or a non-overlapping title swap, would be cleaner than the current simultaneous text crossfade.

No app source or UI state was changed during this review.

## Evidence

- [Recording](welcome-motion.mp4)
- [Forward transitions](welcome-motion-sheet-1.jpg)
- [Reverse transitions](welcome-motion-sheet-2.jpg)
- [Rapid advance](welcome-motion-sheet-3.jpg)

## Follow-up implementation · pending fresh native verification

After inspecting the double-title frames, the welcome heading was changed to one persistent `Text` view. Its page-dependent identity and opacity transition were removed, so the old and new heading strings no longer occupy separate transition views. Artwork still uses the existing 0.42-second vertical transition, or the existing opacity fallback under Reduce Motion. Routes, labels, and CTA behavior are unchanged. No timers or additional state were added.

The pre-fix source is preserved separately at `../../before-heading-fix.swift`. The recording and contact sheets above document the issue **before** this follow-up. A new native build and recording are required before claiming the visual issue is verified fixed.

## Recheck after removing heading identity · issue still present

Two new captures were reviewed after the first heading fix:

- `welcome-motion-final.mp4`, copied byte-for-byte from the 01.03.21 Desktop recording, approximately 48 seconds.
- `welcome-motion-reduced-final.mp4`, copied byte-for-byte from the 01.04.05 Desktop recording, approximately 30 seconds.

Despite the historical `final` filenames, **both are intermediate verification captures, not evidence that the heading issue is resolved**. The first correction removed competing SwiftUI view identities, but the text still visibly interpolates under the parent animation.

Normal-motion observations:

- The double heading remains visible near requested times 15.35 and 26.00 seconds. The Next / Get started label also briefly overlaps near 26.00 seconds.
- Artwork directions remain coherent in forward and backward transitions; the CTA position remains stable.
- The two rapid advances near 42.65–43.15 seconds settle on the third intro without stuck content. Settled artwork is fully visible.

Reduce Motion observations:

- The parent observed Reduce Motion enabled in Device Hub while recording. The exported movie contains the phone screen, not the inspector; that setting observation is separate from the movie evidence.
- Sampled artwork uses a short opacity blend instead of travelling vertically, consistent with the intended reduced-motion fallback.
- The heading can still show two strings during that blend, visible around requested times 10.20 and 25.70 seconds. The settled state is clear and controls retain their positions.

The parent then applied a second, narrower correction: suppress the inherited animation transaction on the heading text and CTA text only. Fresh builds and recordings of that correction are pending; these intermediate captures must not be used to claim it passed.

Selected diagnostic contact sheets:

- [Normal: first advance](welcome-heading-intermediate-normal-sheet-1.jpg)
- [Normal: back transition](welcome-heading-intermediate-normal-sheet-3.jpg)
- [Normal: rapid advance](welcome-heading-intermediate-normal-sheet-5.jpg)
- [Reduce Motion: back / forward](welcome-heading-intermediate-reduced-sheet-2.jpg)
- [Reduce Motion: final advance](welcome-heading-intermediate-reduced-sheet-4.jpg)

Requested and actual extraction timestamps are recorded in `welcome-heading-intermediate-normal-manifest.json` and `welcome-heading-intermediate-reduced-manifest.json`. These samples do not measure frame rate or prove physical-device performance.

## Transaction correction recheck · text overlap resolved, contrast timing remains

Source: Desktop recording `Screen Recording iPhone 17 Pro 2026-11-04 at 01.07.56.mp4`, approximately 46.5 seconds. The preserved byte-for-byte copy is `welcome-motion-transaction-intermediate.mp4`. A total of 157 requested samples covers the forward, reverse, rapid-advance, and Reduce Motion transition windows; requested/actual times are in `welcome-transaction-manifest.json`.

- **Text-overlap check passed in the inspected frames:** no simultaneous old/new heading or CTA text strings are visible after the transaction correction.
- Forward/back directions are coherent, the CTA geometry stays anchored, and rapid advance settles on the third intro. No persistent clipping or stuck content is visible at rest.
- Reduce Motion artwork uses a short opacity blend without the normal vertical travel.
- **A brief contrast mismatch remains during the green/white theme change.** At requested 16.55 and 34.85 seconds, the next heading becomes dark while the previous green backdrop is still present. The next CTA label becomes white while the capsule is still light, making the label briefly appear blank. In the reverse color direction, the dark label can similarly appear on the still-dark capsule (near 9.15 / 41.00 seconds). Text colors now snap while backgrounds still animate.

The narrow ghosting fix is verified; full transition refinement is not yet marked complete because of this remaining color-timing issue. [Contrast timing proof](welcome-transaction-contrast-proof.jpg) shows the relevant normal and Reduce Motion samples. No source changes were made during this review.

## Latest scoped-animation correction · recording pending

A read-only source inspection confirms the latest correction in `ChoraiWelcomeView`:

- `move(to:)` updates direction and page immediately, without a broad `withAnimation` transaction.
- The intro animation is attached only to the artwork `GeometryReader` and the pager indicators.
- The heading remains one persistent text view without page identity or an explicit content transition.
- CTA text, foreground, and capsule background share `.animation(nil, value: page)`, while the existing press-feedback style remains on the button.
- The earlier heading/CTA `.transaction` modifiers have been removed. The normal artwork offset transition and Reduce Motion opacity fallback remain intact.

Fresh command logs inspected for this version:

- `/tmp/chorai-auth-polish-scoped-motion-final-local.log`: `BUILD SUCCEEDED`.
- `/tmp/chorai-auth-polish-scoped-motion-production.log`: `BUILD SUCCEEDED`.
- `/tmp/chorai-auth-polish-scoped-motion-regression.log`: `TEST SUCCEEDED`; one welcome-return test, zero failures.

These checks confirm the implementation structure, compilation, and narrow navigation regression. **They do not prove the final animation appearance.** The Mac locked before the combined normal / Reduce Motion recording could be captured; the parent has requested user unlock. A fresh recording and frame inspection of this exact version are still outstanding. No final motion pass is claimed, and all prior recordings remain labeled with their actual intermediate outcomes.


## Scoped-animation native recheck · text and contrast verified

The user unlocked the Mac and the latest scoped-animation build was recorded as `Screen Recording iPhone 17 Pro 2026-11-04 at 01.17.03.mp4` (50.97 seconds). Its byte-for-byte verified copy is [welcome-motion-scoped-reviewed.mp4](welcome-motion-scoped-reviewed.mp4), with a clean opening [poster](welcome-motion-scoped-poster.jpg). This supersedes the preceding recording-pending status. Earlier movies are preserved unchanged.

A one-second overview and 163 requested samples at 0.05-second intervals covered normal forward/back, rapid advance, and Reduce Motion transition windows. Requested and actual timestamps are in `welcome-scoped-reviewed-manifest.json`.

- **Heading and CTA overlap: passed in the inspected frames.** The old and new strings do not coexist during either normal or reduced-motion samples.
- **Foreground/background timing: passed in the inspected frames.** The green/white page palette and CTA label/capsule colors switch together. The previous dark-on-green heading and white-on-white CTA dip do not recur.
- **Normal transition geometry: passed.** Forward and back travel in opposite coherent directions. Moving artwork stays clipped below the heading and above the CTA; a small contact-sheet view initially suggested a header overlap, but the full-size 18.10-second frame confirms a clear gap. CTA location stays anchored. Rapid Next near 30.90–31.50 seconds settles on the third intro without a stuck intermediate state.
- **Reduce Motion scope:** the parent observed Reduce Motion enabled before the last two transitions. The next 2→3 transition near 45.05–45.25 seconds fades and settles cleanly. The first Back immediately after changing the setting, near 38.15–38.25 seconds, still shows brief upward travel of the outgoing, already-mounted artwork while it fades; the incoming artwork fades in place. This is a remaining hot-toggle transition nuance, so this recording does **not** establish a pure-opacity transition for that first action after toggling the setting. It does verify stable heading/CTA and correct settled navigation throughout.

Selected proof frames:

- [Normal next: paired palette and CTA update at 10.95s](welcome-scoped-next-palette-proof.jpg)
- [Normal back: heading remains separate from clipped artwork at 18.10s](welcome-scoped-back-clipping-proof.jpg)
- [Reduce Motion forward: stable heading and CTA during artwork blend at 45.10s](welcome-scoped-reduced-forward-proof.jpg)

These are native offline visual samples. They do not measure playback frame rate, physical-device responsiveness, haptics, audio, or live authentication. No app source was changed during this inspection.


## Final Reduce Motion setting recheck · verified

The remaining first-transition issue after changing Reduce Motion was addressed by including the current motion preference in the artwork identity. This refreshes the mounted artwork when the preference changes, so its next removal uses the current transition. This review made no source changes.

The latest exact-build recording is `Screen Recording iPhone 17 Pro 2026-11-04 at 01.28.28.mp4` (31.40 seconds). The byte-for-byte SHA256-verified copy is [welcome-motion-setting-verified.mp4](welcome-motion-setting-verified.mp4), with a clean opening [poster](welcome-motion-setting-poster.jpg). The preceding 50.97-second movie remains unchanged as broader normal/rapid-navigation evidence; this shorter capture closes the explicitly documented Reduce Motion setting edge.

A whole-recording overview and 143 requested samples at 0.05-second intervals were extracted for the normal sanity check and the two reduced-motion transitions. Requested and actual sample timestamps are saved in `welcome-motion-setting-verified-manifest.json`.

- **First Back after enabling Reduce Motion: passed.** At 17.60–17.75 seconds both outgoing and incoming artwork fade in place. The upward movement seen in the prior recording is absent.
- **Following Next with Reduce Motion still on: passed.** At 22.20–22.40 seconds artwork fades in place and settles on the third intro.
- **Heading and CTA: passed in both transitions.** Each displays a single string; foreground/background changes remain paired, labels stay readable, and control positions remain fixed.
- **Normal-motion sanity check: passed.** The 2→3 transition near 4.00–4.35 seconds retains the intended vertical travel without title ghosts or the earlier contrast mismatch.

Representative frames:

- [First reduced-motion Back, 17.65s](welcome-motion-setting-first-back-proof.jpg)
- [Following reduced-motion Next, 22.25s](welcome-motion-setting-next-proof.jpg)
- [Normal-motion transition, 4.10s](welcome-motion-setting-normal-proof.jpg)

**The earlier hot-toggle residual is closed for the recorded sequence.** These findings are bounded native offline visual verification, not a measurement of frame rate, physical-device haptics/audio, or live authentication. All prior recordings and diagnostic outcomes are preserved.


## User-requested slower normal timing · 0.58 seconds verified

Following the user's request for a slower welcome animation, the parent changed only the normal intro duration from 0.42 to 0.58 seconds. The 0.16-second Reduce Motion fade remains unchanged. The latest native recording is preserved as [welcome-motion-slower-058.mp4](welcome-motion-slower-058.mp4), copied byte-for-byte from `Screen Recording iPhone 17 Pro 2026-11-04 at 01.43.12.mp4`; SHA256 matches the original. The [new poster](welcome-motion-slower-058-poster.jpg) shows its clean opening state. Prior recordings remain intact.

The recording metadata duration is 22.00 seconds. The whole-recording overview and 80 samples at 0.1-second intervals covered both forward transitions, both backward transitions, and rapid double-Next. Exact requested/actual sample timestamps are in `welcome-motion-slower-058-manifest.json`.

- **Slower transition check: passed.** Forward 2→3 near sampling timestamps 4.90–5.50 seconds and Back 3→2 near 8.30–8.90 seconds show a longer, readable travel-and-settle sequence. Direction remains coherent.
- **Text and palette stability: passed.** The inspected transitions show one heading and CTA label at a time, paired text/background colors, and anchored controls; the previous ghosting/contrast issues do not recur.
- **Rapid advance: passed.** Two closely spaced advances near 15.90–16.60 seconds settle on the third intro. There is no stuck intermediate state or persistent clipping at rest.

This is a narrow visual recheck of the normal duration change. It does not remeasure or replace the preceding Reduce Motion verification, whose implementation was unchanged, and does not claim frame-rate, audio, haptic, or live-authentication testing. No source or Git changes were made by this review.
