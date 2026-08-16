import CoreFlow
import Combine
import SwiftUI

struct MergeTaskRail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    let summaries: [MergeTaskSummary]
    @Binding var isExpanded: Bool
    let onSelect: (String) -> Void

    private var hasActiveTask: Bool {
        summaries.contains {
            $0.visualState == .working || $0.visualState == .committing
        }
    }

    private var hasFailedTask: Bool {
        summaries.contains { $0.visualState == .failed }
    }

    private var hasRecoveringTask: Bool {
        summaries.contains { $0.visualState == .recovering }
    }

    private var hasCompleteTask: Bool {
        summaries.contains { $0.visualState == .complete }
    }

    private var aggregateState: String {
        if hasFailedTask { return "failed" }
        if hasActiveTask { return "working" }
        if hasCompleteTask { return "complete" }
        if hasRecoveringTask { return "recovering" }
        return "idle"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                collapsedControl

                if isExpanded, summaries.count > 1 {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(
                                Array(summaries.enumerated()),
                                id: \.element.jobID
                            ) { index, summary in
                                taskButton(summary, number: index + 1)
                            }
                        }
                    }
                    .frame(height: expandedListHeight)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .onChange(of: summaries.count) { count in
            if count < 2 {
                isExpanded = false
            }
        }
    }

    private var expandedListHeight: CGFloat {
        let count = CGFloat(min(summaries.count, 4))
        return count * 44 + max(0, count - 1) * 8
    }

    private var collapsedControl: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: handleCollapsedTap) {
                ZStack {
                    railShell

                    Image("menu_merge")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 21, height: 21)
                        .foregroundStyle(.white)

                    MergeTaskActivityRing(
                        isActive: hasActiveTask,
                        reduceMotion: reduceMotion,
                        color: aggregateAccent
                    )

                    aggregateStatusShape
                        .offset(x: -13, y: 13)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                summaries.count == 1 ? "Merge task" : "Merge tasks"
            )
            .accessibilityValue("\(summaries.count), \(aggregateState)")
            .accessibilityHint(
                summaries.count == 1
                    ? summaries.first.map(destinationHint) ?? "Opens Merge"
                    : "Shows merge tasks"
            )
            .accessibilityIdentifier("merge.task-rail")

            if summaries.count > 1 {
                Text(String(summaries.count))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Circle().fill(aggregateAccent))
                    .overlay(Circle().stroke(Color.white.opacity(0.72)))
                    .offset(x: 5, y: -5)
                    .allowsHitTesting(false)
                    .accessibilityLabel(String(summaries.count))
                    .accessibilityIdentifier("merge.task-count")
            }
        }
        .frame(width: 49, height: 49, alignment: .bottomLeading)
    }

    private var railShell: some View {
        Circle()
            .fill(reduceTransparency
                ? AnyShapeStyle(ZenVisualTokens.opaqueCardFill)
                : AnyShapeStyle(.ultraThinMaterial))
            .overlay(
                Circle()
                    .fill(ZenVisualTokens.glassTint.opacity(
                        reduceTransparency ? 0 : 0.52
                    ))
            )
            .overlay(
                Circle().stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 12, y: 7)
    }

    @ViewBuilder
    private var aggregateStatusShape: some View {
        if hasFailedTask {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white, aggregateAccent)
                .frame(width: 17, height: 17)
                .background(Circle().fill(aggregateAccent))
        } else if hasCompleteTask {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(aggregateAccent))
        } else if hasRecoveringTask {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white, aggregateAccent)
                .frame(width: 17, height: 17)
                .background(Circle().fill(aggregateAccent))
        }
    }

    private var aggregateAccent: Color {
        if hasFailedTask { return Color(red: 0.93, green: 0.31, blue: 0.36) }
        if hasCompleteTask {
            return Color(red: 0.34, green: 0.78, blue: 0.61)
        }
        if hasRecoveringTask {
            return Color(red: 0.96, green: 0.64, blue: 0.22)
        }
        return ZenVisualTokens.accent
    }

    private func taskButton(
        _ summary: MergeTaskSummary,
        number: Int
    ) -> some View {
        Button {
            isExpanded = false
            onSelect(summary.jobID)
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(reduceTransparency
                        ? AnyShapeStyle(ZenVisualTokens.opaqueCardFill)
                        : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(
                        Circle().fill(ZenVisualTokens.glassTint.opacity(
                            reduceTransparency ? 0 : 0.56
                        ))
                    )
                    .overlay(
                        Circle().stroke(
                            Color.white.opacity(0.16),
                            lineWidth: 1
                        )
                    )

                MergeTaskStateGlyph(
                    state: summary.visualState,
                    number: number,
                    reduceMotion: reduceMotion
                )
                .frame(width: 44, height: 44, alignment: .center)

                if summary.visualState != .working,
                   summary.visualState != .committing {
                    Text(String(number))
                        .font(.system(
                            size: 9,
                            weight: .bold,
                            design: .rounded
                        ))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(ZenVisualTokens.accent))
                        .offset(x: 3, y: -3)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Merge task \(number), \(summary.sourceCount) sources"
        )
        .accessibilityValue(summary.visualState.rawValue)
        .accessibilityHint(destinationHint(for: summary))
        .accessibilityIdentifier("merge.task.\(number)")
    }

    private func handleCollapsedTap() {
        guard let first = summaries.first else { return }
        if summaries.count == 1 {
            onSelect(first.jobID)
        } else {
            withAnimation(
                reduceMotion ? nil : .easeOut(duration: 0.22)
            ) {
                isExpanded.toggle()
            }
        }
    }

    private func destinationHint(for summary: MergeTaskSummary) -> String {
        switch summary.visualState {
        case .complete:
            return "Opens Merge preview"
        case .failed:
            return "Opens Merge failure details"
        case .working, .committing, .recovering:
            return "Opens Merge progress"
        }
    }
}

struct MergeTaskRailShellOverlay<Callout: View>: View {
    let summaries: [MergeTaskSummary]
    @Binding var isExpanded: Bool
    let onSelect: (String) -> Void
    let isHaloVisible: Bool
    private let callout: Callout

    @State private var catchesOutsideTaps = false

    init(
        summaries: [MergeTaskSummary],
        isExpanded: Binding<Bool>,
        onSelect: @escaping (String) -> Void,
        isHaloVisible: Bool,
        @ViewBuilder callout: () -> Callout
    ) {
        self.summaries = summaries
        _isExpanded = isExpanded
        self.onSelect = onSelect
        self.isHaloVisible = isHaloVisible
        self.callout = callout()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isExpanded, catchesOutsideTaps {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        catchesOutsideTaps = false
                        isExpanded = false
                    }
                    .accessibilityHidden(true)
            }

            VStack(alignment: .trailing, spacing: 10) {
                callout

                MergeTaskRail(
                    summaries: summaries,
                    isExpanded: $isExpanded,
                    onSelect: onSelect
                )
                .frame(
                    width: 49,
                    height: railHeight,
                    alignment: .topTrailing
                )
                .overlay(alignment: .topTrailing) {
                    ContextualGuideTargetHalo(isVisible: isHaloVisible)
                        .offset(x: 2, y: -2)
                }
            }
            .padding(.top, 112)
            .padding(.trailing, 20)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topTrailing
        )
        .onChange(of: isExpanded) { expanded in
            guard expanded else {
                catchesOutsideTaps = false
                return
            }
            DispatchQueue.main.async {
                if isExpanded {
                    catchesOutsideTaps = true
                }
            }
        }
    }

    private var railHeight: CGFloat {
        guard isExpanded, summaries.count > 1 else { return 49 }
        let visibleCount = min(summaries.count, 4)
        return CGFloat(visibleCount * 52 + 49)
    }
}

struct MergeTaskRailPortalModifier<Callout: View>: ViewModifier {
    let summaries: [MergeTaskSummary]
    @Binding var isExpanded: Bool
    let isHidden: Bool
    let onSelect: (String) -> Void
    let isHaloVisible: Bool
    let callout: Callout

    func body(content: Content) -> some View {
        ZStack {
            content
            if !isHidden, !summaries.isEmpty {
                MergeTaskRailShellOverlay(
                    summaries: summaries,
                    isExpanded: $isExpanded,
                    onSelect: onSelect,
                    isHaloVisible: isHaloVisible
                ) {
                    callout
                }
                .zIndex(1)
            }
        }
    }
}

extension View {
    func mergeTaskRailPortal<Callout: View>(
        summaries: [MergeTaskSummary],
        isExpanded: Binding<Bool>,
        isHidden: Bool,
        onSelect: @escaping (String) -> Void,
        isHaloVisible: Bool,
        @ViewBuilder callout: () -> Callout
    ) -> some View {
        modifier(
            MergeTaskRailPortalModifier(
                summaries: summaries,
                isExpanded: isExpanded,
                isHidden: isHidden,
                onSelect: onSelect,
                isHaloVisible: isHaloVisible,
                callout: callout()
            )
        )
    }
}

@MainActor
enum MergeTaskPortalLifecycleSynchronizer {
    @discardableResult
    static func synchronize(
        coordinator: MergeTaskCoordinator,
        onboardingStore: OnboardingGuideStore,
        contextualTipStore: ContextualGuideTipStore,
        verifiedActorID: String?,
        isApplicationActive: Bool,
        isNetworkAvailable: Bool,
        shouldLoadOnboarding: Bool
    ) -> Bool {
        let actorDidChange = coordinator.synchronizeLifecycle(
            verifiedActorID: verifiedActorID,
            isApplicationActive: isApplicationActive,
            isNetworkAvailable: isNetworkAvailable
        )
        guard actorDidChange else { return false }

        onboardingStore.reset()
        contextualTipStore.reset()
        guard shouldLoadOnboarding, let verifiedActorID else { return true }
        onboardingStore.load(actorID: verifiedActorID)
        return true
    }
}

struct GlobalMergeTaskPortalModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var onboardingStore = OnboardingGuideStore(
        service: NetworkCoreOnboardingService(),
        persistence: UserDefaultsOnboardingGuidePersistence()
    )
    @StateObject private var contextualTipStore = ContextualGuideTipStore(
        persistence: UserDefaultsContextualGuideTipPersistence()
    )
    @StateObject private var coordinator = MergeTaskCoordinator(
        service: NetworkCoreMergeService(),
        persistence: UserDefaultsMergeTaskStore(
            keyPrefix: MergeTaskStorageConfiguration.keyPrefix,
            legacy: UserDefaultsMergeSessionStore(
                keyPrefix: MergeSessionStorageConfiguration.keyPrefix
            )
        )
    )
    @State private var isExpanded = false

    private var verifiedActorID: String? {
        authManager.sessionPhase == .verified
            ? authManager.currentUser?.id
            : nil
    }

    private func synchronizeLifecycle() {
        var shouldLoadOnboarding = true
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["CHORAI_UI_TEST"] == "1",
           environment["CHORAI_UI_TEST_ONBOARDING"] != "1" {
            shouldLoadOnboarding = false
        }
        #endif
        MergeTaskPortalLifecycleSynchronizer.synchronize(
            coordinator: coordinator,
            onboardingStore: onboardingStore,
            contextualTipStore: contextualTipStore,
            verifiedActorID: verifiedActorID,
            isApplicationActive: scenePhase == .active,
            isNetworkAvailable: NetworkManager.shared.isConnected,
            shouldLoadOnboarding: shouldLoadOnboarding
        )
    }

    private var presentation: Binding<Bool> {
        Binding(
            get: { coordinator.presentation != nil },
            set: { isPresented in
                if !isPresented {
                    coordinator.minimize()
                }
            }
        )
    }

    private var presentedJobID: String? {
        switch coordinator.presentation {
        case .progress(let jobID), .preview(let jobID), .failure(let jobID):
            return jobID
        case nil:
            return nil
        }
    }

    private func select(jobID: String) {
        isExpanded = false
        contextualTipStore.complete(
            .mergeResume,
            onboardingState: onboardingStore.contextualTipState,
            targetIsVisible: !coordinator.summaries.isEmpty
        )
        coordinator.present(jobID: jobID)
    }

    func body(content: Content) -> some View {
        content
            .environmentObject(onboardingStore)
            .environmentObject(contextualTipStore)
            .environmentObject(coordinator)
            .environment(\.cardNavigationMergeCoordinator, coordinator)
            .mergeTaskRailPortal(
                summaries: coordinator.summaries,
                isExpanded: $isExpanded,
                isHidden: coordinator.presentation != nil,
                onSelect: select,
                isHaloVisible: contextualTipStore.isVisible(
                    .mergeResume,
                    onboardingState: onboardingStore.contextualTipState,
                    targetIsVisible: true
                )
            ) {
                ContextualGuideCallout(
                    store: contextualTipStore,
                    tip: .mergeResume,
                    onboardingState: onboardingStore.contextualTipState,
                    targetIsVisible: true
                )
            }
            .fullScreenCover(isPresented: presentation) {
                if let jobID = presentedJobID {
                    ExistingMergeTaskHost(jobID: jobID)
                        .environmentObject(coordinator)
                } else {
                    EmptyView()
                }
            }
            .onAppear(perform: synchronizeLifecycle)
            .onChange(of: authManager.currentUser?.id) { _ in
                synchronizeLifecycle()
            }
            .onChange(of: authManager.sessionPhase) { _ in
                synchronizeLifecycle()
            }
            .onChange(of: scenePhase) { _ in
                synchronizeLifecycle()
            }
            .onReceive(
                NetworkManager.shared.$isConnected.removeDuplicates()
            ) { _ in
                synchronizeLifecycle()
            }
    }
}

extension View {
    func globalMergeTaskPortal() -> some View {
        modifier(GlobalMergeTaskPortalModifier())
    }
}

private struct MergeTaskActivityRing: View {
    let isActive: Bool
    let reduceMotion: Bool
    let color: Color

    @State private var rotation = 0.0

    var body: some View {
        if isActive {
            Circle()
                .trim(from: 0.12, to: 0.82)
                .stroke(
                    color.opacity(reduceMotion ? 0.78 : 1),
                    style: StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round
                    )
                )
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
                .onAppear(perform: updateAnimation)
                .onChange(of: reduceMotion) { _ in
                    updateAnimation()
                }
        }
    }

    private func updateAnimation() {
        rotation = 0
        guard !reduceMotion else { return }
        withAnimation(
            .linear(duration: 1.15).repeatForever(autoreverses: false)
        ) {
            rotation = 360
        }
    }
}

private struct MergeTaskStateGlyph: View {
    let state: MergeTaskVisualState
    let number: Int
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            switch state {
            case .working, .committing:
                Text(String(number))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                MergeTaskActivityRing(
                    isActive: true,
                    reduceMotion: reduceMotion,
                    color: ZenVisualTokens.accent
                )
            case .complete:
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            case .recovering:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        Color(red: 0.96, green: 0.64, blue: 0.22)
                    )
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        Color(red: 0.93, green: 0.31, blue: 0.36)
                    )
            }
        }
    }
}

#if DEBUG
struct MergeTaskRailFixtureScreen: View {
    private let mode = ProcessInfo.processInfo.environment[
        "CHORAI_UI_TEST_MERGE_TASK_FIXTURE"
    ]

    @ViewBuilder
    var body: some View {
        switch mode {
        case "working-cancel":
            MergeWorkingCancelFixtureScreen()
        case "root-lifecycle":
            MergeRootLifecycleFixtureScreen()
        default:
            MergeTaskRailRouteFixtureScreen()
        }
    }
}

private struct MergeTaskRailRouteFixtureScreen: View {
    private enum Route: String, Hashable {
        case spark
        case homeDetail = "home-detail"
        case exploreDetail = "explore-detail"
    }

    @State private var isExpanded: Bool
    @State private var path: [Route] = []

    private let visualState: MergeTaskVisualState?

    init() {
        let environment = ProcessInfo.processInfo.environment
        visualState = environment[
            "CHORAI_UI_TEST_MERGE_TASK_VISUAL_STATE"
        ].flatMap(MergeTaskVisualState.init(rawValue:))
        _isExpanded = State(
            initialValue: environment[
                "CHORAI_UI_TEST_MERGE_TASK_EXPANDED"
            ] == "1"
        )
    }

    private var summaries: [MergeTaskSummary] {
        if let visualState {
            return [
                MergeTaskSummary(
                    jobID: "fixture-\(visualState.rawValue)",
                    sourceCount: 2,
                    createdAt: Date(timeIntervalSince1970: 1),
                    visualState: visualState
                )
            ]
        }
        return [
            MergeTaskSummary(
                jobID: "fixture-complete",
                sourceCount: 3,
                createdAt: Date(timeIntervalSince1970: 3),
                visualState: .complete
            ),
            MergeTaskSummary(
                jobID: "fixture-working",
                sourceCount: 2,
                createdAt: Date(timeIntervalSince1970: 2),
                visualState: .working
            ),
            MergeTaskSummary(
                jobID: "fixture-failed",
                sourceCount: 4,
                createdAt: Date(timeIntervalSince1970: 1),
                visualState: .failed
            ),
        ]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ZenVisualTokens.background.ignoresSafeArea()
                VStack(spacing: 14) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("merge.portal.destination.root")
                    ForEach(
                        [Route.spark, .homeDetail, .exploreDetail],
                        id: \.self
                    ) { route in
                        Button(route.rawValue) {
                            path.append(route)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier(
                            "merge.portal.route.\(route.rawValue)"
                        )
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                ZStack {
                    ZenVisualTokens.background.ignoresSafeArea()
                    VStack(spacing: 18) {
                        Text(route.rawValue)
                            .accessibilityIdentifier(
                                "merge.portal.destination.\(route.rawValue)"
                            )
                        Button("Back") {
                            path.removeAll()
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("merge.portal.route.back")
                    }
                }
            }
        }
        .mergeTaskRailPortal(
            summaries: summaries,
            isExpanded: $isExpanded,
            isHidden: false,
            onSelect: { _ in },
            isHaloVisible: false
        ) {
            Color.clear
                .frame(width: 240, height: 44)
                .accessibilityHidden(true)
        }
    }
}

@MainActor
private final class MergeWorkingCancelFixtureRecorder: ObservableObject {
    @Published private(set) var isPollActive = false
    @Published private(set) var cancelCalls: [String] = []

    func markPollActive() {
        isPollActive = true
    }

    func recordCancel(jobID: String) {
        cancelCalls.append(jobID)
    }
}

private struct MergeFixtureControlledSleeper: MergeSleeping {
    let recorder: MergeWorkingCancelFixtureRecorder?

    func sleep(nanoseconds: UInt64) async throws {
        await recorder?.markPollActive()
        try await Task.sleep(nanoseconds: 60_000_000_000)
    }
}

private actor MergeFixtureService: CoreMergeServing {
    let recorder: MergeWorkingCancelFixtureRecorder?

    init(recorder: MergeWorkingCancelFixtureRecorder? = nil) {
        self.recorder = recorder
    }

    func capabilities() async throws -> [MergeCapability] {
        []
    }

    func createJob(_ request: MergeCreateRequest) async throws -> MergeJob {
        throw CoreMergeError.server(code: "fixture_create_unavailable")
    }

    func job(id: String) async throws -> MergeJob {
        mergeFixtureJob(id: id, status: .generating)
    }

    func artifact(jobID: String) async throws -> MergeArtifact {
        throw CoreMergeError.server(code: "fixture_artifact_unavailable")
    }

    func cancel(jobID: String) async throws -> MergeJob {
        await recorder?.recordCancel(jobID: jobID)
        return mergeFixtureJob(id: jobID, status: .cancelled)
    }

    func commit(
        jobID: String,
        request: MergeCommitRequest
    ) async throws -> MergeCommitResult {
        throw CoreMergeError.server(code: "fixture_commit_unavailable")
    }
}

private final class MergeFixtureTaskStore: MergeTaskCollectionPersisting {
    private var collections: [String: MergeTaskCollection]

    init(collections: [MergeTaskCollection]) {
        self.collections = Dictionary(
            uniqueKeysWithValues: collections.map { ($0.actorID, $0) }
        )
    }

    func collection(actorID: String) -> MergeTaskCollection {
        collections[actorID] ?? .empty(actorID: actorID)
    }

    func save(_ collection: MergeTaskCollection) {
        collections[collection.actorID] = collection
    }

    func update(
        actorID: String,
        _ mutation: (inout MergeTaskCollection) -> Void
    ) {
        var value = collection(actorID: actorID)
        mutation(&value)
        save(value)
    }

    func remove(actorID: String) {
        collections[actorID] = nil
    }
}

@MainActor
private struct MergeWorkingCancelFixtureScreen: View {
    private static let actorID = "fixture-working-actor"
    private static let jobID = "fixture-working-job"

    @StateObject private var recorder: MergeWorkingCancelFixtureRecorder
    @StateObject private var coordinator: MergeTaskCoordinator
    @State private var didStart = false
    private let persistence: MergeFixtureTaskStore

    init() {
        let recorder = MergeWorkingCancelFixtureRecorder()
        let persistence = MergeFixtureTaskStore(
            collections: [
                mergeFixtureCollection(
                    actorID: Self.actorID,
                    jobID: Self.jobID
                )
            ]
        )
        _recorder = StateObject(wrappedValue: recorder)
        _coordinator = StateObject(
            wrappedValue: MergeTaskCoordinator(
                service: MergeFixtureService(recorder: recorder),
                persistence: persistence,
                sleeper: MergeFixtureControlledSleeper(recorder: recorder)
            )
        )
        self.persistence = persistence
    }

    var body: some View {
        ZStack {
            ZenVisualTokens.background.ignoresSafeArea()
            if coordinator.session(jobID: Self.jobID) != nil {
                ExistingMergeTaskHost(jobID: Self.jobID)
                    .environmentObject(coordinator)
            } else {
                Text("Cancelled")
                    .foregroundStyle(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 1) {
                mergeFixtureAnchor(
                    Self.jobID,
                    identifier: "merge.fixture.persisted-job-id"
                )
                mergeFixtureAnchor(
                    recorder.isPollActive ? "active" : "waiting",
                    identifier: "merge.fixture.poll-state"
                )
                mergeFixtureAnchor(
                    recorder.cancelCalls.isEmpty
                        ? "none"
                        : recorder.cancelCalls.joined(separator: ","),
                    identifier: "merge.fixture.cancel-calls"
                )
                mergeFixtureAnchor(
                    targetState,
                    identifier: "merge.fixture.target-state"
                )
            }
        }
        .task {
            guard !didStart else { return }
            didStart = true
            coordinator.activate(actorID: Self.actorID)
            coordinator.present(jobID: Self.jobID)
        }
    }

    private var targetState: String {
        let isDurable = persistence.collection(actorID: Self.actorID)
            .tasks[Self.jobID] != nil
        return coordinator.session(jobID: Self.jobID) == nil && !isDurable
            ? "removed"
            : "retained"
    }
}

private final class MergeRootLifecycleOnboardingService:
    OnboardingGuideServing {
    private let actorTwoStatus = PassthroughSubject<
        OnboardingStatusSnapshot,
        OnboardingGuideError
    >()
    private let actorOneCurrent = PassthroughSubject<
        OnboardingGuideSession,
        OnboardingGuideError
    >()
    private let actorTwoCurrent = PassthroughSubject<
        OnboardingGuideSession,
        OnboardingGuideError
    >()
    private var statusCallCount = 0
    private var currentCallCount = 0

    func status() -> AnyPublisher<
        OnboardingStatusSnapshot,
        OnboardingGuideError
    > {
        statusCallCount += 1
        if statusCallCount == 1 {
            return Just(onboardingFixtureStatus(actor: 1))
                .setFailureType(to: OnboardingGuideError.self)
                .eraseToAnyPublisher()
        }
        return actorTwoStatus.eraseToAnyPublisher()
    }

    func start(
        flowVersion: Int
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        Fail(error: .unknown).eraseToAnyPublisher()
    }

    func current() -> AnyPublisher<
        OnboardingGuideSession,
        OnboardingGuideError
    > {
        currentCallCount += 1
        return (currentCallCount == 1 ? actorOneCurrent : actorTwoCurrent)
            .eraseToAnyPublisher()
    }

    func respond(
        sessionID: String,
        input: OnboardingGuideInput
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        Fail(error: .unknown).eraseToAnyPublisher()
    }

    func complete(
        sessionID: String
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        Fail(error: .unknown).eraseToAnyPublisher()
    }

    func skip(
        sessionID: String
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        Fail(error: .unknown).eraseToAnyPublisher()
    }

    func resolveActorTwo() {
        actorTwoStatus.send(onboardingFixtureStatus(actor: 2))
        DispatchQueue.main.async { [actorTwoCurrent] in
            actorTwoCurrent.send(onboardingFixtureSession(actor: 2))
        }
    }

    @MainActor
    func resolveStaleActorOne() {
        actorOneCurrent.send(onboardingFixtureSession(actor: 1))
    }
}

private final class MergeFixtureContextualPersistence:
    ContextualGuideTipPersisting {
    private var outcomes: [String: ContextualGuideTipOutcome] = [:]

    func outcome(
        actorID: String,
        sessionID: String?,
        tip: ContextualGuideTipID
    ) -> ContextualGuideTipOutcome? {
        outcomes[key(actorID: actorID, sessionID: sessionID, tip: tip)]
    }

    func save(
        _ outcome: ContextualGuideTipOutcome,
        actorID: String,
        sessionID: String?,
        tip: ContextualGuideTipID
    ) {
        outcomes[key(actorID: actorID, sessionID: sessionID, tip: tip)] =
            outcome
    }

    private func key(
        actorID: String,
        sessionID: String?,
        tip: ContextualGuideTipID
    ) -> String {
        "\(actorID)|\(sessionID ?? "none")|\(tip.rawValue)"
    }
}

private final class MergeFixtureOnboardingPersistence:
    OnboardingGuidePersisting {
    private var pending: [String: [OnboardingGuideEvidence]] = [:]

    func pendingEvidence(
        actorID: String,
        sessionID: String
    ) -> [OnboardingGuideEvidence] {
        pending[key(actorID: actorID, sessionID: sessionID)] ?? []
    }

    func savePendingEvidence(
        _ evidence: [OnboardingGuideEvidence],
        actorID: String,
        sessionID: String
    ) {
        pending[key(actorID: actorID, sessionID: sessionID)] = evidence
    }

    func clear(actorID: String, sessionID: String) {
        pending[key(actorID: actorID, sessionID: sessionID)] = nil
    }

    private func key(actorID: String, sessionID: String) -> String {
        "\(actorID)|\(sessionID)"
    }
}

@MainActor
private struct MergeRootLifecycleFixtureScreen: View {
    private static let actorOneID = "actor_1"
    private static let actorTwoID = "actor_2"
    private static let actorOneJobID = "fixture-actor-1-job"

    @StateObject private var coordinator: MergeTaskCoordinator
    @StateObject private var onboardingStore: OnboardingGuideStore
    @StateObject private var contextualTipStore: ContextualGuideTipStore
    @State private var didStart = false
    @State private var currentActorID: String? = Self.actorOneID
    private let persistence: MergeFixtureTaskStore
    private let onboardingService: MergeRootLifecycleOnboardingService

    init() {
        let persistence = MergeFixtureTaskStore(
            collections: [
                mergeFixtureCollection(
                    actorID: Self.actorOneID,
                    jobID: Self.actorOneJobID
                ),
                .empty(actorID: Self.actorTwoID)
            ]
        )
        let onboardingService = MergeRootLifecycleOnboardingService()
        _coordinator = StateObject(
            wrappedValue: MergeTaskCoordinator(
                service: MergeFixtureService(),
                persistence: persistence,
                sleeper: MergeFixtureControlledSleeper(recorder: nil)
            )
        )
        _onboardingStore = StateObject(
            wrappedValue: OnboardingGuideStore(
                service: onboardingService,
                persistence: MergeFixtureOnboardingPersistence()
            )
        )
        _contextualTipStore = StateObject(
            wrappedValue: ContextualGuideTipStore(
                persistence: MergeFixtureContextualPersistence()
            )
        )
        self.persistence = persistence
        self.onboardingService = onboardingService
    }

    var body: some View {
        ZStack {
            ZenVisualTokens.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Button("Logout") {
                    currentActorID = nil
                    synchronize(actorID: nil)
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("merge.lifecycle.logout")

                Button("Activate actor 2") {
                    currentActorID = Self.actorTwoID
                    synchronize(actorID: Self.actorTwoID)
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("merge.lifecycle.activate-actor-2")

                Button("Resolve actor 2") {
                    onboardingService.resolveActorTwo()
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("merge.lifecycle.resolve-actor-2")

                Button("Resolve stale actor 1") {
                    onboardingService.resolveStaleActorOne()
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("merge.lifecycle.resolve-stale-actor-1")
            }
            .foregroundStyle(.white)
        }
        .overlay(alignment: .topLeading) {
            VStack(spacing: 1) {
                mergeFixtureAnchor(
                    presentationJobID,
                    identifier: "merge.lifecycle.presentation"
                )
                mergeFixtureAnchor(
                    String(coordinator.summaries.count),
                    identifier: "merge.lifecycle.summary-count"
                )
                mergeFixtureAnchor(
                    actorOneDurableState,
                    identifier: "merge.lifecycle.actor-1-durable"
                )
                mergeFixtureAnchor(
                    onboardingPhaseLabel,
                    identifier: "merge.lifecycle.onboarding-phase"
                )
                mergeFixtureAnchor(
                    onboardingStore.session?.sessionID ?? "none",
                    identifier: "merge.lifecycle.onboarding-session"
                )
                mergeFixtureAnchor(
                    contextualTipStore.actorID ?? "none",
                    identifier: "merge.lifecycle.contextual-actor"
                )
            }
        }
        .onChange(of: onboardingStore.session?.sessionID) { _ in
            synchronizeContextualStore()
        }
        .task {
            guard !didStart else { return }
            didStart = true
            synchronize(actorID: Self.actorOneID)
            contextualTipStore.load(actorID: Self.actorOneID)
            coordinator.present(jobID: Self.actorOneJobID)
        }
    }

    private func synchronize(actorID: String?) {
        MergeTaskPortalLifecycleSynchronizer.synchronize(
            coordinator: coordinator,
            onboardingStore: onboardingStore,
            contextualTipStore: contextualTipStore,
            verifiedActorID: actorID,
            isApplicationActive: true,
            isNetworkAvailable: true,
            shouldLoadOnboarding: true
        )
    }

    private func synchronizeContextualStore() {
        guard onboardingStore.phase == .active,
              let currentActorID,
              let sessionID = onboardingStore.session?.sessionID else {
            return
        }
        contextualTipStore.load(
            actorID: currentActorID,
            sessionID: sessionID
        )
    }

    private var presentationJobID: String {
        switch coordinator.presentation {
        case .progress(let jobID), .preview(let jobID), .failure(let jobID):
            return jobID
        case nil:
            return "none"
        }
    }

    private var actorOneDurableState: String {
        persistence.collection(actorID: Self.actorOneID)
            .tasks[Self.actorOneJobID] == nil ? "removed" : "retained"
    }

    private var onboardingPhaseLabel: String {
        switch onboardingStore.phase {
        case .idle: return "idle"
        case .loading: return "loading"
        case .active: return "active"
        case .completed: return "completed"
        case .skipped: return "skipped"
        case .deferred: return "deferred"
        case .unavailable: return "unavailable"
        }
    }
}

private func mergeFixtureCollection(
    actorID: String,
    jobID: String
) -> MergeTaskCollection {
    let sources = [
        MergeSource(
            assetID: "fixture-anchor",
            versionID: "fixture-anchor-version",
            preview: "Fixture anchor"
        ),
        MergeSource(
            assetID: "fixture-companion",
            versionID: "fixture-companion-version",
            preview: "Fixture companion"
        )
    ]
    let snapshot = MergeSessionSnapshot(
        actorID: actorID,
        anchorAssetID: sources[0].assetID,
        anchorPreview: sources[0].preview,
        createRequest: MergeCreateRequest(
            sources: sources,
            capability: "auto",
            idempotencyKey: "fixture-create-key",
            context: ["fixture": .string("working-cancel")]
        ),
        selectedCapability: nil,
        jobID: jobID,
        lastStatus: .created,
        artifactID: nil,
        commitRequest: nil,
        committedAssetID: nil
    )
    let record = MergeTaskRecord(
        operationID: "fixture-operation-\(jobID)",
        snapshot: snapshot,
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 100),
        replacesJobID: nil
    )
    var collection = MergeTaskCollection.empty(actorID: actorID)
    collection.tasks[jobID] = record
    return collection
}

private func mergeFixtureJob(
    id: String,
    status: MergeJobStatus
) -> MergeJob {
    MergeJob(
        jobID: id,
        status: status,
        capability: "auto",
        selectedCapability: "structured_text",
        planScore: nil,
        artifactID: nil,
        latestCommit: nil,
        failureStage: nil,
        errorCode: nil,
        failureReason: nil
    )
}

private func onboardingFixtureStatus(actor: Int) -> OnboardingStatusSnapshot {
    let sessionID = "fixture-actor-\(actor)-session"
    return OnboardingStatusSnapshot(
        completed: false,
        needsOnboarding: true,
        latestSessionID: sessionID,
        activeSessionID: sessionID,
        status: "active",
        state: "product_merge_intro"
    )
}

@MainActor
private func onboardingFixtureSession(actor: Int) -> OnboardingGuideSession {
    OnboardingGuideSession(
        sessionID: "fixture-actor-\(actor)-session",
        flowKey: "onboarding_conversation",
        flowVersion: OnboardingGuideStore.canonicalFlowVersion,
        status: "active",
        state: "product_merge_intro",
        scene: OnboardingGuideScene(
            speaker: "chora",
            text: "Fixture actor \(actor)",
            inputMode: "choice",
            choices: [],
            canSkip: true,
            nextRoute: "explore",
            presentation: "guide_overlay",
            targetAnchor: nil,
            placement: nil,
            spotlight: false,
            choraMode: "guide"
        )
    )
}

private func mergeFixtureAnchor(
    _ value: String,
    identifier: String
) -> some View {
    Text(value)
        .font(.system(size: 1))
        .foregroundStyle(.white.opacity(0.01))
        .frame(width: 1, height: 1)
        .accessibilityIdentifier(identifier)
}
#endif
