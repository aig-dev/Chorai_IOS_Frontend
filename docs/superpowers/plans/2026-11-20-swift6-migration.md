# Staged Swift 6 migration

Goal: migrate each active first-party iOS module carefully, preserving its business
behavior and improving concurrency where evidence supports it. A module is complete
only after its compiler, caller integration and runtime behavior pass verification.

The user authorized continuous implementation on 2026-11-20. Use inline execution
with test-first changes, verified module checkpoints and one independent review of
the complete migration before completion.
The binding behavior specification is [execution boundaries](../../architecture/execution.md),
the current production implementation and its existing business tests.

## Scope and constraints

- Active first-party targets: BlockNoteEditor, CoreFlow, ArcNote and their tests.
  Third-party package language modes are interoperability dependencies, not a
  reason to rewrite vendor code or upgrade unrelated dependencies.
- Preserve iOS 16 / macOS 13 package deployment floors, current APIs, persisted
  records, endpoint/error meanings, account/environment boundaries and UI features.
- Keep explicit worker execution outside MainActor and UI publication on MainActor.
  Do not enable default MainActor isolation or Approachable Concurrency as a shortcut.
- Do not delete tests or weaken assertions to satisfy the compiler. Compare actual
  test identities and feature coverage, not only aggregate passing counts.
- Audit any unavoidable SDK/legacy safety boundary locally. No blanket unchecked
  Sendable conformance or suppression across a module.
- Local/synthetic runtime verification; Production builds only. No physical-device
  sampling prerequisite. Keep known baseline failures separate from migration regressions.
- Stay on the current branch; preserve all pre-existing changes, including xcuserdata.
  The earlier editor pilot is still an uncommitted part of this worktree.

## Current baseline

- BlockNoteEditor production/tests: Swift 6, 76 existing tests passed.
- CoreFlow: Swift 5 + complete checking, 1056 tests (six intentional live-API skips).
- App: Swift 5 + complete checking, 73 hosted tests; six selected editor UI flows.
- Clean CoreFlow production/test compilation observed 98 concurrency diagnostic
  locations: seven production locations in four files and 91 test locations.
  This is a Swift 5 complete-checking inventory, not an exhaustive Swift 6 error list.
- The long Merge selection/geometry test has a pre-existing approximately 3-point
  clipping failure; dedicated Back/reopen and lossy-draft tests cover persistence.
- The current six-case UI gate covers editor flows, not the entire App feature set.

## Milestone 1 — CoreFlow

- [x] Record baseline diagnostics, existing test identities and affected callers.
- [x] Date parsing: characterize accepted/rejected inputs, offset calendar dates,
  fractional precision and NoteSyncHTTP decoding before changing shared formatter
  ownership. Preserve `dateOnly(from: String) -> String` and `parse(String) -> Date?`.
  Verify parallel parsing and compare cold/warm cost to the existing implementation.
- [x] Recent reads: express MainActor ownership and preserve synchronous notification
  eviction, LRU capacity, session retirement and observer lifetime. Exercise
  CommentReadStore and the App CardDetailReader, including shared-read cancellation.
- [x] Persistence: make transaction/mutation closure ownership explicit without
  moving managed objects out of their private context. Preserve rollback/reset,
  committed-only publication, original-scope final saves and stale-receipt rejection.
- [x] Tests: repair test isolation/lifetime in FlowDeck, onboarding and local-note
  suites without removing cases or changing their business expectations.
- [x] Enable Swift 6 for CoreFlow production and tests, iterating on newly revealed
  diagnostics. Keep the App in Swift 5 during this module milestone.
- [x] Run full CoreFlow/editor suites, App integration and affected simulator flows,
  all three build configurations, actual compiler mode checks and independent review.
- [x] Update architecture, history, verification runner and module validation record.

## Milestone 2 — App infrastructure

- [x] Inventory complete-checking diagnostics and map each shared API to its callers.
- [x] Migrate network decoding and Combine callback ownership while retaining lazy
  shared reads, eager mutations, cancellation, stale-session handling and HTTP error
  semantics (including credential errors embedded in HTTP 200 responses).
- [x] Migrate image work, scoped display readers and session/lifecycle owners while
  retaining actual concurrency bounds, stale-result rejection and accepted-event drains.
- [x] Verify success/failure/cancellation/retry behavior with isolated HTTP, real
  temporary storage and background-worker tests before moving to UI consumers.

## Milestone 3 — App UI, test targets and Swift 6 mode

- [x] Audit UIKit/WebKit delegates, SwiftUI callbacks, observer cleanup and fixtures.
- [x] Resolve isolation at each owning boundary while preserving synchronous decisions,
  action enablement, navigation, keyboard/focus and background-work placement.
- [x] Extend feature-to-test mapping beyond the editor: auth/account changes, Library
  and trash, Explore/search, Spark/Merge, comments/likes/follows, profiles/privacy,
  share/link/import, notifications and settings. Record gaps and add runtime coverage
  for changed behavior where only source-contract assertions currently exist.
- [x] Switch App, hosted tests and UI tests to Swift 6 after their boundaries are ready.
- [x] Verify Local, Production and Release configurations and actual compiler invocations.

## Milestone 4 — Completion audit

- [x] All active first-party targets use Swift 6 without an unchecked/suppression blanket.
- [x] Retained feature/caller contracts and test identities are accounted for; all new
  failures and skips are explained and resolved or established as unchanged baseline.
- [x] Full package/App suites and affected real simulator flows pass; worker/runtime
  regressions still establish execution placement, ordering and lifetime behavior.
- [x] Validate build/verification tooling against missing or renamed tests and settings drift.
- [x] Complete independent final review and update current architecture/history/evidence.
  Do not mark the overall goal complete merely because CoreFlow or a narrow test set passes.

Completed 2026-11-20. The [final validation record](../../qa/2026-11-20-swift6-migration-validation.md)
records all package/App results, 47 exact UI selectors, retained test identities,
review fixes, the final cold gate and the explicit device/live-provider limits.

## Review focus

1. Date formatter replacement may change timezone/precision or accept/reject behavior
   used by synchronization, despite producing the same visible date.
2. An added Task hop can defer cache invalidation or a permission decision.
3. Sendable fixes must not change transaction rollback, receipt identity or final-save scope.
4. XCTest isolation fixes must preserve failure/cancellation interleavings and assertions.
5. Callback conversions must not move heavy work onto MainActor, make writes lazy, or
   let one canceled consumer cancel another consumer's shared work.
