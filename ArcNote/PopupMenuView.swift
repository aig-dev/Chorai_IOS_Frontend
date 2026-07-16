import SwiftUI

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
    @Binding var isPresented: Bool
    let layout: PopupMenuLayout
    let cardData: UserCard?
    let isOwnCard: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isPresented {
                        PopupMenuOverlay(isPresented: $isPresented, layout: layout, cardData: cardData, isOwnCard: isOwnCard)
                    }
                }
            )
    }
}

// MARK: - PopupMenu Overlay
struct PopupMenuOverlay: View {
    @Binding var isPresented: Bool
    let layout: PopupMenuLayout
    let cardData: UserCard?
    let isOwnCard: Bool
    
    var body: some View {
        ActionBoxOverlay(
            isPresented: $isPresented,
            accessibilityLabel: "Card Actions",
            accessibilityIdentifier: "popup-menu.overlay",
            closeAccessibilityIdentifier: "popup-menu.close",
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
    
    // MARK: 菜单内容
    @ViewBuilder
    private var menuContent: some View {
        switch layout {
        case .grid2x2:
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_spark", text: "Spark", color: .red, onTap: {
                        isPresented = false
                        if let cardId = cardData?.id {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("NavigateToSpark"),
                                object: nil,
                                userInfo: ["cardId": cardId]
                            )
                        }
                    })
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
                        LinkPopupManager.shared.show(cardId: cardData?.id, isInitiatingCardOwned: isOwnCard)
                    })
                    MenuButton(icon: isOwnCard ? "menu_view" : "menu_view", text: isOwnCard ? "Edit" : "View", color: .blue, onTap: {
                        isPresented = false
                        if isOwnCard {
                            if let cardId = cardData?.id {
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("NavigateToEdit"),
                                    object: nil,
                                    userInfo: ["cardId": cardId]
                                )
                            }
                        } else {
                            if let cardId = cardData?.id {
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("NavigateToDetail"),
                                    object: nil,
                                    userInfo: ["cardId": cardId]
                                )
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
                            NotificationCenter.default.post(
                                name: NSNotification.Name("NavigateToEdit"),
                                object: nil,
                                userInfo: ["cardId": cardId]
                            )
                        }
                    })
                    MenuButton(icon: "menu_spark", text: "Spark", color: .red, onTap: {
                        isPresented = false
                        if let cardId = cardData?.id {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("NavigateToSpark"),
                                object: nil,
                                userInfo: ["cardId": cardId]
                            )
                        }
                    })
                    MenuButton(icon: "menu_merge", text: "Merge", color: .orange, onTap: {
                        isPresented = false
                        if let cardId = cardData?.id {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("NavigateToMerge"),
                                object: nil,
                                userInfo: ["cardId": cardId]
                            )
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
                        LinkPopupManager.shared.show(cardId: cardData?.id, isInitiatingCardOwned: isOwnCard)
                    })
                }
                HStack(spacing: 15) {
                    if let card = cardData {
                        MenuButton(icon: "menu_root", text: "Root", color: .teal, onTap: {
                            isPresented = false
                            NotificationCenter.default.post(
                                name: NSNotification.Name("NavigateToRoot"),
                                object: nil,
                                userInfo: ["cardId": card.id]
                            )
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
                            NotificationCenter.default.post(
                                name: NSNotification.Name("NavigateToDetail"),
                                object: nil,
                                userInfo: ["cardId": cardId]
                            )
                        }
                    })
                    MenuButton(icon: "menu_spark", text: "Spark", color: .red, onTap: {
                        isPresented = false
                        if let cardId = cardData?.id {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("NavigateToSpark"),
                                object: nil,
                                userInfo: ["cardId": cardId]
                            )
                        }
                    })
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
                        LinkPopupManager.shared.show(cardId: cardData?.id, isInitiatingCardOwned: isOwnCard)
                    })
                }
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_root", text: "Root", color: .teal, onTap: {
                        // grid3x2 布局来自 AIList，传递 type: "favourite"
                        if let cardId = cardData?.id {
                        isPresented = false
                            // 使用 NotificationCenter 发送导航通知
                            NotificationCenter.default.post(
                                name: NSNotification.Name("NavigateToRoot"),
                                object: nil,
                                userInfo: ["cardId": cardId, "type": "favourite"]
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
    let onTap: (() -> Void)?
    
    init(icon: String, text: String, color: Color, onTap: (() -> Void)? = nil) {
        self.icon = icon
        self.text = text
        self.color = color
        self.onTap = onTap
    }
    
    var body: some View {
        ActionBoxTile(
            icon: .asset(icon),
            text: text,
            color: color,
            accessibilityIdentifier: "popup-menu.item.\(text.lowercased().replacingOccurrences(of: " ", with: "-"))",
            action: onTap ?? {}
        )
    }
}

// MARK: - View Extension
extension View {
    func popupMenu(isPresented: Binding<Bool>, layout: PopupMenuLayout = .grid2x2, cardData: UserCard? = nil, isOwnCard: Bool = false) -> some View {
        self.modifier(PopupMenuModifier(isPresented: isPresented, layout: layout, cardData: cardData, isOwnCard: isOwnCard))
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
