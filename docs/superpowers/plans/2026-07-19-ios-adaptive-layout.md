# iPhone Adaptive Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Make every iPhone-native Chorai screen and overlay follow one safe, aesthetically inset responsive layout system across compact, standard, and large phones.

**Architecture:** Add a presentation-only AdaptiveLayout layer in the ArcNote target. It calculates metrics from live container geometry, provides semantic content-gutter and glass-surface helpers, and is injected at the app root. Migrate root screen families to those helpers and replace every UIScreen.main.bounds layout dependency with geometry from the actual parent container.

**Tech Stack:** Swift 5, SwiftUI, iOS 16, XCTest/XCUITest, Swift Package Manager source-contract tests, Xcode project file references.

## Global Constraints

- Support iPhone only; TARGETED_DEVICE_FAMILY = 1 and the deployment target remains iOS 16.
- Decorative backgrounds may be full-bleed; interactive content uses the shared 16/20/24 pt horizontal gutter.
- Production layout reads live GeometryReader or AdaptiveLayoutMetrics values; no UIScreen.main.bounds remains in ArcNote.
- Preserve API contracts, navigation destinations, Dynamic Type, existing accessibility identifiers, and 44 x 44 pt effective tap targets.
- Keep SwiftUI presentation rules in ArcNote rather than CoreFlow state code.
- Use apply_patch for all source, test, documentation, and project-file changes.

---

## File Structure

| Path | Responsibility |
| --- | --- |
| ArcNote/AdaptiveLayout.swift | Metrics, environment injection, standard content gutter, glass surface, and DEBUG layout fixture. |
| ArcNote/ArcNoteApp.swift | App-wide metric injection and --ui-test-adaptive-layout route. |
| ArcNote.xcodeproj/project.pbxproj | Registers AdaptiveLayout.swift in the ArcNote group and Sources phase. |
| Packages/CoreFlow/Tests/CoreFlowTests/AdaptiveLayoutSourceContractTests.swift | Requires the layout layer, selected screen migrations, and removal of global screen reads. |
| ArcNoteUITests/ArcNoteUITests.swift | Asserts inset frames and captures deterministic visual regression images. |
| Main pages and overlays in Tasks 3–5 | Consume the single gutter or local parent geometry. |

## Shared Interfaces

~~~swift
struct AdaptiveLayoutMetrics {
    static let compactMaximumWidth: CGFloat = 375
    static let standardMaximumWidth: CGFloat = 402
    static let compactGutter: CGFloat = 16
    static let standardGutter: CGFloat = 20
    static let wideGutter: CGFloat = 24
    static let surfaceCornerRadius: CGFloat = 24
    static let minimumHitTarget: CGFloat = 44

    let size: CGSize
    let safeAreaInsets: EdgeInsets
    var horizontalGutter: CGFloat { get }
    var contentWidth: CGFloat { get }
    var drawerWidth: CGFloat { get }
}

struct AdaptiveLayoutReader<Content: View>: View {
    init(@ViewBuilder content: @escaping (AdaptiveLayoutMetrics) -> Content)
}

struct AdaptiveScreen<Background: View, Content: View>: View {
    init(
        @ViewBuilder background: () -> Background,
        @ViewBuilder content: @escaping (AdaptiveLayoutMetrics) -> Content
    )
}

struct AdaptiveSurface<Content: View>: View {
    init(contentInsets: CGFloat = 20, @ViewBuilder content: () -> Content)
}

extension View {
    func adaptiveContentGutter() -> some View
}
~~~

## Device Validation Matrix

| Destination | Layout risk |
| --- | --- |
| iPhone SE (3rd generation) | 375 pt compact gutter and short vertical budget |
| iPhone 16e | 393 pt standard gutter |
| iPhone 17 Pro | Dynamic Island safe top region |
| iPhone 17 Pro Max | wide gutter and large bottom safe area |

### Task 1: Add a Failing Cross-Screen Layout Contract

**Files:**

- Create: Packages/CoreFlow/Tests/CoreFlowTests/AdaptiveLayoutSourceContractTests.swift
- Test: Packages/CoreFlow/Tests/CoreFlowTests/AdaptiveLayoutSourceContractTests.swift

**Consumes:** Existing CoreFlow source-contract convention.

**Produces:** A test that fails until the shared layout source, selected screen migrations, and UIScreen removal all exist.

- [ ] **Step 1: Write the failing source-contract test**

~~~swift
import Foundation
import XCTest

final class AdaptiveLayoutSourceContractTests: XCTestCase {
    private let responsiveRoots = [
        "ArcNote/ContentView.swift",
        "ArcNote/TabBarView.swift",
        "ArcNote/HomeView.swift",
        "ArcNote/ExploreView.swift",
        "ArcNote/ChatView.swift",
        "ArcNote/DetailView.swift",
        "ArcNote/RootView.swift",
        "ArcNote/UserProfileView.swift",
        "ArcNote/MyProfileView.swift",
        "ArcNote/SettingsView.swift",
        "ArcNote/ChoraProfileView.swift",
        "ArcNote/NotificationView.swift",
        "ArcNote/TrashView.swift",
        "ArcNote/PreferencesView.swift",
        "ArcNote/AccountDetailsView.swift",
        "ArcNote/EditProfileView.swift",
        "ArcNote/APIAndPluginsView.swift",
        "ArcNote/InvitationCreditView.swift",
        "ArcNote/FollowListView.swift",
        "ArcNote/BlockedActorsView.swift",
        "ArcNote/ChooseInterestsView.swift",
        "ArcNote/NewInsightView.swift",
        "ArcNote/NewNoteView.swift",
        "ArcNote/SparkView.swift",
        "ArcNote/MergeView.swift"
    ]

    func testAppOwnsSharedAdaptiveLayout() throws {
        let layout = try source(at: "ArcNote/AdaptiveLayout.swift")
        let project = try source(at: "ArcNote.xcodeproj/project.pbxproj")
        XCTAssertTrue(layout.contains("struct AdaptiveLayoutMetrics"))
        XCTAssertTrue(layout.contains("static let compactGutter: CGFloat = 16"))
        XCTAssertTrue(layout.contains("static let standardGutter: CGFloat = 20"))
        XCTAssertTrue(layout.contains("static let wideGutter: CGFloat = 24"))
        XCTAssertTrue(layout.contains("struct AdaptiveLayoutReader<Content: View>"))
        XCTAssertTrue(layout.contains("struct AdaptiveScreen<Background: View, Content: View>"))
        XCTAssertTrue(layout.contains("struct AdaptiveSurface<Content: View>"))
        XCTAssertTrue(project.contains("/* AdaptiveLayout.swift in Sources */"))
    }

    func testEveryResponsiveRootUsesTheSharedGutter() throws {
        for path in responsiveRoots {
            XCTAssertTrue(
                try source(at: path).contains(".adaptiveContentGutter()"),
                "\(path) must use the shared responsive content gutter"
            )
        }
    }

    func testNativeLayoutSourcesDoNotReadGlobalScreenBounds() throws {
        let appDirectory = Self.repositoryRoot.appendingPathComponent("ArcNote")
        let files = FileManager.default.enumerator(
            at: appDirectory,
            includingPropertiesForKeys: nil
        )!
        for case let url as URL in files where url.pathExtension == "swift" {
            let contents = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(
                contents.contains("UIScreen.main.bounds"),
                "\(url.lastPathComponent) must use parent geometry instead"
            )
        }
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
~~~

- [ ] **Step 2: Prove the test is red**

Run:

~~~bash
cd /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend/Packages/CoreFlow
swift test --filter AdaptiveLayoutSourceContractTests
~~~

Expected: FAIL because the adaptive source does not yet exist, root pages do not all consume the shared gutter, and five views still read global screen bounds.

- [ ] **Step 3: Commit the red test**

~~~bash
git add Packages/CoreFlow/Tests/CoreFlowTests/AdaptiveLayoutSourceContractTests.swift
git commit -m "test: define adaptive layout contract"
~~~

### Task 2: Add Shared Live-Container Metrics and a Test Route

**Files:**

- Create: ArcNote/AdaptiveLayout.swift
- Modify: ArcNote/ArcNoteApp.swift:15-175
- Modify: ArcNote.xcodeproj/project.pbxproj:9-129, 217-464, 586-704
- Test: Packages/CoreFlow/Tests/CoreFlowTests/AdaptiveLayoutSourceContractTests.swift

**Consumes:** Task 1 and SwiftUI GeometryReader safe-area values.

**Produces:** A single environment value for app-wide metrics and a deterministic fixture for UI-frame tests.

- [ ] **Step 1: Implement the shared metrics and environment**

~~~swift
import SwiftUI

struct AdaptiveLayoutMetrics {
    static let compactMaximumWidth: CGFloat = 375
    static let standardMaximumWidth: CGFloat = 402
    static let compactGutter: CGFloat = 16
    static let standardGutter: CGFloat = 20
    static let wideGutter: CGFloat = 24
    static let compactSpacing: CGFloat = 12
    static let regularSpacing: CGFloat = 16
    static let surfaceCornerRadius: CGFloat = 24
    static let minimumHitTarget: CGFloat = 44

    let size: CGSize
    let safeAreaInsets: EdgeInsets

    var horizontalGutter: CGFloat {
        switch size.width {
        case ...Self.compactMaximumWidth: Self.compactGutter
        case ...Self.standardMaximumWidth: Self.standardGutter
        default: Self.wideGutter
        }
    }

    var contentWidth: CGFloat {
        max(0, size.width - horizontalGutter * 2)
    }

    var drawerWidth: CGFloat {
        min(max(size.width * 0.78, 280), min(360, size.width - horizontalGutter))
    }
}

private struct AdaptiveLayoutMetricsKey: EnvironmentKey {
    static let defaultValue = AdaptiveLayoutMetrics(
        size: .zero,
        safeAreaInsets: EdgeInsets()
    )
}

extension EnvironmentValues {
    var adaptiveLayoutMetrics: AdaptiveLayoutMetrics {
        get { self[AdaptiveLayoutMetricsKey.self] }
        set { self[AdaptiveLayoutMetricsKey.self] = newValue }
    }
}

struct AdaptiveLayoutReader<Content: View>: View {
    private let content: (AdaptiveLayoutMetrics) -> Content

    init(@ViewBuilder content: @escaping (AdaptiveLayoutMetrics) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = AdaptiveLayoutMetrics(
                size: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets
            )
            content(metrics)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.adaptiveLayoutMetrics, metrics)
        }
    }
}
~~~

- [ ] **Step 2: Implement screen, surface, gutter, and DEBUG fixture**

~~~swift
struct AdaptiveScreen<Background: View, Content: View>: View {
    private let background: Background
    private let content: (AdaptiveLayoutMetrics) -> Content

    init(
        @ViewBuilder background: () -> Background,
        @ViewBuilder content: @escaping (AdaptiveLayoutMetrics) -> Content
    ) {
        self.background = background()
        self.content = content
    }

    var body: some View {
        AdaptiveLayoutReader { metrics in
            ZStack {
                background.ignoresSafeArea()
                content(metrics).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct AdaptiveSurface<Content: View>: View {
    @Environment(\.adaptiveLayoutMetrics) private var metrics
    private let contentInsets: CGFloat
    private let content: Content

    init(contentInsets: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.contentInsets = contentInsets
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentInsets)
            .background {
                RoundedRectangle(
                    cornerRadius: metrics.surfaceCornerRadius,
                    style: .continuous
                )
                .fill(.ultraThinMaterial.opacity(0.72))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: metrics.surfaceCornerRadius,
                        style: .continuous
                    )
                    .stroke(.white.opacity(0.16), lineWidth: 1)
                }
            }
    }
}

private struct AdaptiveContentGutter: ViewModifier {
    @Environment(\.adaptiveLayoutMetrics) private var metrics

    func body(content: Content) -> some View {
        content.padding(.horizontal, metrics.horizontalGutter)
    }
}

extension View {
    func adaptiveContentGutter() -> some View {
        modifier(AdaptiveContentGutter())
    }
}

#if DEBUG
struct AdaptiveLayoutFixtureScreen: View {
    @Environment(\.adaptiveLayoutMetrics) private var metrics

    var body: some View {
        AdaptiveScreen {
            Color(red: 0.05, green: 0.04, blue: 0.09)
        } content: { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.regularSpacing) {
                    Text("Adaptive layout").font(.title.bold())
                    AdaptiveSurface {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Shared inset surface")
                            Text("\(Int(metrics.horizontalGutter)) pt horizontal gutter")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("adaptive-layout.surface")
                }
                .adaptiveContentGutter()
                .padding(.vertical, max(metrics.safeAreaInsets.top, 24))
            }
        }
        .accessibilityIdentifier("adaptive-layout.root")
    }
}
#endif
~~~

- [ ] **Step 3: Inject metrics and expose the fixture route**

Add this DEBUG predicate near current route predicates:

~~~swift
private let isAdaptiveLayoutUITestRoute = ProcessInfo.processInfo.arguments
    .contains("--ui-test-adaptive-layout")
~~~

Wrap the complete existing Group inside WindowGroup:

~~~swift
AdaptiveLayoutReader { _ in
    Group {
        // retain every existing route branch
    }
}
.environmentObject(chatHistoryDependency)
~~~

Add this branch before the normal ContentView branch:

~~~swift
} else if isAdaptiveLayoutUITestRoute {
    AdaptiveLayoutFixtureScreen()
~~~

- [ ] **Step 4: Register the source in the project**

Add one PBXBuildFile, PBXFileReference, ArcNote-group child, and ArcNote Sources entry. Use one unused stable 24-character identifier in all four locations. The entries must include:

~~~text
/* AdaptiveLayout.swift in Sources */
/* AdaptiveLayout.swift */
path = AdaptiveLayout.swift;
~~~

- [ ] **Step 5: Verify and commit**

Run:

~~~bash
cd /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend/Packages/CoreFlow
swift test --filter AdaptiveLayoutSourceContractTests/testAppOwnsSharedAdaptiveLayout
cd /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend
xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -sdk iphonesimulator -configuration Debug build
~~~

Expected: the shared-layer contract and simulator build pass. The migration and UIScreen contract cases remain red until Tasks 3–5.

~~~bash
git add ArcNote/AdaptiveLayout.swift ArcNote/ArcNoteApp.swift ArcNote.xcodeproj/project.pbxproj
git commit -m "feat: add adaptive iPhone layout layer"
~~~

### Task 3: Migrate Primary Screens and Profile Boundaries

**Files:**

- Modify: ArcNote/ContentView.swift, ArcNote/SignInView.swift, ArcNote/SignUpView.swift, ArcNote/ChooseInterestsView.swift
- Modify: ArcNote/TabBarView.swift, ArcNote/HomeView.swift, ArcNote/ExploreView.swift, ArcNote/ChatView.swift, ArcNote/SearchView.swift
- Modify: ArcNote/DetailView.swift, ArcNote/RootView.swift, ArcNote/UserProfileView.swift, ArcNote/MyProfileView.swift
- Modify: ArcNoteUITests/ArcNoteUITests.swift
- Test: Packages/CoreFlow/Tests/CoreFlowTests/AdaptiveLayoutSourceContractTests.swift

**Consumes:** The metrics, surface, and gutter interfaces from Task 2.

**Produces:** App entry, tabs, discovery, detail, and profile pages that share one outer boundary. The profile glass card no longer touches both device edges.

- [ ] **Step 1: Apply the gutter once at each root collection**

Add the environment in every listed root:

~~~swift
@Environment(\.adaptiveLayoutMetrics) private var adaptiveLayout
~~~

Use this outer-content form and retain existing inner row padding:

~~~swift
ScrollView {
    VStack(alignment: .leading, spacing: adaptiveLayout.regularSpacing) {
        // existing rows, navigation, and product actions
    }
    .adaptiveContentGutter()
    .padding(.bottom, 120)
}
~~~

Replace title-bar outer 20 values with:

~~~swift
.padding(.horizontal, adaptiveLayout.horizontalGutter)
.frame(minHeight: AdaptiveLayoutMetrics.minimumHitTarget)
~~~

- [ ] **Step 2: Place both profile cards inside AdaptiveSurface**

In UserProfileView.swift and MyProfileView.swift, preserve avatar overlap and all social/count actions inside this form:

~~~swift
VStack(spacing: 0) {
    Spacer().frame(height: 30)
    AdaptiveSurface(contentInsets: 0) {
        ZStack(alignment: .topLeading) {
            // existing profile information and note list
        }
    }
    .accessibilityIdentifier("profile.primary-surface")
}
.adaptiveContentGutter()
~~~

For title-plus-follow/chat rows, wrap the existing first HStack in ViewThatFits. Its first candidate keeps the current title, Spacer, chat button, and follow button in one row; its second candidate places the existing title above the unchanged chat/follow action HStack. The own-profile variant keeps its current title-only row. No action is removed or given a target smaller than 44 pt.

- [ ] **Step 3: Size authentication and search from their actual parent**

In login GeometryReader roots:

~~~swift
let metrics = AdaptiveLayoutMetrics(
    size: geometry.size,
    safeAreaInsets: geometry.safeAreaInsets
)
content.padding(.horizontal, metrics.horizontalGutter)
~~~

In SearchView, apply adaptiveContentGutter() to the header/content boundary and pass an explicit width into FlowLayout:

~~~swift
let availableWidth = max(0, proxy.size.width - adaptiveLayout.horizontalGutter * 2)
FlowLayout(availableWidth: availableWidth, spacing: 10, alignment: .leading) {
    // existing search filter tags
}
~~~

- [ ] **Step 4: Add deterministic UI-frame coverage**

~~~swift
func testAdaptiveLayoutFixtureKeepsSurfaceInsideWindowEdges() {
    app.launchArguments = ["--ui-test-adaptive-layout"]
    app.launch()
    let window = app.windows.element(boundBy: 0)
    let surface = waitFor("adaptive-layout.surface")
    XCTAssertGreaterThanOrEqual(surface.frame.minX, 16)
    XCTAssertLessThanOrEqual(surface.frame.maxX, window.frame.maxX - 16)
    XCTAssertLessThan(surface.frame.width, window.frame.width)
    captureVisual("adaptive-layout-fixture")
}
~~~

The existing profile route asserts the same bounds for profile.primary-surface.

- [ ] **Step 5: Verify and commit**

Run:

~~~bash
cd /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNote -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ArcNoteUITests/ArcNoteUITests/testAdaptiveLayoutFixtureKeepsSurfaceInsideWindowEdges
cd Packages/CoreFlow
swift test --filter AdaptiveLayoutSourceContractTests/testEveryResponsiveRootUsesTheSharedGutter
~~~

Then commit:

~~~bash
git add ArcNote/ContentView.swift ArcNote/SignInView.swift ArcNote/SignUpView.swift ArcNote/ChooseInterestsView.swift ArcNote/TabBarView.swift ArcNote/HomeView.swift ArcNote/ExploreView.swift ArcNote/ChatView.swift ArcNote/SearchView.swift ArcNote/DetailView.swift ArcNote/RootView.swift ArcNote/UserProfileView.swift ArcNote/MyProfileView.swift ArcNoteUITests/ArcNoteUITests.swift
git commit -m "feat: adapt primary iPhone screens"
~~~

### Task 4: Migrate Settings, Account, Lists, and Workflows

**Files:**

- Modify: ArcNote/SettingsView.swift, ArcNote/PreferencesView.swift, ArcNote/AccountDetailsView.swift, ArcNote/EditProfileView.swift, ArcNote/APIAndPluginsView.swift
- Modify: ArcNote/ChoraProfileView.swift, ArcNote/ChoraProfileSections.swift, ArcNote/ChoraIdentityGrowthSections.swift, ArcNote/ChoraChatHistorySection.swift
- Modify: ArcNote/InvitationCreditView.swift, ArcNote/InvitationCreditDetailViews.swift, ArcNote/FollowListView.swift, ArcNote/BlockedActorsView.swift, ArcNote/NotificationView.swift, ArcNote/NotificationDetailView.swift, ArcNote/TrashView.swift
- Modify: ArcNote/NewInsightView.swift, ArcNote/NewNoteView.swift, ArcNote/CardEditor/CardEditorShell.swift, ArcNote/SparkView.swift, ArcNote/MergeView.swift
- Modify: ArcNote/CoreFlow/FlowViews.swift, ArcNote/CoreFlow/MergeLifecycleViews.swift, ArcNote/CoreFlow/SparkContinuationViews.swift, ArcNote/CoreFlow/ShareCardView.swift, ArcNote/CoreFlow/ContentReportView.swift, ArcNote/PopupMenuView.swift
- Modify: ArcNoteUITests/ArcNoteUITests.swift

**Consumes:** Task 2 helpers and the Task 3 root-gutter convention.

**Produces:** Settings/account/auxiliary pages and creation/flow workflows that have one outer content boundary while preserving intentional full-bleed scenes.

- [ ] **Step 1: Apply single-gutter scroll roots and inset native list rows**

~~~swift
ScrollView {
    VStack(alignment: .leading, spacing: adaptiveLayout.regularSpacing) {
        // existing section content
    }
    .adaptiveContentGutter()
    .padding(.vertical, adaptiveLayout.regularSpacing)
}
.background(Color.black.ignoresSafeArea())
~~~

For native List roots, retain native scrolling and use:

~~~swift
.listRowInsets(
    EdgeInsets(
        top: 8,
        leading: adaptiveLayout.horizontalGutter,
        bottom: 8,
        trailing: adaptiveLayout.horizontalGutter
    )
)
~~~

- [ ] **Step 2: Use AdaptiveSurface only for page-level cards**

Use the following stable outer-surface identifiers when a page has a glass card: adaptive-surface.settings, adaptive-surface.chora, adaptive-surface.invitation, adaptive-surface.notification, adaptive-surface.account, and adaptive-surface.preferences. Keep existing section rows inside the same outer card so nested rows do not create a second glass layer.

Do not wrap rows already inside a page-level surface. For dense headers/actions, retain readable text with:

~~~swift
ViewThatFits(in: .horizontal) {
    HStack(spacing: 12) { title; Spacer(minLength: 8); actions }
    VStack(alignment: .leading, spacing: 12) { title; actions }
}
actions.frame(
    minWidth: AdaptiveLayoutMetrics.minimumHitTarget,
    minHeight: AdaptiveLayoutMetrics.minimumHitTarget
)
~~~

- [ ] **Step 3: Keep writing canvases full-bleed but inset interactive content**

In CardEditorShell.swift, retain the existing top-level ZStack with CardEditorAmbientBackdrop and CardEditorFloatingControls. Change only the existing ScrollView's inner VStack from fixed horizontal 20 pt padding to adaptiveContentGutter(), preserving its top 56 pt and bottom 96 pt editor-specific spacing.

Use the same outer gutter around New Note, New Insight, Spark, Merge, Flow, Share, and Report controls. Do not rewrite ActionBoxOverlay; it already computes safe-area-constrained geometry.

- [ ] **Step 4: Assert fixture card/list surfaces are inset**

Use current DEBUG routes --ui-test-settings, --ui-test-chora-profile, --ui-test-invitation-credits, --ui-test-notification-inbox, and --ui-test-card-editor-shell. Add stable identifiers to outer surfaces and reuse:

~~~swift
private func assertInset(_ element: XCUIElement, in window: XCUIElement) {
    XCTAssertGreaterThanOrEqual(element.frame.minX, 16)
    XCTAssertLessThanOrEqual(element.frame.maxX, window.frame.maxX - 16)
}
~~~

- [ ] **Step 5: Verify and commit**

Run:

~~~bash
cd /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNote -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorActionBoxFitsAdaptivePortraitViewport -only-testing:ArcNoteUITests/ArcNoteUITests/testChoraProfileFixtureStates -only-testing:ArcNoteUITests/ArcNoteUITests/testNotificationInboxUIContract
cd Packages/CoreFlow
swift test --filter AdaptiveLayoutSourceContractTests/testEveryResponsiveRootUsesTheSharedGutter
~~~

Then commit:

~~~bash
git add ArcNote ArcNoteUITests
git commit -m "feat: adapt iPhone page surfaces"
~~~

### Task 5: Replace Every Global Screen Measurement in Overlays

**Files:**

- Modify: ArcNote/SideMenuView.swift
- Modify: ArcNote/ChatDetailView.swift
- Modify: ArcNote/CommentPopupView.swift
- Modify: ArcNote/LinkPopupView.swift
- Modify: ArcNote/SearchView.swift
- Modify: ArcNoteUITests/ArcNoteUITests.swift
- Test: Packages/CoreFlow/Tests/CoreFlowTests/AdaptiveLayoutSourceContractTests.swift

**Consumes:** Local GeometryReader values and AdaptiveLayoutMetrics.

**Produces:** Drawers, chat bubbles, search tags, and modal overlays that size themselves relative to their actual container.

- [ ] **Step 1: Rewrite side-menu width and offset from the parent**

~~~swift
GeometryReader { proxy in
    let metrics = AdaptiveLayoutMetrics(
        size: proxy.size,
        safeAreaInsets: proxy.safeAreaInsets
    )
    let drawerWidth = metrics.drawerWidth

    ZStack(alignment: .leading) {
        Color.black.opacity(isPresented ? 0.5 : 0)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { isPresented = false }

        menuContent
            .frame(width: drawerWidth)
            .offset(x: isPresented ? 0 : -drawerWidth)
            .accessibilityIdentifier("adaptive-layout.drawer")
    }
}
~~~

Move the current image/background and navigation destinations into menuContent. Retain its rounded trailing corners and safe-area behavior.

- [ ] **Step 2: Pass chat width from its parent instead of reading the device**

~~~swift
struct ChatMessageView: View {
    let availableWidth: CGFloat
    // existing message values
}

ChatMessageView(
    message: message,
    availableWidth: max(0, geometry.size.width - adaptiveLayout.horizontalGutter * 2)
)

.frame(maxWidth: availableWidth * 0.8, alignment: alignment)
AttachedNotesBubbleView(notes: attachedNotes, maxWidth: max(0, availableWidth - 32))
~~~

The card selector uses geometry.size.height * 0.4 for both its frame and position calculation.

- [ ] **Step 3: Animate comment and link sheets using their local height**

In CommentPopupView.swift, apply the following frame, position, and offset to the existing popup VStack after its current input/footer content:

~~~swift
let sheetHeight = geometry.size.height * 0.6
let hiddenOffset = sheetHeight + geometry.safeAreaInsets.bottom

.frame(maxWidth: geometry.size.width, maxHeight: sheetHeight)
.position(
    x: geometry.size.width / 2,
    y: geometry.size.height - sheetHeight / 2 - keyboardHeight + geometry.safeAreaInsets.bottom
)
.offset(y: slideOffset)
~~~

Set slideOffset to hiddenOffset in the existing show/hide and onAppear handlers, then animate it to zero only after the local geometry is available. LinkPopupView uses its existing popup VStack and a local height of geometry.size.height * 0.55.

Use the same local formula in LinkPopupView with geometry.size.height * 0.55. The search flow layout receives the actual availableWidth passed by SearchView; it does not subtract a second hard-coded 40 pt margin.

- [ ] **Step 4: Add overlay frame checks**

~~~swift
private func assertContained(_ element: XCUIElement, in window: XCUIElement) {
    XCTAssertGreaterThanOrEqual(element.frame.minX, 0)
    XCTAssertLessThanOrEqual(element.frame.maxX, window.frame.maxX)
    XCTAssertGreaterThanOrEqual(element.frame.minY, 0)
    XCTAssertLessThanOrEqual(element.frame.maxY, window.frame.maxY)
}
~~~

Attach adaptive-layout.comment-surface and adaptive-layout.link-surface identifiers, invoke their deterministic DEBUG states, and assert each surface is contained.

- [ ] **Step 5: Verify the final contract and commit**

Run:

~~~bash
cd /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend/Packages/CoreFlow
swift test --filter AdaptiveLayoutSourceContractTests
cd /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNote -destination 'platform=iOS Simulator,name=iPhone SE (3rd generation)' -only-testing:ArcNoteUITests/ArcNoteUITests/testAdaptiveLayoutFixtureKeepsSurfaceInsideWindowEdges
~~~

Then commit:

~~~bash
git add ArcNote/SideMenuView.swift ArcNote/ChatDetailView.swift ArcNote/CommentPopupView.swift ArcNote/LinkPopupView.swift ArcNote/SearchView.swift ArcNoteUITests/ArcNoteUITests.swift
git commit -m "fix: size iOS overlays from local geometry"
~~~

### Task 6: Verify the Full Device Matrix and Finish

**Files:**

- Modify: ArcNoteUITests/ArcNoteUITests.swift only when a deterministic frame assertion is missing.
- Test: Packages/CoreFlow/Tests/CoreFlowTests/AdaptiveLayoutSourceContractTests.swift
- Test: ArcNoteUITests/ArcNoteUITests.swift

**Consumes:** Every prior task.

**Produces:** Build, source-contract, UI-test, and visual evidence for compact through maximum-width iPhones.

- [ ] **Step 1: Run final focused tests**

~~~bash
cd /Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend/Packages/CoreFlow
swift test
cd ../..
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNote -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ArcNoteUITests/ArcNoteUITests/testAdaptiveLayoutFixtureKeepsSurfaceInsideWindowEdges -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorActionBoxFitsAdaptivePortraitViewport -only-testing:ArcNoteUITests/ArcNoteUITests/testNotificationInboxUIContract
~~~

Expected: all CoreFlow tests and focused UI tests pass.

- [ ] **Step 2: Capture and inspect device screenshots**

For every booted device class, launch the deterministic route and capture the screen:

~~~bash
SIMCTL_CHILD_CHORAI_UI_TEST=1 xcrun simctl launch --terminate-running-process 86CD9628-7C27-4799-B237-3EEC82E7E9B5 com.michen.arcnote --ui-test-adaptive-layout
xcrun simctl io 86CD9628-7C27-4799-B237-3EEC82E7E9B5 screenshot /tmp/chorai-adaptive-se3.png
~~~

Repeat representative settings, Chora profile, editor, and drawer states. Inspect for full-frame backgrounds, 16/20/24 pt visible content edges, contained rounded surfaces, safe bottom controls, and no clipping.

- [ ] **Step 3: Run the fixture test on all four destinations**

~~~bash
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNote -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -only-testing:ArcNoteUITests/ArcNoteUITests/testAdaptiveLayoutFixtureKeepsSurfaceInsideWindowEdges
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNote -destination 'platform=iOS Simulator,id=8F00CE99-FEBE-4774-9A07-4BBAF8A0FD1D' -only-testing:ArcNoteUITests/ArcNoteUITests/testAdaptiveLayoutFixtureKeepsSurfaceInsideWindowEdges
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNote -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' -only-testing:ArcNoteUITests/ArcNoteUITests/testAdaptiveLayoutFixtureKeepsSurfaceInsideWindowEdges
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNote -destination 'platform=iOS Simulator,id=6C5CFF17-3628-42F9-81ED-072775106919' -only-testing:ArcNoteUITests/ArcNoteUITests/testAdaptiveLayoutFixtureKeepsSurfaceInsideWindowEdges
~~~

- [ ] **Step 4: Review and commit**

~~~bash
git diff --check
git status --short
git diff --stat
git add ArcNote ArcNoteUITests Packages/CoreFlow/Tests/CoreFlowTests ArcNote.xcodeproj/project.pbxproj docs/superpowers
git commit -m "test: verify adaptive iPhone layout"
~~~

Expected: git diff --check is empty and the commit contains only adaptive-layout implementation, coverage, and design artifacts.
