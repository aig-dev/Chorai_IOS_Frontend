# Swift 6 editor pilot validation — 2026-11-20

Scope: persist complete concurrency checking; migrate BlockNoteEditor production
and test targets to Swift 6. App/CoreFlow remain Swift 5; minimum iOS remains 16.
No runtime algorithm, persistence contract, generated editor asset, default actor
isolation or Approachable Concurrency change.

## Reproduction

```sh
make check-concurrency
make check-concurrency IOS_DEVICE=<dedicated-simulator-UUID>
python3 scripts/check-concurrency.py --settings-only
```

The first command needs Xcode, Swift 6 tools and Python 3, but no booted simulator.
The second additionally runs existing Local simulator regressions. It never
selects an arbitrary booted simulator or launches the Production scheme. Set
`CONCURRENCY_OUTPUT` to choose the log/DerivedData directory (default:
`.build/concurrency`). No language-mode or strict-checking overrides are passed.

## Evidence

- Baseline: `a46f21e982be4ab752629e9076e159f89a0adb1d`.
- Toolchain: locally installed Xcode 27.2 (27B52), Apple Swift 6.4.2.
- RED: resolved Debug/ArcNoteTests settings had no complete checking. Both
  packages previously had implicit Swift 5 and no persistent strict setting.
- GREEN: effective settings in all nine App/test target/configuration pairs
  report Swift 5, complete checking and iOS 16; both CoreFlow targets have
  unconditional complete checking; editor production/tests inherit Swift 6.
- Initial Swift 6 editor run: 76 tests passed, including real macOS WebKit flows,
  ordered bridge work, accepted-event draining and resource validation. No
  business-source or test-source workaround was necessary.
- Actual Xcode compiler commands in the build activity logs confirm
  `-swift-version 6` for BlockNoteEditor and `-swift-version 5` plus
  `StrictConcurrency` for CoreFlow/App on both arm64 and x86_64 iOS 16 Simulator
  targets. With this Xcode version, the App setting maps to
  `-enable-upcoming-feature StrictConcurrency`; CoreFlow's tools-5.9 manifest maps
  to `-enable-experimental-feature StrictConcurrency`.
- Validation runner failure-path probes reject a command exiting 17 and an
  invalid simulator UUID; neither is reported as a passing check.
- Independent review identified silent omission when a UI selector becomes stale.
  Five runner regressions first failed: misspelled selector, zero cases, skipped
  case, failed case and a same-named method in another bundle. The runner now
  requires each selected bundle/class/method to be Passed in the actual xcresult;
  all six runner tests pass, including the valid-result control.

## Final verification

The final `make check-concurrency` invocation exited **0** with
`IOS_DEVICE=ebaca372-c94a-4a14-9947-634df3918495` (canonicalized to Xcode's uppercase
UUID). Device: dedicated Chorai Execution QA, iPhone 17 Pro / iOS 26.2.

| Check | Result |
| --- | --- |
| Resolved project/package settings | All expected modes, complete checks and iOS 16 verified |
| Validation runner regressions | 6 passed |
| CoreFlow | 1056 total, 1050 passed, 6 intentional live-API skips |
| BlockNoteEditor, Swift 6 production and tests | 76 passed |
| App-hosted Local tests | 73 passed, 0 skipped |
| Local / Production / Release Simulator builds | All exited 0 |
| Selected editor UI tests | Each of the 6 requested identifiers verified Passed, 0 skipped |

The selected UI cases cover ordinary save/back, bridge retry, image rendering,
read-only compatibility content, Merge immediate Back/reopen with pending tags,
and retaining lossy draft content/tags when snapshot acceptance fails. The actual
`xcresulttool` summary reports 6 passed, 0 failed; the runner separately verifies
each bundle/class/method identifier rather than trusting the count alone.

Local evidence is retained under
`.superpowers/sdd/2026-11-20-swift6-editor/`: final `check.log`,
`final-app-summary.json`, `final-ui-summary.json`, `compiler-evidence.json`,
the initial failed runs, and `validation/` logs/result bundles. Initial runner
invocations exposed and fixed lowercase UUID matching and the empty App scheme
TestAction; the final command uses the dedicated `ArcNoteUITests` scheme.

One independent final review found the stale-selector gate issue documented
above. Its fix is covered by failing-then-passing runner regressions and the final
complete command. Python syntax, modified documentation's local links and
`git diff --check` pass. No App/editor business-source workaround was needed.

## Limits and remaining migration work

Swift 5 warnings remain visible and do not yet fail the gate. Examples include
CoreFlow's shared ISO8601DateFormatter, Core Data transaction closures and
RecentCardReads callbacks, plus App Combine/decode and UIKit isolation boundaries.
These need ownership-specific fixes before those modules switch language modes.
No blanket `@unchecked Sendable`, `@preconcurrency`, or unsafe isolation escape
was added by this pilot.

Package tests execute on macOS. App integration builds and Local simulator tests
cover the iOS source branches. Release is built for the Simulator with signing
disabled; this is not a signed device archive. No physical-device performance,
energy, memory, production-network or full visual-matrix claim is made.

The first six-case UI selection passed five cases and reproduced the known
`testMergeArtifactEditsInPlaceAndRestoresDraft` geometry failure: 299.0 versus
302.3333435058594 after horizontal selection. The exact same failure was
[previously reproduced on the pre-migration baseline](2026-11-19-ios-execution-validation.md#existing-ui-and-fixture-limitations).
The UI test and editor production sources are unchanged in this pilot. That
long visual test stops before its restore assertions, so the concurrency gate
uses the existing focused immediate-Back/reopen and lossy-draft/retained-tag tests
for lifecycle coverage. The visual test and its assertion remain unchanged; its
clipping issue is still open and is not counted as a passing test.
