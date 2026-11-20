# iOS execution boundaries

UI state owners remain on MainActor. Expensive pure transformations run outside MainActor and return values that the owner validates before applying. This incrementally implements the [approved design](../superpowers/specs/2026-11-19-ios-execution-boundaries-design.md); the [plan](../superpowers/plans/2026-11-19-ios-execution-boundaries.md) tracks remaining work.

## Eight rules for new features

1. Keep SwiftUI rendering, navigation, authorization decisions and published state on MainActor. `Task {}` created there does not by itself move synchronous work off MainActor.
2. Pass immutable input snapshots into a module-owned worker. Never send a view, mutable store or live authentication object into a compute closure.
3. Put CPU-intensive parsing, encoding and validation on an explicit non-main executor. Bound actual running synchronous work; cancellation does not free a slot until that work returns.
4. Check identity before starting and before publishing. Include account/environment scope and data revision where ownership or freshness depends on them. Cancellation alone is insufficient.
5. Reuse the existing module reader/cache. Share identical in-flight reads, retain only bounded display data and invalidate on session/card changes. A display cache does not authorize writes or replace confirmed reads.
6. Preserve accepted editor events in order. An editor close or account transition must drain accepted events and persist with the original scope before releasing its owner. This contract must exist before editor compute is moved.
7. Keep cancellation local to the operation's semantics. A canceled display consumer may discard a result; it must not silently cancel an accepted mutation or another consumer's shared read.
8. Prove the boundary with runtime tests: thread/executor, overlap limit, stale result rejection, cancellation and final-save behavior. Profile synthetic workloads and distinguish measured values from unmeasured claims.

## Card previews — implemented

`CardPreviewReader` is the application entry point. `LibraryCardPreviewCache` owns a two-operation queue, a 40-entry/4 MiB LRU and in-flight sharing. It produces preview text, image references and plain text together; view bodies only construct inputs and display prepared values.

Remote inputs retain the card hash or loaded snapshot identity and actual display content. Local inputs require an explicit `NoteStoreScope` and body revision projected from `NoteLibraryStore`; missing local identity cannot fall back to a remote read. Reader access and cache tokens are checked on both sides of the await. Distinct immutable versions keep their own readers; they cannot cancel one another. Only the latest registered version may publish into the shared cache. A canceled last consumer retires its result while an already running parse continues to occupy its queue slot.

```swift
// Stable identity for the loaded card snapshot, owned by the view.
@State private var snapshotID = UUID()

// Preserves explicit local ownership when present.
CardPreviewValue(input: card.previewInput(snapshotID: snapshotID)) { value in
    Text(value?.plainText ?? "")
}
```

Production views use the shared reader. Explicit DEBUG visual-fixture roots inject an isolated reader/cache; this does not grant anonymous product access.

### Home row dependencies

`NotesCard` receives its own immutable card and action closures. It does not observe `HomeCardsManager`; list loading and another card's favorite state cannot independently invalidate every row. The owning list still projects changed card values, and preview authorization keeps its own subscription. Small guidance decorations independently observe their tip store, so dismissing or re-enabling a tip updates both halo and callout without a card change. DEBUG-only optional environment observers count actual body evaluations and guide visibility without retaining or logging note content.

### Local note thumbnails

`LocalNoteThumbnailReader` owns shared local image reads and prepared bitmaps. `NoteLibraryStore` issues an identity from its already-published immutable note snapshot, bound to the current account/environment, local note, body revision and owned immutable attachment preview ID. Identity resolution does not fetch and decode another whole database record before consumers can share work. Reference extraction, media binding, display-URL assembly and SHA-derived remote download IDs run on `NoteMediaReferenceWorker` with exact-body reuse (40 entries / 4 MiB); its lazy remote-reference index shares that byte budget and includes the server asset ID in its version. Local attachment binding bypasses remote hashing. Legacy URL-only content is inspected on the worker as well. An identity cannot authorize an attachment removed from the current body or a trashed note.

Identical identities and target pixel sizes share a flight. At most two whole read/verify/prepare pipelines run, and synchronous thumbnail work stays off main. Last-consumer cancellation retires its result but holds the slot until actual completion. Cached bitmaps use a 40-entry / 16 MiB LRU charged by decoded `bytesPerRow × height`; memory pressure clears retained results. Account/session retirement clears work, and body/lifecycle changes retire obsolete identities. Authorization and revision are checked before reuse and after awaiting, and view task identity includes scope, note, revision, source and reader generation.

Attachment IDs already have immutable bytes and metadata; this cache does not weaken `NoteAttachmentFiles` integrity checks. Warm bitmap reuse does not reread and hash those same immutable bytes. The two existing local source forms (media reference and preview URL) share this path; remote `AsyncImage` transport is unchanged. Requested thumbnail dimensions and existing image/loading/failure layout remain unchanged. UIKit's [thumbnail preparation API](https://developer.apple.com/documentation/uikit/uiimage/preparingthumbnail(of:)) avoids full-size decode for display; the reader bounds concurrent calls rather than starting one per appearance.

### Supplied HTML text

`HTMLTextRenderer` supplies a stable card ID and the already-owned HTML snapshot to `HTMLTextReader`. The reader reuses `LibraryCardPreviewCache`'s two-operation queue, cancellation handling and 40-entry / 4 MiB budget with `LegacyHTMLTextFormatter`; there is no new general scheduler. The formatter deliberately preserves the old case-sensitive tag replacement, entity order and whitespace behavior instead of substituting the richer Markdown preview dialect. Source equality invalidates old results, and SwiftUI displays only the result for its current request.

Chat attachments, user profiles, trash, linked notes, editor metadata and discovery paths all use this entry. Text conversion does not fetch note data or grant access: anonymous/public snapshots already supplied by a screen still render. Account/session changes retire cached and in-flight conversion tokens; the owning screen remains responsible for deciding which input it may display. Font, color, line limit and alignment stay with the renderer's caller.

Runtime cases, synthetic measurements and limitations are recorded in [render/image/text validation](../qa/2026-11-19-ios-render-image-text-validation.md).

## Verification

- Concurrency migration gate: `make check-concurrency`; add `IOS_DEVICE=<dedicated-simulator-UUID>` for App-hosted tests and six ordinary/Merge editor UI flows. See [Swift 6 migration validation](../qa/2026-11-20-swift6-migration-validation.md).
- CoreFlow: `swift test --package-path Packages/CoreFlow`.
- App-hosted tests: shared `ArcNoteTests` scheme, Local configuration, isolated network sessions.
- [Synthetic baseline and limitations](../qa/2026-11-19-ios-execution-baseline.md).
- [History](execution.history.md).

### Swift 6 adoption — all first-party targets

ArcNote, CoreFlow, BlockNoteEditor and their hosted/package/UI tests use Swift 6.
All App/test configurations (Debug, Debug-Production, Release) also retain
`SWIFT_STRICT_CONCURRENCY = complete`. The workspace requires Swift tools 6.2 or
newer for isolated destruction and isolated protocol conformances; iOS 16 and
package macOS 13 deployment floors remain unchanged. BlockNoteEditor's own
manifest retains tools 6.0; its tests depend on the tools 6.2 CoreFlow package.

Neither default MainActor isolation nor Approachable Concurrency is enabled.
Mutable UI/authentication owners and synchronous publisher-facing services belong
to MainActor. Async business adapters are checked Sendable and retain nonisolated
mapping/file work; only publisher creation and consumption enter MainActor.
Explicit workers, accepted-event draining and account/revision checks remain the
execution contract. UI environment callbacks preserve actor ownership, Sendable
captures and optional action absence. WebKit/keyboard observer cleanup uses
isolated destruction; callbacks already delivered on main retain synchronous
behavior without a new Task hop.

CoreFlow date parsing keeps the original ISO8601DateFormatter behavior inside a
private lock, also reused for App Chora/notification dates. Recent-read cache
invalidation/destruction belongs to MainActor. Core Data transaction closures
require Sendable captures while managed objects remain on their private queue.
See the [CoreFlow checkpoint](../qa/2026-11-20-swift6-coreflow-validation.md) and
[whole migration evidence](../qa/2026-11-20-swift6-migration-validation.md).

`scripts/check-concurrency.py` inspects resolved Xcode settings and package
manifests, runs its own regressions and both package suites, and builds Local,
Production and Release. It never injects language-mode or checking overrides.
An explicit `IOS_DEVICE` adds Local App and six ordinary/Merge editor UI tests;
Production is never launched. The broader migration feature matrix is recorded
in the validation document; six editor cases alone are not whole-App coverage.

The gate checks every selected UI bundle/class/method and its passing status in
a separate `.xcresult`. Missing, skipped or renamed cases fail even when
`xcodebuild` exits zero. Machine-readable stdout is kept separate from stderr.
First-party concurrency warnings also fail: legacy SDK imports can downgrade
Swift 6 violations to warnings. Vendor and ordinary style warnings remain visible
without redefining the migration scope. Runner regressions cover all nine App/test
configuration pairs, implicit-actor settings drift, warning handling and incomplete
UI results. Every gate run uses fresh temporary SwiftPM build products and Xcode
DerivedData, preventing cached products from hiding an unchanged warning on retry.
Downloaded dependencies are retained. Each package's products are removed before
the next suite; Xcode products are removed when its phase exits. App and UI
xcresults live outside those temporary products and survive a failed run.
Logs, source-package downloads and xcresults default to `.build/concurrency/`,
configurable with `CONCURRENCY_OUTPUT`; `--settings-only` checks configuration
quickly. The full gate deliberately pays for recompilation to verify diagnostics.

The [editor pilot](../qa/2026-11-20-swift6-editor-validation.md) and CoreFlow
checkpoint record earlier mixed-mode states. Their pending-App statements describe
those checkpoints, not the current language modes. New first-party features enter
the existing actor/worker boundaries and compile under the same Swift 6 gate.

### Main delivery and next integration checks

The complete migration and local integration fixes were committed and pushed to
`main` as `9ccbeea` on 2026-11-20. A fresh full gate passed all three builds,
1,065 CoreFlow cases (six additional live-API cases skipped), 76 editor cases,
79 hosted cases, 18 runner checks and six exact editor UI cases. See the
[delivery record](../qa/2026-11-20-main-delivery.md) for scope and evidence.

The [next-stage plan](../superpowers/plans/2026-11-20-post-swift6-integration.md)
is not yet implemented. It prioritizes mandatory simulator/CI wiring, ordinary
account live synchronization, account switching, retained-data upgrades and
Merge failure diagnosis. First-party language migration is complete; these
runtime and cross-end checks remain distinct. The local M1/M2 backend options
are restricted to dev/test and do not establish production synchronization
readiness. Keep the current explicit concurrency semantics while closing these
gaps.

## Network responses — implemented

### Local lifecycle action dispatch

A native owned-card menu must send `local-note:` removal through the existing
`LocalNotesController.setLifecycle` operation. The local transaction is authoritative
for My Notes; the coordinator owns the guarded cloud deletion, retry and receipt.
The native confirmation and current account/environment validation remain intact.
The failed-sync local Trash regression and real Go
edit/relaunch/delete/restore/purge flow pass. Cloud-only action routing is unchanged.

### Online administrator access and offline eligibility

The real Go access resolver can return `mode: unavailable`, `status: allowed`,
`reason_code: admin_bypass` for a currently authorized administrator, even when
the policy service is unavailable. The client must recognize this exact online
response without treating it as a private-beta membership or persisting offline
note access. A verified, connected session may open its scoped local library;
without connectivity it must have a separately retained offline grant. Token
rejection must check that retained grant rather than the current online bypass.
Other unavailable/allowed combinations remain invalid. Model/store/offline and
hosted regressions cover these boundaries; the real authenticated simulator now
loads and edits scoped notes. Full lifecycle evidence is tracked in the
[live integration record](../qa/2026-11-20-ios-live-integration.md). Server
permissions and policy configuration remain authoritative.

NetworkManager owns authentication, request construction and UI delivery on
MainActor. Its nonisolated response preparation continues on the existing serial
decode queue for generic JSON, raw errors and native uploads. Final results,
loading state and alerts return to MainActor; credential-exchange errors embedded
in HTTP 200 responses retain their original meaning.

Async adapters bridge Sendable values through `NetworkManager.firstValue` using
AsyncThrowingStream, with subscription and cancellation on MainActor. This retains
immediate cached values, empty completion and original failures without sending a
Combine iterator between executors. Merge canonical request encoding is prepared
by the nonisolated service before entering NetworkManager. NoteImport retains its
specialized cancellation/termination drain: security-scoped files stay accessible
until the upload actually terminates.

Only card detail GET uses a subscription-owned cancelable request. CardDetailReader still owns the single shared transport; invalidating a card/session cancels the real Alamofire request. Canceling one async reader does not cancel another reader. Mutation publishers remain eager shared Futures. Payload and credential values are not logged.

## Native image preparation — implemented

CardImagePreparation serializes JPEG encoding outside the main thread. A canceled queued entry releases its image; an already running encoder occupies its slot until completion. Quality, orientation and dimensions follow UIImage.jpegData unchanged. Profile, Chora avatar and note-camera callers validate selection/task identity and account scope before uploading or applying. The profile image launchers and their bindings reject replacement while saving, including late callbacks from an already-presented picker. PhotosPicker data is not encoded again.

## Bundled editor resources — implemented

BlockNoteResourceValidator owns one shared in-flight task and successful manifest per immutable app-bundle lifetime. Validation, including complete SHA checks, runs outside MainActor. Failures remain retryable. Independent test validators have independent caches. The coordinator loads WKWebView only after validation and a live attachment check; tearing down one view never cancels another view's shared validation.

## Local editor persistence — implemented before bridge offload

Each controller attachment exposes a fixed drain handle and idempotent closing boundary. Inactive/disappear flushes do not seal a reusable editor. Dismantle seals synchronously, rejects new commands and fails pending snapshots, while retaining accepted-event drains.

LocalNoteEditorPersistenceSession holds the original NoteStoreScope, body model and editing store. It drains before checking dirty/untouched state, serializes saves independently of View tasks, and releases its registration only after the relevant attachment closed and saving succeeded. A replacement binding cannot be unregistered by an old completion.

LocalNotesController suspends old-scope synchronization, seals/drains registered sessions and only then configures the latest authentication target. Failure retains the original store/session and exposes a retry state. ContentView checks actual scope agreement immediately and hides old content while saving or retrying. Snapshot requests also capture their original controller/instance/revision base before awaiting.

## Editor bridge execution — implemented for both profiles

A per-attachment MainActor mailbox captures bounded scalar envelopes and submits one ordered stream to BlockNoteBridgeWorker. The worker owns the existing stateful session/adapter, JSON decoding, document reconciliation and command encoding. WK calls and UI publication stay on MainActor. Ready, body, commands, focus observations and snapshots share the same sequence; drain completes only after the corresponding UI/store callback has run.

Closing seals ingress synchronously and appends one close item after accepted events. Delivery survives coordinator teardown until that close drains, then releases the handler and document state. Snapshot deadlines include queue time and complete once. Focus probes carry an observation revision so a late probe cannot override newer focus. Both standard and Merge profiles use this worker; Merge was enabled after its retirement tests passed.

## Merge conversion and retirement — implemented

MergeArtifactEditorWorker converts immutable document/manifest values and prepares display URLs and unresolved media references. MergeArtifactDraftController owns projection generation, editor instance and local revision. It marks pending work before suspension, serializes conversion, coalesces only unstarted ordinary inputs, and awaits every explicit snapshot. A result cannot overwrite a newer revision or a replacement editor. Applying a body preserves current store tags.

Accept and Back complete pending tags, establish a per-action lock, and await their exact snapshot conversion and local store update. Accept then flushes and commits through the existing store; Back minimizes after local confirmation. Closing revokes the action but drains already accepted conversion. Canonical server reprojection drains the original bridge watermark and checks the live pending count again on MainActor. If more events arrived after the cutoff, it drains again; replacing the editor has no suspension between the empty-mailbox check and sealing. Bridge retry preserves the document profile and authorized URLs, and resubmits the replacement instance's retained body when necessary.

MergeTaskCoordinator keeps registered editor drain capabilities alive after View disappearance. Actor transition hides old rail/cover immediately, freezes old network work, seals ingress, drains and persists with the original actor, then invalidates the old store and activates the latest target. Ordinary disappearance blocks reopening the same job until the original editor finishes draining. A failed hidden editor enters the same retained-owner Retry transition, preventing a fresh editor from overwriting unsaved text. Inactive flushes do not seal. MergeSessionStore.beginLocalEditorDrain invalidates remote result tokens without resetting pendingSaveWasAttempted: an attempted idempotency key keeps its exact request body.

Canonical clean-draft preparation now uses the same per-job worker as editor projection. A single pure decode is reused only for byte-identical input, with a 1 MiB estimated input/output retention limit. Display URLs remain freshly validated on each projection. Initial loading publishes the artifact and clean draft together after preparation; conflict adoption and explicit reload recheck owner, request identity and newer local edits after awaiting. Oversized and incompatible inputs keep the previous compatibility behavior without entering the cache.

Synchronous Merge persistence remains unchanged (about 3 ms in the synthetic macOS Debug sample). The [follow-up validation record](../qa/2026-11-19-ios-merge-home-read-validation.md) distinguishes it from the decode moved off-main.

CoreFlow/editor actor inputs and results are Sendable; the JPEG queue has checked Sendable ownership with an explicitly Sendable encoder. UIKit/WK interactions and observable state retain their main-thread ownership. The Swift 6 migration resolved the former NetworkManager Combine type-transfer warnings through explicit callback ownership and a Sendable value bridge. Background response preparation and the existing execution boundaries remain covered by the migration regressions.

## Library list projection — implemented

HomeCardsManager owns one HomeCardProjectionWorker and one drainer. Immutable OfflineNote snapshots carry their original NoteStoreScope into the worker. Mapping, date formatting and sorting run off-main; changed rows are sorted and merged with unaffected rows in O(n + k log k). Scope/sort resets supersede queued input, per-ID deltas coalesce, and MainActor publishes only a result with the current generation and no newer pending changes. Scope changes clear visible cards immediately. Library mode and public-profile mode cannot publish into one another. Initial loading remains active until synchronization and the current projection finish, preventing a populated offline library from briefly showing its empty state.

NoteLibraryStore retains synchronous authority and revision checks while merging committed batches in O(n + k log k), avoiding repeated array scans. This atomic publication does not gain an await. Immediate post-edit action state reads the committed local note while its display projection is pending.

## Shared reads and public pagination — implemented

NoteLibraryStore owns one in-flight missing-note download per asset in its current account/environment generation, including the single apply/publish. Canceling a consumer only discards its own result; scope retirement cancels owned tasks and prevents their publication. Completed local notes are reused, failure is retryable, and an older completion cannot retire a replacement task. Existing NoteSyncCoordinator synchronization sharing remains the sole sync-flight owner.

Chat referenced-note hydration uses CardDetailReader's lazy publisher adapter, sharing transport with asynchronous detail readers. Home post-edit cloud refresh uses the same reader with explicit fresh-read semantics; display cache values never bypass confirmation. Public profile pagination holds one session/profile/page request, coalesces repeated same-page loads, advances a page once and rejects superseded results. Refresh replaces an in-flight later page; account change retires and clears the profile list.

Comment session invalidation closes an active read synchronously and invalidates
its outstanding response. An unopened/already closed comment store does not publish
an unchanged idle state during session restoration; this prevents nested SwiftUI
publication when a view first resolves the authentication owner.
