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
            onRetryFailure: nil,
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

private struct MergeLifecycleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var store: MergeSessionStore
    @ObservedObject var candidates: MergeCandidateStore
    @State private var searchText = ""
    @FocusState private var isTextInputFocused: Bool
    @State private var showCancelConfirmation = false
    @State private var showDiscardConfirmation = false

    private let onBack: () -> Void
    private let onJobAccepted: ((String) -> Void)?
    private let canRetryFailure: Bool
    private let canCancelFailure: Bool
    private let canRemoveFailure: Bool
    private let onRetryFailure: (() -> Void)?
    private let onCancelFailure: (() -> Void)?
    private let onRemoveFailure: (() -> Void)?
    private let onboardingStore: OnboardingGuideStore?
    private let contextualTipStore: ContextualGuideTipStore?

    init(
        store: MergeSessionStore,
        candidates: MergeCandidateStore,
        onBack: @escaping () -> Void,
        onJobAccepted: ((String) -> Void)?,
        canRetryFailure: Bool = true,
        canCancelFailure: Bool = false,
        canRemoveFailure: Bool = false,
        onRetryFailure: (() -> Void)?,
        onCancelFailure: (() -> Void)? = nil,
        onRemoveFailure: (() -> Void)?,
        onboardingStore: OnboardingGuideStore?,
        contextualTipStore: ContextualGuideTipStore?
    ) {
        self.store = store
        self.candidates = candidates
        self.onBack = onBack
        self.onJobAccepted = onJobAccepted
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
            ZStack {
                atmosphere

                VStack(spacing: 0) {
                    header
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

            }
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
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Merge", role: .destructive) {
                onCancelFailure?()
            }
            Button("Keep", role: .cancel) {}
        }
        .confirmationDialog(
            "Discard Merge?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                store.discardArtifact()
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
                    guard value.translation.width > 100,
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
            selectionContent
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Color.black.opacity(reduceTransparency ? 0.72 : 0.58)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            if let artifact = store.artifact {
                MergeArtifactReviewPanel(
                    artifact: artifact,
                    sourceCount: store.selectedSources.count,
                    error: store.artifactActionError,
                    operation: artifactOperation,
                    onDiscard: { showDiscardConfirmation = true },
                    onSave: store.commit
                )
                .adaptiveContentGutter()
                .padding(.vertical, 24)
                .overlay(alignment: .topLeading) {
                    automationText(
                        "ready",
                        identifier: "merge.artifact.ready"
                    )
                }
            }
        }
    }

    private var artifactOperation: MergeArtifactOperation {
        switch store.phase {
        case .committing:
            return .saving
        case .cancelling:
            return .discarding
        default:
            return .idle
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
                        showCancelConfirmation = true
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

private enum MergeArtifactOperation: Equatable {
    case idle
    case discarding
    case saving
}

private struct MergeArtifactReviewPanel: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let artifact: MergeArtifact
    let sourceCount: Int
    let error: CoreMergeError?
    let operation: MergeArtifactOperation
    let onDiscard: () -> Void
    let onSave: () -> Void

    private var isBusy: Bool { operation != .idle }

    private var estimatedBodyHeight: CGFloat {
        let estimatedLines = artifact.document.blocks.reduce(into: 0) {
            partialResult, block in
            let textLength = max(
                1,
                block.plainTextLines.joined(separator: " ").count
            )
            partialResult += max(1, Int(ceil(Double(textLength) / 38)))
        }
        let interBlockSpacing = max(0, artifact.document.blocks.count - 1) * 12
        return CGFloat(estimatedLines) * 22
            + CGFloat(interBlockSpacing)
            + 40
    }

    private func panelHeight(in availableHeight: CGFloat) -> CGFloat {
        let chromeHeight: CGFloat = error == nil ? 178 : 212
        let idealHeight = chromeHeight + estimatedBodyHeight
        return min(max(390, idealHeight), min(620, availableHeight * 0.68))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("Merge preview")
                        .font(.system(size: 18, weight: .semibold))

                    Text("\(sourceCount) sources → 1 card")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.54))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 18)

                Divider()
                    .overlay(Color.white.opacity(0.12))

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let subtitle = artifact.document.subtitle,
                           !subtitle.trimmingCharacters(
                                in: .whitespacesAndNewlines
                           ).isEmpty {
                            Text(subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.58))
                                .padding(.bottom, 2)
                        }

                        ForEach(
                            Array(artifact.document.blocks.enumerated()),
                            id: \.offset
                        ) { _, block in
                            MergeArtifactBlockView(block: block, depth: 0)
                        }

                        if artifact.document.blocks.isEmpty {
                            Text("No body")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("merge.artifact.body")
                }
                .scrollIndicators(.hidden)

                if error != nil {
                    Text("Couldn’t complete that action. Try again.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 1, green: 0.70, blue: 0.70))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        .accessibilityIdentifier("merge.artifact.error")
                }

                Divider()
                    .overlay(Color.white.opacity(0.12))

                HStack(spacing: 12) {
                    MergeArtifactTextAction(
                        title: operation == .discarding ? "Discarding…" : "Discard",
                        systemImage: "xmark",
                        isFilled: false,
                        isBusy: operation == .discarding,
                        isEnabled: !isBusy,
                        identifier: "merge.discard",
                        action: onDiscard
                    )

                    MergeArtifactTextAction(
                        title: operation == .saving ? "Saving…" : "Save",
                        systemImage: "checkmark",
                        isFilled: true,
                        isBusy: operation == .saving,
                        isEnabled: !isBusy,
                        identifier: "merge.commit",
                        action: onSave
                    )
                }
                .padding(16)
            }
            .frame(
                width: geometry.size.width,
                height: panelHeight(in: geometry.size.height),
                alignment: .top
            )
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        reduceTransparency
                            ? Color(red: 0.10, green: 0.065, blue: 0.15)
                            : Color(red: 0.09, green: 0.055, blue: 0.14)
                                .opacity(0.94)
                    )
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color(red: 0.58, green: 0.20, blue: 0.72)
                                    .opacity(0.24),
                                Color.clear,
                                Color(red: 0.18, green: 0.42, blue: 0.68)
                                    .opacity(0.16),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                        )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(
                                Color.white.opacity(
                                    contrast == .increased ? 0.42 : 0.20
                                ),
                                lineWidth: contrast == .increased ? 1.5 : 1
                            )
                    }
            }
            .shadow(color: Color.black.opacity(0.34), radius: 26, y: 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Merge preview")
        .accessibilityIdentifier("merge.artifact.panel")
    }
}

private struct MergeArtifactTextAction: View {
    let title: String
    let systemImage: String
    let isFilled: Bool
    let isBusy: Bool
    let isEnabled: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(isEnabled || isBusy ? 0.94 : 0.42))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                Capsule()
                    .fill(
                        isFilled
                            ? Color.white.opacity(isEnabled ? 0.18 : 0.08)
                            : Color.clear
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                Color.white.opacity(isEnabled ? 0.24 : 0.10),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
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
    @State private var operation: MergeArtifactOperation = .idle

    private var blocks: [MergeBlock] {
        let copy = [
            "Clarity comes from keeping the relationship between ideas visible.",
            "A quiet interface can preserve context without asking for another decision.",
            "The resulting card should feel complete, but still belong to the same library.",
            "Rate color is ambient metadata, never the primary content.",
            "Direct actions make the review state easy to understand and easy to leave.",
            "Long artifacts scroll inside the panel while their actions remain reachable.",
            "The exact server document is what Save commits.",
            "No title, tags, or route controls are invented by the client.",
        ]
        let values = usesLongDocument
            ? copy + copy + copy
            : Array(copy.prefix(3))
        return values.enumerated().map { index, text in
            MergeBlock(
                id: "fixture-block-\(index)",
                type: index == 0 ? "heading_2" : "paragraph",
                content: [
                    MergeInline(type: "text", text: text, properties: [:])
                ],
                properties: [:],
                children: []
            )
        }
    }

    private var artifact: MergeArtifact {
        MergeArtifact(
            artifactID: "fixture-artifact",
            jobID: "fixture-job",
            capabilityID: "structured_text",
            outputKind: .document,
            document: MergeDocument(
                schemaVersion: "card_doc.v1",
                title: nil,
                subtitle: nil,
                blocks: blocks,
                metadata: [:]
            ),
            fragments: [],
            metadata: [:]
        )
    }

    var body: some View {
        ZStack {
            Image("home_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

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

            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            MergeArtifactReviewPanel(
                artifact: artifact,
                sourceCount: 3,
                error: nil,
                operation: operation,
                onDiscard: { operation = .discarding },
                onSave: { operation = .saving }
            )
            .adaptiveContentGutter()
            .padding(.vertical, 24)
        }
        .preferredColorScheme(.dark)
    }
}
#endif

private struct MergeArtifactBlockView: View {
    let block: MergeBlock
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let text = ownText {
                Text(prefix + text)
                    .font(font)
                    .foregroundStyle(.white.opacity(textOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, CGFloat(depth) * 14)
            }

            ForEach(Array(block.children.enumerated()), id: \.offset) { _, child in
                MergeArtifactBlockView(block: child, depth: depth + 1)
            }

            if ownText == nil && block.children.isEmpty {
                Text("…")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.42))
                    .accessibilityLabel("Unsupported Merge content")
            }
        }
    }

    private var ownText: String? {
        let inline = block.content
            .compactMap(\.plainText)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !inline.isEmpty { return inline }
        for key in ["text", "label", "title", "name", "summary", "content"] {
            if let value = block.properties[key]?.textValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private var prefix: String {
        switch block.type.lowercased() {
        case "list_item", "bullet", "bullet_item": return "• "
        case "quote", "blockquote": return "“"
        default: return ""
        }
    }

    private var font: Font {
        switch block.type.lowercased() {
        case "heading", "heading_1", "h1":
            return .system(size: 19, weight: .semibold)
        case "heading_2", "h2":
            return .system(size: 17, weight: .semibold)
        default:
            return .system(size: 15, weight: .regular)
        }
    }

    private var textOpacity: Double {
        block.type.lowercased().contains("heading") ? 0.96 : 0.82
    }
}

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
