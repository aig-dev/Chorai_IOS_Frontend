# First-party Swift 6 migration validation

Date: 2026-11-20. Baseline: `a46f21e`. The prior concurrency/editor pilot and this
staged migration are one uncommitted worktree change. Toolchain: Apple Swift
6.4.2, Xcode 27.2 (27B52). Dedicated simulator: Chorai Execution QA, iPhone 17 Pro,
iOS 26.2. Runtime verification uses Local/synthetic data; Production is build-only.

## Current status

Implementation, package/App regressions, all 47 selected UI flows and independent
review are complete. The review identified two tooling defects, now fixed with
regressions. The corrected full gate passed with fresh build products after local
disk recovery, including all 78 hosted cases and six exact editor UI cases.
Its earlier disk-full failure is retained below with the recovery evidence.
No claim of physical-device speedup, signed archive or complete live-provider
acceptance is made.

## Scope and retained behavior

All first-party production and test targets use Swift 6: CoreFlow,
BlockNoteEditor, ArcNote, ArcNoteTests and ArcNoteUITests. All nine Xcode
target/configuration pairs retain complete checking and iOS 16. The combined
workspace requires Swift tools 6.2; package macOS 13 floors remain unchanged.
Default MainActor isolation and Approachable Concurrency remain disabled.
Third-party dependency language modes and generated editor assets are unchanged.

- CoreFlow: the [module checkpoint](2026-11-20-swift6-coreflow-validation.md)
  characterizes timestamp precision/acceptance, synchronous cache invalidation,
  observer/destruction lifetime and private-context transactions. The original
  parser is retained under a private lock; App Chora/notification parsing reuses
  it with identical options. No persisted schema, endpoint or error contract changed.
- NetworkManager: authentication, request creation, Combine subscriptions and UI
  publication belong to MainActor. Generic/raw/upload response preparation remains
  nonisolated on the existing serial decode queue. Credential errors inside HTTP
  200 responses, stale-auth alert rejection, eager shared mutations and lazy
  cancellable detail reads retain their original semantics.
- Async services: checked Sendable adapters enter MainActor only to create and
  consume publishers. AsyncThrowingStream transfers values without exporting a
  Combine iterator or promise. Immediate cached values, empty completion, failure
  and cancellation are covered. Merge canonical request bytes are prepared off
  MainActor. NoteImport retains its distinct upload-termination drain and
  security-scoped file lifetime instead of adopting the generic value bridge.
- UI: existing state owners and service factories are explicitly MainActor.
  Binding setters and action callbacks retain their original stores, identity
  checks and synchronous behavior. Optional absent actions remain nil. Google
  sign-in snapshots token/error flags before the existing UI dispatch hop; SDK
  objects do not cross executors. Provider cancellation and attempt equality
  retain their prior logic. WebKit KVO and keyboard observation cleanup are
  actor-isolated; already-main callbacks gain no Task hop.
- Workers: preview parsing, thumbnail/media work, JPEG preparation, Merge codecs,
  Home projection and editor event processing retain their explicit workers,
  real concurrency limits, revision/account checks and accepted-event drains.
  LibrarySearch's background Combine map is explicitly Sendable so isolation of
  its UI owner does not move parsing onto MainActor.
- Tests: UI XCTest owners use MainActor and async setup. HTTP fixture callbacks
  require Sendable captures; request tables, counters and URLSession result slots
  are protected by locks. The loopback server keeps its serial queue and the
  mutable CFHTTPMessage never escapes its lock. All original method identities
  and business assertions remain. Two source-contract tests now match the same
  action wiring through explicit closures and actor-safe optional callback types.

## Verification completed

| Check | Result |
| --- | --- |
| CoreFlow after App/UI integration | 1,067 total, 1,061 passed, same six intentional live-API skips |
| BlockNoteEditor with CoreFlow 6 | 76 passed |
| Swift 6 App-hosted suite | 78 passed, zero skips |
| Added hosted network cases | Five: worker service call, raw data, off-main Merge encoding, immediate/empty/error bridge, cancellation on MainActor |
| Original test method inventory | All 1,484 methods retained; 16 additional Swift methods (11 CoreFlow, five App) |
| Swift 6 App and both test target compilation | Passed; no first-party concurrency diagnostics; one existing hosted weak-variable style warning |
| Runner regression suite | 18 passed; settings drift, SDK warnings, repeat-run cache escape, ordinary-warning rejection, product lifetime and retained failure results observed failing before fixes |
| Formal `make check-concurrency` with dedicated simulator | Corrected fresh-products run passed end to end: settings, 18 runner cases, both packages, all three builds, App and six exact editor UI cases |
| Extended UI feature matrix | All 47 exact selectors passed, zero skips/failures: six gate cases plus 41 extended cases |
| Independent whole-change review | No application-code blocker; both tooling findings fixed and verified by regressions and the final complete gate |

Earlier checkpoint evidence remains useful but is not substituted for final
Swift 6 integration: CoreFlow had 12 passing UI flows; the network milestone had
14 passing feature/transport flows while App was still in Swift 5.

## Feature coverage

The [exact 47 UI selectors](2026-11-20-swift6-ui-selectors.json) are retained as
reproducible input. Each bundle/class/method must appear as Passed in xcresult;
exit zero or a lower aggregate count alone does not satisfy the matrix.

| Feature / risk | Runtime and contract coverage |
| --- | --- |
| Ordinary and Merge editing | Six editor UI gate cases; bridge failure/retry, compatibility read-only, image rendering, immediate Back/tag drain and lossy drafts; 76 editor cases plus hosted persistence/retirement tests |
| Library, offline and image ownership | Four recent-note sync UI flows: remote image offline relaunch, conflict with undownloaded image, photo-only local draft, partial history with recent-note editing; hosted thumbnails/projection/cache and CoreFlow local storage/trash tests |
| Auth/account transition | Sign-in validation/offline recovery, send/rejected-code recovery, email change, retained signup draft, interest selection; root logout rejects stale actor callbacks; CoreFlow access/registration/account tests |
| Feed/search, likes and favorites | Browse versus explicit writes, shared detail transport, immediate reopen, native search return; FlowDeck/CardLike/Spark interaction suites and source contracts |
| Comments and nested presentation | Cached first page, keyboard/reset, Spark-sheet dismissal and interactive reopen; CommentReadStore ordering/cache tests |
| Profiles, follows and privacy | Public-profile/follow navigation, failed privacy update and blocked list, MyProfile action wiring/chat routing; CoreFlow profile/privacy stores and contracts |
| Chora, imports and Notion | Actual transport contract fixture including security-scope/termination order; partial save keeps only failed draft; imported-asset destination; history visibility and section behavior |
| Invitation credits | Transport contract, retained pending redemption draft, original detail destinations; CoreFlow idempotency/redemption/pagination cases |
| Notifications/discovery | Contract routes, inbox row/filter behavior and original scopes; shared discovery reads and source-order contracts |
| Owned actions, link/share/report | Four owned-action UI cases cover cancel, failure/retry, receipt-driven visibility/pin and refresh; nested link selection retains origin/callback; hosted raw-share transport and CoreFlow Share/ContentReport stores/contracts |
| Settings/chat/layout | Edit-profile Back returns to Settings; MyProfile opens companion chat; keyboard/composer and root lifecycle checks |

## Gate and evidence

Run `IOS_DEVICE=<dedicated UUID> make check-concurrency`. Without IOS_DEVICE,
package suites, resolved modes and all three simulator build configurations still
run, while simulator runtime tests are explicitly omitted. No language-mode or
strict-checking command-line overrides are used.

The gate additionally rejects first-party concurrency warnings from successful
compiler processes: SDK interoperability can downgrade violations to warnings
even in Swift 6. Vendor and ordinary style warnings stay visible. Regression
coverage proves all nine App/test configuration pairs reject Swift 5 drift,
implicit MainActor/Approachable settings are rejected, and missing/renamed,
skipped, failed or wrong-bundle UI cases cannot pass. JSON stdout is isolated
from diagnostic stderr, retaining both logs.

The independent review found that incremental products could hide a previously
rejected warning on retry. Every invocation now uses fresh temporary SwiftPM
scratch paths and Xcode DerivedData; downloaded dependencies remain reusable.
Each package's products are released before the next suite, and Xcode products
are removed on phase exit. App/UI xcresults live outside temporary products so
failed runs retain their evidence. Recompilation is the deliberate cost of
complete warning coverage. A real Swift 6 Foundation callback reproduced the
old escape (first run rejected, identical retry accepted); two fresh builds both
rejected the unchanged source. The scanner also excludes quoted identifiers and
matches whole diagnostic words, so ordinary variables named `factory` or `actor`
do not fail the concurrency gate. Both issues have failing-before/passing-after
runner regressions; no application code changed for these review fixes.

The first cold rerun passed the package suites and all three builds, then failed
during App tests with explicit disk-full errors (Cocoa 640 / POSIX 28). Only
task-generated rebuildable products were removed; source files, logs and existing
result bundles were retained. This exposed the need to release completed package
products earlier and preserve App results outside temporary DerivedData. Both
tooling changes have failing-before/passing-after regressions. After disk
recovery, the entire hosted suite passed: all 78 exact case identities, including
each of the five previously failed storage/projection/editor-save cases. No App
source change or weakened assertion was needed. The final six editor UI cases
then passed, and the complete gate exited zero. Temporary products were removed;
both App and UI result bundles survived cleanup as intended.

Artifacts are under `.superpowers/sdd/2026-11-20-swift6-migration/`: baseline and
retained method inventories, compiler diagnostics, full package logs,
`App-Swift6.xcresult`, `Extended-UI-Swift6.xcresult`, exact results in
`final-ui-results.json`, the `gate/`, `gate-reviewed/` and `gate-final/` runs, and
`warning-retry-integration/`. `final-review.md` records findings and disposition. Prior
editor/CoreFlow/network checkpoints retain separate bundles. Tests do not touch
the user's other simulator. Unrelated xcuserdata modifications are preserved.

## Subsequent live-integration follow-up

The three previously excluded geometry/fixture scenarios were investigated and
rerun separately. See the [local Go integration record](2026-11-20-ios-live-integration.md)
for measured causes, scoped test fixtures, newly observed product defects and
current acceptance. This does not retroactively count them in the migration gate.

## Deliberate boundaries and limitations

The date parser stays legacy-compatible because eight of 23 characterized inputs
changed under a value-style replacement; fresh formatters were about four times
slower in the local synthetic comparison. MainActor isolated destruction uses
Swift 6.2 with compiler back-deployment support, rather than weakening deployment
floors or exporting mutable cache objects. The narrow lock/SDK boundaries remain
explicit: Operation payload lifetime, UserDefaults wrappers, NoteImport completion
state and test transport confinement. No module-wide unchecked conformance,
preconcurrency import or unsafe global isolation was added.

Live Google/Apple sign-in, production services, signed archive and physical iOS 16
runtime are outside these Local checks. The existing long Merge selection test's
approximately three-point geometry failure and old Home-menu/empty-Trash fixture
gaps were established before this migration; their assertions are retained.
Dedicated lifecycle/offline tests verify persistence, while CoreFlow tests cover
trash behavior. These limits prevent claiming every live feature or device is
perfect solely from compiler/simulator results.
