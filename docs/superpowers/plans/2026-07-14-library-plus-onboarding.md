# Library Plus Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Make Library's existing circular + the only iOS note-creation entry, remove Quick Capture/Record completely, and make Go v1 onboarding begin with Library note creation while safely completing legacy sessions.

**Architecture:** Go remains the canonical owner of onboarding transitions and normalizes the removed persisted terminal state. CoreFlow exposes note-oriented evidence and ordinary retry persistence only. The iOS shell removes all Quick Capture state, routes the opening guide to Library, forwards successful NewNoteView creation, and gives the existing + a restrained guided-state halo.

**Tech Stack:** Swift 5.9, SwiftUI, Combine, XCTest, XCUITest, Go, testify.

## Global Constraints

- iOS worktree: /tmp/chorai-invitations-credits-ios-20260714 on codex/ios-invitations-credits.
- Go worktree: /tmp/chorai-go-mysql-port-20260714/chorai-go on codex/fix-local-mysql-port.
- Do not modify /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend; it contains user work.
- Do not change chorai_web_frontend; it is reference-only.
- Keep NewNoteView and the Library + destination unchanged.
- Do not add another lightweight editor, sheet, draft surface, or shortcut.
- Preserve Go v1 persisted state strings needed to read legacy sessions; do not expose Quick Capture UI or copy.
- Do not stage ../Chorai_Agent/agents/__pycache__/__init__.cpython-314.pyc.
- Visual thesis: preserve the dark glass workspace and make the existing Library + the only quiet accent.
- Content plan: one Chora guide line, the existing Library workspace, and one emphasized creation action.
- Interaction thesis: route into Library, apply a static non-blocking halo to +, then use the existing push transition into NewNoteView.

---

### Task 1: Make Go v1 Start in Library and Skip Quick Capture

**Files:**
- Modify: /tmp/chorai-go-mysql-port-20260714/chorai-go/internal/ontology/services/onboarding_service_test.go
- Modify: /tmp/chorai-go-mysql-port-20260714/chorai-go/internal/ontology/services/onboarding_service.go

**Interfaces:**
- Consumes: persisted v1 states elicit_signal, deepen_signal, and product_quick_capture_intro.
- Produces: a v1 Library-create scene, direct elicit_signal to product_curator_intro, direct product_library_intro to build_ignite, and effectiveOnboardingState.

- [ ] **Step 1: Write failing Go contract tests**

Update TestOnboardingServiceStartKeepsExplicitLegacyFlowOnLegacyOpening to require:

~~~go
assert.Equal(t, domainmodels.OnboardingStateElicitSignal, got.State)
assert.Equal(t, "guide_overlay", got.Scene.Presentation)
assert.Equal(t, "home", got.Scene.NextRoute)
assert.Equal(t, "library.create_note", got.Scene.TargetAnchor)
assert.True(t, got.Scene.Spotlight)
assert.Empty(t, got.Scene.Choices)
~~~

Add:

~~~go
func TestOnboardingServiceLegacyV1UsesLibraryNoteThenSkipsQuickCapture(t *testing.T) {
    repo := newOnboardingTestRepo()
    svc := NewOnboardingService(repo)
    started, err := svc.Start(context.Background(), "act_ios", dto.StartOnboardingSessionRequest{FlowVersion: 1})
    require.NoError(t, err)

    curator, err := svc.Respond(context.Background(), "act_ios", started.SessionID, dto.OnboardingRespondRequest{
        InputType: "text",
        Text:      "My first Library note",
    })
    require.NoError(t, err)
    assert.Equal(t, domainmodels.OnboardingStateProductCuratorIntro, curator.State)

    repo.sessions[started.SessionID].CurrentState = domainmodels.OnboardingStateProductLibraryIntro
    finished, err := svc.Respond(context.Background(), "act_ios", started.SessionID, dto.OnboardingRespondRequest{
        InputType: "choice",
        ChoiceID:  "activation:library.viewed",
    })
    require.NoError(t, err)
    assert.Equal(t, domainmodels.OnboardingStateBuildIgnite, finished.State)
}

func TestOnboardingServiceLegacyQuickCaptureStateCompletesWithoutClientSupport(t *testing.T) {
    repo := newOnboardingTestRepo()
    svc := NewOnboardingService(repo)
    started, err := svc.Start(context.Background(), "act_ios", dto.StartOnboardingSessionRequest{FlowVersion: 1})
    require.NoError(t, err)
    repo.sessions[started.SessionID].CurrentState = domainmodels.OnboardingStateProductQuickCaptureIntro

    current, err := svc.GetCurrent(context.Background(), "act_ios")
    require.NoError(t, err)
    assert.Equal(t, domainmodels.OnboardingStateBuildIgnite, current.State)

    completed, err := svc.Complete(context.Background(), "act_ios", started.SessionID)
    require.NoError(t, err)
    assert.Equal(t, domainmodels.OnboardingSessionStatusCompleted, completed.Status)
}
~~~

- [ ] **Step 2: Run the tests and verify RED**

    go test ./internal/ontology/services -run 'TestOnboardingService(StartKeepsExplicitLegacyFlowOnLegacyOpening|LegacyV1UsesLibraryNoteThenSkipsQuickCapture|LegacyQuickCaptureStateCompletesWithoutClientSupport)$'

Expected: old scene/transition assertions fail and legacy completion is rejected.

- [ ] **Step 3: Implement the transitions**

Use these v1 transitions:

~~~go
case domainmodels.OnboardingStateElicitSignal:
    return domainmodels.OnboardingStateProductCuratorIntro
case domainmodels.OnboardingStateProductLibraryIntro:
    return domainmodels.OnboardingStateBuildIgnite
case domainmodels.OnboardingStateProductQuickCaptureIntro:
    return domainmodels.OnboardingStateBuildIgnite
~~~

Add and use this in toResponse and Complete:

~~~go
func effectiveOnboardingState(session *domainmodels.OnboardingSession) string {
    if session.FlowVersion == 1 &&
        session.CurrentState == domainmodels.OnboardingStateProductQuickCaptureIntro {
        return domainmodels.OnboardingStateBuildIgnite
    }
    return session.CurrentState
}
~~~

Build elicit_signal as:

~~~go
return dto.OnboardingSceneDTO{
    Speaker:      "chora",
    Text:         "Library is where your own material begins. Tap + to create your first note.",
    InputMode:    "text",
    CanSkip:      true,
    NextRoute:    "home",
    Presentation: "guide_overlay",
    TargetAnchor: "library.create_note",
    Placement:    "top",
    Spotlight:    true,
    ChoraMode:    "guide",
    Meta:         activationMeta("library.note_created"),
}
~~~

Return the build_ignite scene for both ProductQuickCaptureIntro and BuildIgnite, so legacy clients never receive Quick Capture copy.

- [ ] **Step 4: Run Go tests and verify GREEN**

    go test ./internal/ontology/services

Expected: package reports ok.

- [ ] **Step 5: Format and commit**

    gofmt -w internal/ontology/services/onboarding_service.go internal/ontology/services/onboarding_service_test.go
    git add internal/ontology/services/onboarding_service.go internal/ontology/services/onboarding_service_test.go
    git commit -m "fix(onboarding): start iOS flow from Library"

---

### Task 2: Replace Record Evidence with Library Note Evidence

**Files:**
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/OnboardingGuideStoreTests.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/MockOnboardingGuideService.swift
- Modify: Packages/CoreFlow/Sources/CoreFlow/OnboardingGuideModels.swift
- Modify: Packages/CoreFlow/Sources/CoreFlow/OnboardingGuideStore.swift
- Modify: Packages/CoreFlow/Sources/CoreFlow/OnboardingGuidePersistence.swift

**Interfaces:**
- Consumes: NewNoteView callback values (cardID: String, content: String).
- Produces: OnboardingGuideEvidence.noteCreated(cardID:content:) and OnboardingGuideStore.shouldGuideLibraryCreation.

- [ ] **Step 1: Write the failing note-evidence test**

Require shouldGuideLibraryCreation and visible guide at elicit_signal, then add:

~~~swift
@MainActor
func testLibraryNoteSuccessAdvancesElicitWithExactCreatedContent() async {
    let service = MockOnboardingGuideService()
    service.statusResults = [.success(status(needs: true))]
    service.startResults = [.success(session(state: "elicit_signal"))]
    service.respondResults = [.success(session(state: "product_curator_intro"))]
    let persistence = InMemoryOnboardingGuidePersistence()
    let store = makeStore(service: service, persistence: persistence)
    store.load(actorID: "act_1")
    await settle(3)

    let evidence = OnboardingGuideEvidence.noteCreated(
        cardID: "ast_note",
        content: "Keep this Library note"
    )
    store.receive(evidence)
    await settle(3)

    XCTAssertEqual(service.responses.map(\.input), [.text("Keep this Library note")])
    XCTAssertEqual(store.session?.state, "product_curator_intro")
    XCTAssertTrue(
        persistence.pendingEvidence(actorID: "act_1", sessionID: "onb_1").isEmpty
    )
}
~~~

Change the final-loop stub so product_library_intro responds with build_ignite and no activation:record.created response is expected.

- [ ] **Step 2: Run the test and verify RED**

    swift test --package-path Packages/CoreFlow --filter OnboardingGuideStoreTests

Expected: compile failure for missing noteCreated and shouldGuideLibraryCreation.

- [ ] **Step 3: Implement note evidence and ordinary persistence**

Replace the evidence case with:

~~~swift
case noteCreated(cardID: String, content: String)
~~~

Expose:

~~~swift
public var shouldGuideLibraryCreation: Bool {
    phase == .active && session?.state == State.elicitSignal
}
~~~

Keep guideScene visible at elicit_signal. Match noteCreated only to elicit_signal and encode it as text(content). Remove quickCaptureIntro, recorded evidence replay, recordedCardEvidence, saveRecordedCardEvidence, and the UserDefaults .record key. Reduce the persistence protocol to pendingEvidence, savePendingEvidence, and clear. Update in-memory persistence and all affected tests.

- [ ] **Step 4: Run onboarding tests and verify GREEN**

    swift test --package-path Packages/CoreFlow --filter 'OnboardingGuide(Store|Models)Tests'

Expected: selected suites pass with zero failures.

- [ ] **Step 5: Commit**

    git add Packages/CoreFlow/Sources/CoreFlow/OnboardingGuideModels.swift Packages/CoreFlow/Sources/CoreFlow/OnboardingGuideStore.swift Packages/CoreFlow/Sources/CoreFlow/OnboardingGuidePersistence.swift Packages/CoreFlow/Tests/CoreFlowTests/OnboardingGuideStoreTests.swift Packages/CoreFlow/Tests/CoreFlowTests/MockOnboardingGuideService.swift
    git commit -m "refactor(onboarding): use Library note evidence"

---

### Task 3: Delete the Quick Capture Product Path

**Files:**
- Create: Packages/CoreFlow/Tests/CoreFlowTests/IOSRecordRemovalContractTests.swift
- Delete: Packages/CoreFlow/Sources/CoreFlow/CaptureDraftStore.swift
- Delete: Packages/CoreFlow/Sources/CoreFlow/QuickCaptureStore.swift
- Delete: Packages/CoreFlow/Tests/CoreFlowTests/QuickCaptureStoreTests.swift
- Modify: Packages/CoreFlow/Sources/CoreFlow/CoreFlowModels.swift
- Modify: Packages/CoreFlow/Sources/CoreFlow/CoreFlowService.swift
- Modify: Packages/CoreFlow/Sources/CoreFlow/CoreFlowCoordinator.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/CoreFlowCoordinatorTests.swift
- Modify: Packages/CoreFlow/Tests/CoreFlowTests/MockCoreFlowService.swift
- Modify: ArcNote/CoreFlow/NetworkCoreFlowService.swift
- Modify: ArcNote/CoreFlow/CoreShellViews.swift
- Modify: ArcNote/TabBarView.swift

**Interfaces:**
- Consumes: three-tab CoreTab and Merge completion.
- Produces: CoreTabBar(selectedTab:), Merge-only refresh state, and no Record/Quick Capture API.

- [ ] **Step 1: Add a failing source-removal contract test**

Create IOSRecordRemovalContractTests with this structure, adding the remaining source reads with the same helper:

~~~swift
import Foundation
import XCTest

final class IOSRecordRemovalContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testRecordProductPathIsRemoved() throws {
        let shell = try source("ArcNote/CoreFlow/CoreShellViews.swift")
        let tabBar = try source("ArcNote/TabBarView.swift")
        XCTAssertFalse(shell.contains("QuickCaptureSheet"))
        XCTAssertFalse(shell.contains("record.open"))
        XCTAssertFalse(tabBar.contains("captureStore"))
        XCTAssertFalse(tabBar.contains("isCapturePresented"))
        XCTAssertFalse(tabBar.contains("recordAcknowledgementID"))
        XCTAssertFalse(try source("Packages/CoreFlow/Sources/CoreFlow/CoreFlowService.swift").contains("createPrivateCard"))
        XCTAssertFalse(try source("Packages/CoreFlow/Sources/CoreFlow/CoreFlowModels.swift").contains("CreatedCard"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent("Packages/CoreFlow/Sources/CoreFlow/QuickCaptureStore.swift").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent("Packages/CoreFlow/Sources/CoreFlow/CaptureDraftStore.swift").path))
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }
}
~~~

- [ ] **Step 2: Run the test and verify RED**

    swift test --package-path Packages/CoreFlow --filter IOSRecordRemovalContractTests

Expected: assertions fail against the current Quick Capture path.

- [ ] **Step 3: Remove Quick Capture and narrow the coordinator**

Delete both Quick Capture source files and their tests. Remove CreatedCard, CapturePhase, createPrivateCard, network adapter implementation, and mock fields.

Replace coordinator behavior with:

~~~swift
@MainActor
public final class CoreFlowCoordinator: ObservableObject {
    @Published public var selectedTab: CoreTab = .flow
    @Published public private(set) var libraryRefreshID = UUID()
    @Published public private(set) var lastMergedCardID: String?

    public init() {}

    public func mergeCompleted(cardID: String) {
        lastMergedCardID = cardID
        libraryRefreshID = UUID()
    }
}
~~~

Make CoreTabBar accept only selectedTab and render only Flow/Library/Chat. Remove QuickCaptureSheet. Remove capture state, sheet, auto-presentation, acknowledgement, and capture-dependent Flow logic from TabBarView. Expose debug-only note.created-card-id from the Library callback and merge.committed-card-id from lastMergedCardID.

- [ ] **Step 4: Verify package and app build**

    swift test --package-path Packages/CoreFlow
    xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO

Expected: 0 test failures and BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

    git add -A Packages/CoreFlow ArcNote/CoreFlow/NetworkCoreFlowService.swift ArcNote/CoreFlow/CoreShellViews.swift ArcNote/TabBarView.swift
    git commit -m "refactor(record): remove Quick Capture path"

---

### Task 4: Route Onboarding Through Library Plus

**Files:**
- Modify: ArcNoteUITests/ArcNoteUITests.swift
- Modify: ArcNote/TabBarView.swift
- Modify: ArcNote/HomeView.swift

**Interfaces:**
- Consumes: shouldGuideLibraryCreation and noteCreated.
- Produces: Library-first routing, note forwarding, Flow continuation, and guided-state styling on note.create.

- [ ] **Step 1: Rewrite UI journeys before production changes**

Replace the Record onboarding journey with:

~~~swift
waitForOnboardingAnchor("onboarding.state", value: "elicit_signal")
waitFor("screen.home.content", timeout: 30)
waitFor("onboarding.guide", timeout: 15)
XCTAssertFalse(exists("record.open", timeout: 2))
tap("note.create")
waitFor("screen.card-editor", timeout: 20)
let editor = waitFor("cardEditorContent", timeout: 20)
editor.tap()
app.typeText(signal)
tap("cardEditorBackButton")
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
tap("cardEditorBackButton")
waitForOnboardingAnchor("onboarding.state", value: "product_explore_card", timeout: 30)
~~~

Replace draft-recovery and global-Record tests with testRecordIsAbsentAndLibraryPlusIsTheOnlyCreateEntry: assert no record.open on Flow, Library, or Chat; tap Library note.create; wait for screen.card-editor. Update the full loop to use note.created-card-id and merge.committed-card-id. Delete openRecordWithEmptyDraft and confirmRecordDiscard.

Add testCancellingOnboardingNoteKeepsLibraryStep: restart Go v1, launch onboarding, tap note.create, immediately tap cardEditorBackButton with empty content, then require onboarding.state remains elicit_signal and note.create is visible again.

- [ ] **Step 2: Run the focused UI journey and verify RED**

Use the currently available booted iPhone 17 simulator:

    xcodebuild test -project ArcNote.xcodeproj -scheme ArcNote -destination 'platform=iOS Simulator,id=0AC2C08A-F6D5-4236-8609-429D64B4EAA3' -only-testing:ArcNoteUITests/ArcNoteUITests/testCanonicalOnboardingLibraryNoteAndFlowResumeGoV1

Expected: old Record presentation or missing Library-first route causes failure.

- [ ] **Step 3: Implement routing, forwarding, and emphasis**

Route:

~~~swift
switch state {
case "elicit_signal":
    coordinator.selectedTab = .library
case "product_curator_intro", "product_explore_card":
    coordinator.selectedTab = .flow
case "product_merge_intro", "product_library_intro":
    coordinator.selectedTab = .library
default:
    return
}
~~~

Forward successful creation:

~~~swift
private func handleNoteCreated(cardID: String, content: String) {
    #if DEBUG
    lastCreatedNoteID = cardID
    #endif
    onboardingStore.receive(.noteCreated(cardID: cardID, content: content))
}
~~~

Pass the optional onboarding store into NotesListView. Render the existing NavigationLink through an observed guided-link subview. During shouldGuideLibraryCreation, overlay:

~~~swift
Circle()
    .stroke(ZenVisualTokens.accent.opacity(0.9), lineWidth: 2)
    .frame(width: 66, height: 66)
    .shadow(color: ZenVisualTokens.accent.opacity(0.35), radius: 10)
    .allowsHitTesting(false)
~~~

Keep accessibilityIdentifier("note.create") and add the guided hint "Create your first Library note". Remove product_quick_capture_intro from Home guide states.

- [ ] **Step 4: Verify unit tests, build, and UI journeys**

    swift test --package-path Packages/CoreFlow --filter OnboardingGuideStoreTests
    xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
    xcodebuild test -project ArcNote.xcodeproj -scheme ArcNote -destination 'platform=iOS Simulator,id=0AC2C08A-F6D5-4236-8609-429D64B4EAA3' -only-testing:ArcNoteUITests/ArcNoteUITests/testCanonicalOnboardingLibraryNoteAndFlowResumeGoV1 -only-testing:ArcNoteUITests/ArcNoteUITests/testCancellingOnboardingNoteKeepsLibraryStep -only-testing:ArcNoteUITests/ArcNoteUITests/testRecordIsAbsentAndLibraryPlusIsTheOnlyCreateEntry

Expected: package tests pass, app builds, and all three UI journeys pass.

- [ ] **Step 5: Commit**

    git add ArcNote/TabBarView.swift ArcNote/HomeView.swift ArcNoteUITests/ArcNoteUITests.swift
    git commit -m "feat(onboarding): guide creation from Library plus"

---

### Task 5: Cross-Repository Completion Audit

**Files:**
- Verify: docs/superpowers/specs/2026-07-14-library-plus-onboarding-design.md
- Verify: every file changed in Tasks 1-4.

- [ ] **Step 1: Search for forbidden iOS remnants**

    rg -n 'QuickCapture|CaptureDraftStore|record\.open|record\.sheet|recordCreated|shouldPresentRecord|activation:record\.created' ArcNote Packages/CoreFlow ArcNoteUITests --glob '*.swift' --glob '!**/.build/**'

Expected: no matches.

- [ ] **Step 2: Run fresh automated verification**

In iOS:

    swift test --package-path Packages/CoreFlow
    xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO

In Go:

    go test ./internal/ontology/services

Expected: 0 Swift failures, BUILD SUCCEEDED, and Go package ok.

- [ ] **Step 3: Verify local services and focused real-API UI journeys**

    curl -fsS http://127.0.0.1:8080/health
    curl -fsS http://127.0.0.1:5001/health

Run both focused UI journeys against CHORAI_API_BASE_URL=http://127.0.0.1:8080 and capture the Library guide/editor handoff.

- [ ] **Step 4: Audit diffs and status**

In each worktree:

    git status --short
    git diff --check
    git log -5 --oneline

Expected: no unstaged feature changes. The only unrelated Go status entry may be the tracked Python bytecode file from the running stack.

- [ ] **Step 5: Map specification requirements to evidence**

Confirm from source plus fresh output:

    Global Record capsule absent on Flow, Library, and Chat.
    Library note.create remains and opens NewNoteView.
    Quick Capture source, drafts, service method, and tests are absent.
    Onboarding starts in Library and successful note creation advances to Flow.
    New v1 path skips deepen_signal and product_quick_capture_intro.
    Legacy product_quick_capture_intro sessions complete through Go normalization.
    No web frontend file changed.

Only after every line has direct evidence, mark the active goal complete.
