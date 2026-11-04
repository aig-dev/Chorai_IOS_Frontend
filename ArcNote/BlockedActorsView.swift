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
        Form {
            SettingsFormSection(title: "Account", identifier: "account-privacy.account.section") {
                profileValue(label: "Username", value: profileManager.userProfile?.username ?? "—")
                profileValue(label: "Email", value: profileManager.userProfile?.email ?? "—")
                profileValue(label: "Membership", value: authManager.membershipDisplayName)
                    .accessibilityIdentifier("account-privacy.membership")
            }
            SettingsFormSection(title: "Audience & Visibility", identifier: "account-privacy.visibility.section") {
                privacyContent
            }
            SettingsFormSection(title: "Community", identifier: "account-privacy.community.section") {
                SettingsRow(imageName: "account", title: "Blocked Users", accessibilityIdentifier: "account-privacy.blocked-users") {
                    navigateToBlockedUsers = true
                }
            }
        }
        .scrollContentBackground(.hidden)
        .choraiPageBackground()
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .navigationTitle("Account & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
                Group {
                    privacyToggle(
                        .showFollowLists,
                        title: "Show follow lists",
                        description: "Let others see who you follow and who follows you."
                    )
                    privacyToggle(
                        .allowFollow,
                        title: "Allow follows",
                        description: "Let new people follow your profile."
                    )
                    privacyToggle(
                        .showEmail,
                        title: "Show email",
                        description: "Display your email on your public profile."
                    )
                    privacyToggle(
                        .showPhone,
                        title: "Show phone",
                        description: "Display your phone number on your public profile."
                    )
                    privacyToggle(
                        .showLocation,
                        title: "Show location",
                        description: "Display your location on your public profile."
                    )
                    privacyToggle(
                        .showBirthday,
                        title: "Show birthday",
                        description: "Display your birthday on your public profile."
                    )

                    if privacyStore.savingSetting != nil {
                        HStack(spacing: 10) {
                            ProgressView().tint(ChoraiTheme.ink)
                            Text("Saving…")
                                .font(.subheadline)
                                .foregroundColor(ChoraiTheme.secondaryInk)
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
                    .foregroundColor(ChoraiTheme.ink)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(ChoraiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 8)
        }
        .toggleStyle(SwitchToggleStyle(tint: ChoraiTheme.accent))
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
                .font(.subheadline)
                .foregroundColor(ChoraiTheme.secondaryInk)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(ChoraiTheme.ink)
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
        VStack(spacing: 0) {
            content
        }
        .choraiPageBackground()
        .tint(ChoraiTheme.accent)
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
            ProgressView().tint(ChoraiTheme.ink)
            Spacer()

        case .empty:
            Text("No blocked users")
                .font(.subheadline.weight(.medium))
                .foregroundColor(ChoraiTheme.secondaryInk)
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
        List {
            ForEach(store.items) { actor in
                row(actor)
                    .listRowBackground(ChoraiTheme.surface)
                    .onAppear {
                        if actor.actorID == store.items.last?.actorID { store.loadMore() }
                    }
            }
            if store.phase == .loadingMore {
                ProgressView()
                    .tint(ChoraiTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .listRowBackground(ChoraiTheme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func failureBanner(
        _ operation: BlockedActorsOperation,
        fillsAvailableSpace: Bool
    ) -> some View {
        VStack(spacing: 10) {
            Text(failureMessage(operation))
                .font(.subheadline.weight(.medium))
                .foregroundColor(ChoraiTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("blocked-users.error")

            Button("Try Again") {
                retry(operation)
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(ChoraiTheme.ink)
            .frame(minWidth: 88, minHeight: 44)
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
                    .font(.body.weight(.semibold))
                    .foregroundColor(ChoraiTheme.ink)
                    .lineLimit(1)

                if let bio = actor.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.footnote)
                        .foregroundColor(ChoraiTheme.secondaryInk)
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
                        ProgressView().tint(ChoraiTheme.ink).frame(width: 55)
                    } else {
                        Text("Unblock")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(ChoraiTheme.ink)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(Capsule().fill(ChoraiTheme.raisedSurface))
            }
            .buttonStyle(.borderless)
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
