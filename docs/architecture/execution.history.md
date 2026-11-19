# Execution boundary history

## 2026-11-19 — Home row dependencies, local thumbnail reuse and legacy HTML

Removed the unused whole-library observer from NotesCard while retaining its own input, actions, guidance and preview lifetime. Added a library-authorized thumbnail identity and background media-reference worker; the app reader shares verified image work, limits actual running pipelines, bounds decoded bitmap retention, and rejects canceled or obsolete scope/body/lifecycle results. Existing immutable attachment and file-integrity contracts remain authoritative.

Moved HTMLTextRenderer's exact legacy transformations to the existing preview queue/cache through HTMLTextReader. Stable card IDs and exact supplied inputs allow reuse across appearance and consumers; public/anonymous supplied text remains supported, without a new data-fetch authority. Existing caller styles and line limits remain intact.

Real SwiftUI row regression reproduced the former extra evaluation. Image, text and hosted-view regressions pass in the focused 20-app/38-CoreFlow run. Final suite/build/UI/review outcomes and the synthetic cold/warm measurements are maintained in the [validation record](../qa/2026-11-19-ios-render-image-text-validation.md).

Independent review then identified repeated identity-stage record hydration, main-actor remote-reference hashing and a stale guidance halo. Added runtime regressions and fixed all three: reuse the already-published body, keep reference binding/indexing on the bounded media worker, and observe guide decorations separately. Final CoreFlow1056 (six live-API skips), App73 and both scheme builds pass; editor76 passes. The validation record explicitly retains the old empty-Trash fixture and physical-device coverage limits.

## 2026-11-19 — T1 preview execution and ownership

Moved Library/selection/Flow/Explore/Spark previews to one scoped reader, including plain-text and accessibility transformations. Local projection now carries its original scope and body revision. The bounded parser queue retains capacity until canceled synchronous work actually ends; replaced generations cannot return stale values.

Added an app-hosted Local test target. Runtime regressions cover local/remote separation, stale results, thread placement, cancellation, real concurrency and local projection. CoreFlow: 1031 tests, six skipped, zero failures; initial app run: eight tests passed, with the isolated-fixture regression added afterward. Measurements and unmeasured items are recorded in the linked baseline. Subsequent implementation and validation are recorded below.

## 2026-11-19 — T2 response decode and detail cancellation

Added an injectable isolated HTTP session and a serial decode queue; moved generic/raw/upload interpretation off main and final delivery onto main. Kept credential-exchange errors and eager mutation semantics. Detail GET starts at subscription and owns cancellation; existing shared reader retirement now reaches URLProtocol.stopLoading. Sensitive response/header/body logging in touched paths was removed.

Runtime tests first failed on main-thread decode, eager detail creation, missing transport cancellation and loading ordering. After implementation, app tests 17/17 and CoreFlow 1031 (six skipped) passed. Cancellation tests also prove one canceled reader does not invalidate the other's shared result.

## 2026-11-19 — T3 JPEG execution and selection lifetime

Added one serial native JPEG preparation queue. Migrated profile images (0.82), Chora avatar (0.88) and note camera (0.9), with selected-image/task/account checks before upload and publication. Queued cancellation releases payloads; synchronous running work keeps its slot. Existing PhotosPicker data and local thumbnail behavior stay on their existing paths.

Six new runtime tests pass: non-main encoding, original JPEG output/quality/orientation, cancellation, bounded real concurrency, queued image release, encoding errors and synthetic 12 MP timing. Caller/source-contract integration is validated separately.

## 2026-11-19 — T4 shared resource validation

Replaced per-open synchronous hashing with a non-main validator actor and a shared in-flight/success cache. WK setup waits for validation and rejects results for torn-down attachments. Failed validation preserves resource_validation_failed and never loads a page. BlockNoteEditor package: 66 tests passed, including cache/cancellation/failure and real WebKit focus, merge, navigation and image runtime tests on macOS.

## 2026-11-19 — T5 ordinary-note drain and final save

Introduced attachment-specific drain/close handles and a persistence session retained by the local notes owner. Replaced view-owned final flush/unregister with lifecycle-owned drain then save. Scope transition now pauses sync, saves with the original scope and uses the latest target; failure retains dirty sessions and blocks old-content presentation with Retry.

Delayed-drain, teardown-after-disappear, inactive/resume, scope change during save, failure/retry, replacement-binding and old-snapshot tests pass. The last test first reproduced a real old snapshot being accepted after editor rebuild; the request now captures and validates its original instance. App host 31/31, BlockNoteEditor 68/68, affected root contracts 8/8 passed. Full CoreFlow's one outdated root-branch text assertion was updated without changing navigation expectations. Simulator regression run is recorded separately.

## 2026-11-19 — T6 ordered editor bridge worker

Moved complete standard-profile bridge computation into one stateful worker per attachment; kept command/snapshot/event delivery order and focus reconciliation. The mailbox retains accepted work through teardown, bounds task creation to one drainer, and releases payloads as they leave the queue. Merge remains temporarily synchronous pending T7.

BlockNoteEditor 76/76, app host 31/31, CoreFlow 1031 (six skipped) passed. Four dedicated simulator editing/failure/image/compatibility flows passed. A 1000-block, 40-revision burst with four snapshots exercised the real adapter: 1090.44 ms total on macOS Debug, peak 47 queued entries / 5,361,600 estimated payload bytes, zero pending after drain. This is one stress observation, not p95 or process peak memory. An earlier fixture without props/children skipped adaptation; its 45 ms result is excluded.

## 2026-11-19 — T7 Merge conversion and original-actor retirement

Implemented network freeze → accepted-event drain → local persistence → lifetime invalidation before moving Merge bridge work. Preserved the exact attempted save request across this transition. Added a pure codec worker, versioned projection/conversion and per-action snapshot completion. Failure retains the original editor/store; repeated actor changes activate only the latest requested target.

Regressions additionally reproduced canonical ACK replacing queued bridge input, and bridge retry losing Merge profile/stranding pending conversion. Canonical reprojection now waits for the bridge watermark; retry preserves profile/URLs and rebinds the new owner's retained body. Back completes pending tags before snapshot capture as specified, including snapshot failure; the prior UI assertion is updated to expect the retained tag chip.

Before Merge bridge activation: 91 focused CoreFlow tests and 11 app lifecycle/conversion tests passed. After activation: CoreFlow 1039 tests (six live-API skips), BlockNoteEditor 76 tests and app host 42 tests passed. Simulator Merge flows and final independent review are recorded in the validation record.

## 2026-11-19 — Final review corrections

The independent review found four important boundary failures. Deterministic regressions reproduced each before the fix: overlapping hashless preview inputs canceled each other's readers; profile picker callbacks could replace the image during save; canonical Merge reprojection could outrun body events accepted after a fixed drain cutoff; and a hidden pending/failed Merge editor did not prevent reopening on stale state.

Preview flights now retain independent immutable versions and only the latest flight updates the cache. Profile launchers and bindings enforce the existing save lock. Merge rechecks the live mailbox before sealing; hidden editors block reopening while draining and retain their original owner for explicit retry on failure. The focused app run passed 29 tests. Final full-suite/build/UI results and remaining limitations are in the [validation record](../qa/2026-11-19-ios-execution-validation.md).

Complete-concurrency checking also identified WebKit bootstrap/callback isolation declarations. These now explicitly belong to MainActor; the existing navigation test follows that actor. No Swift language mode or minimum deployment target changed.

## 2026-11-19 — Canonical Merge, large Library lists and shared reads

Moved remaining clean-draft decoding into the per-job Merge worker, with bounded byte-exact decode reuse across initial preparation and editor projection. New gated tests cover initial loading, retirement, clean conflict and explicit reload while new edits arrive.

Introduced a Library-owned background projection and coalescing drainer. Bulk mapping/date formatting/sorting leave main; both display and committed-note batch publication use linear merges. Added scoped missing-note download sharing, chat/detail transport reuse and public-profile request ownership. No Swift version, deployment target, API, storage schema or generated editor resource changes.

CoreFlow 1050 tests (six live-API skips), editor 76 and full app 58 passed. A denied profile entry also retires an earlier owned-list projection, verified RED→GREEN. Synthetic 1000-row/200-change list update p50 fell from 12.11 ms on main to 2.23 ms including the worker round trip; the main publication measured 0.075 ms without layout. Final review/build/UI results and measurement limits are tracked in the [follow-up validation](../qa/2026-11-19-ios-merge-home-read-validation.md).

The final independent review identified early loading completion during first offline list projection. A gated test reproduced the false empty state; loading now awaits the existing drainer and then rechecks the mode/generation. Full app regression passed 58/58 with complete-concurrency diagnostics. The review introduced no further deferred minor items; baseline limitations remain documented.
