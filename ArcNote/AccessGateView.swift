import CoreFlow
import SwiftUI

@MainActor
struct AccessGateView: View {
    @ObservedObject var store: AccessStore
    let unavailable: Bool
    let onAllowed: (AccessState) -> Void
    let onSignOut: () -> Void

    @State private var code = ""
    @State private var campaign: CampaignBlock?

    init(
        store: AccessStore,
        unavailable: Bool = false,
        onAllowed: @escaping (AccessState) -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.store = store
        self.unavailable = unavailable
        self.onAllowed = onAllowed
        self.onSignOut = onSignOut
    }

    var body: some View {
        ZStack {
            Image("login_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 54)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(campaign?.content.title ?? "Join the Chorai Private Beta")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(
                            campaign?.content.description ??
                                "Enter your Product Access Code to unlock the full app."
                        )
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Product Access Code", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 56)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(.white.opacity(0.28), lineWidth: 1)
                            )
                            .accessibilityIdentifier("access.code")

                        Button {
                            store.save(code)
                            Task { await store.claim() }
                        } label: {
                            HStack(spacing: 10) {
                                if store.phase == .claiming {
                                    ProgressView().tint(.white)
                                }
                                Text(
                                    store.phase == .claiming
                                        ? "Checking…"
                                        : campaign?.content.actionLabel ?? "Continue"
                                )
                                .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .foregroundStyle(.white)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.37, green: 0.22, blue: 0.61),
                                        Color(red: 0.18, green: 0.53, blue: 0.58),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: Capsule()
                            )
                        }
                        .disabled(store.phase == .claiming)
                        .accessibilityIdentifier("access.claim")

                        if unavailable || store.phase == .failed {
                            Button("Retry access check") {
                                Task { await store.load() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .accessibilityIdentifier("access.retry")
                        }

                        if let message = store.message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(Color(red: 1, green: 0.68, blue: 0.7))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("access.message")
                        }
                    }

                    Button("Sign out", action: onSignOut)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("access.signout")
                }
                .padding(.horizontal, 28)
                .padding(.top, 72)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            if code.isEmpty {
                code = store.pendingCode ?? KeychainStore.shared.load() ?? ""
            }
        }
        .task {
            async let nextCampaign = NetworkAccess.shared.campaign()
            await store.load()
            campaign = await nextCampaign
        }
        .onChange(of: store.pendingCode) { pending in
            if let pending, pending != code { code = pending }
        }
        .onChange(of: store.phase) { phase in
            guard phase == .allowed, let state = store.state else { return }
            onAllowed(state)
        }
    }
}
