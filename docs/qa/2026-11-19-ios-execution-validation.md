# iOS execution implementation validation — 2026-11-19

Scope: approved T1–T7, current main checkout, uncommitted. No backend/API/schema changes, language-mode upgrade, minimum-iOS increase, generated JS changes or production execution. Existing xcuserdata changes are preserved.

## Implemented boundaries

| Task | Implementation | Runtime evidence |
| --- | --- | --- |
| T1 | Scoped shared preview reader, bounded real parser concurrency, cache/in-flight reuse | stale scope/result, same-ID isolation, URL identity, cancellation capacity, real iOS reader tests |
| T2 | Serial non-main decode, main delivery, shared detail transport cancellation | isolated URLProtocol stopLoading, reader sharing, eager mutation semantics, stale 401 and credential errors |
| T3 | One native JPEG encoder, caller selection/account checks | off-main byte/quality/orientation equivalence, running/queued cancellation, real concurrency limit |
| T4 | Shared resource validation per bundle lifetime | successful cache, shared cancellation, failed-hash retry, closed WK never loads |
| T5 | Fixed attachment drain and local persistence session | delayed accepted edit, real temporary note storage, View removal, scope switch, failure/retry, stale snapshot |
| T6 | One ordered bridge mailbox/worker per attachment | complete stateful adapter, FIFO ready/focus/body/commands/snapshots, deadline, close drain and release |
| T7 | Pure Merge worker, versioned application, exact final-action snapshots and two-phase actor retirement | pending revision/canonical ACK race, tags during encode, Accept/Back order, failed drain, latest target, attempted request immutability, late network ACK, bridge retry |

## Verification completed

- CoreFlow full: 1042 tests, six intentional live-API skips, zero failures (`verified-coreflow.log`).
- BlockNoteEditor full: 76 tests, zero failures, including real macOS WK editor flows (`verified-editor.log`).
- iOS app host: 48 tests, zero failures on dedicated iPhone 17 Pro / iOS 26.2 Simulator, Local Debug (`verified-app.log`, repeated with complete-concurrency diagnostics in `verified-app-diagnostics.log`). Includes all 15 Merge conversion/retirement regressions after enabling the Merge bridge worker.
- Dedicated ordinary-editor simulator flows: four passed (`t6-ui.log`): short-note typing, fresh-WK retry, inline image pixels and compatibility read-only behavior.
- Six existing Merge/lifecycle simulator flows passed after review corrections (`verified-ui.log`): lossy Back retains the completed tag, clean conflict adopts canonical body, clean conflict preserves pending tag, delayed Accept locks editing, retry preserves the exact attempted operation, logout rejects stale actor state. The corrected immediate-Back/reopen test passed separately (`verified-ui-immediate-back.log`), retaining both body and pending tag. Its first draft included an invalid relaunch assertion against an in-memory visual fixture; see limitations below. Together these cover seven selected Merge/lifecycle flows; this is not a claim that the full UI target is green.
- Complete-concurrency package builds succeed: BlockNoteEditor without warnings (`verified-strict-editor.log`); CoreFlow retains two pre-existing ISO8601DateFormatter shared-state warnings at CardTimestamp.swift:22,28 (`verified-strict-coreflow.log`). That source is unchanged from HEAD. No Swift 6 migration claim is made.
- Full application complete-concurrency diagnostics also build and all 48 hosted tests pass. The exact-HEAD comparison build reports 141 unique source warning locations; the first implemented snapshot reports 154, including 50 in NetworkManager versus 35 at HEAD. The comparison includes generic Codable/metatype and Combine callback/Promise transfer warnings at the new decode boundary; these are **not all legacy warnings**. UIImage preparation now uses checked Sendable conformance and a Sendable encoder closure, and Merge's owned projection task makes its strong capture explicit, clearing those two new diagnostics. NetworkManager's existing non-actor-isolated generic Combine API still needs a separately scoped Swift 6 typing migration. Runtime tests establish queue placement and main delivery, not whole-program Swift 6 static safety. No blanket unchecked conformance or warning suppression was added to NetworkManager.

## Builds and configuration

- Default Local scheme `ArcNote`: build succeeded with `SWIFT_STRICT_CONCURRENCY=complete` (`verified-build-local-final.log`).
- `ArcNote Production`: build succeeded (`verified-build-production-final.log`). Production was not installed or launched for testing.
- After explicit termination, launching the installed Local app without arguments again logged `environment=local` and the unchanged local base URL; the before/after process IDs differ (`local-relaunch.log`). CUA could not resolve Simulator by name or its installed Xcode path, and its app inventory omitted Simulator. Literal Simulator-icon tapping therefore remains unverified.
- Existing build-configuration Swift language mode and deployment targets match exact HEAD. New app/test sources have target membership; project plist and local documentation links validate. `git diff --check` passes. No generated JS/CSS or API schema changes are present.

Reproduction commands (use the dedicated simulator available locally):

```sh
swift test --package-path Packages/CoreFlow
swift test --package-path Packages/BlockNoteEditor
xcodebuild -project ArcNote.xcodeproj -scheme ArcNoteTests -destination 'platform=iOS Simulator,id=EBACA372-C94A-4A14-9947-634DF3918495' CODE_SIGNING_ALLOWED=NO test
xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete build
xcodebuild -project ArcNote.xcodeproj -scheme 'ArcNote Production' -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

UI runs use scheme `ArcNoteUITests` and explicit `-only-testing:ArcNoteUITests/ArcNoteUITests/<method>` selections listed above; the full target contains live-server tests and was not run. Local logs/xcresults are under `.superpowers/sdd/2026-11-19-ios-execution-boundaries/`.

## Existing UI and fixture limitations

`testNativeFidelityHomeMenuOpensRealUnboxedEditor` failed before editor entry because it expects `home.card.menu.preview-note`. At HEAD the home list already projects scoped local notes, while that display-only development profile supplies no authenticated/offline note scope. This test still uses the older remote preview fixture. The task does not grant anonymous product note access to make it pass. Dedicated editor fixtures and real scoped disk lifecycle tests provide the editor evidence; this fixture mismatch remains explicit.

`testMergeArtifactEditsInPlaceAndRestoresDraft` fails its paragraph-frame top-bound assertion by about 3 points after horizontal text selection. Two current-code repetitions and a build of exact HEAD `c5f005037f2c88bdccdbc5209060a62f68d40bd0` from `git archive` fail at the same original line 1119 with the same values (299.0 versus 302.3333435058594). Logs: `t7-ui-long-repeat.log`, `ui-baseline-build-cached.log`, `ui-baseline-test.log`. The existing assertion and generated CSS are unchanged. Its earlier failure prevents that test from reaching save/restore, so a focused immediate-Back/reopen test independently covers the new execution path.

The new focused test's first draft also attempted process relaunch. Inspection confirmed `MergeArtifactFixturePersistence` deliberately holds only an in-memory snapshot; process restart creates a fresh fixture. The invalid relaunch assertion was removed, while immediate Back, reopening and body/tag assertions remain. Real UserDefaults persistence and coordinator restoration are exercised in app-host tests. Process-relaunch draft recovery is not claimed from this visual fixture.

The existing SwiftUI "Publishing changes from within view updates" fixture warning is also present in the exact baseline run. Neither existing visual fixture issue is hidden by changing product authorization, geometry tolerances or generated resources.

## Performance and remaining work

See [measurements](2026-11-19-ios-execution-baseline.md). These are synthetic Debug simulator/macOS observations, not physical-device frame improvements. No peak process-memory, 1000-note scrolling, production-network or physical-device energy claim is made. Mailbox estimated payload occupancy is not process peak memory.

A 15-second Time Profiler launch of the existing long Merge fixture completed normally and exported 1459 samples (`verified-merge-launch.trace`, `verified-trace-samples.xml`). Stack occurrences included resource validation on other threads (11), bridge worker apply on other threads (32), Merge prepareDraft on other threads (8), and the residual makeCleanDraft on main (2). These counts are diagnostic evidence of placement, not time percentiles. Builds were running concurrently, so this capture is not a controlled before/after performance comparison. Instruments reported one table without a known input source; the exported time-profile samples themselves are nonempty and inspected.

The largest measured remaining synchronous Merge cost is makeCleanDraft's codec decode: about 36.6 ms p50 / 37.3 ms p95 for 1000 blocks on the Mac fixture. The unchanged store's UserDefaults JSON save measured about 2.9 / 3.0 ms. These are reported as remaining work, not counted as migrated computation. Full HomeCardsManager projection, SSE and Merge persistence API changes remain outside this iteration.

## Decisions and review

One fresh-context independent review covered all changed production sources and relevant tests, including untracked additions. Its first response explicitly lacked full coverage; the same reviewer completed the original review before the fix pass. There was no second review cycle. Four Important findings were reproduced before fixing:

| Finding | Correction | Regression evidence |
| --- | --- | --- |
| Distinct preview versions cancel each other's readers | Keep version-specific flights; only the latest flight publishes to cache | 14 cache tests plus app overlap regression |
| Profile selection can change while JPEG save awaits | Disable both launchers and guard both binding setters, including late callbacks | Real gated JPEG/binding test plus caller contracts |
| Fixed canonical-drain cutoff misses later accepted body | Drain again while the original attachment has pending events; synchronously check before sealing/reloading | Real worker/mailbox test with two gates and post-cutoff body |
| Hidden pending/failed editor permits reopening stale state | Block that job during ordinary close; retain failed owner in existing Retry transition | Pending-close and failed-close/retry tests with actual UserDefaults |

Review rulings:

- Returning an older immutable preview to its own still-live reader is valid; it cannot replace the latest cache entry. Scope/card invalidation still rejects all invalidated readers. This intentionally replaces the earlier over-broad retirement behavior that blanked simultaneous views.
- A rare hidden conversion failure uses the existing global Merge retry transition. This temporarily blocks Merge actions and retains the only owner of the unsaved body; it adds no general task framework.
- The Minor suggestion to automate full object-envelope/raw-JSON field parity is deferred. No current missing message field was identified. Future protocol changes must update capture and decoding together; the field-parity regression is follow-up work.
- Canonical reload waits until the live accepted-event queue is empty and local state remains clean. Continuous editing may postpone canonical reprojection; preserving local input takes precedence.
- Back completes a pending tag before snapshot capture even if the snapshot subsequently fails, following the approved action ordering. Lossless-rejection and no-minimize behavior remain tested.
- Direct same-actor `activate` preserves its previous force-reset semantics; lifecycle synchronization remains idempotent.
- Shared fixture preview readers remain isolated from product authorization. The obsolete Home fixture does not justify granting anonymous local-note access.
- Keep synchronous makeCleanDraft decode and UserDefaults persistence as measured residuals. Their store restoration/acknowledgement ownership, Home projection and SSE are outside this iteration.
- Physical-device latency/energy, peak process memory, 1000-note scrolling and live-server behavior remain unverified. Synthetic tests do not establish production frame-rate improvement.
- Work stays on the existing checkout without commit/push; the three pre-existing xcuserdata changes are preserved. The ignored [implementation ledger](../../.superpowers/sdd/2026-11-19-ios-execution-boundaries/progress.md) and logs are retained locally because no commit was authorized.

### Additional implementation rulings retained from the ledger

- Cache byte-budget fixtures use 160 rather than 128 bytes because prepared plain text adds to value size; production remains 40 entries/4 MiB. The fixture still proves one value fits while two require eviction. Risk of an incorrect fixture would be missed eviction behavior, covered by runtime budget assertions.
- Fixed attachment drain/close handles are public because the app persistence owner must seal and drain a package-owned editor. This is the minimum ownership contract, not a general execution framework. A wrong lifetime contract would lose final edits; teardown/replacement/retirement regressions cover it.
- Scope and Merge ownership were established before enabling the relevant bridge worker. The temporary synchronous Merge branch was removed only after original-actor drain tests passed. A wrong ordering would permit late writes into the next owner.
- The retained-view final tasks intentionally own their controller until completion. The projection task's explicit strong capture documents existing lifetime ownership; its nested document callback stays weak. A wrong release boundary could retain an editor indefinitely; closed mailbox state and handlers are released at the final close event.
- The final test/document records are retained locally because they have not been committed. The existing main checkout is preserved under the approved no-commit/no-push workflow; no integration menu or worktree cleanup is needed.
