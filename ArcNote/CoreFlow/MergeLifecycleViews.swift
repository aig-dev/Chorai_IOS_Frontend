import Combine
import CoreFlow
import SwiftUI

enum MergeSessionStorageConfiguration {
    static var keyPrefix: String {
        ProcessInfo.processInfo.environment[
            "CHORAI_UI_TEST_MERGE_SESSION_SCOPE"
        ].map { "chorai.merge.session.\($0)" }
            ?? "chorai.merge.session"
    }
}

enum MergeTaskStorageConfiguration {
    static var keyPrefix: String {
        ProcessInfo.processInfo.environment[
            "CHORAI_UI_TEST_MERGE_SESSION_SCOPE"
        ].map { "chorai.merge.tasks.\($0)" }
            ?? "chorai.merge.tasks"
    }
}

struct MergeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var candidates: MergeCandidateStore
    private let onboardingStore: OnboardingGuideStore?
    private let contextualTipStore: ContextualGuideTipStore?

    init(
        cardId: String,
        onboardingStore: OnboardingGuideStore? = nil,
        contextualTipStore: ContextualGuideTipStore? = nil
    ) {
        self.onboardingStore = onboardingStore
        self.contextualTipStore = contextualTipStore
        _candidates = StateObject(
            wrappedValue: MergeCandidateStore(anchorCardID: cardId)
        )
    }

    var body: some View {
        Group {
            if authManager.currentUser?.id != nil,
               let anchor = candidates.anchorCard {
                NewMergeSessionHost(
                    anchor: anchor,
                    candidates: candidates,
                    onBack: dismiss.callAsFunction,
                    onboardingStore: onboardingStore,
                    contextualTipStore: contextualTipStore
                )
            } else if let error = candidates.anchorError {
                MergeEntryFailureView(
                    message: error,
                    onBack: dismiss.callAsFunction,
                    onRetry: candidates.retryAnchor
                )
            } else {
                MergeEntryLoadingView(onBack: dismiss.callAsFunction)
            }
        }
        .task {
            candidates.load()
        }
    }
}

private struct NewMergeSessionHost: View {
    @EnvironmentObject private var mergeCoordinator: MergeTaskCoordinator
    @State private var draft: MergeDraftSession?

    let anchor: MergeCard
    @ObservedObject var candidates: MergeCandidateStore
    let onBack: () -> Void
    let onboardingStore: OnboardingGuideStore?
    let contextualTipStore: ContextualGuideTipStore?

    var body: some View {
        Group {
            if let draft {
                NewMergeSessionDraftHost(
                    draft: draft,
                    candidates: candidates,
                    onBack: abandonDraftAndDismiss,
                    onboardingStore: onboardingStore,
                    contextualTipStore: contextualTipStore
                )
            } else {
                MergeEntryLoadingView(onBack: abandonDraftAndDismiss)
                    .task {
                        guard draft == nil else { return }
                        draft = mergeCoordinator.makeDraft(
                            anchor: anchor.coreMergeSource
                        )
                }
            }
        }
        .onDisappear {
            abandonDraftIfNeeded()
        }
    }

    private func abandonDraftAndDismiss() {
        abandonDraftIfNeeded()
        onBack()
    }

    private func abandonDraftIfNeeded() {
        guard let draft else { return }
        mergeCoordinator.abandon(draft)
    }
}

private struct NewMergeSessionDraftHost: View {
    @EnvironmentObject private var mergeCoordinator: MergeTaskCoordinator
    @StateObject private var store: MergeSessionStore
    @State private var adoptionRetryJobID: String?

    let draft: MergeDraftSession
    @ObservedObject var candidates: MergeCandidateStore
    let onBack: () -> Void
    let onboardingStore: OnboardingGuideStore?
    let contextualTipStore: ContextualGuideTipStore?

    init(
        draft: MergeDraftSession,
        candidates: MergeCandidateStore,
        onBack: @escaping () -> Void,
        onboardingStore: OnboardingGuideStore?,
        contextualTipStore: ContextualGuideTipStore?
    ) {
        self.draft = draft
        self.candidates = candidates
        self.onBack = onBack
        self.onboardingStore = onboardingStore
        self.contextualTipStore = contextualTipStore
        _store = StateObject(wrappedValue: draft.store)
    }

    var body: some View {
        MergeLifecycleView(
            store: store,
            candidates: candidates,
            onBack: onBack,
            onJobAccepted: adopt,
            failureCancellationIntent: .working,
            canCancelFailure: store.canCancelCanonicalJob,
            onRetryFailure: nil,
            onCancelFailure: store.cancel,
            onRemoveFailure: nil,
            onboardingStore: onboardingStore,
            contextualTipStore: contextualTipStore
        )
        .task {
            store.start()
        }
        .alert(
            "Couldn’t Keep Merge Running",
            isPresented: adoptionRetryBinding
        ) {
            Button("Retry") {
                retryAdoption()
            }
        } message: {
            Text("Keep this screen open and retry saving the merge.")
        }
    }

    private var adoptionRetryBinding: Binding<Bool> {
        Binding(
            get: { adoptionRetryJobID != nil },
            set: { isPresented in
                if !isPresented {
                    adoptionRetryJobID = nil
                }
            }
        )
    }

    private func retryAdoption() {
        guard let jobID = adoptionRetryJobID else { return }
        adoptionRetryJobID = nil
        Task { @MainActor in
            await Task.yield()
            adopt(jobID)
        }
    }

    private func adopt(_ jobID: String) {
        guard mergeCoordinator.adopt(draft) == jobID else {
            adoptionRetryJobID = jobID
            return
        }
        adoptionRetryJobID = nil
        onboardingStore?.receive(.mergeStarted(jobID: jobID))
        Task { @MainActor in
            await Task.yield()
            onBack()
        }
    }
}

struct ExistingMergeTaskHost: View {
    @EnvironmentObject private var mergeCoordinator: MergeTaskCoordinator
    let jobID: String

    var body: some View {
        if let store = mergeCoordinator.session(jobID: jobID) {
            let failureActions = mergeCoordinator.failureActions(jobID: jobID)
            ExistingMergeTaskSessionHost(
                store: store,
                canRetryFailure: failureActions.contains(.retry),
                canCancelFailure: failureActions.contains(.cancel),
                canRemoveFailure: failureActions.contains(.remove),
                onBack: mergeCoordinator.minimize,
                onRetryFailure: {
                    mergeCoordinator.retryFailed(jobID: jobID)
                },
                onCancelFailure: {
                    mergeCoordinator.cancelFailed(jobID: jobID)
                },
                onRemoveFailure: {
                    mergeCoordinator.removeFailed(jobID: jobID)
                }
            )
            .id(jobID)
        } else {
            MergeEntryFailureView(
                message: "Merge unavailable",
                onBack: mergeCoordinator.minimize,
                onRetry: { mergeCoordinator.present(jobID: jobID) }
            )
        }
    }
}

private struct ExistingMergeTaskSessionHost: View {
    @ObservedObject var store: MergeSessionStore
    @StateObject private var candidates: MergeCandidateStore
    let canRetryFailure: Bool
    let canCancelFailure: Bool
    let canRemoveFailure: Bool
    let onBack: () -> Void
    let onRetryFailure: () -> Void
    let onCancelFailure: () -> Void
    let onRemoveFailure: () -> Void

    init(
        store: MergeSessionStore,
        canRetryFailure: Bool,
        canCancelFailure: Bool,
        canRemoveFailure: Bool,
        onBack: @escaping () -> Void,
        onRetryFailure: @escaping () -> Void,
        onCancelFailure: @escaping () -> Void,
        onRemoveFailure: @escaping () -> Void
    ) {
        self.store = store
        self.canRetryFailure = canRetryFailure
        self.canCancelFailure = canCancelFailure
        self.canRemoveFailure = canRemoveFailure
        self.onBack = onBack
        self.onRetryFailure = onRetryFailure
        self.onCancelFailure = onCancelFailure
        self.onRemoveFailure = onRemoveFailure
        _candidates = StateObject(
            wrappedValue: MergeCandidateStore(
                anchorCardID: store.anchor.assetID
            )
        )
    }

    var body: some View {
        MergeLifecycleView(
            store: store,
            candidates: candidates,
            onBack: onBack,
            onJobAccepted: nil,
            failureCancellationIntent: .failure,
            canRetryFailure: canRetryFailure,
            canCancelFailure: canCancelFailure,
            canRemoveFailure: canRemoveFailure,
            onRetryFailure: onRetryFailure,
            onCancelFailure: onCancelFailure,
            onRemoveFailure: onRemoveFailure,
            onboardingStore: nil,
            contextualTipStore: nil
        )
        .task {
            candidates.load()
        }
    }
}

@MainActor
final class MergeCandidateStore: ObservableObject {
    @Published private(set) var anchorCard: MergeCard?
    @Published private(set) var cards: [MergeCard] = []
    @Published private(set) var isLoadingCards = false
    @Published private(set) var cardsError: String?
    @Published private(set) var anchorError: String?

    private let anchorCardID: String
    private let network: NetworkManager
    private var anchorCancellable: AnyCancellable?
    private var cardsCancellable: AnyCancellable?
    private var searchTask: Task<Void, Never>?
    private var hasLoaded = false

    init(
        anchorCardID: String,
        network: NetworkManager = .shared
    ) {
        self.anchorCardID = anchorCardID
        self.network = network
    }

    func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        loadAnchor()
        loadCards(search: "")
    }

    func retryAnchor() {
        anchorError = nil
        loadAnchor()
    }

    func scheduleSearch(_ rawQuery: String) {
        searchTask?.cancel()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask = Task { [weak self] in
            if !query.isEmpty {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard !Task.isCancelled else { return }
            self?.loadCards(search: query)
        }
    }

    private func loadAnchor() {
        anchorCancellable = network.getCard(id: anchorCardID)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard case .failure = completion else { return }
                    self?.anchorError = "Card unavailable"
                },
                receiveValue: { [weak self] response in
                    guard response.success else {
                        self?.anchorError = "Card unavailable"
                        return
                    }
                    self?.anchorError = nil
                    self?.anchorCard = MergeCard(
                        id: response.data.id,
                        versionID: response.data.noteDocumentVersionID,
                        date: Self.relativeDate(response.data.createdAt),
                        content: response.data.content,
                        contentJSON: response.data.contentJSON,
                        backgroundMediaRef: response.data.backgroundMediaRef,
                        tags: response.data.tags,
                        isUserCard: response.data.author != nil,
                        userName: response.data.author?.username,
                        avatarUrl: response.data.author?.avatar,
                        favoriteCount: response.data.favoriteCount,
                        rate: response.data.rate
                    )
                }
            )
    }

    private func loadCards(search: String) {
        isLoadingCards = true
        cardsError = nil
        cardsCancellable?.cancel()
        cardsCancellable = network.getUserAllCards(
            searchType: "own+favorited",
            search: search,
            limit: 50,
            cardId: anchorCardID
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                self?.isLoadingCards = false
                if case .failure = completion {
                    self?.cardsError = "Cards unavailable"
                }
            },
            receiveValue: { [weak self] response in
                guard let self else { return }
                cardsError = nil
                cards = Self.mergeCards(
                    response.data.ownCards
                        + response.data.favoritedCards
                        + response.data.likedCards
                        + response.data.linkedCards,
                    excluding: anchorCardID
                )
            }
        )
    }

    private static func mergeCards(
        _ values: [UserAllCard],
        excluding anchorCardID: String
    ) -> [MergeCard] {
        var seen = Set([anchorCardID])
        return values.compactMap { card in
            guard seen.insert(card.id).inserted else { return nil }
            return MergeCard(
                id: card.id,
                versionID: card.noteDocumentVersionID,
                date: relativeDate(card.createdAt),
                content: card.content,
                contentJSON: card.contentJSON,
                backgroundMediaRef: card.backgroundMediaRef,
                tags: card.tags,
                isUserCard: card.author != nil,
                userName: card.author?.username,
                avatarUrl: card.author?.avatar,
                favoriteCount: card.favoriteCount,
                rate: card.rate
            )
        }
    }

    private static func relativeDate(_ raw: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: raw) else { return "" }
        let days = Calendar.current.dateComponents(
            [.day],
            from: date,
            to: Date()
        ).day ?? 0
        switch days {
        case ...0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }
}

private enum MergeCancellationIntent {
    case working
    case failure
}

private struct MergeLifecycleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var store: MergeSessionStore
    @ObservedObject var candidates: MergeCandidateStore
    @State private var searchText = ""
    @FocusState private var isTextInputFocused: Bool
    @State private var pendingCancellationIntent: MergeCancellationIntent?

    private let onBack: () -> Void
    private let onJobAccepted: ((String) -> Void)?
    private let failureCancellationIntent: MergeCancellationIntent
    private let canRetryFailure: Bool
    private let canCancelFailure: Bool
    private let canRemoveFailure: Bool
    private let onRetryFailure: (() -> Void)?
    private let onCancelFailure: () -> Void
    private let onRemoveFailure: (() -> Void)?
    private let onboardingStore: OnboardingGuideStore?
    private let contextualTipStore: ContextualGuideTipStore?

    init(
        store: MergeSessionStore,
        candidates: MergeCandidateStore,
        onBack: @escaping () -> Void,
        onJobAccepted: ((String) -> Void)?,
        failureCancellationIntent: MergeCancellationIntent,
        canRetryFailure: Bool = true,
        canCancelFailure: Bool = false,
        canRemoveFailure: Bool = false,
        onRetryFailure: (() -> Void)?,
        onCancelFailure: @escaping () -> Void,
        onRemoveFailure: (() -> Void)?,
        onboardingStore: OnboardingGuideStore?,
        contextualTipStore: ContextualGuideTipStore?
    ) {
        self.store = store
        self.candidates = candidates
        self.onBack = onBack
        self.onJobAccepted = onJobAccepted
        self.failureCancellationIntent = failureCancellationIntent
        self.canRetryFailure = canRetryFailure
        self.canCancelFailure = canCancelFailure
        self.canRemoveFailure = canRemoveFailure
        self.onRetryFailure = onRetryFailure
        self.onCancelFailure = onCancelFailure
        self.onRemoveFailure = onRemoveFailure
        self.onboardingStore = onboardingStore
        self.contextualTipStore = contextualTipStore
    }

    private var isMergeTipVisible: Bool {
        contextualTipStore?.isVisible(
            .mergeAction,
            onboardingState: onboardingStore?.contextualTipState,
            targetIsVisible: store.canCreate
        ) ?? false
    }

    private func dismissMergeTipIfVisible() {
        guard isMergeTipVisible else { return }
        contextualTipStore?.dismiss(
            .mergeAction,
            onboardingState: onboardingStore?.contextualTipState,
            targetIsVisible: store.canCreate
        )
    }

    var body: some View {
        KeyboardStableViewport(isFocused: isTextInputFocused) { _ in
            VStack(spacing: 0) {
                if !isArtifactPresentation {
                    header
                }
                if !isArtifactPresentation,
                   let onboardingStore {
                    OnboardingGuideLine(
                        store: onboardingStore,
                        allowedStates: [
                            "product_merge_intro",
                            "product_merge_preview"
                        ]
                    )
                    .adaptiveContentGutter()
                    .padding(.bottom, 10)
                }
                phaseContent
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top
            )
            .background { atmosphere }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if case .selection = store.phase {
                selectionAction
            }
        }
        .foregroundStyle(.white)
        .overlay(alignment: .topLeading) {
            automationAnchors
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Cancel Merge?",
            isPresented: cancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Merge", role: .destructive) {
                let intent = pendingCancellationIntent
                pendingCancellationIntent = nil
                switch intent {
                case .working:
                    store.cancel()
                case .failure:
                    onCancelFailure()
                case nil:
                    break
                }
            }
            Button("Keep", role: .cancel) {}
        }
        .onChange(of: searchText) { query in
            dismissMergeTipIfVisible()
            candidates.scheduleSearch(query)
        }
        .onChange(of: isTextInputFocused) { isFocused in
            if isFocused {
                dismissMergeTipIfVisible()
            }
        }
        .onChange(of: store.job?.jobID) { jobID in
            guard let jobID, !jobID.isEmpty else { return }
            onJobAccepted?(jobID)
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    guard !isArtifactPresentation,
                          value.translation.width > 100,
                          abs(value.translation.height) < 50 else {
                        return
                    }
                    dismissMergeTipIfVisible()
                    onBack()
                }
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.22),
            value: phaseIdentity
        )
    }

    private var cancelConfirmation: Binding<Bool> {
        Binding(
            get: { pendingCancellationIntent != nil },
            set: { isPresented in
                if !isPresented {
                    pendingCancellationIntent = nil
                }
            }
        )
    }

    private var atmosphere: some View {
        ZStack {
            if reduceTransparency {
                Color(red: 0.055, green: 0.035, blue: 0.09)
            } else {
                Image("home_bg")
                    .resizable()
                    .scaledToFill()
            }
            LinearGradient(
                colors: [Color.black.opacity(0.08), Color.black.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                dismissMergeTipIfVisible()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("merge.back")

            Spacer()

            Text("Merge")
                .font(.system(size: 20, weight: .semibold))

            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .adaptiveContentGutter()
        .padding(.top, 4)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch store.phase {
        case .selection:
            selectionContent
        case .idle, .checkingAvailability:
            quietState(label: "Checking", identifier: "merge.phase.checking")
        case .creating:
            quietState(label: "Weaving", identifier: "merge.phase.creating")
        case .weaving:
            quietState(label: "Weaving", identifier: "merge.phase.weaving")
        case .loadingArtifact:
            quietState(label: "Opening", identifier: "merge.phase.artifact-loading")
        case .ready:
            artifactContent
        case .committing:
            artifactContent
        case .cancelling:
            if store.artifact != nil {
                artifactContent
            } else {
                quietState(label: "Cancelling", identifier: "merge.phase.cancelling")
            }
        case .paused:
            recoverableContent(label: "Paused", identifier: "merge.phase.paused")
        case .failed:
            recoverableContent(label: "Couldn’t weave", identifier: "merge.phase.failed")
        case .cancelled:
            terminalContent(label: "Cancelled", identifier: "merge.phase.cancelled")
        case .completed(let assetID):
            if assetID == nil, onRemoveFailure != nil {
                recoverableContent(
                    label: "Couldn’t open card",
                    identifier: "merge.phase.failed"
                )
            } else {
                terminalContent(label: "Saved", identifier: "merge.phase.completed")
                    .overlay(alignment: .topLeading) {
                        if let assetID {
                            automationText(
                                assetID,
                                identifier: "merge.completed.asset-id"
                            )
                        }
                    }
            }
        }
    }

    private var selectionContent: some View {
        VStack(spacing: 0) {
            if let anchor = candidates.anchorCard {
                FixedMergeCardView(card: anchor)
                    .padding(.top, 12)
                    .accessibilityIdentifier("merge.anchor.card")
            }

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
                .adaptiveContentGutter()
                .padding(.vertical, 16)

            searchBar

            ScrollView {
                LazyVStack(spacing: 16) {
                    if candidates.isLoadingCards && candidates.cards.isEmpty {
                        ProgressView()
                            .tint(.white)
                            .padding(.top, 70)
                    } else if let error = candidates.cardsError {
                        Text(error)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.top, 70)
                            .accessibilityIdentifier("merge.cards.error")
                    } else if candidates.cards.isEmpty {
                        Text("No cards")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .padding(.top, 70)
                            .accessibilityIdentifier("merge.cards.empty-message")
                    } else {
                        ForEach(candidates.cards) { card in
                            MergeCardView(
                                card: card,
                                isSelected: store.selectedSources.contains {
                                    $0.assetID == card.id
                                },
                                onToggleSelection: {
                                    dismissMergeTipIfVisible()
                                    store.toggleSelection(card.coreMergeSource)
                                }
                            )
                            .accessibilityHint(
                                store.selectedSources.contains {
                                    $0.assetID == card.id
                                }
                                    ? "Remove from Merge"
                                    : "Select for Merge"
                            )
                        }
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.7))

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .focused($isTextInputFocused)
                .accessibilityIdentifier("merge.search.input")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MergeSearchSurface())
        .adaptiveContentGutter()
    }

    private var selectionAction: some View {
        MergeSelectionPrimaryAction(
            count: store.selectedSources.count,
            isEnabled: store.canCreate
        ) {
            contextualTipStore?.complete(
                .mergeAction,
                onboardingState: onboardingStore?.contextualTipState,
                targetIsVisible: store.canCreate
            )
            store.create()
        }
        .overlay {
            ContextualGuideTargetHalo(
                isVisible: isMergeTipVisible
            )
        }
        .overlay(alignment: .topTrailing) {
            if let contextualTipStore {
                ContextualGuideCallout(
                    store: contextualTipStore,
                    tip: .mergeAction,
                    onboardingState: onboardingStore?.contextualTipState,
                    targetIsVisible: store.canCreate
                )
                .offset(y: -58)
            }
        }
    }

    private var artifactContent: some View {
        ZStack {
            Color.black.opacity(reduceTransparency ? 0.72 : 0.58)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            if store.artifact != nil {
                MergeArtifactEditorHost(
                    store: store,
                    onBack: onBack
                )
                .adaptiveContentGutter()
                .padding(.vertical, 18)
                .overlay(alignment: .topLeading) {
                    automationText(
                        "ready",
                        identifier: "merge.artifact.ready"
                    )
                }
            }
        }
        .background {
            selectionContent
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func quietState(
        label: String,
        identifier: String
    ) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image("loading_logo")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
            Spacer()

            if store.canCancelCanonicalJob {
                MergeLifecycleAction(
                    systemImage: "xmark",
                    assetImage: nil,
                    isFilled: false,
                    accessibilityLabel: "Cancel Merge",
                    accessibilityIdentifier: "merge.cancel"
                ) {
                    pendingCancellationIntent = .working
                }
                .adaptiveContentGutter()
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            automationText(label, identifier: identifier)
        }
    }

    private func recoverableContent(
        label: String,
        identifier: String
    ) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image("menu_merge")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
            Spacer()

            HStack(spacing: 16) {
                if canRemoveFailure, let onRemoveFailure {
                    MergeLifecycleAction(
                        systemImage: "xmark",
                        assetImage: nil,
                        isFilled: false,
                        accessibilityLabel: "Remove Merge",
                        accessibilityIdentifier: "merge.remove",
                        action: onRemoveFailure
                    )
                }

                if canCancelFailure {
                    MergeLifecycleAction(
                        systemImage: "xmark",
                        assetImage: nil,
                        isFilled: false,
                        accessibilityLabel: "Cancel Merge",
                        accessibilityIdentifier: "merge.cancel"
                    ) {
                        pendingCancellationIntent = failureCancellationIntent
                    }
                }

                if canRetryFailure {
                    MergeLifecycleAction(
                        systemImage: nil,
                        assetImage: "menu_merge",
                        isFilled: true,
                        accessibilityLabel: "Retry Merge",
                        accessibilityIdentifier: "merge.retry"
                    ) {
                        if let onRetryFailure {
                            onRetryFailure()
                        } else {
                            store.retry()
                        }
                    }
                }
            }
            .adaptiveContentGutter()
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            automationText(label, identifier: identifier)
        }
    }

    private func terminalContent(
        label: String,
        identifier: String
    ) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image("menu_merge")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
            Text(label)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            automationText(label, identifier: identifier)
        }
    }

    private var automationAnchors: some View {
        VStack(spacing: 1) {
            automationText("loaded", identifier: "screen.merge.loaded")
            automationText(
                store.anchor.assetID,
                identifier: "merge.source.card-id"
            )

            if candidates.isLoadingCards {
                automationText("loading", identifier: "merge.cards.loading")
            } else if candidates.cards.isEmpty {
                automationText("empty", identifier: "merge.cards.empty")
            } else {
                automationText("loaded", identifier: "merge.cards.loaded")
            }

            if let job = store.job {
                automationText(job.jobID, identifier: "merge.job.id")
                automationText(
                    job.status.serverValue,
                    identifier: "merge.job.status"
                )
            }
        }
        .frame(width: 1, height: 1)
        .accessibilityElement(children: .contain)
    }

    private func automationText(
        _ value: String,
        identifier: String
    ) -> some View {
        Text(value)
            .font(.system(size: 1))
            .foregroundStyle(.white.opacity(0.01))
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(identifier)
    }

    private var phaseIdentity: String {
        switch store.phase {
        case .idle: return "idle"
        case .checkingAvailability: return "checking"
        case .selection: return "selection"
        case .creating: return "creating"
        case .weaving(let status): return status.serverValue
        case .loadingArtifact: return "artifact-loading"
        case .ready: return "ready"
        case .committing: return "committing"
        case .paused: return "paused"
        case .failed: return "failed"
        case .cancelling: return "cancelling"
        case .cancelled: return "cancelled"
        case .completed: return "completed"
        }
    }

    private var isArtifactPresentation: Bool {
        guard store.artifact != nil else { return false }
        switch store.phase {
        case .ready, .committing, .cancelling:
            return true
        default:
            return false
        }
    }

}

private struct MergeSelectionPrimaryAction: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let count: Int
    let isEnabled: Bool
    let action: () -> Void

    private var label: String {
        count == 1 ? "Merge 1 card" : "Merge \(count) cards"
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.46))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background {
                    Capsule()
                        .fill(
                            isEnabled
                                ? LinearGradient(
                                    colors: [
                                        Color(red: 0.58, green: 0.28, blue: 0.68),
                                        Color(red: 0.32, green: 0.22, blue: 0.56),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.10),
                                        Color.white.opacity(0.07),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    Color.white.opacity(isEnabled ? 0.22 : 0.10),
                                    lineWidth: 1
                                )
                        }
                }
            }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("merge.action")
        .adaptiveContentGutter()
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(MergeSelectionActionDockSurface())
    }
}

private struct MergeSelectionActionDockSurface: View {
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(red: 0.055, green: 0.035, blue: 0.09)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Color(red: 0.055, green: 0.035, blue: 0.09)
                    .opacity(0.84)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

@MainActor
private struct MergeArtifactEditorHost: View {
    @StateObject private var controller: MergeArtifactDraftController
    let onBack: () -> Void

    init(store: MergeSessionStore, onBack: @escaping () -> Void) {
        _controller = StateObject(
            wrappedValue: MergeArtifactDraftController(
                store: store,
                // The current artifact contract exposes no authorized display
                // URL. Keep canonical media references and show the surface's
                // explicit secure-preview fallback instead of inventing one.
                authorizedDisplayURLsByMediaReference: [:]
            )
        )
        self.onBack = onBack
    }

    var body: some View {
        MergeArtifactEditorSurface(
            controller: controller,
            onBack: onBack
        )
    }
}

#if DEBUG
@MainActor
struct MergeSelectionVisualFixtureScreen: View {
    @State private var isCandidateSelected = true
    @State private var didMerge = false

    private let customBackgroundMediaRef: String? = {
        let value = ProcessInfo.processInfo.environment[
            "CHORAI_UI_TEST_MERGE_BACKGROUND_URL"
        ]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }()

    private let anchorCard = MergeCard(
        id: "merge-fixture-anchor",
        versionID: "ver_merge_fixture_anchor",
        date: "Today",
        content: "A small thought worth connecting to another note.",
        tags: ["Ideas", "Writing"],
        isUserCard: false,
        rate: 1
    )
    private var candidateCard: MergeCard {
        MergeCard(
            id: "merge-fixture-candidate",
            versionID: "ver_merge_fixture_candidate",
            date: "2 days ago",
            content: "Good interfaces make related thinking feel close without making the screen feel crowded.",
            backgroundMediaRef: customBackgroundMediaRef,
            tags: ["Design", "Product"],
            isUserCard: true,
            userName: "Mira",
            favoriteCount: 12,
            rate: 4
        )
    }

    private var selectedCount: Int {
        isCandidateSelected ? 2 : 1
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                Spacer()
                Text("Merge")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .foregroundStyle(.white)
            .adaptiveContentGutter()
            .padding(.top, 4)

            FixedMergeCardView(card: anchorCard)
                .padding(.top, 12)
                .accessibilityIdentifier("merge.anchor.card")

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)
                .adaptiveContentGutter()
                .padding(.vertical, 16)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                Text("Search")
            }
            .font(.system(size: 16))
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(MergeSearchSurface())
            .adaptiveContentGutter()

            ScrollView {
                LazyVStack(spacing: 16) {
                    MergeCardView(
                        card: candidateCard,
                        isSelected: isCandidateSelected,
                        onToggleSelection: {
                            isCandidateSelected.toggle()
                        }
                    )

                    MergeCardView(
                        card: MergeCard(
                            id: "merge-fixture-secondary",
                            versionID: "ver_merge_fixture_secondary",
                            date: "Last week",
                            content: "A second candidate keeps the scrolling surface representative.",
                            tags: ["Research"],
                            isUserCard: false,
                            rate: 6
                        ),
                        isSelected: false,
                        onToggleSelection: {}
                    )
                }
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .foregroundStyle(.white)
        .background {
            Image("home_bg")
                .resizable()
                .scaledToFill()
                .clipped()
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MergeSelectionPrimaryAction(
                count: selectedCount,
                isEnabled: isCandidateSelected
            ) {
                didMerge = true
            }
            .accessibilityValue(didMerge ? "merged" : "ready")
        }
        .background(
            Color(red: 0.055, green: 0.035, blue: 0.09)
                .ignoresSafeArea()
        )
    }

}

@MainActor
struct MergeArtifactVisualFixtureScreen: View {
    let usesLongDocument: Bool
    @StateObject private var store: MergeSessionStore
    @StateObject private var operationProbe: MergeArtifactFixtureOperationProbe
    @State private var isPresented = true

    init(usesLongDocument: Bool) {
        self.usesLongDocument = usesLongDocument
        let behavior = MergeArtifactFixtureBehavior.current
        let artifact = MergeArtifactFixtureFactory.artifact(
            usesLongDocument: usesLongDocument,
            includesLossyPassthrough: behavior.includesLossyPassthrough
        )
        let persistence = MergeArtifactFixturePersistence(
            snapshot: MergeArtifactFixtureFactory.snapshot()
        )
        let operationProbe = MergeArtifactFixtureOperationProbe()
        _operationProbe = StateObject(wrappedValue: operationProbe)
        _store = StateObject(
            wrappedValue: MergeSessionStore(
                actorID: MergeArtifactFixtureFactory.actorID,
                anchor: MergeArtifactFixtureFactory.sources[0],
                service: MergeArtifactFixtureService(
                    artifact: artifact,
                    behavior: behavior,
                    operationProbe: operationProbe
                ),
                persistence: persistence,
                pollDelaysNanoseconds: [0],
                pollDelayJitter: { $0 },
                maxPollAttempts: 1
            )
        )
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            if isPresented, store.artifact != nil {
                MergeArtifactEditorHost(
                    store: store,
                    onBack: { isPresented = false }
                )
                .adaptiveContentGutter()
                .padding(.vertical, 18)
            } else if isPresented {
                ProgressView()
                    .tint(.white)
            } else {
                Button {
                    isPresented = true
                } label: {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(Color.white.opacity(0.16))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel("Complete Merge")
                .accessibilityValue("1, complete")
                .accessibilityIdentifier("merge.task-rail")
            }
        }
        .background {
            VStack(spacing: 18) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 180)
                    .adaptiveContentGutter()

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 250)
                    .adaptiveContentGutter()
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 54)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .background {
            Image("home_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .environment(
            \.sizeCategory,
            ProcessInfo.processInfo.environment[
                "CHORAI_UI_TEST_MERGE_DYNAMIC_TYPE"
            ] == "AX5"
                ? .accessibilityExtraExtraExtraLarge
                : .large
        )
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                Text(String(operationProbe.commitCallCount))
                    .accessibilityIdentifier(
                        "fixture.merge.commit-call-count"
                    )
                Text(String(operationProbe.cancelCallCount))
                    .accessibilityIdentifier(
                        "fixture.merge.cancel-call-count"
                    )
                Text(String(operationProbe.saveCallCount))
                    .accessibilityIdentifier(
                        "fixture.merge.save-call-count"
                    )
                Text(String(operationProbe.retryMatchesFirstPayload))
                    .accessibilityIdentifier(
                        "fixture.merge.retry-same-payload"
                    )
                Text(String(operationProbe.retryMatchesFirstKey))
                    .accessibilityIdentifier(
                        "fixture.merge.retry-same-key"
                    )
            }
            .font(.system(size: 1))
            .foregroundStyle(.white.opacity(0.01))
            .frame(width: 1, height: 5)
            .accessibilityElement(children: .contain)
        }
        .task {
            store.start()
        }
    }
}

private enum MergeArtifactFixtureFactory {
    static let actorID = "fixture-merge-artifact-actor"
    static let sources = [
        MergeSource(
            assetID: "fixture-source-one",
            versionID: "fixture-version-one",
            preview: "First source"
        ),
        MergeSource(
            assetID: "fixture-source-two",
            versionID: "fixture-version-two",
            preview: "Second source"
        ),
        MergeSource(
            assetID: "fixture-source-three",
            versionID: "fixture-version-three",
            preview: "Third source"
        ),
    ]

    static func snapshot() -> MergeSessionSnapshot {
        MergeSessionSnapshot(
            actorID: actorID,
            anchorAssetID: sources[0].assetID,
            anchorPreview: sources[0].preview,
            createRequest: MergeCreateRequest(
                sources: sources,
                capability: "structured_text",
                idempotencyKey: "fixture-create",
                context: [:]
            ),
            selectedCapability: "structured_text",
            jobID: "fixture-merge-wysiwyg-job",
            lastStatus: .artifactReady,
            artifactID: "fixture-merge-wysiwyg-artifact",
            commitRequest: nil,
            committedAssetID: nil
        )
    }

    static func artifact(
        usesLongDocument: Bool,
        includesLossyPassthrough: Bool
    ) -> MergeArtifact {
        let extraBlocks = usesLongDocument
            ? #",{"content":[{"text":"An additional long-fixture paragraph keeps compact phones honest.","type":"text"}],"id":"blk_fixture_extra","type":"paragraph"}"#
            : ""
        let passthroughBlock = includesLossyPassthrough
            ? #",{"content":[{"text":"Preserved passthrough quote","type":"text"}],"id":"blk_fixture_quote","type":"quote"}"#
            : ""
        let baseDocument =
            #"{"blocks":[{"content":[{"styles":{"bold":true},"text":"A durable merged insight","type":"text"}],"id":"blk_fixture_heading","props":{"level":2},"type":"heading"},{"content":[{"text":"Clarity comes from keeping related ideas visible on one editable surface.","type":"text"}],"id":"blk_fixture_intro","type":"paragraph"},{"content":[{"text":"Scrolling is preview, and a tap edits the exact same document.","type":"text"}],"id":"blk_fixture_scroll","type":"paragraph"},{"content":[{"styles":{"italic":true},"text":"The card keeps its typography, frame, and material while focus changes.","type":"text"}],"id":"blk_fixture_focus","type":"paragraph"},{"content":[{"text":"Tags stay aligned with the Card Editor and never gain colored dots.","type":"text"}],"id":"blk_fixture_tags","type":"bullet_list"},{"content":[{"text":"Local snapshots survive minimizing the completed task.","type":"text"}],"id":"blk_fixture_restore","type":"paragraph"},{"content":[{"text":"Final WYSIWYG fixture paragraph.","type":"text"}],"id":"blk_fixture_final","type":"paragraph"}"#
        let documentSuffix =
            #"],"meta":{"producer":"merge.fixture","route":"text_fusion"},"schemaVersion":"card_doc.v1"}"#
        let documentJSON = Data(
            (baseDocument + passthroughBlock + extraBlocks + documentSuffix).utf8
        )
        var legacyBlocks = [
            "A durable merged insight",
            "Clarity comes from keeping related ideas visible on one editable surface.",
            "Scrolling is preview, and a tap edits the exact same document.",
            "The card keeps its typography, frame, and material while focus changes.",
            "Tags stay aligned with the Card Editor and never gain colored dots.",
            "Local snapshots survive minimizing the completed task.",
            "Final WYSIWYG fixture paragraph.",
        ].enumerated().map { index, text in
            MergeBlock(
                id: "blk_fixture_legacy_\(index)",
                type: index == 0 ? "heading" : "paragraph",
                content: [
                    MergeInline(type: "text", text: text, properties: [:])
                ],
                properties: [:],
                children: []
            )
        }
        if includesLossyPassthrough {
            legacyBlocks.append(
                MergeBlock(
                    id: "blk_fixture_quote",
                    type: "quote",
                    content: [
                        MergeInline(
                            type: "text",
                            text: "Preserved passthrough quote",
                            properties: [:]
                        )
                    ],
                    properties: [:],
                    children: []
                )
            )
        }
        return MergeArtifact(
            artifactID: "fixture-merge-wysiwyg-artifact",
            jobID: "fixture-merge-wysiwyg-job",
            capabilityID: "structured_text",
            outputKind: .document,
            document: MergeDocument(
                schemaVersion: "card_doc.v1",
                title: nil,
                subtitle: nil,
                blocks: legacyBlocks,
                metadata: [:]
            ),
            fragments: [],
            metadata: [:],
            latestRevision: 1,
            latestHash: "fixture-document-hash-1",
            documentJSON: documentJSON,
            presentationHash: "fixture-presentation-hash-1",
            presentation: MergeArtifactPresentation(
                schemaVersion: "merge_artifact_presentation.v1",
                tags: ["Design", "Inspiration", "Nature"],
                rate: 3
            )
        )
    }
}

private actor MergeArtifactFixtureService: CoreMergeServing {
    private let initialArtifact: MergeArtifact
    private let behavior: MergeArtifactFixtureBehavior
    private let operationProbe: MergeArtifactFixtureOperationProbe
    private var revision: Int

    init(
        artifact: MergeArtifact,
        behavior: MergeArtifactFixtureBehavior,
        operationProbe: MergeArtifactFixtureOperationProbe
    ) {
        initialArtifact = artifact
        self.behavior = behavior
        self.operationProbe = operationProbe
        revision = artifact.latestRevision
    }

    func capabilities() async throws -> [MergeCapability] {
        [
            MergeCapability(
                capabilityID: "structured_text",
                displayName: "Structured text",
                outputKind: .document,
                blockExport: false,
                slotCommit: false,
                isEnabled: true,
                rolloutStage: "fixture"
            )
        ]
    }

    func createJob(_ request: MergeCreateRequest) async throws -> MergeJob {
        try await job(id: initialArtifact.jobID)
    }

    func job(id: String) async throws -> MergeJob {
        return MergeJob(
            jobID: id,
            status: .artifactReady,
            capability: "structured_text",
            selectedCapability: "structured_text",
            planScore: nil,
            artifactID: initialArtifact.artifactID,
            latestCommit: nil,
            failureStage: nil,
            errorCode: nil,
            failureReason: nil
        )
    }

    func artifact(jobID: String) async throws -> MergeArtifact {
        initialArtifact
    }

    func saveArtifact(
        jobID: String,
        request: MergeArtifactSaveRequest
    ) async throws -> MergeArtifactSaveResult {
        let callCount = await operationProbe.recordSave(request)
        if behavior.saveFailsOnceWithTimeout, callCount == 1 {
            throw CoreMergeError.timeout
        }
        revision += 1
        return MergeArtifactSaveResult(
            artifactID: initialArtifact.artifactID,
            revision: revision,
            documentHash: "fixture-document-hash-\(revision)",
            presentationHash: "fixture-presentation-hash-\(revision)",
            presentation: MergeArtifactPresentation(
                schemaVersion: "merge_artifact_presentation.v1",
                tags: request.tags,
                rate: 3
            )
        )
    }

    func cancel(jobID: String) async throws -> MergeJob {
        await operationProbe.recordCancel()
        if behavior.cancelDelayNanoseconds > 0 {
            try await Task.sleep(
                nanoseconds: behavior.cancelDelayNanoseconds
            )
        }
        if behavior.cancelShouldFail {
            throw CoreMergeError.unavailable(code: "fixture_cancel_failure")
        }
        return MergeJob(
            jobID: jobID,
            status: .cancelled,
            capability: "structured_text",
            selectedCapability: "structured_text",
            planScore: nil,
            artifactID: initialArtifact.artifactID,
            latestCommit: nil,
            failureStage: nil,
            errorCode: nil,
            failureReason: nil
        )
    }

    func commit(
        jobID: String,
        request: MergeCommitRequest
    ) async throws -> MergeCommitResult {
        await operationProbe.recordCommit()
        if behavior.commitDelayNanoseconds > 0 {
            try await Task.sleep(
                nanoseconds: behavior.commitDelayNanoseconds
            )
        }
        if behavior.commitShouldFail {
            throw CoreMergeError.unavailable(code: "fixture_commit_failure")
        }
        return MergeCommitResult(
            commitID: "fixture-commit",
            status: "COMMITTED",
            targetType: "new_card",
            assetID: "fixture-accepted-card",
            versionID: "fixture-accepted-version",
            activityID: nil,
            logID: nil,
            errorCode: nil,
            backgroundMediaReference: nil
        )
    }
}

private struct MergeArtifactFixtureBehavior: Sendable {
    let includesLossyPassthrough: Bool
    let saveFailsOnceWithTimeout: Bool
    let commitDelayNanoseconds: UInt64
    let commitShouldFail: Bool
    let cancelDelayNanoseconds: UInt64
    let cancelShouldFail: Bool

    static var current: Self {
        let environment = ProcessInfo.processInfo.environment
        return Self(
            includesLossyPassthrough: environment[
                "CHORAI_UI_TEST_MERGE_LOSSY_PASSTHROUGH"
            ] == "1",
            saveFailsOnceWithTimeout: environment[
                "CHORAI_UI_TEST_MERGE_SAVE_FAILS_ONCE_TIMEOUT"
            ] == "1",
            commitDelayNanoseconds: UInt64(
                environment[
                    "CHORAI_UI_TEST_MERGE_COMMIT_DELAY_NANOSECONDS"
                ] ?? ""
            ) ?? 0,
            commitShouldFail: environment[
                "CHORAI_UI_TEST_MERGE_COMMIT_SHOULD_FAIL"
            ] == "1",
            cancelDelayNanoseconds: UInt64(
                environment[
                    "CHORAI_UI_TEST_MERGE_CANCEL_DELAY_NANOSECONDS"
                ] ?? ""
            ) ?? 0,
            cancelShouldFail: environment[
                "CHORAI_UI_TEST_MERGE_CANCEL_SHOULD_FAIL"
            ] == "1"
        )
    }
}

@MainActor
private final class MergeArtifactFixtureOperationProbe: ObservableObject {
    @Published private(set) var commitCallCount = 0
    @Published private(set) var cancelCallCount = 0
    @Published private(set) var saveCallCount = 0
    @Published private(set) var retryMatchesFirstPayload = false
    @Published private(set) var retryMatchesFirstKey = false

    private var firstSaveRequest: MergeArtifactSaveRequest?

    func recordCommit() {
        commitCallCount += 1
    }

    func recordCancel() {
        cancelCallCount += 1
    }

    @discardableResult
    func recordSave(_ request: MergeArtifactSaveRequest) -> Int {
        saveCallCount += 1
        if let firstSaveRequest {
            retryMatchesFirstPayload =
                request.baseRevision == firstSaveRequest.baseRevision
                && request.baseHash == firstSaveRequest.baseHash
                && request.documentJSON == firstSaveRequest.documentJSON
                && request.tags == firstSaveRequest.tags
            retryMatchesFirstKey = request.idempotencyKey
                == firstSaveRequest.idempotencyKey
        } else {
            firstSaveRequest = request
        }
        return saveCallCount
    }
}

private final class MergeArtifactFixturePersistence: MergeSessionPersisting {
    private var value: MergeSessionSnapshot?

    init(snapshot: MergeSessionSnapshot) {
        value = snapshot
    }

    func snapshot(actorID: String) -> MergeSessionSnapshot? {
        value?.actorID == actorID ? value : nil
    }

    func save(_ snapshot: MergeSessionSnapshot) {
        value = snapshot
    }

    func remove(actorID: String) {
        if value?.actorID == actorID {
            value = nil
        }
    }

    func resumeMetadata(actorID: String) -> MergeResumeMetadata? {
        guard let value = snapshot(actorID: actorID) else { return nil }
        return MergeResumeMetadata(
            actorID: value.actorID,
            anchorAssetID: value.anchorAssetID,
            anchorPreview: value.anchorPreview,
            sourceCount: value.createRequest.sources.count,
            jobID: value.jobID,
            status: value.lastStatus,
            committedAssetID: value.committedAssetID
        )
    }
}
#endif

private struct MergeLifecycleAction: View {
    let systemImage: String?
    let assetImage: String?
    let isFilled: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                } else if let assetImage {
                    Image(assetImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(MergeCapsuleSurface(isFilled: isFilled))
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct MergeCapsuleSurface: View {
    let isFilled: Bool

    var body: some View {
        Capsule()
            .fill(isFilled ? Color.white.opacity(0.2) : Color.clear)
            .overlay(highlight(center: .topLeading, endRadius: 35).offset(y: -1))
            .overlay(highlight(center: .bottomTrailing, endRadius: 35))
            .overlay(edgeHighlight(start: .top, end: UnitPoint(x: 0, y: 0.05)).offset(y: -1))
            .overlay(edgeHighlight(start: .bottom, end: UnitPoint(x: 1, y: 0.05)).offset(y: 1))
    }

    private func highlight(center: UnitPoint, endRadius: CGFloat) -> some View {
        Capsule()
            .stroke(Color.white, lineWidth: 1)
            .mask(
                Capsule().fill(
                    RadialGradient(
                        colors: [Color.white, Color.clear],
                        center: center,
                        startRadius: 10,
                        endRadius: endRadius
                    )
                )
            )
    }

    private func edgeHighlight(start: UnitPoint, end: UnitPoint) -> some View {
        Capsule()
            .stroke(Color.white, lineWidth: 1)
            .mask(
                Capsule().fill(
                    LinearGradient(
                        colors: [Color.white, Color.clear],
                        startPoint: start,
                        endPoint: end
                    )
                )
            )
    }
}

private struct MergeSearchSurface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 25)
            .fill(Color(red: 0.2, green: 0.1, blue: 0.3))
            .overlay(highlight(center: .topLeading).offset(y: -1))
            .overlay(highlight(center: .bottomTrailing))
            .overlay(edgeHighlight(start: .top, end: UnitPoint(x: 0, y: 0.05)).offset(y: -1))
            .overlay(edgeHighlight(start: .bottom, end: UnitPoint(x: 1, y: 0.05)).offset(y: 1))
    }

    private func highlight(center: UnitPoint) -> some View {
        RoundedRectangle(cornerRadius: 25)
            .stroke(Color.white, lineWidth: 1)
            .mask(
                RoundedRectangle(cornerRadius: 25).fill(
                    RadialGradient(
                        colors: [Color.white, Color.clear],
                        center: center,
                        startRadius: 10,
                        endRadius: 35
                    )
                )
            )
    }

    private func edgeHighlight(start: UnitPoint, end: UnitPoint) -> some View {
        RoundedRectangle(cornerRadius: 25)
            .stroke(Color.white, lineWidth: 1)
            .mask(
                RoundedRectangle(cornerRadius: 25).fill(
                    LinearGradient(
                        colors: [Color.white, Color.clear],
                        startPoint: start,
                        endPoint: end
                    )
                )
            )
    }
}

private struct MergeEntryLoadingView: View {
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Image("home_bg").resizable().scaledToFill().ignoresSafeArea()
            ProgressView().tint(.white)
            VStack {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("merge.back")
                    Spacer()
                }
                Spacer()
            }
            .adaptiveContentGutter()
        }
        .foregroundStyle(.white)
        .navigationBarHidden(true)
    }
}

private struct MergeEntryFailureView: View {
    let message: String
    let onBack: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Image("home_bg").resizable().scaledToFill().ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                MergeLifecycleAction(
                    systemImage: nil,
                    assetImage: "menu_merge",
                    isFilled: true,
                    accessibilityLabel: "Retry Merge",
                    accessibilityIdentifier: "merge.entry.retry",
                    action: onRetry
                )
                .adaptiveContentGutter()
                Spacer()
            }
            VStack {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("merge.back")
                    Spacer()
                }
                Spacer()
            }
            .adaptiveContentGutter()
        }
        .foregroundStyle(.white)
        .navigationBarHidden(true)
    }
}

private extension MergeCard {
    var coreMergeSource: MergeSource {
        let rawPreview = content
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return MergeSource(
            assetID: id,
            versionID: versionID,
            preview: String(rawPreview.prefix(140))
        )
    }
}
