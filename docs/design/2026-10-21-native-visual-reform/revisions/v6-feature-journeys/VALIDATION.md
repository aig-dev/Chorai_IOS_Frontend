# V6 verification · 2026-10-21

## Result

- Final app rebuilt after adding the review lab’s System appearance option; explicit light/dark journey logic is unchanged.
- Standalone simulator app built successfully. Plist valid, ad-hoc signature applied.
- 54 original / swipe / rich-content model checks passed.
- 8 distinct new journey UI tests passed across the initial run and targeted rerun. Initial run: 4 passed, 4 failed due to test locators; final targeted rerun: all 4 passed, no failures. App logic was not changed to bypass assertions.
- Browser source graph: 6 flows, 35 states, 91 valid action links, 23 valid hotspots, 51 existing image resources. No missing references.
- Browser UI checked: Spark reading and return; theme change preserves state; Merge selection → selected → progress → background → ready; source-only social node; overview state jump; explicit light-only notice and matching alt text; responsive 390×844 layout and automatic reveal of new image; no console error/warning observed in the inspected log.
- Offline single HTML tested in-browser: image data embedded and loaded, results → deeper → dark preserved, no external asset elements. No external scripts, fonts or fetch calls.
- Old manifests: V4 all 101 files match; V5 all 36 files match.

## Native UI cases

1. Spark collect → read → return keeps current result and shared collection count.
2. Spark deeper requires explicit sample continuation; returning to earlier node preserves its result; original source remains accessible.
3. Append retry keeps existing result and appends sample results without creating a deeper node.
4. Merge minimum-source guard, background, close/reopen, resume, Accept, private Home note, no duplicate Accept.
5. Closing edited draft retains text, creates no accepted note.
6. Discard confirmation removes only task/draft; original notes and collection count remain.
7. Sync error blocks Accept; recovery retains edited text, does not auto-save.
8. Conflict Keep retains edited text; Reload replaces it with alternate prepared content.

Test-locator repairs: SwiftUI confirmation dialog exposes nested buttons sharing an ID; `.firstMatch` resolves the actual target. Spark parent container identifiers are inherited by child buttons on this OS; exact labels supplement the expected IDs. No assertion was removed.

## Environment and evidence

- Xcode 27.1, simulator SDK 27.1; target arm64 iOS Simulator 26.0.
- iPhone 17 Pro, iOS 26.5; UDID `92DE3535-B261-49B5-844F-9BD9B8C241B4`.
- All commands use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; global developer selection unchanged.
- Build log: `/tmp/chorai-v6-build.log`.
- Initial run: `/tmp/chorai-v6-journeys-ui.log` and `/tmp/chorai-v6-journeys-ui.xcresult`.
- Passing rerun: `/tmp/chorai-v6-journeys-rerun.log` and `/tmp/chorai-v6-journeys-rerun.xcresult`.
- Initial failure diagnostics also warned that an internal diagnostic subprocess could not locate simctl; the actual test runner used Xcode and executed tests. The successful rerun exited 0. OS build-number parsing warnings remain non-fatal.
- 40 new native PNG screenshots at 1206×2622; browser proof in `feature-journeys-preview.png` and mobile proof in `screenshots/atlas-mobile.png`.
- Design comparison and repaired visibility issue documented in `design-qa.md`.

## Scope

This validates the independent offline prototype, not production ArcNote, authentication, live recommendations, Merge generation, real background processing, cloud synchronization, report submission or sharing delivery. The source-only states and light-only captures are marked in the viewer. The V6 TextEditor does not replace the production BlockNote implementation.

Native working tree remains at its pre-task modifications: ArcNoteApp.swift, NetworkManager.swift, ArcNoteUITests.swift, two LocalPreview package files, and docs/design. This task edits design artifacts and standalone prototype only. No branch, push, global proxy or production API changes.
