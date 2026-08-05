import CoreFlow
import SwiftUI

@MainActor
struct InvitationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: InvitationHistoryStore
    let actorID: String

    init(actorID: String, store: InvitationHistoryStore) {
        self.actorID = actorID
        self.store = store
    }

    var body: some View {
        InvitationCreditDetailShell(
            title: "Invitation History",
            screenIdentifier: "screen.invitation-history",
            dismiss: dismiss.callAsFunction
        ) {
            content
        }
        .task(id: actorID) {
            guard store.actorID != actorID else { return }
            await store.load(actorID: actorID)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            InvitationCreditDetailLoading(
                text: "Loading invitations…",
                identifier: "invitation-history.loading"
            )
        case .empty:
            InvitationCreditDetailEmpty(
                text: "No invitations yet. Share your invitation to get started.",
                identifier: "invitation-history.empty"
            )
        case .failed(let error):
            InvitationCreditDetailFailure(
                text: InvitationCreditPresentation.message(
                    error,
                    fallback: "Invitation history couldn’t be loaded."
                ),
                identifier: "invitation-history.error"
            ) {
                Task { await store.retry() }
            }
        case .ready, .loadingMore:
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.items) { record in
                        invitationRow(record)
                        InvitationCreditRowDivider()
                    }
                    pagination
                }
                .adaptiveContentGutter()
                .padding(.bottom, 40)
            }
        }
    }

    private func invitationRow(_ record: InvitationRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Invited member")
                    .font(.body.weight(.medium))
                    .foregroundColor(.white)
                Spacer(minLength: 12)
                Text(
                    InvitationCreditPresentation.readable(
                        record.status.canonical
                    )
                )
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            }
            Text(InvitationCreditPresentation.date(record.createdAt))
                .font(.footnote)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Invited member, \(InvitationCreditPresentation.readable(record.status.canonical)), \(InvitationCreditPresentation.date(record.createdAt))"
        )
        .accessibilityIdentifier("invitation-history.row.\(record.id)")
    }

    @ViewBuilder
    private var pagination: some View {
        if let error = store.paginationError {
            InvitationCreditPaginationFailure(
                text: InvitationCreditPresentation.message(
                    error,
                    fallback: "More invitations couldn’t be loaded."
                ),
                identifier: "invitation-history.pagination-error"
            ) {
                Task { await store.retry() }
            }
        } else if store.phase == .loadingMore {
            ProgressView()
                .tint(.white)
                .padding(.vertical, 20)
                .accessibilityLabel("Loading more invitations")
                .accessibilityIdentifier("invitation-history.loading-more")
        } else if store.hasMore {
            SettingsOutlineButton(title: "Load More") {
                Task { await store.loadMore() }
            }
            .padding(.top, 20)
            .accessibilityLabel("Load more invitations")
            .accessibilityIdentifier("invitation-history.load-more")
        }
    }
}

@MainActor
struct InvitationRewardsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: InvitationRewardStore
    let actorID: String

    init(actorID: String, store: InvitationRewardStore) {
        self.actorID = actorID
        self.store = store
    }

    var body: some View {
        InvitationCreditDetailShell(
            title: "Rewards",
            screenIdentifier: "screen.invitation-rewards",
            dismiss: dismiss.callAsFunction
        ) {
            content
        }
        .task(id: actorID) {
            guard store.actorID != actorID else { return }
            await store.load(actorID: actorID)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            InvitationCreditDetailLoading(
                text: "Loading rewards…",
                identifier: "invitation-rewards.loading"
            )
        case .empty:
            InvitationCreditDetailEmpty(
                text: "No rewards have been issued yet.",
                identifier: "invitation-rewards.empty"
            )
        case .failed(let error):
            InvitationCreditDetailFailure(
                text: InvitationCreditPresentation.message(
                    error,
                    fallback: "Rewards couldn’t be loaded."
                ),
                identifier: "invitation-rewards.error"
            ) {
                Task { await store.retry() }
            }
        case .ready, .loadingMore:
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.items) { reward in
                        rewardRow(reward)
                        InvitationCreditRowDivider()
                    }
                    pagination
                }
                .adaptiveContentGutter()
                .padding(.bottom, 40)
            }
        }
    }

    private func rewardRow(_ reward: InvitationReward) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(rewardAmount(reward.amount))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text("Credits")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer(minLength: 12)
                Text(
                    InvitationCreditPresentation.readable(
                        reward.status.canonical
                    )
                )
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.62))
            }

            HStack(spacing: 10) {
                Text(InvitationCreditPresentation.date(reward.createdAt))
                if reward.isMilestoneBonus {
                    Text("Milestone bonus")
                        .fontWeight(.medium)
                }
            }
            .font(.footnote)
            .foregroundColor(.white.opacity(0.5))
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rewardAccessibilityLabel(reward))
        .accessibilityIdentifier("invitation-rewards.row.\(reward.id)")
    }

    private func rewardAmount(_ value: Int) -> String {
        value >= 0 ? "+\(value.formatted())" : value.formatted()
    }

    private func rewardAccessibilityLabel(_ reward: InvitationReward) -> String {
        [
            rewardAmount(reward.amount),
            "Credits",
            InvitationCreditPresentation.readable(reward.status.canonical),
            reward.isMilestoneBonus ? "Milestone bonus" : nil,
            InvitationCreditPresentation.date(reward.createdAt)
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    @ViewBuilder
    private var pagination: some View {
        if let error = store.paginationError {
            InvitationCreditPaginationFailure(
                text: InvitationCreditPresentation.message(
                    error,
                    fallback: "More rewards couldn’t be loaded."
                ),
                identifier: "invitation-rewards.pagination-error"
            ) {
                Task { await store.retry() }
            }
        } else if store.phase == .loadingMore {
            ProgressView()
                .tint(.white)
                .padding(.vertical, 20)
                .accessibilityLabel("Loading more rewards")
                .accessibilityIdentifier("invitation-rewards.loading-more")
        } else if store.hasMore {
            SettingsOutlineButton(title: "Load More") {
                Task { await store.loadMore() }
            }
            .padding(.top, 20)
            .accessibilityLabel("Load more rewards")
            .accessibilityIdentifier("invitation-rewards.load-more")
        }
    }
}

@MainActor
struct CreditLedgerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CreditLedgerStore
    let actorID: String

    init(actorID: String, store: CreditLedgerStore) {
        self.actorID = actorID
        self.store = store
    }

    var body: some View {
        InvitationCreditDetailShell(
            title: "Credit Activity",
            screenIdentifier: "screen.credit-ledger",
            dismiss: dismiss.callAsFunction
        ) {
            content
        }
        .task(id: actorID) {
            guard store.actorID != actorID else { return }
            await store.load(actorID: actorID)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            InvitationCreditDetailLoading(
                text: "Loading credit activity…",
                identifier: "credit-ledger.loading"
            )
        case .empty:
            InvitationCreditDetailEmpty(
                text: "No credit activity yet.",
                identifier: "credit-ledger.empty"
            )
        case .failed(let error):
            InvitationCreditDetailFailure(
                text: InvitationCreditPresentation.message(
                    error,
                    fallback: "Credit activity couldn’t be loaded."
                ),
                identifier: "credit-ledger.error"
            ) {
                Task { await store.retry() }
            }
        case .ready, .loadingMore:
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.entries) { entry in
                        ledgerRow(entry)
                        InvitationCreditRowDivider()
                    }
                    pagination
                }
                .adaptiveContentGutter()
                .padding(.bottom, 40)
            }
        }
    }

    private func ledgerRow(_ entry: CreditLedgerEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(InvitationCreditPresentation.action(entry.actionType))
                        .font(.body.weight(.medium))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(InvitationCreditPresentation.readable(entry.category))
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text(signedDelta(entry))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(
                    InvitationCreditPresentation.readable(
                        entry.direction.canonical
                    )
                )
                Text(
                    InvitationCreditPresentation.readable(
                        entry.status.canonical
                    )
                )
                Spacer(minLength: 8)
                Text("Balance \(entry.runningBalance.formatted())")
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundColor(.white.opacity(0.58))

            Text(InvitationCreditPresentation.date(entry.createdAt))
                .font(.footnote)
                .foregroundColor(.white.opacity(0.44))
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ledgerAccessibilityLabel(entry))
        .accessibilityIdentifier("credit-ledger.row.\(entry.id)")
    }

    private func signedDelta(_ entry: CreditLedgerEntry) -> String {
        let magnitude = String(entry.delta).replacingOccurrences(of: "-", with: "")
        switch entry.direction {
        case .earn: return "+\(magnitude)"
        case .spend: return "-\(magnitude)"
        case .unknown:
            return entry.delta >= 0 ? "+\(entry.delta)" : String(entry.delta)
        }
    }

    private func ledgerAccessibilityLabel(_ entry: CreditLedgerEntry) -> String {
        [
            InvitationCreditPresentation.action(entry.actionType),
            InvitationCreditPresentation.readable(entry.category),
            InvitationCreditPresentation.readable(entry.direction.canonical),
            signedDelta(entry),
            "Balance \(entry.runningBalance)",
            InvitationCreditPresentation.readable(entry.status.canonical),
            InvitationCreditPresentation.date(entry.createdAt)
        ].joined(separator: ", ")
    }

    @ViewBuilder
    private var pagination: some View {
        if let error = store.paginationError {
            InvitationCreditPaginationFailure(
                text: InvitationCreditPresentation.message(
                    error,
                    fallback: "More credit activity couldn’t be loaded."
                ),
                identifier: "credit-ledger.pagination-error"
            ) {
                Task { await store.retry() }
            }
        } else if store.phase == .loadingMore {
            ProgressView()
                .tint(.white)
                .padding(.vertical, 20)
                .accessibilityLabel("Loading more credit activity")
                .accessibilityIdentifier("credit-ledger.loading-more")
        } else if store.hasMore {
            SettingsOutlineButton(title: "Load More") {
                Task { await store.loadMore() }
            }
            .padding(.top, 20)
            .accessibilityLabel("Load more credit activity")
            .accessibilityIdentifier("credit-ledger.load-more")
        }
    }
}

private struct InvitationCreditDetailShell<Content: View>: View {
    let title: String
    let screenIdentifier: String
    let dismiss: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        screenIdentifier: String,
        dismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.screenIdentifier = screenIdentifier
        self.dismiss = dismiss
        self.content = content()
    }

    var body: some View {
        ZStack {
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                SettingsDestinationHeader(title: title, dismiss: dismiss)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .topLeading) {
            InvitationCreditScreenAnchor(
                identifier: screenIdentifier,
                label: title
            )
        }
    }
}

private struct InvitationCreditDetailLoading: View {
    let text: String
    let identifier: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private struct InvitationCreditDetailEmpty: View {
    let text: String
    let identifier: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.68))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier(identifier)
    }
}

private struct InvitationCreditDetailFailure: View {
    let text: String
    let identifier: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(text)
                .font(.subheadline)
                .foregroundColor(Color(red: 1, green: 0.62, blue: 0.64))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
            SettingsOutlineButton(title: "Retry", action: retry)
                .frame(maxWidth: 220)
                .accessibilityLabel("Retry")
                .accessibilityIdentifier("\(identifier).retry")
        }
        .adaptiveContentGutter()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InvitationCreditPaginationFailure: View {
    let text: String
    let identifier: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.footnote)
                .foregroundColor(Color(red: 1, green: 0.62, blue: 0.64))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
            Button("Retry", action: retry)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
                .frame(minWidth: 88, minHeight: 40)
                .accessibilityLabel("Retry loading more")
                .accessibilityIdentifier("\(identifier).retry")
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }
}

private struct InvitationCreditRowDivider: View {
    var body: some View {
        Divider().background(Color.white.opacity(0.16))
    }
}

extension InvitationCreditPresentation {
    static func action(_ canonical: String) -> String {
        let labels = [
            "REGISTER_ACTOR": "Sign up reward",
            "AUTHENTICATE": "Daily login",
            "CREATE_ASSET": "Published note",
            "CREATE_COMMENT": "Commented",
            "LIKE_ASSET": "Liked",
            "UNLIKE": "Unliked",
            "FAVORITE_ASSET": "Favorited",
            "UNFAVORITE_ASSET": "Unfavorited",
            "FOLLOW_ACTOR": "Followed user",
            "UNFOLLOW_ACTOR": "Unfollowed",
            "AGENT_CHAT_TURN": "AI chat",
            "SPARK_SIMILAR": "Spark similar",
            "MERGE": "Merge note",
            "CREATE_WORKSPACE": "Created workspace",
            "INVITE_MEMBER": "Invited member",
            "IMPORT_EXTERNAL_CONTENT": "Imported content",
            "AGENT_EXECUTE_CAPABILITY": "AI capability call",
            "MEMORY_REFLECTION": "Memory reflection",
            "MEMORY_SEMANTIC_EXTRACTION": "Memory extraction",
            "MEMORY_SOUL_GOVERN": "Memory governance"
        ]
        return labels[canonical] ?? readable(canonical)
    }
}
