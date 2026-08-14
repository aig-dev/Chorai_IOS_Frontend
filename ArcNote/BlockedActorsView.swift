import CoreFlow
import SwiftUI

struct AccountPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authManager = AuthManager.shared
    @ObservedObject private var profileManager = UserProfileManager.shared
    @StateObject private var privacyStore: PrivacySettingsStore
    @State private var navigateToBlockedUsers = false

    init(
        service: any CorePrivacySettingsServing = NetworkPrivacySettingsService()
    ) {
        _privacyStore = StateObject(
            wrappedValue: PrivacySettingsStore(service: service)
        )
    }

    var body: some View {
        ZStack {
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsDestinationHeader(
                    title: "Account & Privacy",
                    dismiss: dismiss.callAsFunction
                )

                ScrollView {
                    VStack(spacing: 24) {
                        ChoraSectionSurface(
                            title: "Account",
                            identifier: "account-privacy.account.section"
                        ) {
                            profileValue(
                                label: "Username",
                                value: profileManager.userProfile?.username ?? "—"
                            )

                            Divider().background(Color.white.opacity(0.2))

                            profileValue(
                                label: "Email",
                                value: profileManager.userProfile?.email ?? "—"
                            )

                            Divider().background(Color.white.opacity(0.2))

                            profileValue(
                                label: "Membership",
                                value: authManager.membershipDisplayName
                            )
                            .accessibilityIdentifier("account-privacy.membership")
                        }

                        ChoraSectionSurface(
                            title: "Audience & Visibility",
                            identifier: "account-privacy.visibility.section"
                        ) {
                            privacyContent
                        }

                        ChoraSectionSurface(
                            title: "Community",
                            identifier: "account-privacy.community.section"
                        ) {
                            SettingsRow(
                                imageName: "account",
                                title: "Blocked Users",
                                accessibilityIdentifier: "account-privacy.blocked-users"
                            ) {
                                navigateToBlockedUsers = true
                            }
                        }
                    }
                    .adaptiveContentGutter()
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $navigateToBlockedUsers) {
            BlockedActorsView()
        }
        .overlay(alignment: .topLeading) {
            Text("Account and Privacy")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("screen.account-privacy")
        }
        .task(id: actorID) {
            await privacyStore.load(actorID: actorID)
        }
        .onAppear {
            profileManager.fetchCurrentUserProfile()
        }
    }

    private var actorID: String {
        authManager.currentUser?.id ?? profileManager.userProfile?.id ?? ""
    }

    @ViewBuilder
    private var privacyContent: some View {
        switch privacyStore.phase {
        case .idle, .loading:
            ChoraLoadingRow(
                text: "Loading privacy settings…",
                identifier: "account-privacy.visibility.loading"
            )

        case .failed(let error):
            ChoraInlineError(
                text: privacyMessage(
                    error,
                    fallback: "Privacy settings couldn’t be loaded."
                ),
                identifier: "account-privacy.visibility.error"
            ) {
                Task { await privacyStore.retryLoad() }
            }

        case .ready:
            if privacyStore.settings != nil {
                VStack(spacing: 0) {
                    privacyToggle(
                        .showFollowLists,
                        title: "Show follow lists",
                        description: "Let others see who you follow and who follows you."
                    )
                    privacyDivider
                    privacyToggle(
                        .allowFollow,
                        title: "Allow follows",
                        description: "Let new people follow your profile."
                    )
                    privacyDivider
                    privacyToggle(
                        .showEmail,
                        title: "Show email",
                        description: "Display your email on your public profile."
                    )
                    privacyDivider
                    privacyToggle(
                        .showPhone,
                        title: "Show phone",
                        description: "Display your phone number on your public profile."
                    )
                    privacyDivider
                    privacyToggle(
                        .showLocation,
                        title: "Show location",
                        description: "Display your location on your public profile."
                    )
                    privacyDivider
                    privacyToggle(
                        .showBirthday,
                        title: "Show birthday",
                        description: "Display your birthday on your public profile."
                    )

                    if privacyStore.savingSetting != nil {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Saving…")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.64))
                        }
                        .padding(.top, 16)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("account-privacy.visibility.saving")
                    }

                    if let error = privacyStore.updateError {
                        ChoraInlineError(
                            text: privacyMessage(
                                error,
                                fallback: "That change wasn’t saved. Your previous setting was restored."
                            ),
                            identifier: "account-privacy.visibility.update-error"
                        ) {
                            Task { await privacyStore.retryFailedUpdate() }
                        }
                        .padding(.top, 16)
                    }
                }
            }
        }
    }

    private var privacyDivider: some View {
        Divider().background(Color.white.opacity(0.16))
    }

    private func privacyToggle(
        _ setting: PrivacySetting,
        title: String,
        description: String
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { privacyStore.settings?.value(for: setting) ?? false },
                set: { enabled in
                    Task { await privacyStore.set(setting, enabled: enabled) }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundColor(.white)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 8)
        }
        .toggleStyle(SwitchToggleStyle(tint: .purple))
        .padding(.vertical, 14)
        .disabled(privacyStore.savingSetting != nil)
        .accessibilityIdentifier("account-privacy.toggle.\(setting.rawValue)")
        .accessibilityValue(
            privacyStore.settings?.value(for: setting) == true
                ? "enabled"
                : "disabled"
        )
    }

    private func privacyMessage(
        _ error: PrivacySettingsError,
        fallback: String
    ) -> String {
        switch error {
        case .invalidActor, .unauthorized:
            return "Sign in again to continue."
        case .requestFailed(let message):
            return message ?? fallback
        case .contract:
            return fallback
        }
    }

    private func profileValue(label: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.62))

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }
}

struct BlockedActorsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: BlockedActorsStore

    init(
        service: any CoreCommunityProfileServing = NetworkCommunityProfileService()
    ) {
        _store = StateObject(wrappedValue: BlockedActorsStore(service: service))
    }

    var body: some View {
        ZStack {
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Text("Blocked Users")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.clear)
                }
                .adaptiveContentGutter()
                .padding(.top, 60)
                .padding(.bottom, 24)

                content
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .topLeading) {
            Text("Blocked users")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("screen.blocked-users")
        }
        .onAppear(perform: store.load)
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            Spacer()
            ProgressView().tint(.white)
            Spacer()

        case .empty:
            Text("No blocked users")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.68))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("blocked-users.empty")

        case .failed(let operation, _):
            if store.items.isEmpty {
                failureBanner(operation, fillsAvailableSpace: true)
            } else {
                VStack(spacing: 0) {
                    failureBanner(operation, fillsAvailableSpace: false)
                    listContent
                }
            }

        default:
            listContent
        }
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.items) { actor in
                    row(actor)
                        .onAppear {
                            if actor.actorID == store.items.last?.actorID {
                                store.loadMore()
                            }
                        }

                    Divider()
                        .background(Color.white.opacity(0.15))
                        .padding(.leading, 84)
                }

                if store.phase == .loadingMore {
                    ProgressView()
                        .tint(.white)
                        .padding(.vertical, 18)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func failureBanner(
        _ operation: BlockedActorsOperation,
        fillsAvailableSpace: Bool
    ) -> some View {
        VStack(spacing: 10) {
            Text(failureMessage(operation))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("blocked-users.error")

            Button("Try Again") {
                retry(operation)
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsAvailableSpace ? .infinity : nil
        )
    }

    private func failureMessage(_ operation: BlockedActorsOperation) -> String {
        switch operation {
        case .load:
            "Couldn’t load blocked users."
        case .loadMore:
            "Couldn’t load more blocked users."
        case .unblock:
            "Couldn’t unblock this user. Your list is unchanged."
        }
    }

    private func retry(_ operation: BlockedActorsOperation) {
        switch operation {
        case .load:
            store.load()
        case .loadMore:
            store.loadMore()
        case .unblock(let actorID):
            store.unblock(actorID: actorID)
        }
    }

    private func row(_ actor: BlockedActor) -> some View {
        HStack(spacing: 12) {
            profileImage(actor.avatarURL)

            VStack(alignment: .leading, spacing: 3) {
                Text(actor.username.isEmpty ? "Blocked user" : actor.username)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let bio = actor.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.62))
                        .lineLimit(1)
                }
            }
            .accessibilityIdentifier("blocked-users.row.\(actor.actorID)")

            Spacer()

            Button {
                store.unblock(actorID: actor.actorID)
            } label: {
                Group {
                    if isUnblocking(actor.actorID) {
                        ProgressView().tint(.black).frame(width: 55)
                    } else {
                        Text("Unblock")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white))
            }
            .disabled(isUnblocking(actor.actorID))
            .accessibilityIdentifier("blocked-users.unblock.\(actor.actorID)")
        }
        .padding(.vertical, 14)
    }

    private func profileImage(_ avatarURL: String?) -> some View {
        Group {
            if let avatarURL, !avatarURL.isEmpty {
                AsyncImage(
                    url: URL(string: APIConfiguration.resourceURLString(avatarURL))
                ) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image("avatar").resizable().aspectRatio(contentMode: .fill)
                }
            } else {
                Image("avatar").resizable().aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
    }

    private func isUnblocking(_ actorID: String) -> Bool {
        if case .unblocking(let currentActorID) = store.phase {
            return currentActorID == actorID
        }
        return false
    }
}
