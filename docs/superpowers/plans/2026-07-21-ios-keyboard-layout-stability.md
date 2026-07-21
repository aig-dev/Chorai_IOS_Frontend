# iOS Keyboard Layout Stability Implementation Plan

> **Execution:** The user explicitly approved autonomous implementation in the
> current task. Follow red-green verification at each behavior boundary and do not
> pause for a solution choice.

**Goal:** Keep every iOS search, form, editor, composer, and input overlay usable
without pushing top chrome outside the viewport when the software keyboard opens.

**Architecture:** Extend the existing presentation-only adaptive layout layer with
keyboard visibility/frame state and a UIKit screen-coordinate probe that cancels
only the measured hosting-root displacement. Apply role-specific policies: stable
top search, scrolling forms, native bottom-composer avoidance, and
keyboard-adjusted overlay geometry. Preserve the native card editor's
already-tested keyboard behavior.

**Tech Stack:** Swift 5, SwiftUI, Combine, UIKit keyboard notifications, iOS 16+,
XCTest/XCUITest, Xcode 26.3.

## Global Constraints

- Work only in `Chorai_IOS_Frontend`.
- Preserve iOS 16 support, existing navigation/API behavior, accessibility IDs,
  Dynamic Type, and 44-point controls.
- Backgrounds may remain full bleed; interactive content must respect container
  and keyboard geometry.
- Do not add dependencies, global device-size reads, hard-coded keyboard heights,
  or duplicate focus state.
- Use test-first changes and focused verification before broad builds.

---

### Task 1: Lock the failing keyboard contracts

**Files:**

- Modify: `ArcNoteUITests/ArcNoteUITests.swift`
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/KeyboardLayoutSourceContractTests.swift`

**Produces:** Executable failures for the supplied Library regression and source
guards for role-specific keyboard layout.

- [x] Extend `testLibrarySearchTransformsHeaderAndWaitsForKeyboardSubmit` to save
  the normal header's top coordinate, wait for the keyboard, and assert the active
  Back/search/filter row remains hittable and at the same top coordinate.
- [x] Add a deterministic sign-in keyboard test that focuses the password field,
  verifies the navigation header stays inside the app frame, scrolls if needed,
  and confirms `signin.submit` is reachable above or by scrolling around the
  keyboard.
- [x] Add source contracts requiring a keyboard observer in
  `AdaptiveLayout.swift`, conditional `CoreTabBar` presentation, interactive
  dismissal on ordinary scrolling forms, and no raw `keyboardFrame.height`
  positioning in comment/link overlays.
- [x] Run the baseline failures before implementation and the same commands after
  implementation:

  ```bash
  cd /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend
  xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -derivedDataPath /tmp/chorai-keyboard-audit \
    -only-testing:ArcNoteUITests/ArcNoteUITests/testLibrarySearchTransformsHeaderAndWaitsForKeyboardSubmit
  swift test --package-path Packages/CoreFlow --filter KeyboardLayoutSourceContractTests
  ```

  Expected before implementation: the Library field is not hittable and the
  source contract reports missing policy markers.

### Task 2: Add shared keyboard presentation state and shell behavior

**Files:**

- Modify: `ArcNote/AdaptiveLayout.swift`
- Modify: `ArcNote/TabBarView.swift`
- Test: `Packages/CoreFlow/Tests/CoreFlowTests/KeyboardLayoutSourceContractTests.swift`

**Produces:** `KeyboardLayoutObserver` publishing the final screen-space keyboard
frame, window visibility, and container overlap, plus `KeyboardStableViewport`
measuring the hosting root's actual screen-space origin.

- [x] Implement notification handling for `keyboardWillChangeFrame` and
  `keyboardWillHide`, delivered on the main thread; intersect the frame with a
  supplied global container frame and treat a non-intersecting frame as zero
  overlap.
- [x] Add a UIKit viewport probe that measures
  `convert(bounds, to: nil).minY`, records the resting top, and cancels only the
  measured upward displacement without `UIScreen` or per-device constants.
- [x] Own one observer in `TabBarView`; render the bottom `CoreTabBar` safe-area
  inset only when the software keyboard is not docked/visible.
- [x] Avoid animating the app's entire content tree when visibility changes; only
  transition the tab bar surface.
- [x] Run the source contract and focused main-tab keyboard regressions.

### Task 3: Stabilize top-search screens

**Files:**

- Modify: `ArcNote/HomeView.swift`
- Modify: `ArcNote/ExploreView.swift`
- Modify: `ArcNote/ChatView.swift`
- Test: `ArcNoteUITests/ArcNoteUITests.swift`

**Produces:** Fixed top chrome with a flexible, dismissible result region.

- [x] Wrap Library search in `KeyboardStableViewport`, retain the full-height
  scroll result surface, and keep explicit focus release on submit and exit.
- [x] Add explicit search `FocusState` to Flow and Chat, request focus after the
  search transition, release it on submit/back, and make result/list scrolling
  dismiss interactively.
- [x] Keep roots top-aligned and cancel their measured hosting-root translation so
  a short keyboard viewport never moves the header through the status region.
- [x] Re-run the Library red test until green on the deterministic Library route.
  Flow and Chat receive the same source-enforced policy; they do not expose
  equivalent offline fixtures.

### Task 4: Convert fixed form/edit stacks to keyboard-scroll layouts

**Files:**

- Modify: `ArcNote/SignInView.swift`
- Modify: `ArcNote/SignUpView.swift`
- Modify: `ArcNote/CoreFlow/ContentReportView.swift`
- Modify: `ArcNote/NewInsightView.swift`
- Modify: `ArcNote/CoreFlow/MergeLifecycleViews.swift`
- Modify: `ArcNote/MergeView.swift`
- Modify: `ArcNote/ChoraProfileView.swift`

**Produces:** Fixed navigation chrome and scrollable editing bodies whose focused
control and primary action can enter the visible keyboard-adjusted region.

- [x] Put the Sign-in form/actions in a vertical `ScrollView` with a minimum
  viewport-height content frame and interactive dismissal; do not scale or hide
  controls to make them fit.
- [x] Add interactive dismissal to the existing Sign-up and Chora scroll roots.
- [x] Make Content Report keep its header fixed and scroll the reason, context,
  errors, and submit button as one form body.
- [x] Make the legacy Insight editor a bounded modal with a scrollable body rather
  than a fixed 230-point editor plus fixed tags/actions in a centered stack.
- [x] Add interactive dismissal and stable viewport handling to current and legacy
  Merge search/title scroll regions.
- [x] Run the sign-in regression on both target devices, the complete CoreFlow
  suite, and source contracts.

### Task 5: Remove double keyboard handling from custom overlays

**Files:**

- Modify: `ArcNote/CommentPopupView.swift`
- Modify: `ArcNote/LinkPopupView.swift`
- Modify: `ArcNote/ChatDetailView.swift`
- Test: `ArcNoteUITests/ArcNoteUITests.swift`

**Produces:** Comment/link/card-selection surfaces laid out once against live
keyboard-adjusted geometry.

- [x] Remove CommentPopup's raw `keyboardFrame.height - 20` state and position the
  bottom sheet inside keyboard-adjusted geometry; its list owns flexible height
  and its composer remains the final fixed row.
- [x] Remove LinkPopup's focus-then-`endEditing(true)` contradiction and unrelated
  recursive UIKit mutation. Request focus on the next main run-loop turn, respect
  keyboard-adjusted geometry, and keep search/results/cancel inside the window.
- [x] Add interactive dismissal to card picker/chat scrolling while retaining
  native bottom avoidance for `chat.message.input`.
- [x] Add source contracts that reject manual keyboard-height, recursive inset,
  and focus-then-dismiss hacks. Link/comment depend on live-data routes, so their
  deterministic verification is source contract plus both-scheme compilation.

### Task 6: Full verification and visual QA

**Files:** All modified files.

- [x] Run the full 507-test CoreFlow suite, source contracts, and existing
  card-editor keyboard UI tests.
- [x] Run Library and Sign-in keyboard regressions on iPhone 17 Pro and
  `Chorai iPhone SE 3 QA`.
- [x] Build both schemes:

  ```bash
  xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote \
    -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
  xcodebuild build -project ArcNote.xcodeproj -scheme 'ArcNote Production' \
    -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
  ```

- [x] Capture and visually inspect the deterministic Library search and Sign-in
  keyboard states. Re-run the existing card-editor keyboard suite; keep
  live-backend Link, Comment, and Merge routes covered by policy contracts and
  compilation.
- [x] Run `git diff --check`, inspect the complete diff for unrelated changes, and
  report environment-limited live-backend flows explicitly.

## Verification Result

- CoreFlow: 507 tests passed, 0 failures.
- UI: Library and Sign-in keyboard regressions passed on iPhone 17 Pro and iPhone
  SE 3; four existing card-editor keyboard regressions passed on iPhone 17 Pro.
- Builds: `ArcNote` and `ArcNote Production` simulator builds passed.
- Visual QA: the Library search row retained its pre-keyboard top coordinate and
  remained below the status/Dynamic Island region; Sign-in chrome stayed fixed and
  its primary action remained reachable.
- Live-backend-only Link, Comment, and Merge presentations were not replayed as
  deterministic UI fixtures; they are covered by source contracts, full package
  tests, and both application builds.
