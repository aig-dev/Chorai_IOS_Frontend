# Initial implementation validation · 2026-10-26

> Historical engineering results for the first implementation, which the user rejected for visual divergence. These are not the final fidelity-correction results. The corrected captures and checks are recorded separately in `fidelity/`.

## Environment and scope

- Xcode 27.1, build 27A9275, selected per command with `DEVELOPER_DIR`.
- iPhone 17 Pro Simulator, iOS 26.5; device `92DE3535-B261-49B5-844F-9BD9B8C241B4`.
- Original `main` checkout, no branch switch, commit or push. Application changes are local working-tree changes.
- Original dependency pins resolved without upgrades. Derived data and SwiftPM scratch directories are external under `/tmp/chorai-ios-reform-*`.
- Local app and explicit offline fixtures only. Production configuration is compiled but never launched. Local port 8180 has no listener at final verification.

## Results

| Check | Observed result |
| --- | --- |
| CoreFlow complete suite | 787 tests passed, 0 failures |
| BlockNoteEditor complete suite | 52 tests passed, 0 failures |
| Final rail / contrast regression slice | 8 tests passed, 0 failures |
| Selected offline UI regressions | 19 distinct cases have passing latest results; see `qa/ui-results.json` |
| ArcNote Production / Debug-Production | Simulator build succeeded, signing disabled; never launched |
| ArcNote / Debug | Simulator build succeeded, signing disabled; Local app installed and launched with --dev-preview |
| Existing prototype integrity | V3–V8 manifests: all 402 recorded files unchanged |
| Protected source/configuration | Six baseline hashes unchanged, including networking, endpoint configuration, model/grade rules and resolved pins; see `qa/preservation.json` |
| Source hygiene | `git diff --check` passed; bundled BlockNote Resources untouched |

The latest UI results cover real native tab navigation, cold sidebar → Collections, Grid → reader → same Grid, browsing-mode preservation across tabs, editor input/save control states, inline image pixels, keyboard/image chooser, Dynamic Type, Merge selection, result discard confirmation, large-text result actions, task-rail hit areas/scrolling, six grade appearances, Chora large text, Discovery Path, notifications, settings and sign-in controls. Grid/reader/Home were run and captured in both light and dark. This is a selected integration set, not the complete backend-dependent UI suite.

## Regressions found and closed

1. **Reader navigation appeared blocked in Local Preview.** The fixture lacked the non-owner author's read-only profile; the resulting error alert intercepted Back. Added that profile and a fail-closed fixture test. The same UI test now returns to Grid and keeps the browse mode. No navigation reset workaround was added.
2. **Cross-screen collection race.** A delayed Grid failure could overwrite a later successful detail collection. Pending tile actions are disabled; the store tracks the latest committed baseline and preserves it on rollback. Three behavioral regressions cover same-card success, unrelated-card isolation and count reconciliation.
3. **Light/dark contrast.** Follow, Unfollow and Unblock retained white capsules under adaptive light text; Merge's error toast retained a black backing under dark ink. Corrected semantic surfaces. Added text contrast checks for approved theme pairs; completed residual notification/toggle/code-panel/WebView loading colors.
4. **Glass task-rail hit region.** A 44-point visual frame exposed a smaller accessibility hit area. Explicit rectangular content shapes preserve the full target. Both collapse/expand and scrolling to the fifth task now pass with the original 44-point assertions.
5. **Existing test infrastructure.** The baseline already failed two assertions parsing quoted `Debug-Production` names; normalized only the parser. Under concurrent build load, Merge tests' fixed-count yields expired before real state changed; changed only test helpers to bounded asynchronous condition waits and guarded failed indexing. Production save/commit state logic was not changed. The complete suite subsequently passed.

## Evidence and limits

`qa/` contains logs, UI result inventory and preservation checks. `screenshots/` contains actual Simulator captures, including light/dark Grid, reader and Home; keyboard/image chooser, largest accessibility text, and all six grade cards. Screenshots show synthetic offline data.

Live authentication, persistent collection, actual Spark/Merge generation, chat responses and server recovery were not exercised. Their existing service contracts remain connected in source; an available backend and test account are required for live acceptance. Remote Help/Terms/Privacy content was not fetched or redesigned. Physical-device testing and running on older iOS versions were not performed; guarded legacy material paths remain compiled with the original iOS 16 deployment target.

## Reproduce

Use `ArcNote.xcodeproj` with the original `ArcNote` and `ArcNote Production` schemes; keep signing disabled for simulator-only verification. Resolve with `-onlyUsePackageVersionsFromResolvedFile`, then build with `-disableAutomaticPackageResolution`.

Run Swift package tests using external scratch paths, for example `swift test --package-path Packages/CoreFlow --scratch-path /tmp/chorai-ios-reform-coreflow`. Use the `ArcNoteUITests` scheme and the identifiers in `qa/ui-results.json` to rerun selected UI cases. All commands must select full Xcode with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` on this Mac.

For an interactive read-only walkthrough, launch the Local Debug Simulator app with `--dev-preview`. Release/Production and a runtime API override cannot enable this mode. Unsupported reads and all writes fail locally; no fake successful mutation is returned.
