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
            ChoraiBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("chorai")
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .foregroundStyle(ChoraiTheme.accent)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(campaign?.content.title ?? "Join the Chorai Private Beta")
                            .font(.system(.largeTitle, design: .serif).weight(.medium))
                            .foregroundStyle(ChoraiTheme.ink)
                        Text(
                            campaign?.content.description ??
                                "Enter your Product Access Code to unlock the full app."
                        )
                        .font(.body)
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        TextField("CRAI-XXXX", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .foregroundStyle(ChoraiTheme.ink)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 56)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(ChoraiTheme.separator, lineWidth: 0.75)
                            )
                            .accessibilityIdentifier("access.code")

                        Button {
                            store.save(code)
                            Task { await store.claim() }
                        } label: {
                            HStack(spacing: 10) {
                                if store.phase == .claiming {
                                    ProgressView().tint(ChoraiTheme.ink)
                                }
                                Text(
                                    store.phase == .claiming
                                        ? "Checking…"
                                        : campaign?.content.actionLabel ?? "Continue"
                                )
                                .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 56)
                            .foregroundStyle(ChoraiTheme.onAccent)
                            .background(ChoraiTheme.accent, in: Capsule())
                        }
                        .disabled(store.phase == .claiming)
                        .accessibilityIdentifier("access.claim")

                        if unavailable || store.phase == .failed {
                            Button("Retry access check") {
                                Task { await store.load() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ChoraiTheme.ink)
                            .accessibilityIdentifier("access.retry")
                        }

                        if let message = store.message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("access.message")
                        }
                    }

                    Button("Sign out", action: onSignOut)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("access.signout")
                }
                .padding(.horizontal, 28)
                .padding(.top, 12)
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
            ChoraiBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image("logo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(ChoraiTheme.ink)
                        .frame(height: 50)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Join the Private Beta")
                            .font(.system(
                                size: 32,
                                weight: .bold,
                                design: .rounded
                            ))
                            .foregroundStyle(ChoraiTheme.ink)

                        Text(
                            "Enter your Product Access Code to create an account."
                        )
                        .font(.system(
                            size: 16,
                            weight: .regular,
                            design: .rounded
                        ))
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        TextField("CRAI-XXXX", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .foregroundStyle(ChoraiTheme.ink)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 56)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(ChoraiTheme.separator, lineWidth: 0.75)
                            )
                            .accessibilityLabel("Product Access Code")
                            .accessibilityIdentifier("private-beta.code")
                            .disabled(isChecking)

                        Button(action: continueToAccountEntry) {
                            HStack(spacing: 10) {
                                if isChecking {
                                    ProgressView()
                                        .tint(ChoraiTheme.ink)
                                        .accessibilityIdentifier(
                                            "private-beta.checking"
                                        )
                                }
                                Text(isChecking ? "Checking…" : "Continue")
                                    .font(.headline)
                            }
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 56)
                                .foregroundStyle(ChoraiTheme.onAccent)
                                .background(ChoraiTheme.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isChecking)
                        .accessibilityIdentifier("private-beta.continue")

                        if let validationMessage {
                            Text(validationMessage)
                                .font(.footnote)
                                .foregroundStyle(
                                    .red
                                )
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("private-beta.message")
                        }
                    }

                    NavigationLink(destination: SignInView()) {
                        Text("Already have an account? Sign In")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ChoraiTheme.secondaryInk)
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
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .navigationTitle("Private Beta")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: cancelAndGoBack) { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Back").accessibilityIdentifier("private-beta.back")
            }
        }
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
