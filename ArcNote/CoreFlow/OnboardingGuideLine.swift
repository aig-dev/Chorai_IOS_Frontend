import CoreFlow
import SwiftUI

struct OnboardingGuideLine: View {
    @ObservedObject var store: OnboardingGuideStore
    let allowedStates: Set<String>?

    init(
        store: OnboardingGuideStore,
        allowedStates: Set<String>? = nil
    ) {
        self.store = store
        self.allowedStates = allowedStates
    }

    var body: some View {
        if let scene = store.guideScene,
           let state = store.session?.state,
           state == "deepen_signal",
           allowedStates?.contains(state) != false {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Text("Chora")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(1.1)
                        .foregroundStyle(ZenVisualTokens.accent.opacity(0.9))

                    Spacer(minLength: 8)

                    if store.isSending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white.opacity(0.64))
                    }
                }

                Text(scene.text)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineSpacing(2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(scene.choices, id: \.id) { choice in
                            Button(choice.label) {
                                store.receive(.deepenChoice(id: choice.id))
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.13), lineWidth: 1)
                                    )
                            )
                            .disabled(store.isSending)
                            .accessibilityIdentifier("onboarding.choice.\(choice.id)")
                        }
                    }
                }

                if store.lastError != nil {
                    Button(action: store.retryPendingEvidence) {
                        Text("Connection paused · Retry")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .disabled(store.isSending)
                    .accessibilityLabel("Retry onboarding")
                    .accessibilityIdentifier("onboarding.retry")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboarding.guide")
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if store.lastError != nil,
                  let state = store.session?.state,
                  allowedStates?.contains(state) != false {
            Button(action: store.retryPendingEvidence) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Connection paused")
                        .font(.system(
                            size: 13,
                            weight: .medium,
                            design: .rounded
                        ))

                    Spacer(minLength: 8)

                    Text("Retry")
                        .font(.system(
                            size: 12,
                            weight: .semibold,
                            design: .rounded
                        ))
                }
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.62))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isSending)
            .accessibilityLabel("Retry onboarding")
            .accessibilityIdentifier("onboarding.retry")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct ContextualGuideCallout: View {
    @ObservedObject var store: ContextualGuideTipStore
    let tip: ContextualGuideTipID
    let onboardingState: String?
    let targetIsVisible: Bool

    private var isVisible: Bool {
        store.isVisible(
            tip,
            onboardingState: onboardingState,
            targetIsVisible: targetIsVisible
        )
    }

    var body: some View {
        if isVisible {
            Text(tip.copy)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 268, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {}
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tip.copy)
                .accessibilityAction(named: Text("Dismiss tip")) {
                    store.dismiss(
                        tip,
                        onboardingState: onboardingState,
                        targetIsVisible: targetIsVisible
                    )
                }
                .accessibilityIdentifier("onboarding.tip.\(tip.accessibilityIdentifier)")
        }
    }
}

struct ContextualGuideTargetHalo: View {
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        if isVisible {
            Circle()
                .stroke(ZenVisualTokens.accent.opacity(0.88), lineWidth: 1.5)
                .frame(width: 54, height: 54)
                .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.12 : 0.92))
                .opacity(reduceMotion ? 0.94 : (isPulsing ? 0.5 : 0.94))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onAppear(perform: updatePulse)
                .onChange(of: reduceMotion) { _ in
                    updatePulse()
                }
        }
    }

    private func updatePulse() {
        guard !reduceMotion else {
            isPulsing = false
            return
        }

        withAnimation(
            .easeInOut(duration: 0.9)
                .repeatForever(autoreverses: true)
        ) {
            isPulsing = true
        }
    }
}

struct ContextualGuideRoundedTargetHalo: View {
    let isVisible: Bool
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        if isVisible {
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .stroke(ZenVisualTokens.accent.opacity(0.88), lineWidth: 1.5)
            .scaleEffect(reduceMotion ? 0.99 : (isPulsing ? 1 : 0.985))
            .opacity(reduceMotion ? 0.94 : (isPulsing ? 0.52 : 0.94))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear(perform: updatePulse)
            .onChange(of: reduceMotion) { _ in
                updatePulse()
            }
        }
    }

    private func updatePulse() {
        guard !reduceMotion else {
            isPulsing = false
            return
        }

        withAnimation(
            .easeInOut(duration: 0.9)
                .repeatForever(autoreverses: true)
        ) {
            isPulsing = true
        }
    }
}
