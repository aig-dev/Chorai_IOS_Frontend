# Import recovery validation — 2026-11-21

Scope: the first-launch IMPORTED_NOTE path, current Swift 6 client and an isolated
local Go/PostgreSQL runtime. Ordinary-account product acceptance remains a
separate launch gate. This work does not enable the production NOTE sync switch.

## Behavior and failures reproduced

- A real Kernel import could commit content before archive/source/outcome failed,
  then delete the recoverable upload. The worker also could not resume its own
  running batch. Fault injection reproduced both before the fix.
- Go ignored iOS `client_request_id`. Concurrent retry created multiple batches;
  changed bytes under one request ID returned 202. The batch now owns an
  actor-scoped identity and ordered file-manifest hash. A matching retry returns
  the original job/status; a different manifest returns 409. Replaying an older
  request cannot cancel a newer batch, and only the retry's uploads are discarded.
- Real API UI loading failed despite HTTP 200 because iOS required the retired
  `soul_status` field. A hosted decode test reproduced `keyNotFound(soul_status)`.
  Transport, CoreFlow and fixtures now follow the service's job/file lifecycle.
  Unknown job states remain lossless and keep polling.
- With no pending ID, a second launch hid a completed result. The store now
  displays the latest terminal batch after active batches, without persisting a
  pending identity. Selecting another file generates a fresh identity.

## Verification

Go uses the existing actor admission lock, scheduler lease and one database
transaction for Action facts, archive, source-state, item result, progress and
required outbox. Real PostgreSQL tests cover archive/source/outcome rollback,
restart, partial success, cancellation, revocation, lost COMMIT acknowledgements,
same-item concurrency, request conflict/replay and actor isolation. Fresh/existing
qualified/unqualified runtime schema reconciliation and the actual backend restart
passed; health returned 200. Seven affected full packages passed. The tracked
cmd/internal/pkg/tests packages compile. An unrelated pre-existing scratch
`tmp/merge-reference-study-20261115/work` failure prevents claiming `go test ./...`.

CoreFlow import state tests: 31 passed. Hosted network tests: 13 passed, including
the current response shape, exact request identity and mixed per-file outcomes.
Full CoreFlow: 1071 tests, 6 existing live API skips, no failures. Four exact UI
fixtures passed: contract decoding, imported asset destination, cancellation/unknown
states and unknown labels. The actual local backend batch
`njob_aee83681-8193-4a21-bda2-a8e6b78d0146` passed two app launches while running and
two more after recovery: Imported 1, Failed 1, one Asset/version and no terminal
cancel action. Screenshots were inspected. All owned fault triggers were removed.
The final backend also returned 400 for an empty source identity before staging.
Default Debug, Debug-Production and Release simulator builds passed, with no
first-party concurrency diagnostics. These are not signed Archive/TestFlight checks.
Tests requiring live API credentials are not inferred from unit tests. Upload
callback and termination lifetime is documented in the
[Task 6 native bridge checkpoint](2026-11-21-native-bridge-validation.md).

Artifacts are in `.superpowers/sdd/2026-11-20-post-swift6-integration/` for this
active launch plan. Private runtime credentials stay outside the repository.
