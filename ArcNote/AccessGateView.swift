import CoreFlow
import SwiftUI
import UIKit

@MainActor
struct AccessGateView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var store: AccessStore
    let unavailable: Bool
    let onAllowed: (AccessState) -> Void
    let onSignOut: () -> Void

    @State private var code = ""
    @State private var campaign: CampaignBlock?
    @FocusState private var codeFocused: Bool
    @ScaledMetric(relativeTo: .title) private var codeSize = 29.0

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
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        AuthEntryHeading(
                            title: campaign?.content.title ?? "Your invitation to Chorai",
                            subtitle: campaign?.content.description ??
                                "Your account needs Private Beta access."
                        )

                        TextField("CRAI-XXXX", text: $code)
                            .accessCodeInput(font: dynamicTypeSize.isAccessibilitySize ? .body : .system(size: codeSize))
                            .padding(.top, accessInputSpacing(height: geometry.size.height, dynamicTypeSize: dynamicTypeSize))
                            .focused($codeFocused)
                            .onSubmit(claim)
                            .disabled(store.phase == .claiming)
                            .accessibilityIdentifier("access.code")

                        if let message = store.message {
                            accessError(message)
                                .accessibilityIdentifier("access.message")
                                .id("access.message")
                        }

                        if unavailable || store.phase == .failed {
                            Button("Retry access check") {
                                Task { await store.load() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("access.retry")
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 26)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: store.message) { message in
                    guard let message else { return }
                    proxy.scrollTo("access.message", anchor: .center)
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            AuthPrimaryButton(
                title: campaign?.content.actionLabel ?? "Continue",
                isLoading: store.phase == .claiming,
                loadingTitle: "Checking access…",
                identifier: "access.claim",
                action: claim
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(ChoraiTheme.background)
        }
        .authEntryPage()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("chorai")
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(ChoraiTheme.ink)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Sign out", action: onSignOut)
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("access.signout")
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

    private func claim() {
        guard store.phase != .claiming else { return }
        codeFocused = false
        store.save(code)
        Task { await store.claim() }
    }
}

@MainActor
struct PrivateBetaEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let preflighter: any AccessCodePreflighting
    private let codeStore: any CodeStoring
    private let onBack: (() -> Void)?
    private let returnsToSignIn: Bool

    @State private var code = ""
    @State private var validationMessage: String?
    @State private var hasLoadedDraft = false
    @State private var showSignUp = false
    @State private var isChecking = false
    @State private var requestID: UUID?
    @State private var checkTask: Task<Void, Never>?
    @FocusState private var codeFocused: Bool
    @ScaledMetric(relativeTo: .title) private var codeSize = 29.0

    init(
        preflighter: any AccessCodePreflighting = NetworkAccess.shared,
        codeStore: any CodeStoring = KeychainStore.shared,
        onBack: (() -> Void)? = nil,
        returnsToSignIn: Bool = false
    ) {
        self.preflighter = preflighter
        self.codeStore = codeStore
        self.onBack = onBack
        self.returnsToSignIn = returnsToSignIn
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        AuthEntryHeading(
                            title: "Your invitation to Chorai",
                            subtitle: "Enter your Product Access Code to get started."
                        )

                        TextField("CRAI-XXXX", text: $code)
                            .accessCodeInput(font: dynamicTypeSize.isAccessibilitySize ? .body : .system(size: codeSize))
                            .padding(.top, accessInputSpacing(height: geometry.size.height, dynamicTypeSize: dynamicTypeSize))
                            .focused($codeFocused)
                            .onSubmit(continueToAccountEntry)
                            .disabled(isChecking)
                            .accessibilityIdentifier("private-beta.code")

                        if let validationMessage {
                            accessError(validationMessage)
                                .accessibilityIdentifier("private-beta.message")
                                .id("private-beta.message")
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 26)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: validationMessage) { message in
                    guard let message else { return }
                    proxy.scrollTo("private-beta.message", anchor: .center)
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            AuthPrimaryButton(
                title: "Continue",
                isLoading: isChecking,
                loadingTitle: "Checking access…",
                identifier: "private-beta.continue",
                action: continueToAccountEntry
            )
            .overlay(alignment: .leading) {
                if isChecking {
                    Color.clear
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Checking access")
                        .accessibilityIdentifier("private-beta.checking")
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(ChoraiTheme.background)
        }
        .authEntryPage()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: cancelAndGoBack) {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier("private-beta.back")
            }
            ToolbarItem(placement: .principal) {
                AuthProgress(step: 1)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Group {
                    if returnsToSignIn {
                        Button("Log In", action: cancelAndGoBack)
                    } else {
                        NavigationLink("Log In", destination: SignInView())
                    }
                }
                .font(.subheadline.weight(.medium))
                .frame(minWidth: 44, minHeight: 44)
                .disabled(isChecking)
                .accessibilityIdentifier("private-beta.sign-in")
            }
        }
        .navigationDestination(isPresented: $showSignUp) {
            SignUpView()
        }
        .onAppear {
            // Reloading on every return would replace an unsubmitted code with stored data.
            guard !hasLoadedDraft else { return }
            hasLoadedDraft = true
            code = codeStore.load() ?? ""
        }
        .onChange(of: code) { _ in
            // onChange observes genuine value changes, not focus/keyboard writes of the same code.
            validationMessage = nil
        }
        .task {
            do {
                try await Task.sleep(for: .milliseconds(reduceMotion ? 50 : 370))
                guard !isChecking, !showSignUp else { return }
                codeFocused = true
            } catch {}
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
                codeFocused = false
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

private func accessInputSpacing(height: CGFloat, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 24 : min(108, max(28, height * 0.19))
}

private extension View {
    func accessCodeInput(font: Font) -> some View {
        self
            .font(font)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .multilineTextAlignment(.center)
            .submitLabel(.continue)
            .foregroundStyle(ChoraiTheme.ink)
            .frame(minHeight: 52)
            .accessibilityLabel("Product Access Code")
    }
}

private func accessError(_ message: String) -> some View {
    Text(message)
        .font(.footnote)
        .foregroundStyle(.red)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
}
