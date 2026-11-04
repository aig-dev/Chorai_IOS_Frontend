import CoreFlow
import SwiftUI
import UIKit

struct SideMenuView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @Binding var isPresented: Bool
    @Environment(\.adaptiveLayoutMetrics) private var adaptiveLayout
    @State private var navigateToNotification = false
    @State private var navigateToTrash = false
    @State private var navigateToSettings = false
    @State private var navigateToMyProfile = false
    @State private var navigateToHelpReport = false
    @State private var pendingLibraryAction: LibraryAction?

    private enum LibraryAction { case notes, favorites }
    @ObservedObject private var userProfileManager: UserProfileManager
    @StateObject private var notificationStore = NotificationInboxStore(
        service: NetworkNotificationService()
    )
    private let loadsDataOnAppear: Bool

    // 回调函数
    var onMyNotesTapped: (() -> Void)?
    var onFavoritesTapped: (() -> Void)?

    init(
        isPresented: Binding<Bool>,
        userProfileManager: UserProfileManager = .shared,
        loadsDataOnAppear: Bool = true,
        onMyNotesTapped: (() -> Void)? = nil,
        onFavoritesTapped: (() -> Void)? = nil
    ) {
        _isPresented = isPresented
        _userProfileManager = ObservedObject(
            wrappedValue: userProfileManager
        )
        self.loadsDataOnAppear = loadsDataOnAppear
        self.onMyNotesTapped = onMyNotesTapped
        self.onFavoritesTapped = onFavoritesTapped
    }

    var body: some View {
        // Only the visual layer leaves this navigation host. Destination bindings
        // remain here so Settings/Profile return to this tab's still-open drawer.
        SidebarOverlayPresenter(
            isPresented: isPresented && !hasActiveDestination,
            drawerWidth: adaptiveLayout.drawerWidth,
            reduceMotion: reduceMotion,
            onClose: closeMenu,
            onDismiss: completeLibrarySelection,
            content: AnyView(
                drawerContent
                    .environment(\.colorScheme, colorScheme)
                    .environment(\.dynamicTypeSize, dynamicTypeSize)
                    .environment(\.adaptiveLayoutMetrics, adaptiveLayout)
            )
        )
        .frame(width: 0, height: 0)
        .navigationDestination(isPresented: $navigateToNotification) {
            NotificationView()
                .toolbar(.hidden, for: .tabBar)
        }
        .navigationDestination(isPresented: $navigateToTrash) {
            TrashView()
                .toolbar(.hidden, for: .tabBar)
        }
        .navigationDestination(isPresented: $navigateToSettings) {
            SettingsView()
                .toolbar(.hidden, for: .tabBar)
        }
        .navigationDestination(isPresented: $navigateToMyProfile) {
            MyProfileView(
                userProfileManager: userProfileManager,
                loadsDataOnAppear: loadsDataOnAppear
            )
            .toolbar(.hidden, for: .tabBar)
        }
        .navigationDestination(isPresented: $navigateToHelpReport) {
            WebViewPage(
                url: ChoraiWebDestination.report,
                title: "Help & Report"
            )
            .toolbar(.hidden, for: .tabBar)
        }
        .onAppear {
            // 当侧边栏出现时加载用户资料
            if isPresented, loadsDataOnAppear {
                userProfileManager.fetchCurrentUserProfile()
                refreshNotificationIndicator()
            }
        }
        .onChange(of: isPresented) { isShowing in
            if isShowing { pendingLibraryAction = nil }
            // 当侧边栏显示时加载用户资料
            if isShowing, loadsDataOnAppear {
                userProfileManager.fetchCurrentUserProfile()
                refreshNotificationIndicator()
            }
        }
    }

    private var hasActiveDestination: Bool {
        navigateToNotification || navigateToTrash || navigateToSettings
            || navigateToMyProfile || navigateToHelpReport
    }

    private var drawerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: closeMenu) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close menu")
                    .accessibilityIdentifier("side-menu.close")
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                profileSummary
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                Divider()
                    .overlay(ChoraiTheme.separator)
                    .padding(.horizontal, 24)

                VStack(spacing: 4) {
                    SideMenuItem(imageName: "mynotes", title: "My Notes") {
                        selectLibrary(.notes)
                    }
                    SideMenuItem(imageName: "favorites", title: "Favorites") {
                        selectLibrary(.favorites)
                    }
                    SideMenuItem(
                        imageName: "notification",
                        title: "Notification",
                        accessibilityIdentifier: "side-menu.notification",
                        showsUnreadIndicator: notificationStore.unreadCount > 0
                    ) {
                        navigateToNotification = true
                    }
                    SideMenuItem(imageName: "trash", title: "Trash") {
                        navigateToTrash = true
                    }
                    SideMenuItem(imageName: "settings", title: "Settings", accessibilityIdentifier: "side-menu.settings") {
                        navigateToSettings = true
                    }
                    SideMenuItem(imageName: "help", title: "Help & Report") {
                        navigateToHelpReport = true
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .background {
            if reduceTransparency || contrast == .increased {
                ChoraiTheme.background.ignoresSafeArea()
            } else {
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
                    .overlay(ChoraiTheme.background.opacity(0.88).ignoresSafeArea())
            }
        }
        .overlay(alignment: .trailing) {
            ChoraiTheme.separator.opacity(0.55).frame(width: 0.5).ignoresSafeArea()
        }
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adaptive-layout.drawer")
    }

    private var profileSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Button {
                    navigateToMyProfile = true
                } label: {
                    Group {
                        if let avatarURL = profileResourceURL(
                            userProfileManager.userProfile?.avatar
                        ) {
                            AsyncImage(url: avatarURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image("avatar").resizable().aspectRatio(contentMode: .fill)
                            }
                        } else {
                            Image("avatar").resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("My profile")
                .accessibilityIdentifier("side-menu.profile")

                Text(userProfileManager.userProfile?.username ?? "Loading...")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Image(systemName: "gift")
                    .foregroundStyle(ChoraiTheme.gold)
                Text(creditText)
                    .fontWeight(.semibold)
                    .foregroundStyle(ChoraiTheme.gold)
                Text("Credits")
            }
            .font(.subheadline)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                userProfileManager.creditBalance == nil
                    ? "Loading Credits"
                    : "\(userProfileManager.creditTotal) Credits"
            )
            .accessibilityIdentifier("side-menu.credit-balance")

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(userProfileManager.userProfile.map { "\($0.followingCount ?? 0)" } ?? "--")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ChoraiTheme.ink)
                    Text("following")
                        .font(.subheadline)
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    Text(userProfileManager.userProfile.map { "\($0.followersCount ?? 0)" } ?? "--")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ChoraiTheme.ink)
                    Text("followers")
                        .font(.subheadline)
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var creditText: String {
        userProfileManager.creditBalance.map { "\($0.balance)" } ?? "--"
    }

    private func closeMenu() {
        isPresented = false
    }

    private func selectLibrary(_ action: LibraryAction) {
        pendingLibraryAction = action
        closeMenu()
    }

    private func completeLibrarySelection() {
        guard !isPresented, let action = pendingLibraryAction else { return }
        pendingLibraryAction = nil
        switch action {
        case .notes: onMyNotesTapped?()
        case .favorites: onFavoritesTapped?()
        }
    }

    private func profileResourceURL(_ rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmedValue = rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedValue.isEmpty else { return nil }
        return URL(string: APIConfiguration.resourceURLString(trimmedValue))
    }

    private func refreshNotificationIndicator() {
        guard let actorID = AuthManager.shared.currentUser?.id,
              !actorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        notificationStore.load(actorID: actorID)
    }
}

// A scene-bound overlay covers the bars without changing their visibility or
// safe areas. Its window cannot become key and never owns navigation destinations.
private struct SidebarOverlayPresenter: UIViewControllerRepresentable {
    let isPresented: Bool
    let drawerWidth: CGFloat
    let reduceMotion: Bool
    let onClose: () -> Void
    let onDismiss: () -> Void
    let content: AnyView

    func makeUIViewController(context: Context) -> SidebarOverlayAnchorController {
        SidebarOverlayAnchorController()
    }

    func updateUIViewController(_ controller: SidebarOverlayAnchorController, context: Context) {
        controller.update(self)
    }

    static func dismantleUIViewController(_ controller: SidebarOverlayAnchorController, coordinator: ()) {
        controller.removeOverlay()
    }
}

private final class SidebarOverlayAnchorController: UIViewController {
    private var configuration: SidebarOverlayPresenter?
    private var overlay: SidebarOverlayController?
    private var overlayWindow: SidebarOverlayWindow?
    private weak var presentingWindow: UIWindow?
    private var previousAccessibilityHidden = false
    private var isAnchorVisible = false
    private var isOverlayVisible = false
    private var transitionID = 0

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isAnchorVisible = true
        reconcilePresentation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isAnchorVisible = false
        reconcilePresentation()
    }

    func update(_ configuration: SidebarOverlayPresenter) {
        self.configuration = configuration
        overlay?.update(content: configuration.content, width: configuration.drawerWidth, onClose: configuration.onClose)
        reconcilePresentation()
    }

    private func reconcilePresentation() {
        guard let configuration else { return }
        let shouldShow = configuration.isPresented && isAnchorVisible && view.window != nil
        guard shouldShow != isOverlayVisible else { return }
        isOverlayVisible = shouldShow
        transitionID += 1
        let currentTransition = transitionID

        if shouldShow, overlay == nil {
            guard let sourceWindow = view.window,
                  let scene = sourceWindow.windowScene else {
                isOverlayVisible = false
                return
            }
            let controller = SidebarOverlayController(content: configuration.content, width: configuration.drawerWidth, onClose: configuration.onClose)
            let window = SidebarOverlayWindow(windowScene: scene)
            window.frame = sourceWindow.frame
            window.windowLevel = sourceWindow.windowLevel + 1
            window.backgroundColor = .clear
            window.rootViewController = controller
            presentingWindow = sourceWindow
            previousAccessibilityHidden = sourceWindow.accessibilityElementsHidden
            sourceWindow.accessibilityElementsHidden = true
            // Adding UIKit subviews to SwiftUI's root hosting view is unsupported.
            // A non-key window owns this visual layer without disturbing that view.
            window.isHidden = false
            controller.view.layoutIfNeeded()
            controller.setProgress(isVisible: false)
            overlay = controller
            overlayWindow = window
        }
        guard let overlay else { return }
        overlay.setControlsEnabled(shouldShow)
        let duration = configuration.reduceMotion ? 0 : 0.24
        UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]) {
            overlay.setProgress(isVisible: shouldShow)
        } completion: { [weak self] _ in
            guard let self, self.transitionID == currentTransition else { return }
            if !shouldShow {
                self.removeOverlay()
                // End the transition before changing the selected tab. No guessed
                // delay can replay a stale selection after another interaction.
                DispatchQueue.main.async { [weak self] in
                    self?.configuration?.onDismiss()
                }
            } else {
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
    }

    func removeOverlay() {
        transitionID += 1
        overlayWindow?.isHidden = true
        overlayWindow?.rootViewController = nil
        overlayWindow = nil
        overlay = nil
        if let presentingWindow {
            presentingWindow.accessibilityElementsHidden = previousAccessibilityHidden
        }
        presentingWindow = nil
        isOverlayVisible = false
    }
}

private final class SidebarOverlayWindow: UIWindow {
    override var canBecomeKey: Bool { false }
}

private final class SidebarOverlayController: UIViewController {
    private let dimmer = UIControl()
    private let drawer = UIView()
    private let host: UIHostingController<AnyView>
    private var drawerWidth: CGFloat
    private var onClose: () -> Void

    init(content: AnyView, width: CGFloat, onClose: @escaping () -> Void) {
        host = UIHostingController(rootView: content)
        drawerWidth = width
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        view.accessibilityIdentifier = "side-menu.presentation"
        dimmer.backgroundColor = .black
        dimmer.isAccessibilityElement = false
        dimmer.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(dimmer)
        drawer.layer.shadowColor = UIColor.black.cgColor
        drawer.layer.shadowOpacity = 0.12
        drawer.layer.shadowRadius = 16
        drawer.layer.shadowOffset = CGSize(width: 4, height: 0)
        view.addSubview(drawer)
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.layer.cornerRadius = 22
        host.view.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        host.view.clipsToBounds = true
        drawer.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dimmer.frame = view.bounds
        // Bounds and center keep layout independent of the animated transform.
        drawer.bounds = CGRect(x: 0, y: 0, width: drawerWidth, height: view.bounds.height)
        drawer.center = CGPoint(x: drawerWidth / 2, y: view.bounds.midY)
        host.view.frame = drawer.bounds
        drawer.layer.shadowPath = UIBezierPath(rect: drawer.bounds).cgPath
    }

    func update(content: AnyView, width: CGFloat, onClose: @escaping () -> Void) {
        host.rootView = content
        drawerWidth = width
        self.onClose = onClose
        view.setNeedsLayout()
    }

    func setControlsEnabled(_ enabled: Bool) {
        // The full-window view keeps absorbing input until it is removed.
        // Only its controls stop accepting taps while the drawer slides away.
        dimmer.isUserInteractionEnabled = enabled
        drawer.isUserInteractionEnabled = enabled
    }

    func setProgress(isVisible: Bool) {
        dimmer.alpha = isVisible ? 0.22 : 0
        drawer.transform = isVisible ? .identity : CGAffineTransform(translationX: -drawerWidth - 20, y: 0)
    }

    @objc private func close() { onClose() }
}

struct SideMenuItem: View {
    let imageName: String
    let title: String
    let accessibilityIdentifier: String?
    let showsUnreadIndicator: Bool
    let action: () -> Void

    init(
        imageName: String,
        title: String,
        accessibilityIdentifier: String? = nil,
        showsUnreadIndicator: Bool = false,
        action: @escaping () -> Void
    ) {
        self.imageName = imageName
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.showsUnreadIndicator = showsUnreadIndicator
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: ChoraiSymbols.name(for: imageName))
                    .font(.body)
                    .frame(width: 24)
                    .foregroundColor(ChoraiTheme.ink)

                Text(title)
                    .font(.body)
                    .foregroundColor(ChoraiTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if showsUnreadIndicator {
                    Circle()
                        .fill(ChoraiTheme.gold)
                        .frame(width: 6, height: 6)
                        .accessibilityIdentifier("side-menu.notification-unread")
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showsUnreadIndicator ? "Unread notifications" : "")
        .accessibilityIdentifier(accessibilityIdentifier ?? "side-menu.item.\(title)")
    }
}

// 自定义圆角形状，支持只设置部分圆角
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}


#Preview {
    SideMenuView(isPresented: .constant(true))
}
