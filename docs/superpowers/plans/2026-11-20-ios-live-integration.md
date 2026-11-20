# Local Go and iOS Visual Integration Plan

> **For agentic workers:** Use superpowers:executing-plans inline. Preserve the existing uncommitted Swift 6 migration; verify each fix and obtain one fresh-context final review of this follow-up delta.

**Goal:** Start the real local backend, visually exercise the iOS simulator against it, fix observed failures and prove the original paths work.

**Architecture:** Use the existing dev stack, normal authenticated Go routes and scoped local note store. XCTest drives the actual simulator and retains screenshots/results; inspect rendered screenshots and correlate with API state. Deterministic fixtures exercise rejection/cancellation separately from the real backend success paths.

**Tech Stack:** Go/PostgreSQL/Redis/MinIO, Python Agent, Swift 6/SwiftUI/WebKit, XCTest, dedicated iPhone simulator.

**Spec:** User goal in this chat plus [execution boundaries](../../architecture/execution.md), Go [offline sync](../../../../Chorai_Go/docs/modules/offline-sync.md) and [Merge](../../../../Chorai_Go/docs/modules/merge.md) contracts.

## Constraints

- Local dev API only; retain iOS 16 and Swift 6 complete checking.
- Use dedicated simulator EBACA372-C94A-4A14-9947-634DF3918495 and task-owned account/data. Preserve other simulator and existing user data.
- Preserve API authorization, note scope, original receipts, cancellation and save ordering.
- Do not edit generated editor JS/CSS directly; use its source/build pipeline if needed.
- Stay on current branches as required by iOS AGENTS.md. Preserve prior migration and unrelated modifications; do not commit/push in this task.
- Record real runtime evidence. Passing static-preview tests cannot replace real API verification.

## Review Focus

1. Home/Trash must read authorized local notes, not bypass access to satisfy old preview assumptions.
2. Permanent deletion must preserve the local note on failure or stale receipt; cancel sends no deletion request.
3. Merge selection must keep actual edited text visible across keyboard/viewport changes; avoid weakening geometry assertions without measured evidence.
4. Relaunch/save must use durable storage rather than an in-memory visual fixture.
5. Backend setup must retain existing data and production configuration; secrets must not enter evidence logs.

## Task 1 — Real stack and baseline

Files: read Go runtime/startup scripts; evidence in `.superpowers/sdd/2026-11-20-ios-live-integration/`.

- [x] Start Docker and `CHORAI_PROFILE=dev make run-stack`; repair observed local startup problems only as required. Expected: Go `/health` 200 and the dependencies required by real flows healthy.
- [x] Authenticate a task-owned Local session using existing account/bootstrap mechanisms; verify access and note-sync readiness. Expected: valid actor and normal authorized product access, no credential output.
- [x] Build current Local App/UI tests into this task's DerivedData; run the three original problem cases and export screenshots/xcresult. Expected: exact current failures, not inferred from old logs.

## Task 2 — Home and Trash integration

Files: `ArcNoteUITests/ArcNoteUITests.swift`, `ArcNoteUITests/NativeRemediationVisualTests.swift`, existing `RecentNotesSyncUITests.swift` helpers where reused. Inspect `HomeCardsManager.swift`, `CoreFlow/LocalNotesController.swift`, `Models/TrashModels.swift` before any product fix.

- [x] Establish real authorized test notes through Go and normal synchronization. Replace obsolete preview setup in the Home/Trash cases with scoped deterministic fixtures using the same production data path.
- [x] Verify Home menu → editor → change/save → reopen/relaunch with API/body agreement and readable screenshots. Preserve direct-open navigation and unchanged-note close behavior.
- [x] Verify Trash cancel/no request, rejected delete/record retained, restore, and successful delete after confirmation. Use task-owned data; observe server and local state. Add a failing regression before any production fix.
- [x] Run focused Home/Trash and existing offline/owned-action suites. Expected: all exact selected cases pass without skips and screenshots show actual notes/actions.

## Task 3 — Merge selection and real backend flow

Files: `ArcNoteUITests/ArcNoteUITests.swift`, `ArcNote/CoreFlow/MergeArtifactEditorSurface.swift`, `Packages/BlockNoteEditor/Sources/BlockNoteEditor/BlockNoteEditorCoordinator.swift`; editor source repository only if measurements establish that layer owns the defect.

- [x] Reproduce `testMergeArtifactEditsInPlaceAndRestoresDraft`; capture screenshot, native viewport and DOM/selection metrics at the failing action. Rank/test inner scroll, outer viewport and AX measurement hypotheses.
- [x] Correct the responsible layer; preserve the complete visibility assertion or replace an invalid measurement with the actual edited line/selection. Expected: original scenario passes without arbitrary tolerance increases.
- [x] Verify portrait/landscape, keyboard and accessibility text behavior plus Back/reopen and body/tag preservation.
- [x] Run real Go-backed Merge creation/read/edit/commit/relaunch using task-owned source notes and current provider configuration. Expected: server job/artifact/commit agree with visible editor and Library result.

## Task 4 — Visual acceptance and review

- [x] Browse representative real Local Home, feed/detail, search, profile and settings paths; record screenshots and correlate network failures with backend evidence. Fix newly discovered in-scope failures with regressions.
- [x] Run affected package/hosted/UI tests, Local/Production builds and concurrency checks appropriate to final changes; inspect exact test results and screenshots. Production is build-only.
- [x] Update architecture/history and `docs/qa/2026-11-20-ios-live-integration.md` with outcomes, fixes, limitations and repeat commands; update Go module/history if changed and run `make check-docs` there.
- [x] Review this task's delta against the recorded pre-task hashes/diff, with one fresh reviewer; address Important/Critical findings using RED→GREEN regressions. Complete only when real backend visual paths and fixes are verified.

## Final execution record

Completed using the documented runtime alternatives: the existing development
schema was retained, required services used isolated task databases, and unchanged
Memory Core/Worker ran natively after the registry failed. Optional full-stack
services were not required or claimed. All three original failures have passing
replacement measurements/fixtures; 17 selected deterministic UI scenarios and four
real-backend scenarios passed across the recorded bundles. Selected CoreFlow suites
passed 79 cases and all 79 hosted App tests passed. Local/Production builds and nine
persisted Swift 6 configurations passed. The final live Merge bundle has no skips
or runtime warnings. Fresh-context review found no Critical/Important defects.

See the [acceptance record](../../qa/2026-11-20-ios-live-integration.md) for the early
Provider failure, test-induced QoS warning and other scope limitations. Preserve the
ignored evidence/baseline while the changes remain uncommitted; no push was made.
