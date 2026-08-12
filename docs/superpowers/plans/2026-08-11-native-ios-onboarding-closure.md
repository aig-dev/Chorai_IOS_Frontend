# Native iOS Onboarding Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Go onboarding flow v1 a visible, resumable iOS journey from first Library note through Flow, Spark, Merge, Library return, and backend `completed` status.

**Architecture:** Go remains the authoritative state machine. CoreFlow adds a pure navigation directive for every route-owning v1 state and expands the actor-scoped contextual-tip catalogue for the currently missing handoffs. `TabBarView` applies directives both when a session first loads and whenever its state changes; product views emit evidence only from real target actions, and guided Merge returns to Library automatically after a successful commit.

**Tech Stack:** Swift 5.9, SwiftUI, Combine, CoreFlow, XCTest/XCUITest, Go/Gin onboarding service, Xcode 26 iOS Simulator.

## Global Constraints

- Keep Go flow v1 and its existing API contract authoritative; do not add client-only server transitions.
- Keep the approved one-sentence, no-`Got it`, no-close-button, no-timer callout behavior.
- A target action may advance server evidence; a dismissed visual tip must never advance or skip server state.
- Preserve the direct top-right Flow Spark control and the existing Library card-menu Merge entry.
- Preserve note-save, Spark favorite, Merge commit, retry persistence, VoiceOver custom dismissal, Dynamic Type, and Reduce Motion behavior.
- A resumed session must expose a visible continuation for every active v1 state that requires user action.

## Canonical Closure Matrix

| Go state | Visible iOS route/target | Evidence that advances |
| --- | --- | --- |
| `elicit_signal` | Library `+` with `Tap + to capture your first note.` | successful `noteCreated` |
| `product_curator_intro` | Flow first card with `Swipe this card to continue.` | current card becomes visible |
| `product_explore_card` | same first-card callout and card/favorite target | card dismissed or saved |
| `product_spark_intro` | Flow top-right Spark callout | Spark activity starts |
| `product_spark_results` | Spark result, or Flow `Tap Spark to return to your results.` after relaunch | results become visible |
| `product_save_material` | Spark Favorite callout, or the same Flow re-entry callout after relaunch | result favorited |
| `product_merge_intro` | Library first note menu with `Open a note's menu to start Merge.`, then Merge selection/action | Merge job starts |
| `product_merge_preview` | active Merge artifact, or Library Resume Merge with `Resume Merge to finish your note.` | Merge commits |
| `product_library_intro` | automatic return to visible Library | Library becomes visible |
| `build_ignite` | no acknowledgement screen | CoreFlow calls backend complete |

---

### Task 1: Encode Route And Tip Contracts In CoreFlow

**Files:**
- Modify: `Packages/CoreFlow/Sources/CoreFlow/OnboardingGuideModels.swift`
- Modify: `Packages/CoreFlow/Sources/CoreFlow/ContextualGuideTipStore.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/OnboardingGuideModelsTests.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/ContextualGuideTipStoreTests.swift`

**Interfaces:**
- Produces: `OnboardingGuideNavigationDirective.forState(_:) -> OnboardingGuideNavigationDirective?`.
- Produces: `destination`, `clearsNavigationPath`, and `recordsLibraryViewedOnInitialLoad` behavior.
- Produces tips: `.flowCard`, `.sparkResume`, `.libraryMergeEntry`, and `.mergeResume`.

- [ ] **Step 1: Write failing navigation tests** requiring Flow routing for curator/explore/Spark states, Library routing for Merge/Library states, stack clearing only for `product_merge_intro`, and initial Library evidence only for `product_library_intro`.
- [ ] **Step 2: Run `swift test --filter OnboardingGuideModelsTests`** and verify the missing directive fails compilation.
- [ ] **Step 3: Implement the pure directive** with literal state mappings and no SwiftUI dependency.
- [ ] **Step 4: Write failing contextual-tip tests** for the four new copies, state eligibility, target visibility, actor isolation, and completed/dismissed terminal outcomes.
- [ ] **Step 5: Run `swift test --filter ContextualGuideTipStoreTests`** and verify the new enum cases fail compilation.
- [ ] **Step 6: Implement the minimal cases and mappings**, retaining versioned actor-scoped persistence.
- [ ] **Step 7: Run both focused suites** and keep all existing cases green.

### Task 2: Close First-Note And Flow Handoffs

**Files:**
- Modify: `ArcNote/TabBarView.swift`
- Modify: `ArcNote/ExploreView.swift`
- Modify: `ArcNote/CoreFlow/FlowViews.swift`
- Modify: `ArcNote/CoreFlow/OnboardingGuideLine.swift`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: `OnboardingGuideNavigationDirective` and `.flowCard`/`.sparkResume` tips.
- Produces: state-change routing, current-card evidence replay, and real card/Spark target completion.

- [ ] **Step 1: Change the live Go XCUITest expectation first** so closing the saved first note waits for `screen.flow.content` and `onboarding.tip.flow-card` without tapping `tab.flow`.
- [ ] **Step 2: Add the rounded card halo primitive** that mirrors existing target-halo semantics, honours Reduce Motion, and allows no hit testing.
- [ ] **Step 3: Replace one-time routing with initial-load plus state-transition routing**; apply `destination` every time the authoritative state changes and clear `navigationPath` only when the directive requires it.
- [ ] **Step 4: Re-emit `flowViewed` when `product_curator_intro` arrives while a Flow card is already loaded** so an off-screen preloaded deck cannot strand the session.
- [ ] **Step 5: Render `.flowCard` on curator/explore states**, complete it only on save/dismiss, dismiss it on other actions, and preserve all existing card behavior.
- [ ] **Step 6: Render `.sparkResume` on Flow Spark for resumed results/save states** while keeping `.flowSpark` for the first Spark entry.

### Task 3: Close Spark, Merge, And Library Return Handoffs

**Files:**
- Modify: `ArcNote/TabBarView.swift`
- Modify: `ArcNote/HomeView.swift`
- Modify: `ArcNote/CoreFlow/MergeLifecycleViews.swift`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: `.libraryMergeEntry`, `.mergeResume`, and the navigation directive.
- Produces: guided card-menu entry, restartable Merge, automatic guided Merge dismissal, and delayed `libraryViewed` evidence after Library is actually revealed.

- [ ] **Step 1: Change the live Go XCUITest first** to require automatic Library return after Favorite, the Library Merge-entry callout, and automatic Merge dismissal/completion after commit.
- [ ] **Step 2: Attach `.libraryMergeEntry` only to the first visible Library note menu**; activating that real menu completes the tip and preserves the existing popup route.
- [ ] **Step 3: Attach `.mergeResume` to the existing Resume Merge control** for `product_merge_preview`, preserving persisted Merge recovery.
- [ ] **Step 4: On successful guided Merge commit, dismiss Merge automatically** after recording `.mergeCommitted`; retain the pending Library-return token so a retry can still finish after a transport error.
- [ ] **Step 5: Send `.libraryViewed` only after Library is visibly restored**, then let `OnboardingGuideStore` advance to `build_ignite` and call backend Complete.

### Task 4: Compile, Review, Test, And Visual Simulator Closure

**Files:**
- Modify test code only if a failing verification exposes a reproducible gap.

- [ ] **Step 1: Compile Debug and Production** with `xcodebuild` for the selected iPhone Simulator and require exit code 0.
- [ ] **Step 2: Update the code-review graph and run change/impact/flow analysis**, then request an independent review against this plan; fix every Critical or Important finding before tests.
- [ ] **Step 3: Run CoreFlow and Go onboarding suites**, followed by focused XCUITests including the complete real-Go first loop.
- [ ] **Step 4: If the default email smoke account is unavailable, let the existing local phone fixture login/register fallback provide a fresh authenticated session**; do not bypass auth or write database rows directly.
- [ ] **Step 5: Capture and inspect Simulator screenshots** for Library create, Flow card, Spark, Favorite, Library Merge entry, Merge action/preview, and completed Library at normal type, accessibility type, and Reduce Motion.
- [ ] **Step 6: Re-run the full completion audit**: every matrix row has current evidence, backend status is `completed`, `needs_onboarding` is false, no active session remains, and `git diff --check` is clean.

## Plan Self-Review

- **Spec coverage:** The approved Library route, four existing callouts, missing first-card handoff, relaunch states, Merge entry, Library return, and backend completion all map to explicit tasks.
- **Type consistency:** The directive and new tip identifiers are defined once in CoreFlow and consumed by SwiftUI; server evidence remains in `OnboardingGuideStore`.
- **Scope:** No auth, registration, web frontend, Go API, or unrelated prototype behavior is changed.
- **No placeholders:** Every state, visible target, evidence event, test suite, and completion condition is named.
