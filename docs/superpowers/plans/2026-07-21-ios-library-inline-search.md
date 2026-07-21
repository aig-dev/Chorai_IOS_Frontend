# iOS Library Inline Search Implementation Plan

> **Execution:** This plan is approved by the user and will be implemented in the current session with red-green verification at each behavior boundary.

**Goal:** Make Library search an inline Header mode: tapping Search replaces the normal Header with a focused search field, Return submits a Library-scoped query, and the Filter control lives at the field's trailing edge. Remove the old standalone Search filter modules.

**Architecture:** Keep `HomeView` as the Library navigation and presentation owner. Add a small, pure `LibrarySearchSession` state machine to `CoreFlow` so draft text and submitted text cannot be conflated. Replace the standalone community `SearchView` implementation with a Library-scoped search manager and results view backed by `/api/cards/user-all-cards`; the active Notes/Collect segment determines the fixed `own`/`favorited` scope. Reuse existing Library card views and popup/navigation paths.

**Tech Stack:** Swift 5.9+, SwiftUI, Combine, CoreFlow, XCTest, Xcode 26.3, iOS 16+

## Constraints

- Preserve the normal Library Header's Menu, Notes/Collect switcher, Filter, and Search controls.
- Search only after keyboard Return/Search; editing a draft after submission must not mutate the displayed result set.
- Lock search scope to the segment active when search mode begins: Notes searches owned cards and Collect searches favorites.
- Emptying the field clears the submission and restores the underlying segment list while keeping search mode active.
- Exiting search clears transient search state and restores the normal Header.
- Keep the existing Library sort choices; in search mode, open them from the Filter button inside the field.
- Remove the old always-visible My Collection, Label, and Time modules and stop using global Explore search for Library.
- Keep interactive targets at least 44 points and respect Reduce Motion, Dynamic Type, safe areas, and VoiceOver.
- Do not modify backend or web production code, add dependencies, create a branch, or overwrite the unrelated Flow UI-test edits already present.

## Task 1: Lock search-session behavior with unit tests

**Files:**
- Add: `Packages/CoreFlow/Tests/CoreFlowTests/LibrarySearchSessionTests.swift`
- Add: `Packages/CoreFlow/Sources/CoreFlow/LibrarySearchSession.swift`

- [x] Add tests for entering with a fixed scope, trimmed Return submission, draft/submission separation, empty clearing, and exit reset.
- [x] Run `swift test --package-path Packages/CoreFlow --filter LibrarySearchSessionTests` and observe RED.
- [x] Implement the smallest state machine and sort descriptors needed by the UI.
- [x] Re-run the focused tests and observe GREEN.

## Task 2: Lock the UI and API source contract

**Files:**
- Add: `Packages/CoreFlow/Tests/CoreFlowTests/LibraryInlineSearchSourceContractTests.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/LibraryCardPreviewSourceContractTests.swift`

- [x] Assert that `HomeView` owns search mode, a focused `TextField`, `.submitLabel(.search)`, Return-only submission, in-field Filter, stable accessibility identifiers, and normal Header Filter/Search controls.
- [x] Assert that Library search uses `getUserAllCards` with owned/favorited scope and that the retired Search file contains none of the old Collection/Label/Time filter modules or `SearchManager.shared`.
- [x] Run the focused source contract and observe RED before production edits.

## Task 3: Build the Library-scoped search data path

**Files:**
- Modify: `ArcNote/Models/UserAllCardsModels.swift`
- Replace implementation in: `ArcNote/SearchView.swift`

- [x] Decode the full card presentation fields already returned by the Go `CardDTO` contract and project them into the existing `UserCard` type.
- [x] Add `LibrarySearchManager` with request cancellation, stale-response protection, loading/error/empty state, a 200-result cap, and deterministic client sorting for the four existing Library sort choices.
- [x] Add `LibrarySearchResultsView` that reuses `NotesCard`/`NotesColorCard` for owned notes and `HomePostCard` for favorites.
- [x] Preserve edit navigation for owned notes, detail/author navigation and unfavorite behavior for collected cards, and existing popup layouts.

## Task 4: Transform the Library Header and content state

**Files:**
- Modify: `ArcNote/HomeView.swift`

- [x] Replace the Search `NavigationLink` with an action that enters inline search and focuses the field.
- [x] Render Back + search field in search mode; put clear and Filter controls inside the field with 44-point targets.
- [x] Keep the centered Notes/Collect switcher and separate Filter/Search buttons in normal mode.
- [x] On Return, submit the trimmed draft and query only the locked segment scope.
- [x] Keep normal content visible before first submit; after submit show loading, results, error, or no-results state.
- [x] Reapply the current sort to submitted results when the user changes a Filter option.
- [x] Exit/clear safely and disable transition animation when Reduce Motion is enabled.

## Task 5: Verification and Simulator acceptance

- [x] Run focused Library search tests.
- [x] Run the complete CoreFlow suite.
- [x] Build `ArcNote` and `ArcNote Production` for an iOS Simulator with code signing disabled.
- [x] Launch the app in Simulator and verify normal Header, inline focus, type-without-search, Return-to-results, in-field Filter, clear, Back, Notes scope, and Collect scope.
- [x] Capture the final inline-search and result states if the local authenticated fixture permits it.
- [x] Review `git diff --check`, confirm the unrelated UI-test diff remains intact, and report any environment-limited checks explicitly.

## Acceptance Criteria

- Tapping `home.search` transforms the Library Header in place; it does not navigate to a new screen.
- The field receives focus and exposes keyboard Search; no request/result swap happens until submission.
- The submitted query is stable while the next draft is edited.
- Notes searches only owned cards; Collect searches only favorited cards.
- The Filter icon is the final interactive item inside the search field and applies the existing Library sort options.
- The old My Collection, Label, and Time search modules are absent.
- Empty, loading, error, results, clear, and exit states are accessible and deterministic.
- Focused tests, full CoreFlow tests, both app builds, and available Simulator checks pass with fresh evidence.
