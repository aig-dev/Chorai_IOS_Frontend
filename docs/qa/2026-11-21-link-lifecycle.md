# First-launch Link and lifecycle acceptance

This slice connects the current iOS and Web clients to Go's existing immutable
Link/Unlink lifecycle. It does not enable the final production NOTE/media
composition or establish launch readiness.

## Behavior

- The actor-owned file journal freezes account, API environment, action,
  endpoints, operation ID and exact unlink target before transmission. Lost ACK,
  cancellation and malformed receipts retain that identity across retry/relaunch.
- NetworkManager validates the exact receipt and rejects late account/session
  responses. An ended create or recovered older unlink requires refresh before
  a new intent. Editor models preserve the server association ID.
- Related links load after local body hydration with a dedicated read identity.
  A complete response applies the exact-instance mutations acknowledged during
  its read; this preserves other existing links and avoids an extra GET. A newer
  read, hydrate or explicit replacement retires older delivery. Body autosave
  and related reads do not invalidate each other. The local service verifies
  account generation and server mapping after the await; draft edits stay intact.
- Go's public conditional delete ends the full association set atomically;
  restore never revives it. A later old unlink cannot remove a newly created link.

## Verification

Evidence directory: `.superpowers/sdd/2026-11-20-post-swift6-integration/`.

- Real ordinary-account UI: both
  `testCardEditorOutgoingUnlinkRemovesCanonicalEdgeAndStaysRemoved` and
  `testNewDirtyCardLinkActionCreatesOnceAndPersistsCanonicalRelation` passed in
  `Link-Ordinary-UI-Review.xcresult` after the final review fix (99.435 s total).
  The preceding hydration-fix run also passed. Three existing Link
  presentation tests also passed. The owned simulator is isolated from the user's
  simulator; credentials remain in temporary session files outside the repo.
- Store regressions: 83 tests passed, including draft preservation, autosave in
  both completion orders, late fetch/create/delete and create/delete ABA,
  explicit hydration, and a create observed before its ACK. Editor source
  contracts: 31 passed, including
  metadata propagation through the consolidated service path.
- Hosted network regressions: 16 passed, including lost ACK, malformed receipt,
  account change and resolving an older unlink before acting on a replacement.
- Ordinary Go HTTP: 18 Link checks and 13 linked-delete/restore checks passed.
  Existing six live sync API tests also passed with zero skips. These use the
  current isolated dev protocol 3 composition.
- Web: 1,028 tests, type checking and production build passed; real NoteEditor
  unlink/relink/reload was checked against the ordinary account and local Go API.
- Full concurrency gate passed after review in `link-review-gate`: 18 runner tests,
  1,089 CoreFlow tests (all six live APIs enabled, zero skips), 76 editor tests,
  Debug / Debug-Production / Release builds, 101 hosted App tests and all six exact
  editor UI selectors. Persisted Swift 6 and complete concurrency settings passed.

Checkpoint review reproduced a further race: autosave retired the initial link
read. Simply dropping reads after relationship writes also lost other existing
links. Both cases have gated RED/GREEN evidence in `task-2-link-autosave-*.log`
and `task-2-link-read-mutations-*.log`. The reviewer rechecked the fix and closed
the finding; the full gate above uses the final implementation.

The first real editor run reproduced the hydration race. A separate assertion
incorrectly used a local-note callback ID in the server API; the test now finds
the uniquely created server note. The first complete package run reported three
obsolete source assertions requiring the removed duplicate View mapping; metadata
remains covered at the canonical service and local identity mapping.

Permanent erase, Merge-source receipt paths, all-writer production composition,
native first-use/OAuth and release-device acceptance remain open. No old-user
data migration or second production compatibility path was added.
