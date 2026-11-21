# Permanent deletion recovery — 2026-11-21

This checkpoint covers the current first-launch client contract and the targeted
ordinary-account API/UI checks below. Final backend composition, remote erasure
fencing and whole-product acceptance remain open.

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

Review follow-up reproduced late manifest and detail responses after the local
purge had already removed the row. Sync now treats those observations as
superseded, including both 404 and successful detail responses, without aborting
other notes. Trash also checks the captured session before applying a terminal
rejection. Fresh validation passed all 1,099 CoreFlow cases (six live API cases
enabled), 19 hosted networking cases, and the companion Web suite of 1,044 tests
plus its production build. Independent fix review and public UI acceptance are
recorded separately; these results do not certify backend cleanup.

## Ordinary-account live checkpoint

The isolated Local API was rebuilt from a recorded source digest. The ordinary
account API sequence passed 36 checks, including recovering the original unknown
purge commands, exact receipt identity, source LINK audit after erasure, foreign
actor rejection, restore/retrash baseline rejection and independent image owners.
After a real API process restart, all five retained erasure commands recovered
their original asset/request/Activity/ActionLog/certificate identities.

Two exact native UI selectors passed, zero skips, in 45.875 seconds:
`testTrashPermanentlyDeletesCardFromGo` and
`testTrashPermanentDeleteFailureKeepsRetryableConfirmation`. The latter restores
and retrashes through the actual API while confirmation remains open; it verifies
that the stale confirmation stays retryable. Fixture corrections select the
actual sidebar button and the local Trash row by this test's unique marker;
remote asset IDs are still used for independent API assertions. The prior tests
failed before deletion because they used a generic toolbar element and a remote
ID for a `local-note:` row. No product navigation or deletion behavior was changed
to make these selectors pass.

The Web companion passed actual ordinary-account deletion, lost response after
server commit, recovery after page reload when the server row is absent, exact
original key/body reuse, and restore/retrash rejection of an open confirmation.
A separate lost-response case also recovered the same complete receipt identity
from a newly opened tab after closing the original tab.
These checks do not represent a complete onboarding run or native lost-ACK UI
relaunch; native durable recovery also has the SQLite/network tests above.

A subsequent fresh plain-text NOTE setup reproduced first-attempt soft-delete
`503/note_action_outcome_unknown`. Its original command later recovered without
changing its key/body. Three immediate Python and three browser lifecycle
sequences then passed, including same-second create/delete. The original cause
remains unconfirmed; these successful sequences do not close that diagnosis. Production
composition, all-writer coverage and complete object/vector erasure remain
separate backend gates.

Private raw logs, source manifest, exact xcresult and checks live under
`.superpowers/sdd/2026-11-20-post-swift6-integration/`. Credentials and frozen
ordinary-account requests remain outside the repository.

The backend cleanup receipt describes server-owned objects. Existing local image
cache/orphan reclamation is not certified by that receipt and remains part of
the image I/O/cache readiness work. No full physical-device/performance claim is made.
