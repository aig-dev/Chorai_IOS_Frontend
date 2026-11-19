# Render, Image and Text Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline, with one fresh final review. Preserve the current uncommitted tree; no branch switch, commit, push or cleanup.

**Goal:** 分步骤实现首页刷新粒度、图片准备复用、其余页面文本计算优化，并仔细审查。

**Architecture:** UI retains its owner and current scope; pure preparation runs behind the existing module execution model. Remove a redundant observer, add bounded scoped image reuse, and preserve legacy HTML output using the existing preview queue/cache.

**Tech Stack:** Swift 5, iOS 16+, SwiftUI, CoreFlow, UIKit/ImageIO, Combine, XCTest.

**Spec:** [范围与验收](../specs/2026-11-19-ios-render-image-text-design.md).

## Global Constraints

- 本次性能优化不以升级语言模式或提高最低 iOS 版本为前提；同时逐步加强并发检查，为 Swift 6 迁移做好准备。
- No API/storage/authorization changes, generated editor edits or new dependency. Local/synthetic verification only; Production build only.
- Baseline is this plan's scratch snapshot, not git HEAD. Preserve all prior changes and xcuserdata.

## Review Focus

1. Row input/actions, dynamic type or contextual guidance changes still propagate after removing the broad subscription.
2. A cached thumbnail cannot survive revoked scope, removed media, replaced image bytes or changed target size as an authorized result.
3. One cancelled consumer, oversized/corrupt image, cache eviction or memory warning cannot strand a shared task or exceed actual running work limits.
4. HTML rendering preserves existing entity/whitespace behavior, anonymous displays and identical-source reuse without showing an older body's result.
5. Long documents/images and repeated appear/disappear must not move work back to main or retain unlimited inputs/results.

## Task 1 — row observation

Files: HomeView.swift and NotesCard callers in SearchView.swift/ArcNoteApp.swift; DEBUG CardRenderingDiagnostics.swift; App HomeCardRenderingTests.swift.

- [x] RED: real UIHostingController counts NotesCard body evaluations; changing manager loading/favorite state must not evaluate the standalone row; changing its own card input still updates it.
- [x] GREEN: remove the unnecessary ObservedObject dependency and obsolete parameter at all callers, preserving independent preview and guidance dependencies.
- [x] Verify focused App rendering tests and affected source contracts; record before/after evaluation counts. No wall-time threshold assertions.

## Task 2 — scoped image preparation

Files: NoteLibraryStore.swift, a CoreFlow media preparation worker, app LocalNoteThumbnailReader.swift and HomeView.swift; package/app media runtime tests.

- [x] RED: concurrent identical thumbnails read/verify/prepare once, reuse after reappearance, independent cancellation, size/version/scope isolation, invalidation, corrupt input, bounded decoded-byte cache and actual preparation concurrency.
- [x] GREEN: NoteLibraryStore supplies immutable authorized image identity/data; media-reference extraction runs off-main with exact-body reuse; app reader owns scoped flights and bounded prepared image cache. Keep authorization checks before cache use and after await.
- [x] Verify package library/image tests and app tests; measure cold/warm synthetic large-image work and count actual file/decode operations. Preserve existing image layout and failure behavior.

## Task 3 — legacy HTML text preparation

Files: HomeView.swift HTMLTextRenderer, CoreFlow legacy formatter and existing LibraryCardPreviewCache extension/adaptation, app text reader; existing HTMLTextRenderer callers as needed.

- [x] RED: exact legacy HTML/entity/whitespace output, unchanged-source reuse, background conversion, changed input/retired session late-result rejection, anonymous rendering and memory bounds.
- [x] GREEN: body displays prepared text only; reuse existing preview queue/cancellation/budget semantics, avoid a second unbounded text cache.
- [x] Verify all current renderer consumers remain connected and styles/line limits remain unchanged; runtime host tests exercise visible text transitions.

## Task 4 — integrated verification and review

- [x] Update execution.md/history and new QA record with measurements and limits.
- [x] Run full CoreFlow/BlockNoteEditor/App suites, affected simulator flows, Local/Production builds, Local restart and doc link checks.
- [x] One fresh read-only review against this iteration's snapshot; reproduce and fix important findings in one pass, then re-run affected full suites.
- [x] Requirement-by-requirement audit of 1/2/3, update goal only when achieved. Retain logs/baseline because no commits are requested.

Validation exceptions: the pre-existing generic dev-preview Trash UI fixture does not seed local Trash, so it stops before any changed text row. Seven other affected simulator flows pass. Native Simulator control is unavailable; the final Local binary passed two no-argument starts including explicit termination, but no literal icon tap was observed. These limits are retained in QA, without changing authorization or claiming unrun device metrics.
