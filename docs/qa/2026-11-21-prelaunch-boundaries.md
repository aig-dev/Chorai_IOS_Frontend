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

The complete required invocation passed against frozen code `48ae69f` on
Xcode 27.2 / Swift 6.4.2, using the dedicated iPhone 17 Pro simulator on iOS
26.2. The runner suite passed 26 tests; CoreFlow passed 1,093, with exactly
three M1 and three M2 opt-in API tests skipped because no session files were
supplied; BlockNoteEditor passed 76. Debug, Debug-Production and Release built
successfully. The hosted bundle passed 104 cases and the UI bundle passed all
ten manifest selectors, with zero missing, skipped or failed required cases.
The original six defaults and historical 47-selector matrix remain unchanged.

Evidence is under this plan's local SDD workspace in
`task-1-local-gate-root/`, with `task-1-local-gate-root-summary.json` and its
App/UI summary files. The root-held command exited zero, and the pre- and
post-run source hashes matched. Its App and EditorUI xcresults remain in
that directory. The preceding agent-held attempt ended without an exit marker
or a complete UI result bundle; that attempt is retained as interrupted, with
no claim of a full pass. Existing ordinary compiler/Xcode warnings remain
visible. This acceptance closes the local gate; the workflow and actual CI
run still require a qualified runner.

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

## Ordinary session recovery

iOS implementation `50dccfbebe435cd1ca85ad364bffff2d90e68274` on `9b9997a`, actual Go `5e601f58`, Xcode 27.2 and the dedicated iPhone 17 Pro simulator on iOS 26.2. A and B are independently admitted ordinary phone accounts. The switch uses a DEBUG UI-test button calling the public Go phone login endpoint and normal AuthManager session persistence. Both releases from the forwarder occur under the test's control. The app retains the same loopback origin for each complete scenario.

Local result paths below are relative to `.superpowers/sdd/2026-11-20-post-swift6-integration/`.

| Result bundle | Passed / failed / skipped | Coverage |
| --- | --- | --- |
| `Task3-Ordinary-Session-Boundaries.xcresult` | 1 / 2 / 0 | Original actor mismatch, cross-origin offline failure and granted-token revocation expectation failure |
| `Task3-Ordinary-Logout.xcresult` | 0 / 1 / 0 | Original any-element sidebar locator failed before opening Settings |
| `Task3-Session-Recovery-Boundary2.xcresult` | 5 / 0 / 0 | No-grant 401, granted-scope 401 and retained local edit, same-origin degraded relaunch, actor mismatch and actual Settings logout with server revocation |
| `Task3-Session-Recovery-Ordinary5.xcresult` | 1 / 2 / 0 | Synthetic online 403 after prior eligibility blocks access, including on subsequent offline relaunch. Two outdated fixture expectations failed |
| `Task3-Session-Recovery-Ordinary7.xcresult` | 3 / 0 / 0 | Both new ordinary selectors and corrected same-origin offline logout |
| `Task3-Session-Recovery-Hosted.xcresult` | 2 / 0 / 0 | Hosted admin bypass and restricted-account state transition |
| `Task3-Session-Recovery-HostedRegression2.xcresult` | 105 / 0 / 0 | Full hosted App suite, including the new access case |
| `Task3-Session-Recovery-TenUI.xcresult` | 10 / 0 / 0 | All ten committed gate selector names matched the result tree |

`ArcNoteUITests/ArcNoteUITests/testLocalGoOrdinaryAccountOfflineReopenAndSync` verified local text and the persisted image after termination without session reseeding. While the entire origin was offline, the coordinator could not obtain its manifest. On recovery, Go committed the pending PUT, the forwarder discarded the first receipt, and a later request reused its operation ID and exact body digest. The editor reached Synced, and the owner's API returned one note with the exact structured text and uploaded file bytes.

`ArcNoteUITests/ArcNoteUITests/testLocalGoAccountSwitchRejectsOldSync` held a successful A update after the owner's API could already read the updated content. A logged out, B authenticated in the same process and opened Home, then the test released the held response. B had no A body, preview or pending status, and the author's private note was inaccessible with B's bearer. A signed back in, reopened the same local note and image, and confirmed the original server sync token, exact content, image bytes and one note. For each operation, a read-only query matched one Activity and one committed ActionLog. The Activity had one EXECUTED_BY for A, one GENERATED and one USED. Exact asset IDs, operation IDs, digests and counts are in `task-3-session-recovery-source.json`.

Six task-owned photo notes remain trashed after the ordinary permanent-delete endpoint returned HTTP 503 with reason `note_action_outcome_unknown`. Their permanent outcome remains open. The existing test cleanup helper discards the first random idempotency key and suppresses errors. The privately retained six-request follow-up journal reconstructs later deterministic keys and current trashed baselines after the attempts. It cannot independently establish the original wire bytes. See `task-3-session-recovery-cleanup.json` for the affected IDs. The Ordinary7 UI assertions completed successfully before the separate cleanup inspection.

The focused CoreFlow scope, access and coordinator suite passed 47/47. The local concurrency runner passed 26 runner tests, 1,093 CoreFlow tests with six opt-in live cases skipped, 76 editor tests and the Debug, Debug-Production and Release builds. Logs are in `task-3-session-build-gate/`. The first-note handoff, ten local UI selectors and historical 47-selector matrix remain in their existing scopes. First-use registration, the complete canonical onboarding → Explore/Spark/Merge → Chat journey, real credential-expiry timing, production and physical-device acceptance remain open.

### Recovery fixture review

At iOS `55ad164`, two isolated observer tests reproduced omitted keyless writes and an intermediate key/body mismatch in the original replay check. Both now pass. A third isolated test commits each cleanup step in a fixture, drops its first acknowledgement, reopens the private journal and verifies the same outgoing HTTP method, path, key, baseline and exact bytes. It verifies wrong-actor rejection and failure propagation. The final `Task3-Fix1-FrozenWire.xcresult` recorded **3 passed, 0 failed, 0 skipped**. The initial RED bundle is `Task3-Fix1-ObserverRed.xcresult`.

The live selectors now require the reopened image's meaningful dimensions, position inside the editor, absence of fallback text and an offline screenshot. B creates a text-only control note and observes its own positive Synced editor state across release of A's held response. The proxy records every card mutation at ingress and associates responses with their original attempts. Each PUT for the target after recovery must share one method, path, key and digest. Live acceptance of these stronger assertions awaits the reviewed photo-purge backend repair. The earlier Ordinary7 result covers its earlier assertion set. No accounts rotated, no new shared photo note was created, and the six prior purge owners were untouched in this fix round.

Fix round 2 (`e55c250`) retained candidate create receipts until the scoped local note acknowledged its server asset. In `Task3-Fix2-OwnershipRed.xcresult`, the former recorder selected an unrelated note with the same actor's bearer and interrupted the target's response. The isolated regression now forwards both responses, leaves an unresolved or mismatched local mapping ineligible for cleanup, then sends both teardown commands only to the verified target. `Task3-Fix2-OwnershipGreen.xcresult` passed all four isolated tests with zero skips.
