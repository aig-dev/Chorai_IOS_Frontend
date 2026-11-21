# First-launch boundary checks

2026-11-21. App and test products are from `b78ffc2`; the actual isolated Go
service was rebuilt from `c538df6b`, with source and binary digests recorded.
The earlier purge UI rerun used Go `f122f19e`. These are Local, protocol 3
checks with ordinary account A (`allowed/product_full`), not production
enablement. The dedicated simulator is iPhone 17 Pro / iOS 26.2, with Xcode
27.2. Swift 6 migration is already complete; the work below checks behavior
that language-mode compilation alone cannot prove.

Evidence is retained in `.superpowers/sdd/2026-11-20-post-swift6-integration/`.
Credentials and request journals remain in the private task runtime directory.
No App production code changed for this checkpoint.

## Ordinary-account UI

`Task3-Ordinary-Core-Surfaces.xcresult` passed all three exact selectors, with
zero skipped tests:

- `ArcNoteUITests/ArcNoteUITests/testLocalGoHomeEditRelaunchTrashRestoreAndPurge`
- `ArcNoteUITests/ArcNoteUITests/testLocalGoProfileAndSettingsRetainAuthenticatedIdentity`
- `ArcNoteUITests/ArcNoteUITests/testExploreTypedSearchResultTapOpensGoDetailRoute`

The Home case verifies edited server content, relaunch, soft deletion, cancelled
permanent deletion, restoration, another deletion and permanent erasure with
the original asset returning API 404. Profile/settings verifies the actor ID;
search checks that the selected result opens the same canonical asset. These
tests seed an authenticated session and do not validate first-use onboarding.

`Purge-Ordinary-UI-Fix1.xcresult` separately passed the permanent-delete success
and retryable-confirmation cases, zero skips. After the later backend restart,
five original permanent-delete requests recovered their six unchanged identity
fields and reported `cleanup_state=COMPLETE`. This bounded result does not
establish safety for every unknown remote write. The shared-history retirement
contract and remote pgvector erasure fence remain separate server work.

## Session expectations requiring corrected fixtures

`Task3-Ordinary-Session-Boundaries.xcresult` has one pass and two failures, with
zero skips. These failures are retained and are not counted as passes:

| Exact method in `ArcNoteUITests/ArcNoteUITests` | Result and diagnosis |
| --- | --- |
| `testSessionActorMismatchClearsLocalProjection` | Passed; a token/user mismatch clears the local session projection. |
| `testOfflineSessionVerificationKeepsRestoredShell` | Failed waiting for `tab.flow`. The fixture changes the API origin to an unreachable port without first obtaining eligibility for that origin. Offline access is scoped to both actor and API environment. |
| `testRevokedSessionRelaunchReturnsToWelcome` | Failed waiting for `welcome.login`. A verified ordinary account has legitimate offline eligibility. Token verification returned 401, and the current contract keeps local notes while requiring login for further sync. The old assertion assumes no offline eligibility. |

Manual diagnosis used the actual app and ordinary account. The changed-origin
case displayed the unavailable access gate. A fresh session first verified
online and persisted its real actor/environment eligibility; after revoking
that session, the app received 401 and retained Home with local notes.

A separate same-origin experiment used a task-owned loopback proxy forwarding
the real Go API. After the app obtained eligibility and loaded notes through
that origin, the app was terminated and only the proxy was stopped. Relaunch
at the identical origin, without reseeding authentication, retained Home and
local text. This verifies API-unavailable restoration, not offline editing of
every attachment. The proxy and diagnostic app were stopped afterward.

Task 3 still needs deterministic automatic coverage for the same-origin
offline-edit/relaunch/sync sequence, account switching with an outstanding
request, and the distinct no-grant, token-revoked and account-restricted states.
Do not weaken authorization or erase legitimate local access to satisfy the
old fixture expectations.

## Concurrency and daily-gate baselines

`Task6-TSan-Baseline.xcresult` passed all 26 existing hosted tests in
`CardImagePreparationTests` and `NetworkResponseExecutionTests`, zero skips,
with no sanitizer reports. The app and hosted test binaries both link the
Thread Sanitizer runtime and contain its instrumentation. This is an existing
boundary baseline; the native import continuation, cancellation and actual
upload-termination cases still need direct tests.

`Task1-Four-UI-Baseline.xcresult` passed the four additional planned daily UI
selectors: Merge editing/draft restoration, Home's real editor, Trash
cancel/rejection and local removal while sync is unavailable. Exact full
selector matching was checked. The required-simulator CLI and CI workflow
have not yet been implemented; runner availability is not established.

## Original Merge failure and remaining scope

The original failed Merge job and stage are still present in the isolated
database. Source freeze, media readiness, modality resolution and planning
succeeded. The first text-fusion attempt recorded provider dispatch at
09:06:17 UTC on November 20 and failed at 09:06:21 with
`TEXT_PROVIDER_FAILED` / `text fusion provider failed`. No retained runtime log in the private task directory
contains the original job correlation. This identifies the failing dispatch
branch but does not establish whether the provider, transport or returned
output caused it. Later successful calls do not resolve that uncertainty.

The controlled provider-fault matrix, ordinary-user onboarding/Chat/multiphoto
Merge, native import bridge tests, measured original-image I/O bounds, final
production NOTE composition and release-device/signing checks remain open.
These checkpoints are not a first-launch readiness declaration.
