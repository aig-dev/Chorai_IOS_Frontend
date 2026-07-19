import CoreFlow
import SwiftUI
import UIKit

@MainActor
struct InvitationCreditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var overview: InvitationCreditOverviewStore
    @StateObject private var redemption: InvitationRedemptionStore
    @StateObject private var invitationHistory: InvitationHistoryStore
    @StateObject private var rewards: InvitationRewardStore
    @StateObject private var ledger: CreditLedgerStore

    @State private var isRedeemExpanded = false
    @State private var sharePayload: InvitationSharePayload?
    @State private var copied = false
    @State private var copyStatusTask: Task<Void, Never>?

    private let actorID: String
    private let refreshProfileCredits: @MainActor () -> Void

    init(
        actorID: String,
        service: any CoreInvitationCreditServing,
        persistence: any PendingInvitationCodePersisting,
        refreshProfileCredits: @escaping @MainActor () -> Void = {}
    ) {
        self.actorID = actorID
        self.refreshProfileCredits = refreshProfileCredits
        _overview = StateObject(
            wrappedValue: InvitationCreditOverviewStore(service: service)
        )
        _redemption = StateObject(
            wrappedValue: InvitationRedemptionStore(
                service: service,
                persistence: persistence
            )
        )
        _invitationHistory = StateObject(
            wrappedValue: InvitationHistoryStore(service: service)
        )
        _rewards = StateObject(
            wrappedValue: InvitationRewardStore(service: service)
        )
        _ledger = StateObject(
            wrappedValue: CreditLedgerStore(service: service)
        )
    }

    static func production(actorID: String) -> InvitationCreditView {
        InvitationCreditView(
            actorID: actorID,
            service: NetworkInvitationCreditService(),
            persistence: UserDefaultsPendingInvitationCodeStore(),
            refreshProfileCredits: {
                UserProfileManager.shared.fetchCurrentUserCredit()
            }
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
                    title: "Invitations & Credits",
                    dismiss: dismiss.callAsFunction
                )

                ScrollView {
                    VStack(spacing: 24) {
                        balanceSection
                        referralSection
                        redemptionSection
                        historySection
                    }
                    .adaptiveContentGutter()
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    await overview.refresh()
                }
            }
        }
        .navigationBarHidden(true)
        .overlay(alignment: .topLeading) {
            InvitationCreditScreenAnchor(
                identifier: "screen.invitation-credits",
                label: "Invitations and Credits"
            )
        }
        .sheet(item: $sharePayload) { payload in
            InvitationShareController(value: payload.value)
        }
        .task(id: actorID) {
            async let overviewLoad: Void = overview.load(actorID: actorID)
            await redemption.load(actorID: actorID)
            guard !Task.isCancelled else { return }
            if redemption.pendingIntent != nil {
                isRedeemExpanded = true
            }
            await overviewLoad
        }
        .onChange(of: redemption.successfulRedemptionID) { identifier in
            guard identifier != nil else { return }
            Task { await refreshAfterRedemption() }
        }
        .onDisappear {
            copyStatusTask?.cancel()
        }
    }

    private var balanceSection: some View {
        ChoraSectionSurface(
            title: "Balances",
            identifier: "invitation-credits.balance.section"
        ) {
            if let balances = overview.balances {
                VStack(spacing: 16) {
                    balanceRow(
                        title: "Credits",
                        value: balances.regular,
                        identifier: "invitation-credits.balance.credit"
                    )
                    Divider().background(Color.white.opacity(0.16))
                    balanceRow(
                        title: "Premium Credits",
                        value: balances.premium,
                        identifier: "invitation-credits.balance.premium-credit"
                    )
                }
            }

            switch overview.balancePhase {
            case .idle, .loading:
                if overview.balances == nil {
                    ChoraLoadingRow(
                        text: "Loading balances…",
                        identifier: "invitation-credits.balance.loading"
                    )
                }
            case .refreshing:
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Refreshing balances")
                    .accessibilityIdentifier(
                        "invitation-credits.balance.refreshing"
                    )
            case .failed(let error):
                InvitationCreditInlineError(
                    text: InvitationCreditPresentation.message(
                        error,
                        fallback: "Balances couldn’t be loaded."
                    ),
                    identifier: "invitation-credits.balance.error"
                ) {
                    Task { await overview.retryBalances() }
                }
            case .ready:
                EmptyView()
            }
        }
    }

    private func balanceRow(
        title: String,
        value: Int,
        identifier: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundColor(.white.opacity(0.68))
            Spacer(minLength: 16)
            Text(value.formatted())
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.formatted())
        .accessibilityIdentifier(identifier)
    }

    private var referralSection: some View {
        ChoraSectionSurface(
            title: "Invite",
            identifier: "invitation-credits.referral.section"
        ) {
            if let referral = overview.referral {
                VStack(alignment: .leading, spacing: 16) {
                    referralValue(
                        label: "Code",
                        value: referral.code,
                        identifier: "invitation-credits.referral.code"
                    )

                    if !referral.link.isEmpty {
                        referralValue(
                            label: "Link",
                            value: referral.link,
                            identifier: "invitation-credits.referral.link"
                        )
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Invited")
                        Spacer()
                        Text(referral.usedCount.formatted())
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.72))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(
                        "invitation-credits.referral.used-count"
                    )

                    if let nextMilestone = referral.nextMilestone {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Next milestone")
                            Spacer()
                            Text(nextMilestone.formatted())
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.72))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(
                            "invitation-credits.referral.next-milestone"
                        )
                    }

                    HStack(spacing: 12) {
                        SettingsOutlineButton(title: "Share") {
                            presentShare()
                        }
                        .disabled(referral.sharePayload == nil)
                        .opacity(referral.sharePayload == nil ? 0.55 : 1)
                        .accessibilityLabel("Share invitation")
                        .accessibilityIdentifier(
                            "invitation-credits.referral.share"
                        )

                        SettingsOutlineButton(title: "Copy") {
                            copyReferral()
                        }
                        .disabled(referral.sharePayload == nil)
                        .opacity(referral.sharePayload == nil ? 0.55 : 1)
                        .accessibilityLabel("Copy invitation")
                        .accessibilityIdentifier(
                            "invitation-credits.referral.copy"
                        )
                    }

                    if copied {
                        Text("Copied")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.white.opacity(0.72))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityIdentifier(
                                "invitation-credits.referral.copy-status"
                            )
                    }
                }
            }

            switch overview.referralPhase {
            case .idle, .loading:
                if overview.referral == nil {
                    ChoraLoadingRow(
                        text: "Loading invitation…",
                        identifier: "invitation-credits.referral.loading"
                    )
                }
            case .refreshing:
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Refreshing invitation")
                    .accessibilityIdentifier(
                        "invitation-credits.referral.refreshing"
                    )
            case .failed(let error):
                InvitationCreditInlineError(
                    text: InvitationCreditPresentation.message(
                        error,
                        fallback: "Your invitation couldn’t be loaded."
                    ),
                    identifier: "invitation-credits.referral.error"
                ) {
                    Task { await overview.retryReferral() }
                }
            case .ready:
                EmptyView()
            }
        }
    }

    private func referralValue(
        label: String,
        value: String,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.5))
            Text(value)
                .font(.body.weight(.medium))
                .foregroundColor(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
        }
    }

    private var redemptionSection: some View {
        ChoraSectionSurface(
            title: "Redeem",
            identifier: "invitation-credits.redeem.section"
        ) {
            Button {
                isRedeemExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    Text("Redeem a code")
                        .font(.body.weight(.medium))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .rotationEffect(
                            .degrees(isRedeemExpanded ? 90 : 0)
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Redeem a code")
            .accessibilityValue(isRedeemExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier(
                "invitation-credits.redeem.disclosure"
            )

            if redemption.pendingIntent != nil {
                Text("This code still needs to be redeemed.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        "invitation-credits.redeem.pending"
                    )
            }

            if isRedeemExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Invitation code")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        TextField(
                            "Enter invitation code",
                            text: Binding(
                                get: { redemption.draft },
                                set: redemption.setDraft
                            )
                        )
                        .font(.body)
                        .foregroundColor(.white)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.1))
                                .cardHighlightEffect()
                        )
                        .accessibilityLabel("Invitation code")
                        .accessibilityIdentifier(
                            "invitation-credits.redeem.code"
                        )
                    }

                    redemptionStatus

                    SettingsOutlineButton(title: redemptionActionTitle) {
                        Task { await redemption.submit() }
                    }
                    .disabled(!redemption.canSubmit)
                    .opacity(redemption.canSubmit ? 1 : 0.55)
                    .accessibilityLabel("Redeem invitation code")
                    .accessibilityIdentifier(
                        "invitation-credits.redeem.submit"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var redemptionStatus: some View {
        switch redemption.phase {
        case .idle, .pendingRetry:
            EmptyView()
        case .validating:
            ChoraLoadingRow(
                text: "Validating code…",
                identifier: "invitation-credits.redeem.validating"
            )
        case .redeeming:
            ChoraLoadingRow(
                text: "Redeeming code…",
                identifier: "invitation-credits.redeem.redeeming"
            )
        case .succeeded(let result):
            Text(
                "Code redeemed · \(InvitationCreditPresentation.readable(result.status.canonical))"
            )
            .font(.subheadline.weight(.medium))
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("invitation-credits.redeem.success")
        case .failed(let error):
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    InvitationCreditPresentation.message(
                        error,
                        fallback: "The code couldn’t be redeemed."
                    )
                )
                .font(.subheadline)
                .foregroundColor(Color(red: 1, green: 0.62, blue: 0.64))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("invitation-credits.redeem.error")

                if redemption.pendingIntent != nil {
                    HStack(spacing: 12) {
                        SettingsOutlineButton(title: "Retry") {
                            Task { await redemption.retry() }
                        }
                        .accessibilityLabel("Retry invitation redemption")
                        .accessibilityIdentifier(
                            "invitation-credits.redeem.retry"
                        )

                        SettingsOutlineButton(title: "Discard") {
                            redemption.discard()
                        }
                        .accessibilityLabel("Discard pending invitation code")
                        .accessibilityIdentifier(
                            "invitation-credits.redeem.discard"
                        )
                    }
                }
            }
        }
    }

    private var redemptionActionTitle: String {
        switch redemption.phase {
        case .validating: "Validating…"
        case .redeeming: "Redeeming…"
        default: "Redeem"
        }
    }

    private var historySection: some View {
        ChoraSectionSurface(
            title: "History",
            identifier: "invitation-credits.history.section"
        ) {
            VStack(spacing: 0) {
                NavigationLink {
                    InvitationHistoryView(
                        actorID: actorID,
                        store: invitationHistory
                    )
                } label: {
                    InvitationCreditDisclosureRow(title: "Invitation History")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("invitation-credits.history.link")

                Divider().background(Color.white.opacity(0.16))

                NavigationLink {
                    InvitationRewardsView(actorID: actorID, store: rewards)
                } label: {
                    InvitationCreditDisclosureRow(title: "Rewards")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("invitation-credits.rewards.link")

                Divider().background(Color.white.opacity(0.16))

                NavigationLink {
                    CreditLedgerView(actorID: actorID, store: ledger)
                } label: {
                    InvitationCreditDisclosureRow(title: "Credit Activity")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("invitation-credits.ledger.link")
            }
        }
    }

    private func presentShare() {
        guard let value = overview.referral?.sharePayload else { return }
        sharePayload = InvitationSharePayload(value: value)
    }

    private func copyReferral() {
        guard let value = overview.referral?.sharePayload else { return }
        UIPasteboard.general.string = value
        copied = true
        copyStatusTask?.cancel()
        copyStatusTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    private func refreshAfterRedemption() async {
        await overview.refresh()
        if invitationHistory.actorID != nil {
            await invitationHistory.load(actorID: actorID)
        }
        if rewards.actorID != nil {
            await rewards.load(actorID: actorID)
        }
        if ledger.actorID != nil {
            await ledger.load(actorID: actorID)
        }
        refreshProfileCredits()
    }
}

struct InvitationCreditScreenAnchor: View {
    let identifier: String
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 1))
            .foregroundStyle(.white.opacity(0.01))
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(identifier)
    }
}

private struct InvitationCreditDisclosureRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundColor(.white)
            Spacer(minLength: 12)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct InvitationCreditInlineError: View {
    let text: String
    let identifier: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.subheadline)
                .foregroundColor(Color(red: 1, green: 0.62, blue: 0.64))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
            SettingsOutlineButton(title: "Retry", action: retry)
                .accessibilityLabel("Retry")
                .accessibilityIdentifier("\(identifier.replacingOccurrences(of: ".error", with: "" )).retry")
        }
    }
}

enum InvitationCreditPresentation {
    static func message(
        _ error: InvitationCreditError,
        fallback: String
    ) -> String {
        switch error {
        case .invalidActor, .unauthorized:
            return "Sign in again to continue."
        case .invalidCode:
            return "Enter a valid invitation code."
        case .requestFailed(let message):
            return message ?? fallback
        case .contract:
            return fallback
        }
    }

    static func readable(_ canonical: String) -> String {
        let text = canonical
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let first = text.first else { return "Unknown" }
        return String(first).uppercased() + text.dropFirst()
    }

    static func tier(_ value: CreditTier) -> String {
        switch value {
        case .credit: return "Credits"
        case .premiumCredit: return "Premium Credits"
        case .unknown(let canonical): return readable(canonical)
        }
    }

    static func date(_ value: Date) -> String {
        value.formatted(
            .dateTime.month(.abbreviated).day().year()
        )
    }
}
