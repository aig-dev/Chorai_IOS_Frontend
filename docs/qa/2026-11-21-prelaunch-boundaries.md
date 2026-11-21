# First-launch boundary checks

2026-11-21. App and test products are from `b78ffc2`; the actual isolated Go
service was rebuilt from `c538df6b`, with source and binary digests recorded.
The earlier purge UI rerun used Go `f122f19e`. Live integration checks used
the Local dev environment, protocol 3 and ordinary account A
(`allowed/product_full`). Production enablement remains open. The dedicated
simulator is iPhone 17 Pro / iOS 26.2, with Xcode 27.2. Swift 6 migration was
already complete before these behavior checks.

Evidence is retained in `.superpowers/sdd/2026-11-20-post-swift6-integration/`.
Credentials and request journals remain in the private task runtime directory.
The original checkpoint used unchanged App production code. The first-note follow-up below uses updated App and test products against Go `646b3fab`.

## Ordinary-account UI

`Task3-Ordinary-Core-Surfaces.xcresult` passed all three exact selectors, with
zero skipped tests:

- `ArcNoteUITests/ArcNoteUITests/testLocalGoHomeEditRelaunchTrashRestoreAndPurge`
- `ArcNoteUITests/ArcNoteUITests/testLocalGoProfileAndSettingsRetainAuthenticatedIdentity`
- `ArcNoteUITests/ArcNoteUITests/testExploreTypedSearchResultTapOpensGoDetailRoute`

The Home case verifies edited server content, relaunch, soft deletion, cancelled
permanent deletion, restoration, another soft deletion and API-visible
permanent deletion. The note disappears from native and API Trash, and the
original asset returns API 404. Profile/settings verifies the actor ID, and
search checks that the selected result opens the same canonical asset. These
tests start with a seeded authenticated session.

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

## Ordinary-account onboarding

`Task3-Ordinary-Onboarding-Resume.xcresult` recorded one pass and one failure,
with zero skips. `testCancellingOnboardingNoteKeepsLibraryStep` passed.
`testCanonicalOnboardingLibraryNoteAndFlowResumeGoV1` failed. The activity
recording shows the editor closing and the guide advancing to Explore before
the user explicitly finishes. The saved note contained the full sample input.

The first-note follow-up reproduced the missing editor after observing the first durable local ID on the old App (`Task3-Handoff-Red.xcresult`). With the fix, `testCanonicalOnboardingLibraryNoteAndFlowResumeGoV1` observed that ID, the open editor and server state `elicit_signal`. It appended more text, explicitly finished, verified a single matching server NOTE containing both chunks, then dismissed a Flow card and resumed the same canonical v1 session after relaunch. The selector passed with zero skips in `Task3-Handoff-Resume.xcresult`. Read-only server inspection found exactly one first-note text event, containing the full 54-character body, and one matching NOTE by the same actor. The ordinary Library autosave and refresh selector passed in `Task3-Handoff-Normal.xcresult`.

One intervening launch (`Task3-Handoff-Green3.xcresult`) reached verified authentication and `elicit_signal` but displayed Explore before the editor was opened. The session had zero user events before the next test restarted it. Holding the tab mount until the real guide became active reproduced the missing Home route in `Task3-Handoff-MountRed.xcresult`. TabBarView now applies the initial route and contextual tips when mounting with an active guide. On the final products, `Task3-Handoff-Final.xcresult` passed both exact selectors with zero skips or runtime warnings: the unforced empty cancellation and the already-loaded guide, two-chunk edit and Flow resume. The final server session `onb_d2b088094a6a48ac` again recorded exactly one text event with the complete 54-character input, one matching NOTE owned by the ordinary actor and the transition to `product_spark_intro`. First-use registration and the full Spark/Merge loop remain open.

### Required check for the two-chunk selector

Run `ArcNoteUITests/ArcNoteUITests/testCanonicalOnboardingLibraryNoteAndFlowResumeGoV1` with an ordinary account against the isolated local Go service. After the selector passes, run the companion against that exact result bundle and its PostgreSQL database from the repository root.

```sh
python3 scripts/check-first-note-handoff.py "$RESULT_BUNDLE" --database "$IOS_LIVE_DATABASE"
```

The selector retains an XCTest attachment with the session ID, ordinary actor ID, server NOTE ID and expected text. The companion reads the isolated `ios_live_*` database in the local `chorai-postgres-dev` container using a read-only transaction. It requires exactly one text submission with the full body for that actor and session, and exactly one matching NOTE owned by that actor with the recorded ID. Both the selector and companion must pass.

## Ordinary-account Chat send and replay

`Task4-Ordinary-Chat-Send.xcresult` recorded one pass in 19.494 s with zero
skips for `testChatConversationSendMessageAppearsInGoList`. The send used the
actual `ACTIVE` binding for ordinary account A. The API confirmed one persisted
input and one `AGENT_REACTIVE` reply. The single persistence-to-persistence
sample was 47.486516 s.

After the native stream disconnected, an authenticated SSE request with
`Last-Event-ID: 17` replayed `agent.thinking` (18), `message.created` (19) and
`agent.response_ready` (20, `succeeded`) for the exact original source. Ordinary
account B received 403 for conversation detail, messages and events. This
checks native send and API/SSE reply and reconnect. Native late-reply
presentation, native reconnect and account-switch acceptance remain open.
This run sets no latency target.

## Concurrency and daily-gate baselines

The credential-free hosted run in `Task6-TSan-Baseline.xcresult` passed all 26
existing tests in `CardImagePreparationTests` and
`NetworkResponseExecutionTests`, with zero skips and no sanitizer reports. The app and hosted test binaries both link the
Thread Sanitizer runtime and contain its instrumentation. This is an existing
boundary baseline; the native import continuation, cancellation and actual
upload-termination cases still need direct tests.

`Task1-Four-UI-Baseline.xcresult` passed the four additional fixture-backed
daily UI selectors for Merge editing/draft restoration, Home's real editor, Trash
cancel/rejection and local removal while sync is unavailable. Exact full
selector matching was checked.

Run the daily gate with `make check-concurrency-required IOS_DEVICE=<UUID>`
using a dedicated iOS simulator. It verifies the
[ten full selectors](../../scripts/ios-ui-gate-selectors.json) in the retained
xcresult and rejects a missing or unavailable device before builds. The gate
has yet to be connected to CI. Repository runner availability and compatibility
with Xcode 27.2 are still under verification.

## Original Merge failure and remaining scope

The original failed Merge job and stage are still present in the isolated
database. Source freeze, media readiness, modality resolution and planning
succeeded. The first text-fusion attempt recorded provider dispatch at
09:06:17 UTC on November 20 and failed at 09:06:21 with
`TEXT_PROVIDER_FAILED` / `text fusion provider failed`. No retained runtime log in the private task directory
contains the original job correlation. This identifies the failing dispatch
branch but does not establish whether the provider, transport or returned
output caused it. Later successful calls do not resolve that uncertainty.

The controlled provider-fault matrix, ordinary-account multiphoto Merge,
native import bridge tests, measured original-image I/O bounds, final
production NOTE composition and release-device/signing checks remain open,
along with the onboarding and Chat acceptance work above.
