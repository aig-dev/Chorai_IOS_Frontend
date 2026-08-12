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
                        TextField("CRAI-XXXX", text: $code)
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

@MainActor
struct PrivateBetaEntryView: View {
    @Environment(\.dismiss) private var dismiss
    private let preflighter: any AccessCodePreflighting
    private let codeStore: any CodeStoring
    private let onBack: (() -> Void)?

    @State private var code = ""
    @State private var validationMessage: String?
    @State private var showSignUp = false
    @State private var isChecking = false
    @State private var requestID: UUID?
    @State private var checkTask: Task<Void, Never>?

    init(
        preflighter: any AccessCodePreflighting = NetworkAccess.shared,
        codeStore: any CodeStoring = KeychainStore.shared,
        onBack: (() -> Void)? = nil
    ) {
        self.preflighter = preflighter
        self.codeStore = codeStore
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            Image("login_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Button(action: cancelAndGoBack) {
                            Image(systemName: "arrow.left")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("private-beta.back")

                        Spacer()
                    }

                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 50)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Join the Private Beta")
                            .font(.system(
                                size: 32,
                                weight: .bold,
                                design: .rounded
                            ))
                            .foregroundStyle(.white)

                        Text(
                            "Enter your Product Access Code to create an account."
                        )
                        .font(.system(
                            size: 16,
                            weight: .regular,
                            design: .rounded
                        ))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        TextField("CRAI-XXXX", text: $code)
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
                            .accessibilityLabel("Product Access Code")
                            .accessibilityIdentifier("private-beta.code")
                            .disabled(isChecking)

                        Button(action: continueToAccountEntry) {
                            HStack(spacing: 10) {
                                if isChecking {
                                    ProgressView()
                                        .tint(.white)
                                        .accessibilityIdentifier(
                                            "private-beta.checking"
                                        )
                                }
                                Text(isChecking ? "Checking…" : "Continue")
                                    .font(.headline)
                            }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .foregroundStyle(.white)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(
                                                red: 0.37,
                                                green: 0.22,
                                                blue: 0.61
                                            ),
                                            Color(
                                                red: 0.18,
                                                green: 0.53,
                                                blue: 0.58
                                            ),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isChecking)
                        .accessibilityIdentifier("private-beta.continue")

                        if let validationMessage {
                            Text(validationMessage)
                                .font(.footnote)
                                .foregroundStyle(
                                    Color(red: 1, green: 0.68, blue: 0.7)
                                )
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("private-beta.message")
                        }
                    }

                    NavigationLink(destination: SignInView()) {
                        Text("Already have an account? Sign In")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(isChecking)
                    .accessibilityIdentifier("private-beta.sign-in")
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSignUp) {
            SignUpView()
        }
        .onAppear {
            code = codeStore.load() ?? ""
        }
        .onDisappear {
            cancelCheck()
        }
    }

    private func continueToAccountEntry() {
        guard isChecking == false else { return }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (9...64).contains(trimmedCode.count) else {
            validationMessage = "Enter a valid Product Access Code."
            return
        }

        let candidate = trimmedCode
        let id = UUID()
        requestID = id
        isChecking = true
        validationMessage = nil
        checkTask?.cancel()
        checkTask = Task {
            do {
                let result = try await preflighter.preflight(
                    accessCode: candidate
                )
                guard !Task.isCancelled, requestID == id else { return }
                finishCheck()
                guard result.available else {
                    applyPreflightError(.invalid, candidate: candidate)
                    return
                }
                codeStore.save(candidate)
                showSignUp = true
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                finishCheck()
                applyPreflightError(
                    error as? AccessCodePreflightError
                        ?? .temporarilyUnavailable,
                    candidate: candidate
                )
            }
        }
    }

    private func finishCheck() {
        requestID = nil
        isChecking = false
        checkTask = nil
    }

    private func applyPreflightError(
        _ error: AccessCodePreflightError,
        candidate: String
    ) {
        switch error {
        case .invalid:
            let storedCode = codeStore.load()?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if storedCode == candidate {
                codeStore.clear()
            }
            validationMessage =
                "This Product Access Code is invalid or no longer available."
        case .rateLimited(let retryAfterSeconds):
            if let retryAfterSeconds {
                validationMessage =
                    "Too many checks. Try again in \(retryAfterSeconds) seconds."
            } else {
                validationMessage = "Too many checks. Try again shortly."
            }
        case .temporarilyUnavailable:
            validationMessage =
                "Code verification is temporarily unavailable. Try again."
        }
    }

    private func cancelAndGoBack() {
        cancelCheck()
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    private func cancelCheck() {
        checkTask?.cancel()
        checkTask = nil
        requestID = nil
        isChecking = false
    }
}
