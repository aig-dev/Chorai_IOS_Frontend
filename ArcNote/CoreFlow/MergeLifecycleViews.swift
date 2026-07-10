import Combine
import CoreFlow
import SwiftUI

struct MergeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var candidates: MergeCandidateStore

    init(cardId: String) {
        _candidates = StateObject(
            wrappedValue: MergeCandidateStore(anchorCardID: cardId)
        )
    }

    var body: some View {
        Group {
            if let actorID = authManager.currentUser?.id,
               let anchor = candidates.anchorCard {
                MergeLifecycleView(
                    actorID: actorID,
                    anchor: anchor,
                    candidates: candidates,
                    onBack: dismiss.callAsFunction
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
                        date: Self.relativeDate(response.data.createdAt),
                        content: response.data.content,
                        tags: response.data.tags,
                        isUserCard: false,
                        favoriteCount: 0,
                        rate: 0
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
                date: relativeDate(card.createdAt),
                content: card.content,
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
    @Environment(\.colorSchemeContrast) private var contrast
    @ObservedObject var candidates: MergeCandidateStore
    @StateObject private var store: MergeSessionStore
    @State private var searchText = ""
    @State private var showCancelConfirmation = false

    private let onBack: () -> Void

    init(
        actorID: String,
        anchor: MergeCard,
        candidates: MergeCandidateStore,
        onBack: @escaping () -> Void
    ) {
        self.candidates = candidates
        self.onBack = onBack
        let scope = ProcessInfo.processInfo.environment[
            "CHORAI_UI_TEST_MERGE_SESSION_SCOPE"
        ]
        let keyPrefix = scope.map { "chorai.merge.session.\($0)" }
            ?? "chorai.merge.session"
        _store = StateObject(
            wrappedValue: MergeSessionStore(
                actorID: actorID,
                anchor: anchor.coreMergeSource,
                service: NetworkCoreMergeService(),
                persistence: UserDefaultsMergeSessionStore(
                    keyPrefix: keyPrefix
                )
            )
        )
    }

    var body: some View {
        ZStack {
            atmosphere

            VStack(spacing: 0) {
                header
                phaseContent
            }

            automationAnchors
        }
        .foregroundStyle(.white)
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Cancel Merge?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Merge", role: .destructive) {
                store.cancel()
            }
            Button("Keep", role: .cancel) {}
        }
        .task {
            store.start()
        }
        .onDisappear {
            store.stop()
        }
        .onChange(of: searchText) { query in
            candidates.scheduleSearch(query)
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    guard value.translation.width > 100,
                          abs(value.translation.height) < 50 else {
                        return
                    }
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
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()

            HStack(spacing: 8) {
                Image("menu_merge")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                Text("Merge")
                    .font(.system(size: 20, weight: .semibold))
            }

            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
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
            quietState(label: "Saving", identifier: "merge.phase.committing")
        case .cancelling:
            quietState(label: "Cancelling", identifier: "merge.phase.cancelling")
        case .paused:
            recoverableContent(label: "Paused", identifier: "merge.phase.paused")
        case .failed:
            recoverableContent(label: "Couldn’t weave", identifier: "merge.phase.failed")
        case .cancelled:
            terminalContent(label: "Cancelled", identifier: "merge.phase.cancelled")
        case .completed(let assetID):
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
                .padding(.horizontal, 20)
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
                .padding(.bottom, 104)
            }
            .overlay(alignment: .bottom) {
                selectionAction
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.7))

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityIdentifier("merge.search.input")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MergeSearchSurface())
        .padding(.horizontal, 20)
    }

    private var selectionAction: some View {
        Button(action: store.create) {
            HStack(spacing: 10) {
                Image("menu_merge")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text("\(store.selectedSources.count)")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(store.canCreate ? .white : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.gray.opacity(0.3))
            )
        }
        .disabled(!store.canCreate)
        .accessibilityLabel("Merge \(store.selectedSources.count) cards")
        .accessibilityIdentifier("merge.action")
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private var artifactContent: some View {
        VStack(spacing: 0) {
            sourceStrip

            ScrollView {
                if let artifact = store.artifact {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField(
                            artifact.document.title ?? "Merged Insight",
                            text: $store.titleOverride
                        )
                        .font(.system(size: 21, weight: .semibold))
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .disabled(store.isTitleOverrideLocked)
                        .accessibilityLabel("Merged card title")
                        .accessibilityIdentifier("merge.artifact.title")
                        .padding(.bottom, 14)

                        if let subtitle = artifact.document.subtitle,
                           !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.65))
                                .padding(.bottom, 16)
                        }

                        VStack(alignment: .leading, spacing: 12) {
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
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("merge.artifact.body")
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                reduceTransparency
                                    ? Color(red: 0.11, green: 0.075, blue: 0.16)
                                    : Color.black.opacity(0.30)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        Color.white.opacity(contrast == .increased ? 0.34 : 0.18),
                                        lineWidth: 1
                                    )
                            )
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 110)
                    .overlay(alignment: .topLeading) {
                        automationText(
                            "ready",
                            identifier: "merge.artifact.ready"
                        )
                    }
                }
            }
            .overlay(alignment: .bottom) {
                artifactActions
            }
        }
    }

    private var sourceStrip: some View {
        HStack(spacing: 8) {
            Image("menu_merge")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text(store.anchor.preview)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
            Spacer()
            Text("\(store.selectedSources.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var artifactActions: some View {
        HStack(spacing: 16) {
            MergeLifecycleAction(
                systemImage: "xmark",
                assetImage: nil,
                isFilled: false,
                accessibilityLabel: "Cancel Merge",
                accessibilityIdentifier: "merge.cancel"
            ) {
                showCancelConfirmation = true
            }

            MergeLifecycleAction(
                systemImage: "checkmark",
                assetImage: nil,
                isFilled: true,
                accessibilityLabel: "Save merged card",
                accessibilityIdentifier: "merge.commit"
            ) {
                store.commit()
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
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
                if store.job?.status.canCancel == true {
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

                MergeLifecycleAction(
                    systemImage: nil,
                    assetImage: "menu_merge",
                    isFilled: true,
                    accessibilityLabel: "Retry Merge",
                    accessibilityIdentifier: "merge.retry"
                ) {
                    store.retry()
                }
            }
            .padding(.horizontal, 24)
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
}

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
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 8)
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
                .padding(.horizontal, 24)
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
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 8)
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
            versionID: nil,
            preview: String(rawPreview.prefix(140))
        )
    }
}
