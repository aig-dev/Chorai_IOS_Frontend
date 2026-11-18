import CoreFlow
import SwiftUI

@MainActor
struct RootView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: DiscoveryPathStore
    @State private var selectedCardID: String?
    @State private var navigateToDetail = false
    @State private var navigateToEdit = false
    @State private var showPopupMenu = false
    @State private var menuCard: UserCard?

    let cardId: String
    let type: String?

    init(
        cardId: String = "",
        type: String? = nil,
        service: (any CoreDiscoveryPathServing)? = nil
    ) {
        self.cardId = cardId
        self.type = type
        _store = StateObject(
            wrappedValue: DiscoveryPathStore(
                service: service ?? NetworkDiscoveryPathService()
            )
        )
    }

    var body: some View {
        ZStack {
            ChoraiBackground()
                .ignoresSafeArea()

            content
        }
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .navigationTitle("Discovery Path")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier("discovery-path.back")
            }
        }
        .overlay(alignment: .topLeading) {
            Text("Discovery Path")
                .font(.system(size: 1))
                .foregroundColor(.white.opacity(0.01))
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("screen.discovery-path")
        }
        .navigationDestination(isPresented: $navigateToDetail) {
            if let selectedCardID {
                DetailView(cardId: selectedCardID)
            }
        }
        .navigationDestination(isPresented: $navigateToEdit) {
            if let selectedCardID {
                NewNoteView(cardId: selectedCardID)
            }
        }
        .popupMenu(
            isPresented: $showPopupMenu,
            layout: .grid2x2,
            cardData: menuCard,
            isOwnCard: menuCard?.isOwner ?? false
        )
        .task(id: cardId) {
            await store.load(cardID: cardId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cardReadInvalidated)) { event in
            if event.object as? String == menuCard?.id { clearMenu() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cardReadSessionDidChange)) { _ in
            clearMenu()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            DiscoveryPathLoadingView()
        case .ready:
            if let snapshot = store.snapshot {
                pathContent(snapshot, showsEmptyState: false)
            }
        case .empty:
            if let snapshot = store.snapshot {
                pathContent(snapshot, showsEmptyState: true)
            }
        case .failed(let error):
            DiscoveryPathFailureView(
                message: message(for: error),
                retry: {
                    Task { await store.retry() }
                }
            )
        }
    }

    private func pathContent(
        _ snapshot: DiscoveryPathSnapshot,
        showsEmptyState: Bool
    ) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                DiscoveryPathTimeline(
                    snapshot: snapshot,
                    openCard: openCard,
                    openMenu: openMenu
                )

                if showsEmptyState {
                    VStack(spacing: 10) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.title.weight(.light))
                            .foregroundColor(ChoraiTheme.secondaryInk)
                        Text("No discovery path recorded")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ChoraiTheme.ink)
                        Text("This card was not saved from a Spark journey.")
                            .font(.footnote)
                            .foregroundColor(ChoraiTheme.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 28)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("discovery-path.empty")
                }
            }
            .adaptiveContentGutter()
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
    }

    private func openCard(_ card: DiscoveryPathCard) {
        selectedCardID = card.id
        let currentActorID = AuthManager.shared.currentUser?.id
        if let ownerActorID = card.ownerActorID, ownerActorID == currentActorID {
            navigateToEdit = true
        } else {
            navigateToDetail = true
        }
    }

    private func openMenu(_ card: DiscoveryPathCard) {
        menuCard = card.asMenuCard
    }

    private func clearMenu() {
        menuCard = nil
        showPopupMenu = false
    }

    private func message(for error: DiscoveryPathError) -> String {
        switch error {
        case .invalidCard:
            return "This card is unavailable."
        case .unauthorized:
            return "Sign in again to view this discovery path."
        case .forbidden:
            return "You no longer have access to part of this path."
        case .requestFailed(let message):
            return message ?? "Couldn’t load the discovery path."
        }
    }
}

private struct DiscoveryPathTimeline: View {
    let snapshot: DiscoveryPathSnapshot
    let openCard: (DiscoveryPathCard) -> Void
    let openMenu: (DiscoveryPathCard) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DiscoveryPathCardView(
                card: snapshot.collected,
                badge: "Collected",
                badgeColor: ChoraiTheme.gold,
                action: { openCard(snapshot.collected) },
                onMenu: { openMenu(snapshot.collected) }
            )
            .accessibilityIdentifier("discovery-path.collected")

            ForEach(Array(snapshot.ancestors.enumerated()), id: \.element.id) {
                index,
                node in
                DiscoveryPathConnector()
                DiscoveryPathCardView(
                    card: node.card,
                    badge: index == snapshot.ancestors.count - 1
                        ? "Origin" : "Step \(node.depth)",
                    badgeColor: index == snapshot.ancestors.count - 1
                        ? ChoraiTheme.accent : ChoraiTheme.secondaryInk,
                    action: { openCard(node.card) },
                    onMenu: { openMenu(node.card) }
                )
                .accessibilityIdentifier(
                    "discovery-path.ancestor.\(node.card.id)"
                )
            }
        }
        .overlay(alignment: .topLeading) {
            Text(snapshot.ancestors.map(\.card.id).joined(separator: ","))
                .font(.system(size: 1))
                .foregroundColor(.white.opacity(0.01))
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("discovery-path.order")
        }
    }
}

private struct DiscoveryPathConnector: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ChoraiTheme.separator)
                .frame(width: 1, height: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 39)
        .accessibilityHidden(true)
    }
}

private extension DiscoveryPathCard {
    var asMenuCard: UserCard {
        let actorID = AuthManager.shared.currentUser?.id
        return UserCard(
            id: id, title: nil, content: content, contentHash: "", isPublic: false,
            tags: tags, createdAt: createdAt, updatedAt: createdAt,
            likeCount: 0, commentCount: nil, isLiked: false, isPinned: false,
            pinnedAt: nil, isFavorited: nil, favoriteCount: nil, rate: rate,
            ownerActorId: ownerActorID,
            isOwner: actorID != nil && ownerActorID == actorID
        )
    }
}

private struct DiscoveryPathCardView: View {
    let card: DiscoveryPathCard
    let badge: String
    let badgeColor: Color
    let action: () -> Void
    let onMenu: () -> Void
    @ScaledMetric(relativeTo: .title3) private var previewFontSize = 20.0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ChoraiTheme.ink)
                        .lineLimit(1)
                    Text(Self.formattedDate(card.createdAt))
                        .font(.caption)
                        .foregroundColor(ChoraiTheme.secondaryInk)
                }

                Spacer()

                NativeCardActionsMenu(
                    cardData: card.asMenuCard, layout: .grid2x2,
                    isOwnCard: card.asMenuCard.isOwner ?? false, onPrepare: onMenu
                ) {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.medium))
                        .foregroundColor(ChoraiTheme.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Card menu")
                .accessibilityIdentifier("discovery-path.menu.\(card.id)")
            }

            Button(action: action) {
                HTMLTextRenderer(
                    htmlContent: card.content,
                    maxLines: 4,
                    font: .system(size: previewFontSize, weight: .regular, design: .serif),
                    foregroundColor: ChoraiTheme.ink
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(card.authorName)'s card")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    pathRoleChip

                    ForEach(card.tags.prefix(4), id: \.self) { tag in
                        tagChip(tag)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LibraryCardBackgroundSurface(
                backgroundMediaRef: nil,
                rate: card.rate
            ) {
                cardBackground
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discovery-path.card.\(card.id)")
    }

    @ViewBuilder
    private var avatar: some View {
        if let rawURL = card.avatarURL,
           let url = URL(string: APIConfiguration.resourceURLString(rawURL)) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                avatarFallback
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        Circle()
            .fill(ChoraiTheme.surface)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.subheadline)
                    .foregroundColor(ChoraiTheme.secondaryInk)
            )
            .frame(width: 40, height: 40)
    }

    private var pathRoleChip: some View {
        Text(badge)
            .font(.caption.weight(.semibold))
            .foregroundColor(badgeColor)
            .padding(.trailing, 6)
            .accessibilityIdentifier("discovery-path.role.\(card.id)")
    }

    private func tagChip(_ tag: String) -> some View {
        Text("#\(tag)")
            .font(.caption)
            .foregroundColor(ChoraiTheme.secondaryInk)
            .lineLimit(1)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(ChoraiTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(ChoraiTheme.separator.opacity(0.6), lineWidth: 0.5)
            )
    }

    private static func formattedDate(_ raw: String) -> String {
        CardTimestamp.dateOnly(from: raw)
    }
}

private struct DiscoveryPathLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(ChoraiTheme.ink)
            Text("Loading discovery path…")
                .font(.subheadline.weight(.medium))
                .foregroundColor(ChoraiTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("discovery-path.loading")
    }
}

private struct DiscoveryPathFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.largeTitle.weight(.light))
                .foregroundColor(ChoraiTheme.secondaryInk)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundColor(ChoraiTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("discovery-path.error")
            Button("Try Again", action: retry)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .choraiGlassButton()
                .accessibilityIdentifier("discovery-path.retry")
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        RootView(cardId: "")
    }
}
