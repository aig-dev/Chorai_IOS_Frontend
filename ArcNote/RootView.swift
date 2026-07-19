import CoreFlow
import SwiftUI

@MainActor
struct RootView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: DiscoveryPathStore
    @State private var selectedCardID: String?
    @State private var navigateToDetail = false
    @State private var navigateToEdit = false

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
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
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
        .task(id: cardId) {
            await store.load(cardID: cardId)
        }
    }

    private var header: some View {
        HStack {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
            }
            .accessibilityLabel("Back")
            .accessibilityIdentifier("discovery-path.back")

            Spacer()

            Text("Discovery Path")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.clear)
                .accessibilityHidden(true)
        }
        .adaptiveContentGutter()
        .padding(.top, 60)
        .padding(.bottom, 24)
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
                    openCard: openCard
                )

                if showsEmptyState {
                    VStack(spacing: 10) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(.white.opacity(0.55))
                        Text("No discovery path recorded")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.82))
                        Text("This card was not saved from a Spark journey.")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 28)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("discovery-path.empty")
                }
            }
            .adaptiveContentGutter()
            .padding(.bottom, 40)
        }
    }

    private func openCard(_ card: DiscoveryPathCard) {
        selectedCardID = card.id
        let currentActorID = AuthManager.shared.currentUser?.id
        if let authorActorID = card.authorActorID,
           authorActorID == currentActorID {
            navigateToEdit = true
        } else {
            navigateToDetail = true
        }
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

    var body: some View {
        VStack(spacing: 0) {
            DiscoveryPathCardView(
                card: snapshot.collected,
                badge: "Collected",
                badgeColor: Color(red: 0.67, green: 0.42, blue: 1),
                action: { openCard(snapshot.collected) }
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
                        ? Color.orange : Color.white.opacity(0.65),
                    action: { openCard(node.card) }
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
        VStack(spacing: 4) {
            Circle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1, height: 34)
        }
        .accessibilityHidden(true)
    }
}

private struct DiscoveryPathCardView: View {
    let card: DiscoveryPathCard
    let badge: String
    let badgeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    avatar

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.authorName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(Self.formattedDate(card.createdAt))
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    Spacer()

                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(badgeColor.opacity(0.12))
                        )
                }

                if let title = card.title,
                   !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                HTMLTextRenderer(htmlContent: card.content, maxLines: 3)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.82))

                if !card.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(card.tags.prefix(4), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.82))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule().fill(Color.white.opacity(0.09))
                                    )
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            [badge, card.title, card.authorName]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
    }

    @ViewBuilder
    private var avatar: some View {
        if let rawURL = card.avatarURL,
           let url = URL(string: rawURL) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                avatarFallback
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        Circle()
            .fill(Color.white.opacity(0.12))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.65))
            )
            .frame(width: 34, height: 34)
    }

    @ViewBuilder
    private var cardBackground: some View {
        ZStack {
            Color(red: 0.08, green: 0.06, blue: 0.14).opacity(0.92)
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var backgroundColors: [Color] {
        switch card.rate {
        case 80...:
            [Color.orange.opacity(0.18), Color.clear]
        case 27...:
            [Color.purple.opacity(0.22), Color.clear]
        case 9...:
            [Color.blue.opacity(0.2), Color.clear]
        case 3...:
            [Color.green.opacity(0.14), Color.clear]
        default:
            [Color.white.opacity(0.07), Color.clear]
        }
    }

    private static func formattedDate(_ raw: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: raw) ?? fallback.date(from: raw) else {
            return raw
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private struct DiscoveryPathLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
            Text("Loading discovery path…")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
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
                .font(.system(size: 30, weight: .light))
                .foregroundColor(.white.opacity(0.6))
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.76))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("discovery-path.error")
            Button("Try Again", action: retry)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(
                    Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1)
                )
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
