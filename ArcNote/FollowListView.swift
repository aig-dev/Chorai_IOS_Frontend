import CoreFlow
import SwiftUI

struct FollowListView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: FollowListStore
    @State private var selectedActorID: String?
    @State private var navigateToProfile = false

    let actorID: String
    let actorName: String
    let kind: FollowListKind
    let viewerActorID: String

    init(
        actorID: String,
        actorName: String,
        kind: FollowListKind,
        viewerActorID: String,
        service: any CoreCommunityProfileServing = NetworkCommunityProfileService()
    ) {
        self.actorID = actorID
        self.actorName = actorName
        self.kind = kind
        self.viewerActorID = viewerActorID
        _store = StateObject(wrappedValue: FollowListStore(service: service))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ChoraiBackground()
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    content
                }
            }
            .navigationTitle(kind == .followers ? "Followers" : "Following")
            .navigationBarTitleDisplayMode(.inline)
            .tint(ChoraiTheme.accent)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.medium))
                            .foregroundColor(ChoraiTheme.ink)
                    .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }

                ToolbarItem(placement: .principal) {
                    Text(kind == .followers ? "Followers" : "Following")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(ChoraiTheme.ink)
                }
            }
            .overlay(alignment: .topLeading) {
                Text("Follow list")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("screen.follow-list")
            }
            .navigationDestination(isPresented: $navigateToProfile) {
                if let selectedActorID {
                    UserProfileView(actorId: selectedActorID)
                }
            }
            .onAppear {
                store.load(
                    actorID: actorID,
                    kind: kind,
                    viewerActorID: viewerActorID
                )
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading, .idle:
            Spacer()
            ProgressView()
                .tint(ChoraiTheme.ink)
            Spacer()

        case .privateList:
            stateMessage(
                "Follow list unavailable",
                detail: "\(actorName) has chosen not to share this list.",
                identifier: "follow-list.private"
            )

        case .empty:
            stateMessage(
                kind == .followers ? "No followers yet" : "Not following anyone yet",
                detail: nil,
                identifier: "follow-list.empty"
            )

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
                        .background(ChoraiTheme.surface)
                        .padding(.leading, 84)
                }

                if store.phase == .loadingMore {
                    ProgressView()
                        .tint(ChoraiTheme.ink)
                        .padding(.vertical, 18)
                }
            }
            .adaptiveContentGutter()
        }
    }

    private func failureBanner(
        _ operation: FollowListOperation,
        fillsAvailableSpace: Bool
    ) -> some View {
        VStack(spacing: 10) {
            Text(failureMessage(operation))
                .font(.subheadline.weight(.medium))
                .foregroundColor(ChoraiTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("follow-list.error")

            Button("Try Again") {
                retry(operation)
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(ChoraiTheme.ink)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(
            maxWidth: .infinity,
            maxHeight: fillsAvailableSpace ? .infinity : nil
        )
    }

    private func failureMessage(_ operation: FollowListOperation) -> String {
        switch operation {
        case .load:
            "Couldn’t load this list."
        case .loadMore:
            "Couldn’t load more people."
        case .follow:
            "Couldn’t update follow. Your list is unchanged."
        }
    }

    private func retry(_ operation: FollowListOperation) {
        switch operation {
        case .loadMore:
            store.loadMore()
        case .follow(let actorID):
            store.toggleFollow(actorID: actorID)
        case .load:
            store.load(
                actorID: actorID,
                kind: kind,
                viewerActorID: viewerActorID
            )
        }
    }

    private func row(_ actor: CommunityActor) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedActorID = actor.actorID
                navigateToProfile = true
            } label: {
                HStack(spacing: 12) {
                    profileImage(actor.avatarURL)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(actor.username)
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

                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("follow-list.row.\(actor.actorID)")

            if actor.actorID != viewerActorID {
                Button {
                    store.toggleFollow(actorID: actor.actorID)
                } label: {
                    Group {
                        if isMutating(actor.actorID) {
                            ProgressView()
                                .tint(actor.isFollowing ? ChoraiTheme.ink : ChoraiTheme.onAccent)
                                .frame(width: 54)
                        } else {
                            Text(actor.isFollowing ? "Following" : "Follow")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(actor.isFollowing ? ChoraiTheme.ink : ChoraiTheme.onAccent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                }
                .choraiGlassButton(prominent: !actor.isFollowing)
                .disabled(isMutating(actor.actorID))
                .accessibilityIdentifier("follow-list.follow.\(actor.actorID)")
            }
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

    private func isMutating(_ actorID: String) -> Bool {
        if case .mutating(let currentActorID) = store.phase {
            return currentActorID == actorID
        }
        return false
    }

    private func stateMessage(
        _ title: String,
        detail: String?,
        identifier: String
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundColor(ChoraiTheme.secondaryInk)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundColor(ChoraiTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(identifier)
    }
}
