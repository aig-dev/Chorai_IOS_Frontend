# Permanent deletion recovery — 2026-11-21

This checkpoint covers the current first-launch client contract. Public backend
composition, physical object cleanup and real ordinary-account UI validation
remain pending; unit coverage alone does not establish launch readiness.

## Contract

The user confirms the displayed trash state. Its existing local NOTE record
atomically stores a UUID request key, immutable request bytes, account/environment,
asset/local identity and generation. DELETE sends the original `base_sync_token`
and `Idempotency-Key`. A timeout or termination cannot create a second command.
There is no offline/background destructive queue and no old-data migration.

An `ERASED` response must bind asset, original request, Activity, ActionLog and
certificate, with cleanup state exactly PENDING or COMPLETE. The local row and
intent are removed together after validation. A generic failure never implies
commit failure. Only declared precommit rejection releases the intent.
`404/purge_target_absent` is separately authoritative about target absence and
this key having no owned outcome; it removes only the unchanged user-confirmed
local copy and does not manufacture an erasure receipt.

Normal sync skips pending purge and preserves it if its manifest began before
the manual operation. Restore/edit are blocked for this one note; a small Trash
message explains retry. Account/session change retires the confirmation view and
late callbacks. No authentication token or additional body copy is persisted in
the command. Original unconditional purge transports are removed.

## Current verification

- CoreFlow related 73 cases passed: SQLite reopen after lost ACK; wrong receipt;
  current account/local identity fences; definitive versus unknown rejection;
  absence from another device; sync-before-purge race; Library and Trash contracts.
- Hosted networking 19 passed before final presentation/absence follow-up:
  lost ACK, malformed exact receipt, same-actor re-login, unknown cleanup state,
  plus existing link/network regressions. The final full gate passed: CoreFlow 1,096 (all six live API cases enabled, zero skips), editor 76, all three build configurations, 104 hosted App tests and all six exact editor UI selectors. The toolchain retains its existing XCTest iOS 17 dylib versus iOS 16 test-target linker warnings; no first-party concurrency diagnostics passed the gate.
- New synchronization-race and terminal-absence tests failed against the prior
  implementation and passed after their corresponding fixes. New type/API tests
  initially failed compilation; they are not claimed as prior behavior failures.
- Web companion: 120 files / 1,038 tests passed; production bundle built. It uses
  the existing frozen-write helper, bounded persistent records and Web Locks,
  defers removing the row until resolution, and checks session generation.

Private raw logs live under `.superpowers/sdd/2026-11-20-post-swift6-integration/`.
Credentials remain outside the repository. Public ordinary-account API and UI
acceptance will be recorded only after the final Go implementation is running.

The backend cleanup receipt describes server-owned objects. Existing local image
cache/orphan reclamation is not certified by that receipt and remains part of
the image I/O/cache readiness work. No full physical-device/performance claim is made.
