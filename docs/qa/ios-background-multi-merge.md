# iOS background multi-merge verification

Date: 2026-08-17
Final result: passed

## Scope and acceptance

This run verifies the iOS global background Merge task rail, its local Go-backed lifecycle, visual states, accessibility settings, and root ownership. The rail must remain numeric-only on screen, reuse the real `menu_merge` asset, expose one 44 x 44-point control for one task, expand newest-first for multiple tasks, show at most four tasks before scrolling, hide while its destination is open, survive minimization/relaunch, retain Complete after closing Preview, disappear on discard/commit, and open the canonical Card after commit.

No backend production code was changed during this task. Unrelated dirty Profile, Chat, Avatar, Credit, PopupMenu, and UI-test work was preserved and excluded from Task 8 staging.

## Environment and preflight

- Outer repository baseline: `af4bc089a514243193287679d60c94477a76b799` on `main`.
- iOS baseline at Task 8 start: `ccb6e3c3f6f5d0c73ccc8ab0f2f33d94ea6d792d` on `main`.
- Go baseline: `2ba4c6e8e3421bc3d11152f5b70636be9474f98e` on `main`.
- Outer recorded gitlinks at Task 8 start:
  - iOS: `9a8912d11d7e54faa652a36b8461b0101737c1f0`
  - Go: `de6262e50db3747c25a68b32f56a9e75d8a08227`
- Primary device: iPhone 17 Pro, UDID `43E6164C-1F4B-47E4-9B65-D154C7281A56`, iOS 26.2 build 23C54, 402 x 874 points, 1206 x 2622 pixels, 3x.
- Short device: `Chorai iPhone SE 3 QA`, UDID `86CD9628-7C27-4799-B237-3EEC82E7E9B5`, iOS 26.2, 375 x 667 points, 750 x 1334 pixels, 2x.
- Local backend: `http://127.0.0.1:8180/health` returned `{"service":"chorai-ontology","status":"healthy"}` before every live gate.
- Full stack checks:
  - Go API: TCP/HTTP 8180 healthy;
  - VDB API: 5001 reachable;
  - agent runtime: TCP 50051 reachable;
  - share renderer: 8092 reachable;
  - marketing service: 8091 reachable;
  - `chorai-mysql8-dev`, `chorai-redis-dev`, and `chorai-minio-dev` running, with MySQL healthy.
- The final required batch began with zero Merge jobs in `CREATED`, `QUEUED`, `GENERATING`, `COMMITTING`, or `CANCELLING`.
- The code-review graph was queried before source exploration in both iOS and Go repositories; the stale Go graph was refreshed before change review.

## Build-for-testing and xctestrun route

The generated UI runner was built into isolated DerivedData:

```sh
xcodebuild build-for-testing -quiet \
  -project ArcNote.xcodeproj \
  -scheme ArcNoteUITests \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' \
  -derivedDataPath /tmp/chorai-task8-deriveddata.qWB8uC \
  CODE_SIGNING_ALLOWED=NO
```

- Generated runner: `/tmp/chorai-task8-deriveddata.qWB8uC/Build/Products/ArcNoteUITests_iphonesimulator26.2-arm64.xctestrun`.
- Live runner: `/tmp/chorai-task8-deriveddata.qWB8uC/Build/Products/ArcNoteUITests_task8_live.xctestrun`.
- The generated runner was copied to the live-runner path; only `CHORAI_UI_TEST_PHONE` was then populated from the existing local credential using `plutil`. The value was never printed or written to this report. `plutil -lint` passed and a value-free structural check confirmed the key was present.
- `xcodebuild test-without-building` was the route that genuinely executed the selected tests and preserved deterministic result bundles.

## CoreFlow verification

Command, run in full without a filter:

```sh
swift test --package-path Packages/CoreFlow
```

### Stale source-contract diagnosis

The first full run executed 679 tests with one failure in 16.62 seconds. An unchanged rerun reproduced 679 tests with one failure in 14.95 seconds (`/tmp/chorai-task8-coreflow-rerun.log`). The failure was `MergeArtifactPresentationSourceContractTests.swift:11`, which still required the literal `if !isArtifactPresentation {`.

- The assertion was introduced as a source contract in `43de236`.
- Task 6 commit `77c2915` intentionally kept the shared header/back action visible in Preview so closing Preview leaves a Complete rail.
- Current code gates only the onboarding line with `if !isArtifactPresentation, let onboardingStore`; this matches the working Preview-close lifecycle.
- Root-cause hypothesis confirmed: stale literal source contract, not product behavior regression.
- Minimal test-only correction: rename the contract to `testArtifactReviewOwnsMutationActionsWithoutDuplicateClose` and remove the obsolete literal condition.
- Focused verification: 2/2 relevant source-contract tests passed.

Final release gate:

- 679 tests passed, 0 failed.
- Test duration: 14.769 seconds; wall time: 15.85 seconds.
- Log: `/tmp/chorai-task8-coreflow-release-gate.log`.

## UI verification

### Final fix-round five-task behavior

The deterministic DEBUG fixture was extended to five tasks without changing release behavior. `testMergeTaskRailScrollsToAndSelectsFifthTask` verifies that exactly four task buttons are visible before scrolling, every task target is at least 44 x 44 points, task 5 can be scrolled into view and selected by its exact canonical job ID, and the collapsed numeric count remains `5` afterward.

- iPhone 17 Pro: passed 1/1 at `/tmp/chorai-final-fix-five-task-17pro-green.xcresult`; the final rail batch passed 3/3 at `/tmp/chorai-final-fix-rail-17pro.xcresult`.
- iPhone SE 3: passed 1/1 at `/tmp/chorai-final-fix-five-task-se-green.xcresult`.

### Final required same-clean batch

Exact command:

```sh
xcodebuild test-without-building -quiet \
  -xctestrun /tmp/chorai-task8-deriveddata.qWB8uC/Build/Products/ArcNoteUITests_task8_live.xctestrun \
  -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/chorai-task8-required-ui-final.xcresult \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testMergeTaskRailShowsCountAndNumberedStatesWithoutText \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testDetailMergeMenuCreatesArtifactAndCancelsGoJob \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testMergeRelaunchResumesCommitsAndOpensCanonicalCard
```

Result: 3/3 passed, 0 failed; 232.064-second test span, 233.69-second wall time.

| Test | Result | Duration | Backend boundary |
| --- | --- | ---: | --- |
| `testDetailMergeMenuCreatesArtifactAndCancelsGoJob` | passed | 1m 38s | `mjob_c7a1a54941afc204709374fd`: `CANCELLED`, stage `artifact_persist`, empty error code |
| `testMergeRelaunchResumesCommitsAndOpensCanonicalCard` | passed | 1m 56s | `mjob_97e24b8e25b8f6977e43845c`: `COMMITTED`, stage `committed`, empty error code |
| `testMergeTaskRailShowsCountAndNumberedStatesWithoutText` | passed | 15s | deterministic fixture |

Both real live tests passed together in this final clean batch. No MySQL `media_ref` 1406 error, provider stall, or other backend failure occurred.

The earlier pre-visual-fix required batch also passed 3/3 in 276.93 seconds at `/tmp/chorai-task8-required-ui.xcresult`; it is retained as history, while the final bundle above is the acceptance result for the final tree.

### Final deterministic lifecycle batch

Exact command:

```sh
xcodebuild test-without-building -quiet \
  -xctestrun /tmp/chorai-task8-deriveddata.qWB8uC/Build/Products/ArcNoteUITests_task8_live.xctestrun \
  -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/chorai-task8-deterministic-ui-final.xcresult \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testMergeTaskRailPortalStaysSingleAcrossNavigationRoutes \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testWorkingMergeCancelConfirmsCanonicalCallAndCleanupDuringActivePoll \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testRootLifecycleLogoutClearsPresentedTaskAndRejectsStaleActorLoad
```

Result: 3/3 passed, 0 failed; 64.348-second test span, 66.23-second wall time.

| Test | Result | Duration |
| --- | --- | ---: |
| exact-one rail across routes | passed | 21s |
| root logout/stale actor lifecycle | passed | 25s |
| controlled Working cancellation | passed | 15s |

### Focused geometry and visual-state regressions

- Visual fixture behavior was test-first:
  - RED: requested Working fixture returned the default `3, failed`; 1/1 failed in 19.92s (`/tmp/chorai-task8-visual-fixture-red.xcresult`).
  - GREEN: requested state published `1, working`; 1/1 passed in 6.98s (`/tmp/chorai-task8-visual-fixture-green.xcresult`).
  - Fixture plus existing count/numbered behavior: 2/2 passed in 21.56s (`/tmp/chorai-task8-visual-fixture-regression.xcresult`).
- Right-edge geometry was test-first:
  - RED: measured trailing gap 95.5 points against 25 +/- 2; 1/1 failed in 25.223s (`/tmp/chorai-task8-rail-position-red.xcresult`).
  - GREEN iPhone 17 Pro: 1/1 passed in 7.262s (`/tmp/chorai-task8-rail-position-green-17pro.xcresult`).
  - GREEN iPhone SE: the same device-independent assertion passed in 29.438s (`/tmp/chorai-task8-rail-position-green-se.xcresult`).
- Expanded glyph/badge separation was test-first:
  - Calibrated RED counts: Complete center 0, Failed center 91, Complete badge 1214, Failed badge 1384; 1/1 failed in 17.924s (`/tmp/chorai-task8-expanded-glyph-calibrated-red.xcresult`).
  - GREEN counts: Complete center 406, Failed center 1028, Complete badge 1211, Failed badge 1381; 1/1 passed in 6.983s (`/tmp/chorai-task8-expanded-glyph-green-metrics.xcresult`).
- Final relevant five-test batch: geometry, numeric count/expanded state, exact-one routes, requested-state fixture, and centered-glyph pixel behavior all passed 5/5 in 54.801s (`/tmp/chorai-task8-rail-regression-final2.xcresult`).
  - `final1` had already passed 5/5 in 54.647s.
  - `final2` was rerun only after adding the successful metrics text attachment. No threshold, product behavior, or production source changed between the runs; this was not threshold chasing.

### Preview synchronization correction

The first Preview-evidence rerun failed its pre-existing immediate `XCTAssertFalse(screen.merge.loaded.exists)` in 44.12s (`/tmp/chorai-task8-preview-visual.xcresult`). A clean-data unchanged repro failed the same assertion in 34.94s (`/tmp/chorai-task8-preview-repro.xcresult`).

- First/second RED probes occurred 0.451-0.472 seconds after tapping Merge.
- The last RED video frame showed the Working rail during the asynchronous dismissal transition.
- Both jobs continued to `ARTIFACT_READY`, stage `artifact_persist`, with empty error codes.
- The same exact test had passed earlier in 121.753s.
- Recent production changes were only rail alignment and glyph centering.
- Existing product ordering predates this task: coordinator adoption publishes the durable task, then a main-actor yield dismisses the selection destination.
- Single root cause: an immediate test probe raced the established two-phase dismissal; this was not a backend or product-lifecycle regression.
- Minimal test-only fix: both duplicate literal assertions now use the existing `waitForMissing("screen.merge.loaded", timeout: 5)` behavior contract.
- Focused GREEN: rail found at 0.819s, first synchronized missing-screen probe at 0.835s, then relaunch, artifact, Preview, Back, commit, and canonical-card navigation completed; 1/1 passed in 111.547s / 115.26s wall (`/tmp/chorai-task8-preview-green.xcresult`).

## Scheme builds

Final-tree release gates:

```sh
xcodebuild -quiet \
  -project ArcNote.xcodeproj \
  -scheme ArcNote \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

- Result: exit 0 in 33.84s.
- Log: `/tmp/chorai-task8-build-arcnote-release-gate.log`.

```sh
xcodebuild -quiet \
  -project ArcNote.xcodeproj \
  -scheme 'ArcNote Production' \
  -configuration 'Debug-Production' \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

- Result: exit 0 in 34.75s.
- Log: `/tmp/chorai-task8-build-production-release-gate.log`.

Both final logs contained only `/usr/bin/time` timing output (`real`, `user`, and `sys`); `xcodebuild` emitted no warnings or errors.

## Visual evidence matrix

Durable directory: `docs/qa/assets/ios-background-multi-merge/`.

### Source truth

| Evidence | Pixels | Purpose |
| --- | ---: | --- |
| `source-right-edge-rail.png` | 90 x 72 | primary right-edge source crop; SHA-256 starts `0bea083` |
| `source-legacy-weaving-context.png` | 708 x 1420 | legacy full-screen context being replaced, not a rail fidelity target |
| `source-legacy-empty-error-context.png` | 584 x 1336 | legacy empty/error context, not a rail fidelity target |

### Final iPhone 17 Pro originals

Every file below is an original 1206 x 2622 simulator screenshot and was opened with the image viewer.

| State | Evidence | Result |
| --- | --- | --- |
| Working normal A/B | `iphone17pro-final-working-normal-frame-a.png`, `...-b.png` | activity ring differs over time |
| Complete static A/B | `iphone17pro-final-complete-static-frame-a.png`, `...-b.png` | static green check; identical focused pixels |
| Failed | `iphone17pro-final-failed-warning.png` | static red warning |
| Recovering | `iphone17pro-final-recovering-warning.png` | static amber warning |
| Collapsed 3 | `iphone17pro-final-collapsed-count-3.png` | numeric `3`, failure aggregate precedence |
| Expanded 3 | `iphone17pro-final-expanded-numbered-3.png` | newest-first `1`, `2`, `3`; centered Complete/Failed glyphs |
| Preview open | `iphone17pro-final-preview-open-no-duplicate-rail.png` | no rail visible |
| Preview closed | `iphone17pro-final-preview-closed-complete-rail.png` | one Complete rail retained |
| Reduce Motion A/B | `iphone17pro-final-working-reduce-motion-frame-a.png`, `...-b.png` | stable non-rotating treatment |
| Reduce Transparency | `iphone17pro-final-complete-reduce-transparency.png` | opaque high-contrast shell |

### Short iPhone SE originals

| State | Evidence | Pixels | Result |
| --- | --- | ---: | --- |
| Collapsed 3 | `iphonese3-final-collapsed-count-3.png` | 750 x 1334 | safe trailing placement, no crop |
| Expanded 3 | `iphonese3-final-expanded-numbered-3.png` | 750 x 1334 | all three 44-point tasks fully visible |

### Combined and focused evidence

| Evidence | Pixels | Contents |
| --- | ---: | --- |
| `comparison-source-vs-final.png` | 1040 x 1080 | source and normalized final at equal 90 x 72 pixels, plus full and native focused implementation views |
| `iphone17pro-final-working-focused-225x180.png` | 225 x 180 | native @3x focused crop |
| `iphone17pro-final-working-focused-normalized-90x72.png` | 90 x 72 | 0.4x Lanczos density normalization |
| `implementation-state-contact-sheet.png` | 1200 x 1600 | complete implementation matrix, including settings and devices |
| `comparison-p2-before-after.png` | 1080 x 1360 | placement before, glyph issue, and final state |

The source-to-final combined input, implementation contact sheet, and P2 history were each opened and judged after generation.

## Motion and accessibility settings

Focused crop used for pair comparisons: `225 x 180` at screenshot coordinates `x=930`, `y=673`.

| Pair | PSNR average | MSE average | Decision |
| --- | ---: | ---: | --- |
| Working normal A/B | 21.695092 | 440.12 | different; rotation proven |
| Working Reduce Motion A/B | infinite | 0.00 | pixel-identical; stable treatment proven |
| Complete static A/B | infinite | 0.00 | pixel-identical; static completion proven |

Actual simulator settings were changed and the simulator was restarted before capture:

```sh
xcrun simctl spawn <17-pro-udid> defaults write com.apple.Accessibility ReduceMotionEnabled -bool YES
xcrun simctl shutdown <17-pro-udid>
xcrun simctl boot <17-pro-udid>
xcrun simctl bootstatus <17-pro-udid> -b
xcrun simctl spawn <17-pro-udid> defaults read com.apple.Accessibility ReduceMotionEnabled
```

Readback was `1`. After the two Working frames, Reduce Motion was restored to `0`.

```sh
xcrun simctl spawn <17-pro-udid> defaults write com.apple.Accessibility ReduceTransparencyEnabled -bool YES
xcrun simctl shutdown <17-pro-udid>
xcrun simctl boot <17-pro-udid>
xcrun simctl bootstatus <17-pro-udid> -b
xcrun simctl spawn <17-pro-udid> defaults read com.apple.Accessibility ReduceTransparencyEnabled
```

Readback was `1`. After capture, Reduce Motion read `0`; the Reduce Transparency key was deleted and a read returned exit 1 / key absent after restart. The final required batch repeated the normal-state readback: Reduce Motion `0`, Reduce Transparency absent.

VoiceOver semantics were verified through the real XCUI accessibility tree and source contract: button role, non-empty label, values, destination hints, exactly one owner, and 44-point hit targets. The visible check/warning shapes ensure state is not color-only.

## Systematic visual review

- Typography: compact rounded bold numbers are readable at 2x/3x; no visible semantic words, wrapping, truncation, or optical-weight mismatch.
- Spacing/layout: final 25 +/- 2-point trailing slot, 44-point controls, 8-point vertical rhythm, four-item viewport cap, no clipping on either device.
- Colors/tokens: dark violet glass, violet active ring, green Complete, red Failed, amber Recovering, and opaque Reduce Transparency fallback remain distinct and high-contrast.
- Image/icon fidelity: the real `menu_merge` asset is used from the existing asset catalog; no approximation.
- Copy/content: visible rail content is numeric-only; state text is accessibility-only.
- Safe areas/resilience: no collision with status, home, or persistent navigation areas; iPhone SE remains usable.
- Duplicate owner: exact-one route tests pass; Preview open suppresses the rail; Preview closed restores exactly one Complete rail.
- Animation: normal Working differs; Reduce Motion Working and Complete remain stable.
- Accessibility: correct semantic labels/values/hints, button shapes, non-color-only status, 44-point targets, and actual system setting behavior.
- P3 residual: simulator screenshots do not independently verify wide-color P3 gamut or a physical OLED panel. This is non-blocking.

## Visual QA iteration history

1. P2 placement — 95.5-point trailing gap. Added failing frame regression, aligned the full portal top-trailing, passed on 17 Pro and SE, and recaptured the same state.
2. P2 expanded glyphs — Complete/Failed glyph pixels were outside the center while badges remained top-trailing. Added failing pixel behavior test, centered only the glyph frame, passed with audited counts, and recaptured the same state.
3. Final — combined source/final evidence, contact sheet, and before/after history show no remaining P0/P1/P2. The source's tightly clipped rectangular context versus the approved 44-point, 25-point-inset iOS circle is an intentional platform adaptation, not a claimed pixel clone.

See project-root `design-qa.md` for the final fidelity decision.

## Artifact policy

Original screenshots and compact comparison sheets are durable. Giant `.xcresult` bundles and screen recordings remain under `/tmp` and are not committed. Temporary `_probe` images were deleted before staging.

## 2026-08-19 WYSIWYG closeout addendum

Task 12 reverified the global background rail together with the final one-surface
Merge artifact editor on iPhone 17 Pro and iPhone SE 3. The final post-sibling
device bundles passed 18/18 and 14/14 tests respectively. They cover the
numeric-only rail, fifth-task scrolling, measured/cached/cold anchors,
landscape adaptive capacity, Preview suppression, Complete restoration,
Working cancellation, Discard confirmation, accessibility Dynamic Type, and
the same-job edit/minimize/relaunch/Accept path, timeout Retry, and clean-409
canonical reprojection with an unfinished tag.

The canonical post-fix job supplied the complete edit/relaunch/Accept/DTO proof.
A separate live product-boundary test then created two jobs from the same three
sources, discarded `mjob_258441c43d722cf89ae17deb`, and proved
`mjob_afce66aefa3b886c938949fe` stayed `ARTIFACT_READY` and remained as the
sole rail task. Its result bundle is
`/private/tmp/chorai-task12-live-sibling-discard-20260819-v3.xcresult` (1/1
passed). The populated default-dev presentation transition remained explicitly
blocked and was not mutated; the hermetic repository cutover gate separately
completed with `MERGE_VNEXT_HARD_CUTOVER_QUALIFIED`.

After evidence capture, the task backend and fixture runtime were stopped,
three temporary source bridge pointers were restored by exact compare-and-set,
the canonical output and its task-only mixed-schema projection rows were
removed, and the three sibling-test source Cards plus their exact bridge rows
were permanently deleted. Both isolated schemas and the earlier task-only
MySQL container/volume were removed. The default runtime, default schemas, and
the existing 22 `ARTIFACT_READY` jobs remained unchanged, including their
sorted-ID hash.

See [iOS Merge WYSIWYG preview verification](ios-merge-wysiwyg-preview.md) for
the exact bundles, backend proof, settings readback, visual matrix, and recorded
operational limitations.
