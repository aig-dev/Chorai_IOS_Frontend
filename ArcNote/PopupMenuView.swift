import CoreFlow
import SwiftUI

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
    static let defaultValue: (CardNavigationRoute) -> Void = { _ in }
}

private struct CardNavigationOnboardingStoreKey: EnvironmentKey {
    static let defaultValue: OnboardingGuideStore? = nil
}

private struct CardNavigationContextualTipStoreKey: EnvironmentKey {
    static let defaultValue: ContextualGuideTipStore? = nil
}

private struct CardNavigationRoutePresentationChangedKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    var navigateCard: (CardNavigationRoute) -> Void {
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

    var cardNavigationRoutePresentationChanged: (Bool) -> Void {
        get { self[CardNavigationRoutePresentationChangedKey.self] }
        set { self[CardNavigationRoutePresentationChangedKey.self] = newValue }
    }
}

private struct CardNavigationDestination: View {
    let route: CardNavigationRoute
    let onboardingStore: OnboardingGuideStore?
    let contextualTipStore: ContextualGuideTipStore?
    let routePresentationChanged: (Bool) -> Void

    var body: some View {
        destination
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
            .environment(\.navigateCard, present)
            .navigationDestination(isPresented: isPresentingRoute) {
                if let presentedRoute {
                    CardNavigationDestination(
                        route: presentedRoute,
                        onboardingStore: onboardingStore,
                        contextualTipStore: contextualTipStore,
                        routePresentationChanged: routePresentationChanged
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
    let scale: CGFloat
    
    func body(content: Content) -> some View {
        content.scaleEffect(scale)
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
    @Environment(\.cardNavigationOnboardingStore) private var onboardingStore
    @Environment(\.cardNavigationContextualTipStore) private var contextualTipStore
    @State private var presentedRoute: CardNavigationRoute?
    @Binding var isPresented: Bool
    let layout: PopupMenuLayout
    let cardData: UserCard?
    let isOwnCard: Bool
    let isSparkEnabled: Bool
    let onSpark: (() -> Void)?
    let onRouteDismissed: (CardNavigationDismissal) -> Void
    let onRoutePresentationChanged: (Bool) -> Void

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
        content
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
                            onNavigate: present
                        )
                    }
                }
            )
            .environment(\.navigateCard, present)
            .navigationDestination(isPresented: isPresentingRoute) {
                if let presentedRoute {
                    CardNavigationDestination(
                        route: presentedRoute,
                        onboardingStore: onboardingStore,
                        contextualTipStore: contextualTipStore,
                        routePresentationChanged:
                            onRoutePresentationChanged
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
    @Binding var isPresented: Bool
    let layout: PopupMenuLayout
    let cardData: UserCard?
    let isOwnCard: Bool
    let isSparkEnabled: Bool
    let onSpark: (() -> Void)?
    let onNavigate: (CardNavigationRoute) -> Void

    init(
        isPresented: Binding<Bool>,
        layout: PopupMenuLayout,
        cardData: UserCard?,
        isOwnCard: Bool,
        isSparkEnabled: Bool = true,
        onSpark: (() -> Void)? = nil,
        onNavigate: @escaping (CardNavigationRoute) -> Void = { _ in }
    ) {
        _isPresented = isPresented
        self.layout = layout
        self.cardData = cardData
        self.isOwnCard = isOwnCard
        self.isSparkEnabled = isSparkEnabled
        self.onSpark = onSpark
        self.onNavigate = onNavigate
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
    
    // MARK: - 删除卡片功能
    private func deleteCard() {
        NotificationCenter.default.post(
            name: NSNotification.Name("DeleteCard"),
            object: nil
        )
        
        isPresented = false
    }
    
    // MARK: - 切换卡片可见性
    private func toggleCardVisibility() {
        guard let card = cardData else { return }
        
        // 通过通知通知HomeView切换卡片可见性
        NotificationCenter.default.post(
            name: NSNotification.Name("ToggleCardVisibility"),
            object: nil,
            userInfo: ["cardId": card.id, "isPublic": card.isPublic]
        )
        
        // 关闭菜单
        isPresented = false
    }
    
    // MARK: 切换卡片Pin状态
    private func toggleCardPin() {
        guard let card = cardData else { return }
        
        
        // 切换卡片Pin状态
        NotificationCenter.default.post(
            name: NSNotification.Name("ToggleCardPin"),
            object: nil,
            userInfo: ["cardId": card.id, "isPinned": card.isPinned]
        )
        
        // 关闭菜单
        isPresented = false
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
                        color: .red,
                        isEnabled: isSparkEnabled,
                        onTap: sparkCard
                    )
                    if isOwnCard {
                        MenuButton(
                            icon: "menu_share",
                            text: "Share",
                            color: .green,
                            onTap: shareCard
                        )
                    } else {
                        MenuButton(
                            icon: "menu_report",
                            text: "Report",
                            color: .green,
                            onTap: reportCard
                        )
                    }
                }
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_link", text: "Link", color: .pink, onTap: {
                        isPresented = false
                        LinkPopupManager.shared.show(
                            cardId: cardData?.id,
                            isInitiatingCardOwned: isOwnCard,
                            onNavigate: onNavigate
                        )
                    })
                    MenuButton(icon: isOwnCard ? "menu_view" : "menu_view", text: isOwnCard ? "Edit" : "View", color: .blue, onTap: {
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
                    MenuButton(icon: "menu_view", text: "Edit", color: .blue, onTap: {
                        isPresented = false
                        if let cardId = cardData?.id {
                            onNavigate(.editor(cardId))
                        }
                    })
                    MenuButton(
                        icon: "menu_spark",
                        text: "Spark",
                        color: .red,
                        isEnabled: isSparkEnabled,
                        onTap: sparkCard
                    )
                    MenuButton(icon: "menu_merge", text: "Merge", color: .orange, onTap: {
                        isPresented = false
                        if let cardId = cardData?.id {
                            onNavigate(.merge(cardId))
                        }
                    })
                }
                HStack(spacing: 15) {
                    if let card = cardData {
                        if !card.isPublic {
                            MenuButton(icon: "open", text: "Public", color: .purple, onTap: {
                                toggleCardVisibility()
                            })
                        } else {
                            MenuButton(icon: "menu_private", text: "Private", color: .purple, onTap: {
                                toggleCardVisibility()
                            })
                        }
                    }
                    
                    MenuButton(
                        icon: "menu_share",
                        text: "Share",
                        color: .green,
                        onTap: shareCard
                    )
                    MenuButton(icon: "menu_link", text: "Link", color: .pink, onTap: {
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
                        MenuButton(icon: "menu_root", text: "Root", color: .teal, onTap: {
                            isPresented = false
                            onNavigate(.root(cardID: card.id, type: nil))
                        })
                    } else {
                    }
                    
                    MenuButton(icon: "menu_remove", text: "Remove", color: .orange, onTap: {
                        deleteCard()
                    })
                    
                    // Pin/Unpin
                    if let card = cardData {
                        if card.isPinned {
                            MenuButton(icon: "unpin", text: "Unpin", color: .orange, onTap: {
                                toggleCardPin()
                            })
                        } else {
                            MenuButton(icon: "menu_pin", text: "Pin", color: .orange, onTap: {
                                toggleCardPin()
                            })
                        }
                    }
                }
            }
        case .grid3x2:
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_view", text: "View", color: .blue, onTap: {
                        isPresented = false
                        if let cardId = cardData?.id {
                            onNavigate(.detail(cardId))
                        }
                    })
                    MenuButton(
                        icon: "menu_spark",
                        text: "Spark",
                        color: .red,
                        isEnabled: isSparkEnabled,
                        onTap: sparkCard
                    )
                }
                HStack(spacing: 15) {
                    MenuButton(
                        icon: "menu_share",
                        text: "Share",
                        color: .green,
                        onTap: shareCard
                    )
                    MenuButton(icon: "menu_link", text: "Link", color: .pink, onTap: {
                        isPresented = false
                        LinkPopupManager.shared.show(
                            cardId: cardData?.id,
                            isInitiatingCardOwned: isOwnCard,
                            onNavigate: onNavigate
                        )
                    })
                }
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_root", text: "Root", color: .teal, onTap: {
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
                        color: .green,
                        onTap: reportCard
                    )
                }
            }
        }
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
    func cardNavigationHost() -> some View {
        modifier(CardNavigationHostModifier())
    }

    func popupMenu(
        isPresented: Binding<Bool>,
        layout: PopupMenuLayout = .grid2x2,
        cardData: UserCard? = nil,
        isOwnCard: Bool = false,
        isSparkEnabled: Bool = true,
        onSpark: (() -> Void)? = nil,
        onRouteDismissed: @escaping (CardNavigationDismissal) -> Void = { _ in },
        onRoutePresentationChanged: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        self.modifier(
            PopupMenuModifier(
                isPresented: isPresented,
                layout: layout,
                cardData: cardData,
                isOwnCard: isOwnCard,
                isSparkEnabled: isSparkEnabled,
                onSpark: onSpark,
                onRouteDismissed: onRouteDismissed,
                onRoutePresentationChanged: onRoutePresentationChanged
            )
        )
    }
}

#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()
        
        VStack {
            Text("Test Content")
                .foregroundColor(.white)
            
            Button("Show Popup Menu") {
                // This would be controlled by @State in real usage
            }
        }
    }
    .popupMenu(isPresented: .constant(true), layout: .grid2x2)
}
