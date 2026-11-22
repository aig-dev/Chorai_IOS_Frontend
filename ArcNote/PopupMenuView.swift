import CoreFlow
import SwiftUI

@MainActor
final class NoteAudiencePicker: ObservableObject {
    struct Choice: Identifiable {
        let id: UUID
        let observation: NotePrivacyObservation
        let select: (NotePrivacyObservation, Bool) -> Void
    }
    @Published var choice: Choice?
    @Published var failed = false
    private var visit = UUID()

    func open(_ identifier: String, select: @escaping (NotePrivacyObservation, Bool) -> Void) {
        let id = UUID()
        visit = id
        choice = nil
        failed = false
        Task {
            do {
                let observation = try await LocalNotesController.shared.observePrivacy(identifier: identifier)
                guard visit == id else { return }
                choice = Choice(id: id, observation: observation, select: select)
            } catch {
                if visit == id { failed = true }
            }
        }
    }

    func close() { visit = UUID(); choice = nil; failed = false }
}

private struct AudiencePickerKey: EnvironmentKey {
    static let defaultValue: NoteAudiencePicker? = nil
}

private extension EnvironmentValues {
    var noteAudiencePicker: NoteAudiencePicker? {
        get { self[AudiencePickerKey.self] }
        set { self[AudiencePickerKey.self] = newValue }
    }
}

struct NoteAudienceDialog: ViewModifier {
    @ObservedObject var picker: NoteAudiencePicker
    @ObservedObject private var auth = AuthManager.shared
    func body(content: Content) -> some View {
        content
            .confirmationDialog("Note audience", isPresented: Binding(
                get: { picker.choice != nil }, set: { if !$0 { picker.choice = nil } }
            ), titleVisibility: .visible, presenting: picker.choice) { choice in
                if let pending = choice.observation.pending {
                    Button("Retry previous change") { choice.select(choice.observation, pending.desired == .PUBLIC) }
                } else {
                    Button("Make Public") { choice.select(choice.observation, true) }
                    Button("Make Private") { choice.select(choice.observation, false) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { choice in
                Text("Current audience: \(choice.observation.policy.audience.rawValue.capitalized)")
            }
            .alert("Couldn’t load the note audience", isPresented: $picker.failed) { Button("OK") {} }
            .onChange(of: auth.sessionGeneration) { _ in picker.close() }
            .onDisappear { picker.close() }
    }
}

private struct OwnedCardActionStoreKey: EnvironmentKey {
    static let defaultValue: OwnedCardActionStore? = nil
}
private struct OwnedCardActionRevisionKey: EnvironmentKey {
    static let defaultValue = 0
}
private struct OwnedCardActionLockKey: EnvironmentKey {
    static let defaultValue = false
}
private struct OwnedCardActionCallbacks: Sendable {
    var onDelete: (@MainActor @Sendable () -> Void)?
    var onToggleVisibility: (@MainActor @Sendable (UserCard, NotePrivacyObservation, Bool) -> Void)?
    var onTogglePin: (@MainActor @Sendable (UserCard) -> Void)?
}
private struct OwnedCardActionCallbacksKey: EnvironmentKey {
    static let defaultValue = OwnedCardActionCallbacks()
}
private extension EnvironmentValues {
    var ownedCardActions: OwnedCardActionStore? {
        get { self[OwnedCardActionStoreKey.self] }
        set { self[OwnedCardActionStoreKey.self] = newValue }
    }
    var ownedCardActionRevision: Int {
        get { self[OwnedCardActionRevisionKey.self] }
        set { self[OwnedCardActionRevisionKey.self] = newValue }
    }
    var ownedCardActionsAreLocked: Bool {
        get { self[OwnedCardActionLockKey.self] }
        set { self[OwnedCardActionLockKey.self] = newValue }
    }
    var ownedCardActionCallbacks: OwnedCardActionCallbacks {
        get { self[OwnedCardActionCallbacksKey.self] }
        set { self[OwnedCardActionCallbacksKey.self] = newValue }
    }
}
private extension UserCard {
    func ownedActionSnapshot(isOwnCard: Bool) -> OwnedCardActionSnapshot {
        .init(cardID: id, isOwned: isOwnCard && isOwner != false,
              isPublic: isPublic, isPinned: isPinned, pinnedAt: pinnedAt)
    }
}

/// Adapts existing owners: durable local lifecycle changes or confirmed cloud receipts.
@MainActor
private final class NetworkOwnedCardActionService: OwnedCardActionServing {
    func perform(_ request: OwnedCardActionRequest) async throws -> OwnedCardActionCommit {
        // Match the existing managers' session boundary, including isolated UI fixtures.
        guard AuthManager.shared.currentUser != nil else {
            throw OwnedCardActionError.requestFailed
        }
        switch request.operation {
        case .remove:
            if request.cardID.hasPrefix("local-note:") {
                // My Notes is locally authoritative. The existing coordinator
                // owns the guarded cloud operation and retains it on failure.
                try await LocalNotesController.shared.setLifecycle(identifier: request.cardID, lifecycle: .trashed)
                return .removed(cardID: request.cardID)
            }
            return try await withCheckedThrowingContinuation { continuation in
                NetworkManager.shared.deleteCard(cardId: request.cardID) { result in
                    switch result {
                    case .success(let response) where response.success:
                        continuation.resume(returning: .removed(cardID: request.cardID))
                    case .success: continuation.resume(throwing: OwnedCardActionError.requestFailed)
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
            }
        case .setVisibility(let value):
            guard let observation = request.privacy else { throw NotePrivacyError.invalidCommand }
            let result = try await LocalNotesController.shared.setPrivacy(identifier: request.cardID, observation: observation, isPublic: value)
            return .visibility(cardID: request.cardID, isPublic: result.audience.isPublic)
        case .setPinned(let value):
            return try await withCheckedThrowingContinuation { continuation in
                let completion: (Result<ToggleCardPinResponse, NetworkError>) -> Void = { result in
                    switch result {
                    case .success(let response):
                        guard response.success, let card = response.data, let pinned = card.isPinned else {
                            continuation.resume(throwing: OwnedCardActionError.invalidResponse)
                            return
                        }
                        continuation.resume(returning: .pin(cardID: card.id, isPinned: pinned, pinnedAt: card.pinnedAt))
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
                if value { NetworkManager.shared.toggleCardPin(cardId: request.cardID, completion: completion) }
                else { NetworkManager.shared.unpinCard(cardId: request.cardID, completion: completion) }
            }
        }
    }
}

private struct OwnedCardActionHostModifier: ViewModifier {
    @ObservedObject private var auth = AuthManager.shared
    @StateObject private var picker = NoteAudiencePicker()
    private let usesNetwork: Bool
    @StateObject private var store: OwnedCardActionStore
    let onCommit: (OwnedCardActionCommit) -> Void
    let authoritativeRefresh: OwnedCardActionRefresh?
    let refreshInFlight: Bool

    init(service: (any OwnedCardActionServing)?, authoritativeRefresh: OwnedCardActionRefresh?, refreshInFlight: Bool, onCommit: @escaping (OwnedCardActionCommit) -> Void) {
        usesNetwork = service == nil
        _store = StateObject(wrappedValue: OwnedCardActionStore(service: service ?? NetworkOwnedCardActionService()))
        self.onCommit = onCommit
        self.authoritativeRefresh = authoritativeRefresh
        self.refreshInFlight = refreshInFlight
    }

    func body(content: Content) -> some View {
        content
            .environment(\.ownedCardActionCallbacks, OwnedCardActionCallbacks())
            .modifier(NoteAudienceDialog(picker: picker))
            .environment(\.noteAudiencePicker, usesNetwork ? picker : nil)
            .environment(\.ownedCardActions, store)
            .environment(\.ownedCardActionRevision, store.stateRevision)
            .environment(\.ownedCardActionsAreLocked, store.isInteractionLocked || refreshInFlight)
            .confirmationDialog("Remove this note?", isPresented: Binding(
                get: { store.removalTarget != nil },
                set: { if !$0 { store.dismissRemovalDialog() } }
            ), titleVisibility: .visible, presenting: store.removalTarget) { target in
                Button("Remove", role: .destructive) { store.confirmRemoval(of: target) }
                    .accessibilityIdentifier("card-action.remove.confirm")
                Button("Cancel", role: .cancel) { store.cancelRemoval() }
            } message: { _ in
                Text("This note will move to Trash.")
            }
            .alert("Couldn’t update this note", isPresented: Binding(
                get: { store.failure != nil },
                set: { if !$0 { store.dismissFailure() } }
            ), presenting: store.failure) { failure in
                if failure.error.mayRetry {
                    Button("Retry") { store.retry(failure) }
                        .accessibilityIdentifier("card-action.retry")
                }
                Button("Cancel", role: .cancel) { store.dismissFailure() }
            } message: { failure in
                if case .privacy(let error) = failure.error {
                    Text(error.localizedDescription)
                } else {
                    Text(failure.request.operation == .remove
                        ? "The note wasn’t removed. Try again."
                        : "The change wasn’t confirmed. Try again.")
                }
            }
            .overlay(alignment: .top) {
                if let request = store.workingRequest {
                    ProgressView(request.operation == .remove ? "Removing note…" : "Updating note…")
                        .font(.callout).padding(12)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 8)
                        .accessibilityIdentifier("card-action.progress")
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: auth.sessionGeneration) { _ in store.retireSession() }
            .onAppear { applyAuthoritativeRefresh() }
            .onChange(of: authoritativeRefresh) { refresh in
                if let refresh { store.applyAuthoritativeRefresh(refresh) }
            }
            .onChange(of: store.commitRevision) { _ in
                if let commit = store.lastCommit { onCommit(commit) }
            }
    }

    private func applyAuthoritativeRefresh() {
        if let authoritativeRefresh { store.applyAuthoritativeRefresh(authoritativeRefresh) }
    }
}

enum CardNavigationRoute {
    case detail(String)
    case editor(String)
    case spark(String)
    case merge(String)
    case root(cardID: String, type: String?)
}

struct CardNavigationDismissal {
    let route: CardNavigationRoute
}

private struct NavigateCardActionKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (CardNavigationRoute) -> Void = { _ in }
}

private struct CardNavigationOnboardingStoreKey: EnvironmentKey {
    static let defaultValue: OnboardingGuideStore? = nil
}

private struct CardNavigationContextualTipStoreKey: EnvironmentKey {
    static let defaultValue: ContextualGuideTipStore? = nil
}

private struct CardNavigationRoutePresentationChangedKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (Bool) -> Void = { _ in }
}

private struct CardNavigationMergeCoordinatorKey: EnvironmentKey {
    static let defaultValue: MergeTaskCoordinator? = nil
}

extension EnvironmentValues {
    var navigateCard: @MainActor @Sendable (CardNavigationRoute) -> Void {
        get { self[NavigateCardActionKey.self] }
        set { self[NavigateCardActionKey.self] = newValue }
    }

    var cardNavigationOnboardingStore: OnboardingGuideStore? {
        get { self[CardNavigationOnboardingStoreKey.self] }
        set { self[CardNavigationOnboardingStoreKey.self] = newValue }
    }

    var cardNavigationContextualTipStore: ContextualGuideTipStore? {
        get { self[CardNavigationContextualTipStoreKey.self] }
        set { self[CardNavigationContextualTipStoreKey.self] = newValue }
    }

    var cardNavigationRoutePresentationChanged: @MainActor @Sendable (Bool) -> Void {
        get { self[CardNavigationRoutePresentationChangedKey.self] }
        set { self[CardNavigationRoutePresentationChangedKey.self] = newValue }
    }

    var cardNavigationMergeCoordinator: MergeTaskCoordinator? {
        get { self[CardNavigationMergeCoordinatorKey.self] }
        set { self[CardNavigationMergeCoordinatorKey.self] = newValue }
    }

}

private struct ForwardMergeCoordinatorModifier: ViewModifier {
    let coordinator: MergeTaskCoordinator?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let coordinator {
            content
                .environmentObject(coordinator)
                .environment(
                    \.cardNavigationMergeCoordinator,
                    coordinator
                )
        } else {
            content
        }
    }
}

private struct CardNavigationDestination: View {
    let route: CardNavigationRoute
    let onboardingStore: OnboardingGuideStore?
    let contextualTipStore: ContextualGuideTipStore?
    let routePresentationChanged: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        destination
            .toolbar(.hidden, for: .tabBar)
            .environment(\.cardNavigationOnboardingStore, onboardingStore)
            .environment(\.cardNavigationContextualTipStore, contextualTipStore)
            .environment(\.cardNavigationRoutePresentationChanged, routePresentationChanged)
    }

    @ViewBuilder
    private var destination: some View {
        switch route {
        case .detail(let cardID):
            DetailView(cardId: cardID)
        case .editor(let cardID):
            NewNoteView(cardId: cardID)
        case .spark(let cardID):
            if let actorID = AuthManager.shared.currentUser?.id {
                SparkContinuationView(
                    cardID: cardID,
                    actorID: actorID,
                    onboardingStore: onboardingStore,
                    contextualTipStore: contextualTipStore
                )
            } else {
                EmptyView()
            }
        case .merge(let cardID):
            MergeView(
                cardId: cardID,
                onboardingStore: onboardingStore,
                contextualTipStore: contextualTipStore
            )
        case .root(let cardID, let type):
            RootView(cardId: cardID, type: type)
        }
    }
}

private struct CardNavigationHostModifier: ViewModifier {
    @Environment(\.cardNavigationOnboardingStore) private var onboardingStore
    @Environment(\.cardNavigationContextualTipStore) private var contextualTipStore
    @Environment(\.cardNavigationRoutePresentationChanged)
    private var routePresentationChanged
    @Environment(\.cardNavigationMergeCoordinator)
    private var mergeCoordinator
    @State private var presentedRoute: CardNavigationRoute?

    private var isPresentingRoute: Binding<Bool> {
        Binding(
            get: { presentedRoute != nil },
            set: { isPresented in
                if !isPresented {
                    let wasPresentingRoute = presentedRoute != nil
                    presentedRoute = nil
                    if wasPresentingRoute {
                        routePresentationChanged(false)
                    }
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .environment(\.navigateCard, { present($0) })
            .navigationDestination(isPresented: isPresentingRoute) {
                if let presentedRoute {
                    CardNavigationDestination(
                        route: presentedRoute,
                        onboardingStore: onboardingStore,
                        contextualTipStore: contextualTipStore,
                        routePresentationChanged: routePresentationChanged
                    )
                    .modifier(
                        ForwardMergeCoordinatorModifier(
                            coordinator: mergeCoordinator
                        )
                    )
                }
            }
    }

    private func present(_ route: CardNavigationRoute) {
        if presentedRoute == nil {
            routePresentationChanged(true)
        }
        presentedRoute = route
    }
}

// MARK: - Custom Scale Transition
extension AnyTransition {
    static func scale(scale: CGFloat) -> AnyTransition {
        .modifier(
            active: ScaleModifier(scale: scale),
            identity: ScaleModifier(scale: 1.0)
        )
    }
}

struct ScaleModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scale: CGFloat

    func body(content: Content) -> some View {
        content.scaleEffect(reduceMotion ? 1 : scale)
    }
}

// MARK: - PopupMenu Layout Type
enum PopupMenuLayout {
    case grid2x2    // 当前布局：Spark, Share, Link, View
    case grid3x3    // 新布局：Edit, Spark, Merge, Private, Share, Link, Root, Remove, Pin
    case grid3x2    // 新布局：View, Spark, Share, Link, Root, Pin

    var rowCount: Int {
        switch self {
        case .grid2x2:
            return 2
        case .grid3x3, .grid3x2:
            return 3
        }
    }
}

// MARK: - PopupMenu Modifier
struct PopupMenuModifier: ViewModifier {
    @Environment(\.noteAudiencePicker) private var audiencePicker
    @Environment(\.ownedCardActions) private var ownedActions
    @Environment(\.ownedCardActionRevision) private var ownedActionRevision
    @Environment(\.cardNavigationOnboardingStore) private var onboardingStore
    @Environment(\.cardNavigationContextualTipStore) private var contextualTipStore
    @State private var presentedRoute: CardNavigationRoute?
    @Binding var isPresented: Bool
    let layout: PopupMenuLayout
    let cardData: UserCard?
    let isOwnCard: Bool
    let isSparkEnabled: Bool
    let onSpark: (() -> Void)?
    let onDelete: (@MainActor @Sendable () -> Void)?
    let onToggleVisibility: (@MainActor @Sendable (UserCard, NotePrivacyObservation, Bool) -> Void)?
    let onTogglePin: (@MainActor @Sendable (UserCard) -> Void)?
    let onRouteDismissed: (CardNavigationDismissal) -> Void
    let onRoutePresentationChanged: (Bool) -> Void

    @Environment(\.cardNavigationMergeCoordinator)
    private var mergeCoordinator

    private var isPresentingRoute: Binding<Bool> {
        Binding(
            get: { presentedRoute != nil },
            set: { isPresented in
                if !isPresented {
                    let wasPresentingRoute = presentedRoute != nil
                    let dismissal = presentedRoute.map {
                        CardNavigationDismissal(route: $0)
                    }
                    presentedRoute = nil
                    if wasPresentingRoute {
                        onRoutePresentationChanged(false)
                    }
                    if let dismissal {
                        onRouteDismissed(dismissal)
                    }
                }
            }
        )
    }

    func body(content: Content) -> some View {
        let _ = ownedActionRevision
        return content
            .overlay(
                Group {
                    if isPresented {
                        PopupMenuOverlay(
                            isPresented: $isPresented,
                            layout: layout,
                            cardData: cardData,
                            isOwnCard: isOwnCard,
                            isSparkEnabled: isSparkEnabled,
                            onSpark: onSpark,
                            onDelete: onDelete,
                            onToggleVisibility: onToggleVisibility,
                            onTogglePin: onTogglePin,
                            ownedActions: ownedActions, audiencePicker: audiencePicker,
                            onNavigate: { present($0) }
                        )
                    }
                }
            )
            .environment(\.navigateCard, { present($0) })
            .environment(\.ownedCardActionCallbacks, OwnedCardActionCallbacks(
                onDelete: onDelete, onToggleVisibility: onToggleVisibility, onTogglePin: onTogglePin
            ))
            .navigationDestination(isPresented: isPresentingRoute) {
                if let presentedRoute {
                    CardNavigationDestination(
                        route: presentedRoute,
                        onboardingStore: onboardingStore,
                        contextualTipStore: contextualTipStore,
                        routePresentationChanged: { onRoutePresentationChanged($0) }
                    )
                    .modifier(
                        ForwardMergeCoordinatorModifier(
                            coordinator: mergeCoordinator
                        )
                    )
                }
            }
    }

    private func present(_ route: CardNavigationRoute) {
        presentedRoute = route
        onRoutePresentationChanged(true)
    }
}

// MARK: - PopupMenu Overlay
struct PopupMenuOverlay: View {
    let audiencePicker: NoteAudiencePicker?
    @Binding var isPresented: Bool
    let layout: PopupMenuLayout
    let cardData: UserCard?
    let isOwnCard: Bool
    let isSparkEnabled: Bool
    let onSpark: (() -> Void)?
    let onDelete: (@MainActor @Sendable () -> Void)?
    let onToggleVisibility: (@MainActor @Sendable (UserCard, NotePrivacyObservation, Bool) -> Void)?
    let onTogglePin: (@MainActor @Sendable (UserCard) -> Void)?
    let onNavigate: @MainActor @Sendable (CardNavigationRoute) -> Void
    let onPrepare: (() -> Void)?
    let ownedActions: OwnedCardActionStore?

    init(
        isPresented: Binding<Bool>,
        layout: PopupMenuLayout,
        cardData: UserCard?,
        isOwnCard: Bool,
        isSparkEnabled: Bool = true,
        onSpark: (() -> Void)? = nil,
        onDelete: (@MainActor @Sendable () -> Void)? = nil,
        onToggleVisibility: (@MainActor @Sendable (UserCard, NotePrivacyObservation, Bool) -> Void)? = nil,
        onTogglePin: (@MainActor @Sendable (UserCard) -> Void)? = nil,
        ownedActions: OwnedCardActionStore? = nil,
        audiencePicker: NoteAudiencePicker? = nil,
        onNavigate: @escaping @MainActor @Sendable (CardNavigationRoute) -> Void = { _ in },
        onPrepare: (() -> Void)? = nil
    ) {
        _isPresented = isPresented
        self.layout = layout
        self.cardData = cardData
        self.isOwnCard = isOwnCard
        self.isSparkEnabled = isSparkEnabled
        self.onSpark = onSpark
        self.onDelete = onDelete
        self.onToggleVisibility = onToggleVisibility
        self.onTogglePin = onTogglePin
        self.onNavigate = onNavigate
        self.onPrepare = onPrepare
        self.audiencePicker = audiencePicker
        self.ownedActions = ownedActions
    }

    private var ownedState: OwnedCardActionSnapshot? {
        guard let card = cardData else { return nil }
        let candidate = card.ownedActionSnapshot(isOwnCard: isOwnCard)
        return ownedActions?.resolved(candidate) ?? candidate
    }

    var body: some View {
        ActionBoxOverlay(
            isPresented: $isPresented,
            accessibilityLabel: "Card Actions",
            accessibilityIdentifier: "popup-menu.overlay",
            rowCount: layout.rowCount
        ) {
            menuContent
        }
    }

    // Each default action belongs to the visible host and its exact card.
    private func deleteCard() {
        defer { isPresented = false }
        if let onDelete { onDelete(); return }
        guard let target = ownedState else { return }
        ownedActions?.requestRemoval(of: target)
    }

    private func toggleCardVisibility() {
        defer { isPresented = false }
        guard let card = cardData else { return }
        guard let target = ownedState else { return }
        if let audiencePicker {
            audiencePicker.open(card.id) { observation, desired in
                if let onToggleVisibility { onToggleVisibility(card, observation, desired); return }
                ownedActions?.setVisibility(of: target, desired: desired, observation: observation)
            }
        } else {
            ownedActions?.toggleVisibility(of: target)
        }
    }

    private func toggleCardPin() {
        defer { isPresented = false }
        guard let card = cardData else { return }
        if let onTogglePin { onTogglePin(card); return }
        guard let target = ownedState else { return }
        ownedActions?.togglePin(of: target)
    }

    private func shareCard() {
        guard let cardID = cardData?.id else { return }
        isPresented = false
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowCardShare"),
            object: nil,
            userInfo: ["cardId": cardID]
        )
    }

    private func reportCard() {
        guard let cardID = cardData?.id else { return }
        isPresented = false
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowContentReport"),
            object: nil,
            userInfo: ["cardId": cardID]
        )
    }

    private func sparkCard() {
        guard isSparkEnabled else { return }
        guard let cardID = cardData?.id else { return }
        isPresented = false

        if let onSpark {
            onSpark()
            return
        }

        onNavigate(.spark(cardID))
    }

    /// Native Menu uses the same ownership branches and dispatch as the legacy overlay.
    @ViewBuilder
    var nativeMenuContent: some View {
        switch layout {
        case .grid2x2:
            nativeAction("Spark", systemImage: "sparkles", enabled: isSparkEnabled, action: sparkCard)
            if isOwnCard {
                nativeAction("Share", systemImage: "square.and.arrow.up", action: shareCard)
            } else {
                nativeAction("Report", systemImage: "flag", action: reportCard)
            }
            nativeAction("Link", systemImage: "link", action: linkCard)
            nativeAction(isOwnCard ? "Edit" : "View", systemImage: isOwnCard ? "square.and.pencil" : "doc.text") {
                guard let card = cardData else { return }
                onNavigate(isOwnCard ? .editor(card.id) : .detail(card.id))
            }
        case .grid3x3:
            Section {
                nativeAction("Edit", systemImage: "square.and.pencil") {
                    guard let card = cardData else { return }
                    onNavigate(.editor(card.id))
                }
                nativeAction("Spark", systemImage: "sparkles", enabled: isSparkEnabled, action: sparkCard)
                nativeAction("Merge", systemImage: "square.stack.3d.up") {
                    guard let card = cardData else { return }
                    onNavigate(.merge(card.id))
                }
                nativeAction("Share", systemImage: "square.and.arrow.up", action: shareCard)
                nativeAction("Link", systemImage: "link", action: linkCard)
                nativeAction("Root", systemImage: "arrow.triangle.branch") {
                    guard let card = cardData else { return }
                    onNavigate(.root(cardID: card.id, type: nil))
                }
            }
            if let card = cardData {
                Section {
                    nativeAction((ownedState?.isPublic ?? card.isPublic) ? "Private" : "Public", systemImage: (ownedState?.isPublic ?? card.isPublic) ? "lock" : "globe", action: toggleCardVisibility)
                    nativeAction((ownedState?.isPinned ?? card.isPinned) ? "Unpin" : "Pin", systemImage: (ownedState?.isPinned ?? card.isPinned) ? "pin.slash" : "pin", action: toggleCardPin)
                }
            }
            Section {
                nativeAction("Remove", systemImage: "trash", role: .destructive, action: deleteCard)
            }
        case .grid3x2:
            nativeAction("View", systemImage: "doc.text") {
                guard let card = cardData else { return }
                onNavigate(.detail(card.id))
            }
            nativeAction("Spark", systemImage: "sparkles", enabled: isSparkEnabled, action: sparkCard)
            nativeAction("Share", systemImage: "square.and.arrow.up", action: shareCard)
            nativeAction("Link", systemImage: "link", action: linkCard)
            nativeAction("Root", systemImage: "arrow.triangle.branch") {
                guard let card = cardData else { return }
                onNavigate(.root(cardID: card.id, type: "favourite"))
            }
            nativeAction("Report", systemImage: "flag", action: reportCard)
        }
    }

    private func nativeAction(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role) {
            onPrepare?()
            isPresented = false
            action()
        } label: {
            Label(title, systemImage: systemImage)
        }
        .disabled(!enabled)
        .accessibilityIdentifier("popup-menu.item.\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }

    private func linkCard() {
        isPresented = false
        LinkPopupManager.shared.show(
            cardId: cardData?.id,
            isInitiatingCardOwned: isOwnCard,
            onNavigate: onNavigate
        )
    }

    // MARK: 菜单内容
    @ViewBuilder
    private var menuContent: some View {
        switch layout {
        case .grid2x2:
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    MenuButton(
                        icon: "menu_spark",
                        text: "Spark",
                        color: ChoraiTheme.gold,
                        isEnabled: isSparkEnabled,
                        onTap: sparkCard
                    )
                    if isOwnCard {
                        MenuButton(
                            icon: "menu_share",
                            text: "Share",
                            color: ChoraiTheme.accent,
                            onTap: shareCard
                        )
                    } else {
                        MenuButton(
                            icon: "menu_report",
                            text: "Report",
                            color: ChoraiTheme.accent,
                            onTap: reportCard
                        )
                    }
                }
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_link", text: "Link", color: ChoraiTheme.accent, onTap: {
                        isPresented = false
                        LinkPopupManager.shared.show(
                            cardId: cardData?.id,
                            isInitiatingCardOwned: isOwnCard,
                            onNavigate: onNavigate
                        )
                    })
                    MenuButton(icon: isOwnCard ? "menu_view" : "menu_view", text: isOwnCard ? "Edit" : "View", color: ChoraiTheme.accent, onTap: {
                        isPresented = false
                        if isOwnCard {
                            if let cardId = cardData?.id {
                                onNavigate(.editor(cardId))
                            }
                        } else {
                            if let cardId = cardData?.id {
                                onNavigate(.detail(cardId))
                            }
                        }
                    })
                }
            }
        case .grid3x3:
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_view", text: "Edit", color: ChoraiTheme.accent, onTap: {
                        isPresented = false
                        if let cardId = cardData?.id {
                            onNavigate(.editor(cardId))
                        }
                    })
                    MenuButton(
                        icon: "menu_spark",
                        text: "Spark",
                        color: ChoraiTheme.gold,
                        isEnabled: isSparkEnabled,
                        onTap: sparkCard
                    )
                    MenuButton(icon: "menu_merge", text: "Merge", color: ChoraiTheme.gold, onTap: {
                        isPresented = false
                        if let cardId = cardData?.id {
                            onNavigate(.merge(cardId))
                        }
                    })
                }
                HStack(spacing: 15) {
                    if let card = cardData {
                        if !(ownedState?.isPublic ?? card.isPublic) {
                            MenuButton(icon: "open", text: "Public", color: ChoraiTheme.accent, onTap: {
                                toggleCardVisibility()
                            })
                        } else {
                            MenuButton(icon: "menu_private", text: "Private", color: ChoraiTheme.accent, onTap: {
                                toggleCardVisibility()
                            })
                        }
                    }

                    MenuButton(
                        icon: "menu_share",
                        text: "Share",
                        color: ChoraiTheme.accent,
                        onTap: shareCard
                    )
                    MenuButton(icon: "menu_link", text: "Link", color: ChoraiTheme.accent, onTap: {
                        isPresented = false
                        LinkPopupManager.shared.show(
                            cardId: cardData?.id,
                            isInitiatingCardOwned: isOwnCard,
                            onNavigate: onNavigate
                        )
                    })
                }
                HStack(spacing: 15) {
                    if let card = cardData {
                        MenuButton(icon: "menu_root", text: "Root", color: ChoraiTheme.accent, onTap: {
                            isPresented = false
                            onNavigate(.root(cardID: card.id, type: nil))
                        })
                    } else {
                    }

                    MenuButton(icon: "menu_remove", text: "Remove", color: .red, onTap: {
                        deleteCard()
                    })

                    // Pin/Unpin
                    if let card = cardData {
                        if ownedState?.isPinned ?? card.isPinned {
                            MenuButton(icon: "unpin", text: "Unpin", color: ChoraiTheme.gold, onTap: {
                                toggleCardPin()
                            })
                        } else {
                            MenuButton(icon: "menu_pin", text: "Pin", color: ChoraiTheme.gold, onTap: {
                                toggleCardPin()
                            })
                        }
                    }
                }
            }
        case .grid3x2:
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_view", text: "View", color: ChoraiTheme.accent, onTap: {
                        isPresented = false
                        if let cardId = cardData?.id {
                            onNavigate(.detail(cardId))
                        }
                    })
                    MenuButton(
                        icon: "menu_spark",
                        text: "Spark",
                        color: ChoraiTheme.gold,
                        isEnabled: isSparkEnabled,
                        onTap: sparkCard
                    )
                }
                HStack(spacing: 15) {
                    MenuButton(
                        icon: "menu_share",
                        text: "Share",
                        color: ChoraiTheme.accent,
                        onTap: shareCard
                    )
                    MenuButton(icon: "menu_link", text: "Link", color: ChoraiTheme.accent, onTap: {
                        isPresented = false
                        LinkPopupManager.shared.show(
                            cardId: cardData?.id,
                            isInitiatingCardOwned: isOwnCard,
                            onNavigate: onNavigate
                        )
                    })
                }
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_root", text: "Root", color: ChoraiTheme.accent, onTap: {
                        // grid3x2 布局来自 AIList，传递 type: "favourite"
                        if let cardId = cardData?.id {
                            isPresented = false
                            onNavigate(
                                .root(cardID: cardId, type: "favourite")
                            )
                        }
                    })
                    MenuButton(
                        icon: "menu_report",
                        text: "Report",
                        color: ChoraiTheme.accent,
                        onTap: reportCard
                    )
                }
            }
        }
    }

}

/// An anchored system menu for the approved card interaction. The surrounding
/// screen retains its existing popupMenu/cardNavigationHost solely as route owner.
struct NativeCardActionsMenu<LabelContent: View>: View {
    @Environment(\.noteAudiencePicker) private var audiencePicker
    @Environment(\.navigateCard) private var navigateCard
    @Environment(\.ownedCardActions) private var ownedActions
    @Environment(\.ownedCardActionCallbacks) private var inheritedCallbacks
    @Environment(\.ownedCardActionRevision) private var ownedActionRevision
    @Environment(\.ownedCardActionsAreLocked) private var ownedActionsAreLocked
    let cardData: UserCard
    let layout: PopupMenuLayout
    let isOwnCard: Bool
    let isSparkEnabled: Bool
    let onPrepare: (() -> Void)?
    let onSpark: (() -> Void)?
    let onDelete: (@MainActor @Sendable () -> Void)?
    let onToggleVisibility: (@MainActor @Sendable (UserCard, NotePrivacyObservation, Bool) -> Void)?
    let onTogglePin: (@MainActor @Sendable (UserCard) -> Void)?
    private let label: LabelContent

    init(
        cardData: UserCard,
        layout: PopupMenuLayout,
        isOwnCard: Bool,
        isSparkEnabled: Bool = true,
        onPrepare: (() -> Void)? = nil,
        onSpark: (() -> Void)? = nil,
        onDelete: (@MainActor @Sendable () -> Void)? = nil,
        onToggleVisibility: (@MainActor @Sendable (UserCard, NotePrivacyObservation, Bool) -> Void)? = nil,
        onTogglePin: (@MainActor @Sendable (UserCard) -> Void)? = nil,
        @ViewBuilder label: () -> LabelContent
    ) {
        self.cardData = cardData
        self.layout = layout
        self.isOwnCard = isOwnCard
        self.isSparkEnabled = isSparkEnabled
        self.onPrepare = onPrepare
        self.onSpark = onSpark
        self.onDelete = onDelete
        self.onToggleVisibility = onToggleVisibility
        self.onTogglePin = onTogglePin
        self.label = label()
    }

    var body: some View {
        let _ = ownedActionRevision
        return Menu {
            PopupMenuOverlay(
                isPresented: .constant(false),
                layout: layout,
                cardData: cardData,
                isOwnCard: isOwnCard,
                isSparkEnabled: isSparkEnabled,
                onSpark: onSpark,
                onDelete: onDelete ?? inheritedCallbacks.onDelete,
                onToggleVisibility: onToggleVisibility ?? inheritedCallbacks.onToggleVisibility,
                onTogglePin: onTogglePin ?? inheritedCallbacks.onTogglePin,
                ownedActions: ownedActions, audiencePicker: audiencePicker,
                onNavigate: navigateCard,
                onPrepare: onPrepare
            ).nativeMenuContent
        } label: {
            label
        }
        .tint(ChoraiTheme.ink)
        .disabled(ownedActionsAreLocked || ownedActions?.isRemoved(cardID: cardData.id) == true)
        .simultaneousGesture(TapGesture().onEnded { onPrepare?() })
    }
}

// MARK: - Menu Button
struct MenuButton: View {
    let icon: String
    let text: String
    let color: Color
    let isEnabled: Bool
    let onTap: (() -> Void)?

    init(
        icon: String,
        text: String,
        color: Color,
        isEnabled: Bool = true,
        onTap: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.text = text
        self.color = color
        self.isEnabled = isEnabled
        self.onTap = onTap
    }

    var body: some View {
        ActionBoxTile(
            icon: .asset(icon),
            text: text,
            color: color,
            isEnabled: isEnabled,
            accessibilityIdentifier: "popup-menu.item.\(text.lowercased().replacingOccurrences(of: " ", with: "-"))",
            action: onTap ?? {}
        )
    }
}

// MARK: - View Extension
extension View {
    func cardNavigationHost(
        ownedCardActionService: (any OwnedCardActionServing)? = nil,
        ownedCardActionRefresh: OwnedCardActionRefresh? = nil,
        ownedCardActionRefreshInFlight: Bool = false,
        onOwnedCardActionCommitted: @escaping (OwnedCardActionCommit) -> Void = { _ in }
    ) -> some View {
        modifier(CardNavigationHostModifier())
            .modifier(OwnedCardActionHostModifier(service: ownedCardActionService, authoritativeRefresh: ownedCardActionRefresh, refreshInFlight: ownedCardActionRefreshInFlight, onCommit: onOwnedCardActionCommitted))
    }

    func popupMenu(
        isPresented: Binding<Bool>,
        layout: PopupMenuLayout = .grid2x2,
        cardData: UserCard? = nil,
        isOwnCard: Bool = false,
        isSparkEnabled: Bool = true,
        onSpark: (() -> Void)? = nil,
        onDelete: (@MainActor @Sendable () -> Void)? = nil,
        onToggleVisibility: (@MainActor @Sendable (UserCard, NotePrivacyObservation, Bool) -> Void)? = nil,
        onTogglePin: (@MainActor @Sendable (UserCard) -> Void)? = nil,
        onRouteDismissed: @escaping (CardNavigationDismissal) -> Void = { _ in },
        onRoutePresentationChanged: @escaping (Bool) -> Void = { _ in },
        ownedCardActionService: (any OwnedCardActionServing)? = nil,
        ownedCardActionRefresh: OwnedCardActionRefresh? = nil,
        ownedCardActionRefreshInFlight: Bool = false,
        onOwnedCardActionCommitted: @escaping (OwnedCardActionCommit) -> Void = { _ in }
    ) -> some View {
        self.modifier(
            PopupMenuModifier(
                isPresented: isPresented,
                layout: layout,
                cardData: cardData,
                isOwnCard: isOwnCard,
                isSparkEnabled: isSparkEnabled,
                onSpark: onSpark,
                onDelete: onDelete,
                onToggleVisibility: onToggleVisibility,
                onTogglePin: onTogglePin,
                onRouteDismissed: onRouteDismissed,
                onRoutePresentationChanged: onRoutePresentationChanged
            )
        )
        .modifier(OwnedCardActionHostModifier(service: ownedCardActionService, authoritativeRefresh: ownedCardActionRefresh, refreshInFlight: ownedCardActionRefreshInFlight, onCommit: onOwnedCardActionCommitted))
    }
}

#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()

        VStack {
            Text("Test Content")
                .foregroundColor(ChoraiTheme.ink)

            Button("Show Popup Menu") {
                // This would be controlled by @State in real usage
            }
        }
    }
    .popupMenu(isPresented: .constant(true), layout: .grid2x2)
}

#if DEBUG
/// Exercises the real shared menu and its host without mounting Home or creating
/// a session. All action receipts are supplied by the process-local service.
struct OwnedCardActionFixtureScreen: View {
    @StateObject private var service = OwnedCardActionFixtureService()
    @State private var cards: [UserCard] = [
        OwnedCardActionFixtureScreen.fixtureCard("A"), OwnedCardActionFixtureScreen.fixtureCard("B")
    ]
    @State private var authoritativeRefresh: OwnedCardActionRefresh?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Memory service · no Home · no network")
                        .accessibilityIdentifier("owned.fixture.offline")
                    Text(String(service.requests.count))
                        .accessibilityLabel(String(service.requests.count))
                        .accessibilityIdentifier("owned.fixture.requests")
                    Text(service.requests.map(Self.describe).joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .accessibilityIdentifier("owned.fixture.history")
                }
                Section("Exact card targets") {
                    ForEach(cards) { card in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Note \(card.id)").font(.headline)
                                Text("\(card.isPublic ? "Public" : "Private"), \(card.isPinned ? "Pinned" : "Unpinned")")
                                    .accessibilityIdentifier("owned.fixture.state.\(card.id)")
                                OwnedCardActionFixtureCacheProbe(card: card)
                            }
                            Spacer()
                            NativeCardActionsMenu(cardData: card, layout: .grid3x3, isOwnCard: true, onSpark: {}) {
                                Image(systemName: "ellipsis").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Actions for Note \(card.id)")
                            .accessibilityIdentifier("owned.fixture.menu.\(card.id)")
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("owned.fixture.card.\(card.id)")
                    }
                }
                Section("Fixture controls") {
                    Button("Keep next visibility receipt private") {
                        service.nextVisibilityReceipt = false
                    }
                    .accessibilityIdentifier("owned.fixture.keep-private")
                    Button("Apply external edit: A private and unpinned") {
                        let card = Self.fixtureCard("A")
                        if let index = cards.firstIndex(where: { $0.id == "A" }) { cards[index] = card }
                        authoritativeRefresh = OwnedCardActionRefresh(snapshot: card.ownedActionSnapshot(isOwnCard: true))
                    }
                    .accessibilityIdentifier("owned.fixture.external-edit")
                }
            }
            .navigationTitle("Card action checks")
            // This harness only exercises mutations; other menu routes remain inert.
            .environment(\.navigateCard, { _ in })
            .cardNavigationHost(
                ownedCardActionService: service,
                ownedCardActionRefresh: authoritativeRefresh,
                onOwnedCardActionCommitted: apply
            )
        }
    }

    private func apply(_ commit: OwnedCardActionCommit) {
        guard let index = cards.firstIndex(where: { $0.id == commit.cardID }) else { return }
        let card = cards[index]
        switch commit {
        case .removed: cards.remove(at: index)
        case .visibility(_, let value):
            cards[index] = Self.fixtureCard(card.id, isPublic: value, isPinned: card.isPinned, pinnedAt: card.pinnedAt)
        case .pin(_, let value, let pinnedAt):
            cards[index] = Self.fixtureCard(card.id, isPublic: card.isPublic, isPinned: value, pinnedAt: pinnedAt)
        }
    }

    private static func describe(_ request: OwnedCardActionRequest) -> String {
        switch request.operation {
        case .remove: return "\(request.cardID):remove"
        case .setVisibility(let value): return "\(request.cardID):public:\(value)"
        case .setPinned(let value): return "\(request.cardID):pin:\(value)"
        }
    }

    private static func fixtureCard(_ id: String, isPublic: Bool = false, isPinned: Bool = false, pinnedAt: String? = nil) -> UserCard {
        UserCard(id: id, title: nil, content: "Owned action fixture \(id)", contentHash: "fixture-\(id)",
                 isPublic: isPublic, tags: [], createdAt: "2026-10-27T00:00:00Z", updatedAt: "2026-10-27T00:00:00Z",
                 likeCount: 0, commentCount: 0, isLiked: false, isPinned: isPinned, pinnedAt: pinnedAt,
                 isFavorited: false, favoriteCount: 0, rate: 0, ownerActorId: "fixture-owner", isOwner: true)
    }
}

private struct OwnedCardActionFixtureCacheProbe: View {
    @Environment(\.ownedCardActions) private var actions
    @Environment(\.ownedCardActionRevision) private var revision
    let card: UserCard

    var body: some View {
        let snapshot = card.ownedActionSnapshot(isOwnCard: true)
        let state = actions?.resolved(snapshot) ?? snapshot
        Text("\(state.isPublic ? "Public" : "Private"), \(state.isPinned ? "Pinned" : "Unpinned")")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("owned.fixture.cache.\(card.id)")
            .accessibilityValue(String(revision))
            .id(revision)
    }
}

@MainActor
private final class OwnedCardActionFixtureService: ObservableObject, OwnedCardActionServing {
    @Published private(set) var requests: [OwnedCardActionRequest] = []
    var nextVisibilityReceipt: Bool?
    private var failsFirstRemoval = true

    func perform(_ request: OwnedCardActionRequest) async throws -> OwnedCardActionCommit {
        requests.append(request)
        try await Task.sleep(nanoseconds: 150_000_000)
        switch request.operation {
        case .remove:
            if failsFirstRemoval {
                failsFirstRemoval = false
                throw OwnedCardActionError.requestFailed
            }
            return .removed(cardID: request.cardID)
        case .setVisibility(let value):
            let confirmedValue = nextVisibilityReceipt ?? value
            nextVisibilityReceipt = nil
            return .visibility(cardID: request.cardID, isPublic: confirmedValue)
        case .setPinned(let value):
            return .pin(cardID: request.cardID, isPinned: value, pinnedAt: value ? "fixture-confirmed" : nil)
        }
    }
}
#endif
