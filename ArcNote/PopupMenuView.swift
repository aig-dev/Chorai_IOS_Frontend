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
}

// MARK: - PopupMenu Modifier
struct PopupMenuModifier: ViewModifier {
    @Binding var isPresented: Bool
    let layout: PopupMenuLayout
    let cardData: UserCard?
    let isOwnCard: Bool
    let searchType: String
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isPresented {
                        PopupMenuOverlay(isPresented: $isPresented, layout: layout, cardData: cardData, isOwnCard: isOwnCard, searchType: searchType)
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
    let searchType: String
    @State private var navigateToEdit = false
    @State private var navigateToSpark = false
    @State private var navigateToMerge = false
    @State private var navigateToRoot = false
    @State private var rootViewType: String? = nil
    @State private var rootCardId: Int? = nil
    @State private var navigateToDetail = false
    @State private var navigateToReport = false
    @State private var animateContent = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 半透明背景遮罩 - 带渐变动画
                Color.black
                    .opacity(animateContent ? 0.5 : 0)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            animateContent = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isPresented = false
                            }
                        }
                    }
                
                // 菜单内容 - 居中显示，带渐变动画
                ZStack {
                    // 关闭按钮 - 绝对定位在右上角
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    animateContent = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        isPresented = false
                                    }
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        
                        Spacer()
                    }
                    
                    // 菜单选项网格 - 根据布局类型显示不同内容
                    menuContent
                        .padding(.horizontal, 0)
                }
                .background(menuBackground)
                .cornerRadius(20)
                .frame(width: geometry.size.width * 0.9, height: geometry.size.width * 0.9)
                .clipped()
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2.2)
                .opacity(animateContent ? 1 : 0)
                .scaleEffect(animateContent ? 1 : 0.8)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                animateContent = true
            }
        }
        .background(
            NavigationLink(destination: NewNoteView(cardId: cardData?.id ?? 0), isActive: $navigateToEdit) {
                EmptyView()
            }
        )
        .background(
            NavigationLink(destination: SparkView(cardId: cardData?.id ?? 0), isActive: $navigateToSpark) {
                EmptyView()
            }
        )
        .background(
            NavigationLink(destination: MergeView(cardId: cardData?.id ?? 0), isActive: $navigateToMerge) {
                EmptyView()
            }
        )
        .background(
            // 创建一个包装视图来确保 destination 使用最新的状态值
            RootNavigationLink(
                isActive: $navigateToRoot,
                cardId: rootCardId ?? cardData?.id ?? 0,
                type: rootViewType
            )
        )
        .background(
            NavigationLink(destination: DetailView(cardId: cardData?.id ?? 0), isActive: $navigateToDetail) {
                EmptyView()
            }
        )
        .background(
            NavigationLink(destination: WebViewPage(url: URL(string: "https://www.chorai.app/report")!, title: "Help & Report"), isActive: $navigateToReport) {
                EmptyView()
            }
        )
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
    
    // MARK: 菜单内容
    @ViewBuilder
    private var menuContent: some View {
        switch layout {
        case .grid2x2:
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_spark", text: "Spark", color: .red, onTap: {
                        isPresented = false
                        navigateToSpark = true
                    })
                    MenuButton(icon: "menu_report", text: "Report", color: .green, onTap: {
                        isPresented = false
                        navigateToReport = true
                    })
                }
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_link", text: "Link", color: .pink, onTap: {
                        isPresented = false
                        LinkPopupManager.shared.show(cardId: cardData?.id, searchType: searchType)
                    })
                    MenuButton(icon: isOwnCard ? "menu_view" : "menu_view", text: isOwnCard ? "Edit" : "View", color: .blue, onTap: {
                        isPresented = false
                        if isOwnCard {
                            navigateToEdit = true
                        } else {
                            navigateToDetail = true
                        }
                    })
                }
            }
        case .grid3x3:
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_view", text: "Edit", color: .blue, onTap: {
                        isPresented = false
                        navigateToEdit = true
                    })
                    MenuButton(icon: "menu_spark", text: "Spark", color: .red, onTap: {
                        isPresented = false
                        navigateToSpark = true
                    })
                    MenuButton(icon: "menu_merge", text: "Merge", color: .orange, onTap: {
                        isPresented = false
                        navigateToMerge = true
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
                    } else {
                        MenuButton(icon: "menu_private", text: "Private", color: .purple)
                    }
                    
                    MenuButton(icon: "menu_share", text: "Share", color: .green)
                    MenuButton(icon: "menu_link", text: "Link", color: .pink, onTap: {
                        isPresented = false
                        LinkPopupManager.shared.show(cardId: cardData?.id, searchType: searchType)
                    })
                }
                HStack(spacing: 15) {
                    if let card = cardData, card.rate >= 2 {
                        MenuButton(icon: "menu_root", text: "Root", color: .teal, onTap: {
                            isPresented = false
                            // 发送导航通知
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
                    } else {
                        MenuButton(icon: "menu_pin", text: "Pin", color: .orange)
                    }
                    if let card = cardData, card.rate < 2 {
                        VStack(spacing: 6) {
                            Color.clear
                                .frame(width: 38, height: 33)
                            
                            Text("")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .frame(width: 90, height: 90)
                    }
                    
                }
            }
        case .grid3x2:
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_view", text: "View", color: .blue, onTap: {
                        isPresented = false
                        navigateToDetail = true
                    })
                    MenuButton(icon: "menu_spark", text: "Spark", color: .red, onTap: {
                        isPresented = false
                        navigateToSpark = true
                    })
                }
                HStack(spacing: 15) {
                    MenuButton(icon: "menu_share", text: "Share", color: .green)
                    MenuButton(icon: "menu_link", text: "Link", color: .pink, onTap: {
                        isPresented = false
                        LinkPopupManager.shared.show(cardId: cardData?.id, searchType: searchType)
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
                    MenuButton(icon: "menu_pin", text: "Pin", color: .orange)
                }
            }
        }
    }
    
    // MARK: - 菜单背景
    private var menuBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial.opacity(1))
            .overlay(menuTopLeftHighlight)
            .overlay(menuBottomRightHighlight)
            .overlay(menuTopEdgeHighlight)
            .overlay(menuBottomEdgeHighlight)
    }
    
    // MARK: - 高光效果
    private var menuTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var menuBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var menuTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var menuBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
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
        VStack(spacing: 6) {
            Image(icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 38, height: 33)
                .foregroundColor(color)
            
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .frame(width: 90, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 177/255, green: 177/255, blue: 177/255, opacity: 10/100))
        )
        .onTapGesture {
            if let onTap = onTap {
                onTap()
            } else {
                // 默认处理按钮点击事件
                print("\(text) button tapped")
            }
        }
    }
}

// MARK: - Root Navigation Link Wrapper
struct RootNavigationLink: View {
    @Binding var isActive: Bool
    let cardId: Int
    let type: String?
    
    var body: some View {
        NavigationLink(
            destination: {
                print("创建 destination: cardId = \(cardId), type = \(type ?? "nil")")
                return RootView(cardId: cardId, type: type)
            }(),
            isActive: $isActive
        ) {
            EmptyView()
        }
        .onChange(of: isActive) { newValue in
            print("isActive 变化: \(newValue), cardId = \(cardId), type = \(type ?? "nil")")
        }
    }
}

// MARK: - View Extension
extension View {
    func popupMenu(isPresented: Binding<Bool>, layout: PopupMenuLayout = .grid2x2, cardData: UserCard? = nil, isOwnCard: Bool = false, searchType: String = "own+favorited") -> some View {
        self.modifier(PopupMenuModifier(isPresented: isPresented, layout: layout, cardData: cardData, isOwnCard: isOwnCard, searchType: searchType))
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
