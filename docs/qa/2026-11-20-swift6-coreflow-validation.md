# CoreFlow Swift 6 migration validation

Date: 2026-11-20. Baseline: `a46f21e`, with the prior uncommitted editor/checking
pilot retained. Apple Swift 6.4.2, Xcode 27.2 (27B52). Local/synthetic runtime only;
Production was built but not launched.

## Preserved behavior and ownership

- Date display still uses the input calendar day. Sync parsing keeps the original
  ISO8601DateFormatter precision, offset handling, whitespace acceptance and invalid
  input rejection. Both formatter instances are private to one synchronous lock.
  A 23-input comparison rejected the faster value-type parser: eight exact results
  differed, including submillisecond precision, whitespace and leap-second handling.
- RecentCardReads state, synchronous notification eviction and destruction belong
  to MainActor. A background post cannot return before eviction; observer removal
  and LRU replacement/capacity semantics are covered. Releasing the last reference
  on a worker failed the main-thread destruction assertion against the baseline,
  then passed with isolated destruction. No Task hop was added to invalidation.
- Core Data transaction and mutation closures require Sendable captures. Managed
  objects remain inside the private context. Save/reset, rollback, generation
  fences, account/environment separation and receipt identity logic are unchanged.
- Tests retain their method identities and business assertions. Changes express
  MainActor helper/lifecycle ownership and capture immutable scope/body values
  instead of passing XCTestCase instances into background hooks or child tasks.
  One Spark callback now explicitly accepts its existing three parameters.
- CoreFlow and its tests use Swift 6. Swift tools 6.2 is the declared minimum for
  `isolated deinit`; iOS 16 and macOS 13 remain the deployment floors. An iOS 16
  object build emitted the compiler's MainActor deinit back-deployment helper and
  a weak runtime reference. This verifies build compatibility, not iOS 16 runtime
  behavior on hardware.

## Verification

| Check | Outcome |
| --- | --- |
| Date/HTTP/cache characterization before source changes | 21 passed |
| Date/HTTP/cache/CommentReadStore after isolation | 31 passed |
| Cache lifetime and observer suite | 8 passed; last-background-release regression first failed on baseline |
| Existing storage/library/sync/image/attachment cases | 90 passed |
| Full CoreFlow, Swift 5 complete checking before switch | 1,067 total; 1,061 passed; same six intentional live-API skips |
| Full CoreFlow, Swift 6 after switch | 1,067 total; 1,061 passed; same six skips; no compiler diagnostics |
| BlockNoteEditor with Swift 6 CoreFlow dependency | 76 passed; one existing weak-variable style warning |
| App hosted regressions with CoreFlow 6 | 73 passed, no skips |
| Selected Local simulator UI flows | All 12 exact bundle/class/method selectors passed |
| Local, Production and Release simulator builds | All passed |
| Persisted settings and language-mode gate | Passed; App/test targets remain Swift 5, both packages Swift 6 |
| Verification runner regressions | 7 passed, including stderr-contaminated JSON output |

The 12 UI cases comprise the six ordinary/Merge editor lifecycle flows from the
[pilot](2026-11-20-swift6-editor-validation.md), detail and comment reopening,
shared transport, swipe/write separation, remote-image offline relaunch, and
local edits surviving a cloud conflict with an undownloaded image. The result
bundle was checked for every exact selector; exit status alone was not accepted.
Simulator: dedicated `Chorai Execution QA`, iPhone 17 Pro, iOS 26.2.

Local warm parsing comparison (1,000 parses, median of seven runs): original
59.07 ms, locked 60.57 ms, fresh formatters 238.89 ms. This is synthetic evidence
for retaining the existing parser/cache, not a device performance target.

Reproducible entry: `make check-concurrency`; set `IOS_DEVICE` for App and the
six editor UI flows. The additional CoreFlow UI selectors and full artifacts are
in `.superpowers/sdd/2026-11-20-swift6-migration/` (`coreflow-ui-selectors.json`,
`CoreFlow-App.xcresult`, `CoreFlow-UI.xcresult`, package/build/settings logs).
JSON stdout and tool stderr now have separate logs: SwiftPM's build-lock status
message previously made a successful manifest command fail JSON parsing.

## Checkpoint scope

The mixed language modes and pending App work above describe this module's earlier
checkpoint. The [full migration record](2026-11-20-swift6-migration-validation.md)
tracks subsequent App/test migration, independent review and final integration.
This module checkpoint is not full App feature acceptance. Existing Merge selection geometry,
old Home-menu/Trash fixtures, live-service coverage, signed archive and physical
sampling limitations remain as recorded in the earlier validation documents.
