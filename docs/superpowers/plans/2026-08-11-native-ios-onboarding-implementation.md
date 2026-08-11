# Native iOS Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the approved private-beta entry and minimal contextual guidance in the real iOS 16+ SwiftUI app.

**Architecture:** Keep the existing Go-backed `OnboardingGuideStore` as the authoritative first-loop state machine and the existing access-code auth contract intact. Add a small CoreFlow-owned, actor-scoped tip-outcome store for visual tips only; it persists each versioned tip as completed or dismissed without skipping or mutating the server onboarding flow. SwiftUI renders those tips only beside their real product target and records target activation before the existing action.

**Tech Stack:** Swift 5.9, SwiftUI, Combine, `CoreFlow`, `UserDefaults`, Keychain, XCTest/XCUITest, Xcode 26 Simulator.

## Approved Product Rules

- The Product Access Code is a standalone private-beta gate before account creation, not a field in the email registration form.
- Apple, Google, and email are valid account-entry methods after that gate. Existing-account sign-in remains available without forcing a code.
- The email path retains `Get Code` for deliverable-address verification and retains `Confirm Password`.
- The existing auth visual system, `NetworkManager` access-pair contract, and Keychain storage remain the implementation base.
- Spark remains the independent top-right control on an Explore card; it is never a primary tab or an ellipsis-menu requirement.
- Contextual tips are exactly one sentence, have no `Got it`, close icon, timer, focus trap, or acknowledgement button, and never move or trap VoiceOver focus.
- Approved tip copy is exactly: `Tap + to capture your first note.`, `Tap Spark to continue from this card.`, `Favorite a result to keep it.`, and `Merge two related notes.`
- A visible tip completes when its real target is activated. A non-target interaction silently dismisses it. Tapping the tip itself is a no-op. Tip outcomes persist per actor, tip id, and version.
- Every tip exposes VoiceOver custom action `Dismiss tip`; Reduce Motion removes the pulse without removing the tip.
- Do not alter Go API contracts or replace the current Spark continuation, email verification, or password-confirmation flows.

---

## File Structure

- Create `Packages/CoreFlow/Sources/CoreFlow/ContextualGuideTipStore.swift`: versioned tip IDs, actor-scoped persistence, eligible-state lookup, and terminal-outcome precedence.
- Create `Packages/CoreFlow/Tests/CoreFlowTests/ContextualGuideTipStoreTests.swift`: unit tests for visibility, persistence isolation, dismissal, and target-completion precedence.
- Modify `ArcNote/CoreFlow/OnboardingGuideLine.swift`: keep only the server-required post-note choice interaction; add native one-sentence tip, target halo, and VoiceOver dismissal primitives.
- Modify `ArcNote/TabBarView.swift`, `ArcNote/HomeView.swift`, `ArcNote/ExploreView.swift`, `ArcNote/CoreFlow/FlowViews.swift`, `ArcNote/CoreFlow/SparkContinuationViews.swift`, and `ArcNote/CoreFlow/MergeLifecycleViews.swift`: inject the single tip store and attach each tip to its actual control.
- Modify `ArcNote/AccessGateView.swift`, `ArcNote/ContentView.swift`, and `ArcNote/SignUpView.swift`: make code entry a pre-auth gate and remove the duplicate field from registration while forwarding Keychain code through existing email/Apple/Google requests.
- Modify `Packages/CoreFlow/Tests/CoreFlowTests/IOSAccessSourceTests.swift` and add focused XCUITest coverage/fixtures in `ArcNoteApp.swift` and `ArcNoteUITests/ArcNoteUITests.swift`.

### Task 1: Testable contextual-tip state

**Files:**
- Create: `Packages/CoreFlow/Sources/CoreFlow/ContextualGuideTipStore.swift`
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/ContextualGuideTipStoreTests.swift`

**Interfaces:**
- `ContextualGuideTipID` exposes the four `v1` tip identifiers, their exact copy, and matching server onboarding states.
- `ContextualGuideTipStore.load(actorID:)`, `isVisible(_:onboardingState:targetIsVisible:)`, `complete(_:onboardingState:targetIsVisible:)`, and `dismiss(_:onboardingState:targetIsVisible:)` own only local visual outcomes and reject interactions outside the matching state/visible target.
- `UserDefaultsContextualGuideTipPersistence` scopes keys by actor ID and the tip's versioned identifier.

- [x] **Step 1: Write failing CoreFlow tests** for all four exact strings, route/state eligibility, target invisibility, actor isolation, reload persistence, and the rule that target completion wins if a simultaneous outside dismissal is recorded first.
- [x] **Step 2: Run the focused test** with `swift test --filter ContextualGuideTipStoreTests` and confirm the type is missing.
- [x] **Step 3: Implement the smallest Codable outcome/persistence/store boundary** without any SwiftUI or network dependency.
- [x] **Step 4: Re-run the focused tests**, then `swift test` for the full CoreFlow package.

### Task 2: Native tip presentation without acknowledgement controls

**Files:**
- Modify: `ArcNote/CoreFlow/OnboardingGuideLine.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/IOSAccessSourceTests.swift`

**Interfaces:**
- `ContextualGuideCallout(tip:store:onboardingState:targetIsVisible:)` emits a compact text-only accessible element with a custom `Dismiss tip` action.
- `ContextualGuideTargetHalo(isVisible:)` is non-interactive, honours Reduce Motion, and never shrinks a target below 44 points.
- `OnboardingGuideLine` remains only for the server-required `deepen_signal` choices, so no server state becomes unreachable.

- [x] **Step 1: Add failing source-contract assertions** that reject `Got it`, a close button, `store.skip`, and the old completion acknowledgement from native tip surfaces, and require the custom accessibility action and approved copy.
- [x] **Step 2: Implement compact visual primitives** using semantic SwiftUI colors/material, two-line maximum copy, no focus takeover, no timer, and a no-op tap on the text surface.
- [x] **Step 3: Limit the legacy server-scene line to `deepen_signal` choices** and keep explicit retry behavior for a transport error.
- [x] **Step 4: Run focused source-contract and CoreFlow tests** before wiring any target.

### Task 3: Wire every real product target

**Files:**
- Modify: `ArcNote/TabBarView.swift`
- Modify: `ArcNote/HomeView.swift`
- Modify: `ArcNote/ExploreView.swift`
- Modify: `ArcNote/CoreFlow/FlowViews.swift`
- Modify: `ArcNote/CoreFlow/SparkContinuationViews.swift`
- Modify: `ArcNote/CoreFlow/MergeLifecycleViews.swift`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- `TabBarView` owns one `ContextualGuideTipStore`, loads it with the verified actor, and passes it down with the existing `OnboardingGuideStore`.
- Each real target invokes eligibility-checked completion before preserving its existing navigation/evidence callback.
- Non-target touch handling invokes eligibility-checked dismissal only while that exact tip is eligible; completion remains the winning terminal outcome.

- [x] **Step 1: Add failing UI/source tests** for: Library plus tip, Explore’s direct `flow.spark.<cardID>` target (not menu/tab), Spark favorite tip, Merge action tip, silent dismissal, and `Dismiss tip` accessibility action.
- [x] **Step 2: Wire the Home plus control** to `libraryCreate`; retain the existing `note.create` identifier and `OnboardingGuideStore.receive(.noteCreated(...))` behavior.
- [x] **Step 3: Wire the top-right Flow Spark button** to `flowSpark`, preserving its direct push to `SparkContinuationView` and retaining no Spark `TabView` route.
- [x] **Step 4: Wire Spark result Favorite and enabled Merge action** to `sparkFavorite` and `mergeAction`, respectively, without changing the existing favorite/merge service sequencing.
- [x] **Step 5: Remove the top-level “First loop complete” acknowledgement** and run focused CoreFlow plus onboarding XCUITest coverage.

### Task 4: Make the private-beta gate precede account entry

**Files:**
- Modify: `ArcNote/AccessGateView.swift`
- Modify: `ArcNote/ContentView.swift`
- Modify: `ArcNote/SignUpView.swift`
- Modify: `ArcNote/ArcNoteApp.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/IOSAccessSourceTests.swift`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- `PrivateBetaEntryView` validates and writes only the pending code to the existing device-only Keychain, then enters the current account-entry surface.
- `ContentView` presents this gate before unauthenticated Apple/Google/email registration and provides an existing-account sign-in escape hatch.
- `SignUpView` reads the Keychain-backed code only for the already-supported atomic `access_code` + `idempotency_key` pair; it renders no access-code field.

- [x] **Step 1: Add failing tests** that require the standalone gate, retain `Get Code` and `Confirm Password`, reject a visible `signup.access-code`, and verify all three account-creation paths use the existing atomic access pair.
- [x] **Step 2: Implement `PrivateBetaEntryView` inside the already-compiled access-gate source file**, using the existing login visual assets and 44-point native controls.
- [x] **Step 3: Route unauthenticated `ContentView` through the private-beta gate**, preserve a direct existing-user sign-in path, and let account entry return to the independent code gate through its existing Back control.
- [x] **Step 4: Remove the SignUp access-code field and state**, update its fixture seeding to Keychain, and preserve email verification, password confirmation, and social login forwarding.
- [x] **Step 5: Run CoreFlow source contracts and the signup/account-entry XCUITest fixture** to prove layout and access-pair behavior.

### Task 5: Build, simulator, and regression closure

**Files:**
- Modify test files only if a failed verification exposes a testable gap.

- [x] **Step 1: Run `swift test` in `Packages/CoreFlow`** and focused onboarding/access source-contract tests.
- [x] **Step 2: Build both schemes**: `xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` and the corresponding `ArcNote Production` build.
- [x] **Step 3: Run the focused native UI tests on the booted iPhone 17 Pro**, including private-beta entry; attempt the canonical live onboarding loop when a valid local Go smoke session is configured.
- [x] **Step 4: Inspect the Simulator at normal and accessibility Dynamic Type**, then with Reduce Motion enabled; confirm compact copy does not cover its target, no horizontal clipping, and direct Spark entry remains discoverable.
- [x] **Step 5: Run `git diff --check`, request review, commit only real iOS/CoreFlow/test/docs files to `main`, and leave unrelated prototype artifacts untouched.**

## Verification Record

- CoreFlow: `swift test` passed 563 tests with zero failures.
- Native builds: both `ArcNote` Debug and `ArcNote Production` simulator builds passed on iPhone 17 Pro.
- Focused XCUITest: five native onboarding/private-beta tests passed, covering target completion, silent outside dismissal, inert callout tap, retained signup methods, and malformed-code rejection.
- Accessibility/visual QA: normal and accessibility Dynamic Type layouts fit; Reduce Motion removes the pulse while retaining the tip.
- Review: the final read-only review reported no remaining Critical or Important findings after eligibility guards and missing non-target paths were fixed.
- Live Go loop: attempted, but the default local smoke login returned HTTP 401 before app launch. No backend account or database state was mutated to bypass that environment precondition.
- Scope: `prototypes/onboarding-html-prototype/IMPLEMENTATION_PLAN.md` remains unrelated and untracked; it is intentionally excluded from the commit.

## Plan Self-Review

- **Coverage:** The plan maps all approved private-beta, auth, Spark, contextual-tip, persistence, accessibility, and test requirements to a concrete task.
- **Boundary safety:** Go access claim remains authenticated and no backend route changes are proposed. The pre-auth screen stores a code for the already-supported auth request pair; it does not falsely claim access.
- **State safety:** Server onboarding evidence remains owned by `OnboardingGuideStore`; visual dismissal cannot skip or corrupt its canonical flow.
- **Scope:** Existing registration layout and Spark continuation remain intact. The prior HTML prototype is not touched or used as runtime code.
