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
                Image("home_bg")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    content
                        .padding(.top, 56)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }

                ToolbarItem(placement: .principal) {
                    Text(kind == .followers ? "Followers" : "Following")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
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
                .tint(.white)
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
        _ operation: FollowListOperation,
        fillsAvailableSpace: Bool
    ) -> some View {
        VStack(spacing: 10) {
            Text(failureMessage(operation))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("follow-list.error")

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
                                .tint(.black)
                                .frame(width: 54)
                        } else {
                            Text(actor.isFollowing ? "Following" : "Follow")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white))
                }
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
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.78))
            if let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(identifier)
    }
}
