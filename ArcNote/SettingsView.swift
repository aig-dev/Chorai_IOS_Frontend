import SwiftUI
import Combine

// MARK: - 圆角按钮高光效果
extension View {
    func roundedButtonHighlightEffect(cornerRadius: CGFloat = 20) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(ChoraiTheme.separator, lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
}

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var showLogoutAlert = false
    @State private var navigateToAccountDetails = false
    @State private var navigateToEditProfile = false
    @State private var navigateToChoraProfile = false
    @State private var navigateToInvitationCredits = false
    @ObservedObject private var userProfileManager = UserProfileManager.shared
    @ObservedObject private var authManager = AuthManager.shared
    @State private var cancellables = Set<AnyCancellable>()
    @State private var isLoggingOut = false
    @State private var logoutError: String?
    private let loadsProfileOnAppear: Bool
    private let choraProfileDestination: (() -> AnyView)?
    private let invitationCreditDestination: (() -> AnyView)?

    init(
        loadsProfileOnAppear: Bool = true,
        choraProfileDestination: (() -> AnyView)? = nil,
        invitationCreditDestination: (() -> AnyView)? = nil
    ) {
        self.loadsProfileOnAppear = loadsProfileOnAppear
        self.choraProfileDestination = choraProfileDestination
        self.invitationCreditDestination = invitationCreditDestination
    }

    var body: some View {
        Form {
            Section {
                SettingsRow(imageName: "personal", title: "Personal Data", accessibilityIdentifier: "settings.personal-data") {
                    navigateToEditProfile = true
                }
                SettingsRow(imageName: "bot", title: "Chora Profile", accessibilityIdentifier: "settings.choraProfile") {
                    navigateToChoraProfile = true
                }
                SettingsRow(
                    imageName: "syn", title: "Invitations & Credits",
                    subtitle: userProfileManager.isCreditLoading
                        ? "Loading…" : "\(userProfileManager.creditTotal.formatted()) Credits",
                    accessibilityIdentifier: "settings.invitation-credits"
                ) {
                    navigateToInvitationCredits = true
                }
                SettingsRow(imageName: "account", title: "Account & Privacy", accessibilityIdentifier: "settings.account-privacy") {
                    navigateToAccountDetails = true
                }
            }
            .listRowBackground(ChoraiTheme.surface)

            Section {
                Button(role: .destructive) { showLogoutAlert = true } label: {
                    HStack {
                        Text("Log Out")
                        Spacer()
                        if isLoggingOut { ProgressView() }
                    }
                    .frame(minHeight: 44)
                }
                .disabled(isLoggingOut)
                .accessibilityIdentifier("settings.logout")

                if let logoutError {
                    Text(logoutError)
                        .font(.footnote)
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                        .accessibilityIdentifier("settings.logout.error")
                }
            } footer: {
                Text("Your notes stay yours. We never sell your data or run ads.")
                    .accessibilityIdentifier("settings.footer")
            }
            .listRowBackground(ChoraiTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .choraiPageBackground()
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                Text("Settings loaded")
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("screen.settings.loaded")
                #if DEBUG
                Text(loadsProfileOnAppear ? "enabled" : "disabled")
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("settings.profile.autoload")
                #endif
            }
        }
        .alert("Log Out", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                performLogout()
            }
        } message: {
            Text("Are you sure you want to log out?")
        }
        .navigationDestination(isPresented: $navigateToAccountDetails) {
            AccountPrivacyView()
        }
        .navigationDestination(isPresented: $navigateToEditProfile) {
            EditProfileView(loadsProfileOnAppear: loadsProfileOnAppear) {
                navigateToEditProfile = false
            }
        }
        .navigationDestination(isPresented: $navigateToChoraProfile) {
            if let choraProfileDestination {
                choraProfileDestination()
            } else {
                ChoraProfileView.production(
                    humanActorID: authManager.currentUser?.id ?? ""
                )
            }
        }
        .navigationDestination(isPresented: $navigateToInvitationCredits) {
            if let invitationCreditDestination {
                invitationCreditDestination()
            } else {
                InvitationCreditView.production(
                    actorID: authManager.currentUser?.id ?? ""
                )
            }
        }
        .onAppear {
            if loadsProfileOnAppear {
                userProfileManager.fetchCurrentUserProfile()
            }
        }
    }

    // MARK: - 执行登出
    private func performLogout() {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        logoutError = nil

        authManager.logoutCurrentSession()
            .sink { completion in
                isLoggingOut = false
                if case .failure = completion {
                    logoutError = "Couldn’t log out. Try again."
                }
            } receiveValue: {
                // AuthManager publishes signed-out state; ContentView replaces
                // the root. Pop this destination to reveal that new root.
                DispatchQueue.main.async {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .store(in: &cancellables)
    }
}

struct SettingsRow: View {
    let imageName: String
    let title: String
    let subtitle: String?
    let accessibilityIdentifier: String?
    let action: () -> Void

    init(imageName: String, title: String, subtitle: String? = nil, accessibilityIdentifier: String? = nil, action: @escaping () -> Void) {
        self.imageName = imageName
        self.title = title
        self.subtitle = subtitle
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: ChoraiSymbols.name(for: imageName))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .foregroundColor(ChoraiTheme.ink)

                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundColor(ChoraiTheme.ink)

                Spacer()

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.regular))
                        .foregroundColor(ChoraiTheme.secondaryInk)
                }

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ChoraiTheme.secondaryInk)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "settings.row.\(title)")
        .accessibilityValue(subtitle ?? "")
    }
}

/// Native grouped settings sections share the app's semantic surface tokens.
struct SettingsFormSection<Content: View>: View {
    let title: String
    let identifier: String
    @ViewBuilder let content: Content

    init(title: String, identifier: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        Section {
            content
                .listRowBackground(ChoraiTheme.surface)
        } header: {
            Text(title)
                .accessibilityIdentifier(identifier)
        }
    }
}

struct SettingsDestinationHeader: View {
    let title: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Button(action: dismiss) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.medium))
                    .foregroundColor(ChoraiTheme.ink)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Back")
            .accessibilityIdentifier("settings.destination.back")

            Spacer()

            Text(title)
                .font(.title2.weight(.bold))
                .foregroundColor(ChoraiTheme.ink)
                .accessibilityIdentifier("settings.destination.title")

            Spacer()

            Image(systemName: "chevron.left")
                .font(.title3.weight(.medium))
                .foregroundColor(.clear)
                    .frame(minWidth: 44, minHeight: 44)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 30)
    }
}

struct SettingsOutlineButton: View {
    let title: String
    var foregroundColor: Color = ChoraiTheme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundColor(foregroundColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .frame(minHeight: 44)
                .choraiGlassSurface(cornerRadius: 24)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
}

/// System symbols for existing navigation/action names; media assets are never routed here.
enum ChoraiSymbols {
    static func name(for assetName: String) -> String {
        switch assetName {
        case "personal": return "person.crop.circle"
        case "account": return "lock.shield"
        case "bot": return "sparkles"
        case "syn": return "gift"
        case "send_chat": return "bubble.left.and.bubble.right"
        case "menu_share": return "square.and.arrow.up"
        case "menu_report": return "flag"
        case "menu_spark": return "sparkles"
        case "menu_merge": return "arrow.triangle.merge"
        case "menu_link": return "link"
        case "menu_pin": return "pin"
        case "menu_private": return "lock"
        case "menu_remove": return "trash"
        case "menu_root": return "point.3.connected.trianglepath.dotted"
        case "menu_view": return "doc.text"
        case "search": return "magnifyingglass"
        case "filter": return "line.3.horizontal.decrease"
        case "settings": return "gearshape"
        case "notification": return "bell"
        case "trash": return "trash"
        case "mynotes": return "doc.text"
        case "favorites": return "bookmark"
        case "favorite": return "bookmark"
        case "favorite_active": return "bookmark.fill"
        case "collect": return "bookmark"
        case "collect_active": return "bookmark.fill"
        case "like": return "heart"
        case "like_active": return "heart.fill"
        case "comment": return "bubble"
        case "pin": return "pin.fill"
        case "unpin": return "pin.slash"
        case "public_icon": return "globe"
        case "private_icon": return "lock"
        case "edit": return "pencil"
        case "send": return "arrow.up"
        case "open": return "arrow.up.right"
        case "menu": return "line.3.horizontal"
        case "preference": return "slider.horizontal.3"
        case "api": return "puzzlepiece.extension"
        case "help": return "questionmark.circle"
        case "feedback": return "bubble.left"
        case "about": return "info.circle"
        case "update": return "arrow.clockwise"
        case "check": return "checkmark"
        case "checkmark_icon": return "checkmark.circle.fill"
        default: return "circle.grid.2x2"
        }
    }
}
