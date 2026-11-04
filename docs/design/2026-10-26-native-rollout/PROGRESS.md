# Implementation ledger — PLAN.md

- Baseline saved: 547 source/config files plus existing working diff in `/tmp/chorai-ios-reform-baseline/`. Current branch remains main per native AGENTS.md.
- Design approved in current user request; V1–V8 preserved as evidence. Ruling: implementation proceeds under this approval; no repeated plan/design approval.
- Ownership: root theme/tier/Home/tab shell/project config/fixtures/integration; Explore, editing/AI and secondary page agents own disjoint groups listed in PLAN.md.
- Baseline CoreFlow was inspected before migration: see the baseline/parser result below.
- Shared theme interface established. No production requests or service-contract changes authorized.
- Baseline CoreFlow: 769 tests, 2 pre-existing assertions in LocalRunSchemeContractTests. Xcode's quoted `Debug-Production` name was not unquoted by the test parser; corrected parser only, preserving all environment assertions.
- Root shell now uses native TabView, removing the global `UIScrollView.appearance().isScrollEnabled = false` hack. Home uses readable adaptive content, native segmented control and authentic glass create action. All API owners remain.
- Original tier artwork copied byte-for-byte into the app asset catalog; grade thresholds stay in CardLevelStyle. Character clearance derives from actual artwork height, not a fixed placeholder.

- All five implementation groups complete. Theme, tier art, native shell, Home, Explore, editor/reader/AI, account/social and secondary surfaces are integrated.
- Independent review closed cross-screen favorite rollback and dark action contrast findings. Final scope audit completed residual purple toggle/read-all colors and local WebView loading surface.
- CoreFlow full suite: 787 passed. BlockNoteEditor: 52 passed. Final rail/contrast slice: 8 passed. Selected UI: 19 distinct cases have passing latest outcomes, including both-theme navigation and six tiers.
- Observed UI failures were repaired and rerun: read-only preview author fixture missing; Merge rail glass hit region below 44pt. Cold sidebar Collections navigation passed without a route workaround.
- Both ArcNote Debug and ArcNote Production Debug-Production final Simulator builds succeeded. Production was never launched. Native Local Debug was reinstalled and opened in the Simulator in light mode with --dev-preview.
- V3–V8 manifests verified: 402 files unchanged. Endpoint/network/model/grade/pin protected baseline hashes unchanged. No vendored editor resource changes. Branch remains main; no commit or push.
- Live service acceptance remains separate: port 8180 has no listener. Full evidence and scope limits are in VALIDATION.md; actual captures are in screenshots/.

- USER CORRECTION: current rollout rejected for visual divergence. Reopened visual acceptance. Home must match V6 open editorial rows; editor V6 unboxed serif writing; Explore V5 native toolbar/deck plus V8 grade details; Spark/Merge V6 geometry. Matched-viewport comparisons required before visual completion.

- FIDELITY CORRECTION: restored V6 open Home/editor structure, V5 native Explore header/deck and V8 compact graded Grid/reader, plus real Spark/Merge views. Current paired light/dark screenshots and original/actual comparison are in fidelity/. Historical initial screenshots are not replaced.
- Final corrected validation: CoreFlow 816 passed; BlockNoteEditor 53 passed; 10 distinct offline UI cases with passing latest results (14 light/dark results). Reader final paragraph, native editor menu/keyboard, tab restoration, sidebar Collections, Spark navigation and actual Merge selection/result/discard are included.
- Local test build and Production Simulator build passed with Xcode 27.1. Production not launched. Preview remains read-only/offline; no live-service claim. Remaining historical owned Detail/Spark delete-confirmation reachability is documented separately; explicit-target safety prevents wrong-card fallback.

- Final long-card walkthrough exposed content painting below the deck viewport. Added a rendered-pixel regression (failed before fix), restored ScrollView clipping with horizontal shadow room, and passed long-card scrolling/footer/Previous in both themes. Latest evidence is 11 distinct UI cases / 16 passing light-dark results; both builds and 10 Flow presentation contracts rerun successfully. Paired captures and preservation hashes refreshed.
