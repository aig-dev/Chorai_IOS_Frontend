import CoreFlow
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct GlobalMergeTaskPortalModifier: ViewModifier {
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
    private enum Route: String, Hashable {
        case spark
        case homeDetail = "home-detail"
        case exploreDetail = "explore-detail"
    }

    @State private var isExpanded = false
    @State private var path: [Route] = []

    private let summaries = [
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
#endif
