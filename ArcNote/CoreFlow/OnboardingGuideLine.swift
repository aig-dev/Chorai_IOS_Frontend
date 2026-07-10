import CoreFlow
import SwiftUI

struct OnboardingGuideLine: View {
    @ObservedObject var store: OnboardingGuideStore

    var body: some View {
        if let scene = store.guideScene,
           let state = store.session?.state {
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

                    if scene.canSkip {
                        Button(action: store.skip) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.54))
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isSending)
                        .accessibilityLabel("Not now")
                        .accessibilityIdentifier("onboarding.skip")
                    }
                }

                Text(scene.text)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineSpacing(2)
                    .lineLimit(state == "deepen_signal" ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if state == "deepen_signal" {
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
                }

                if store.lastError != nil {
                    Text("Connection paused · tap to retry")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .accessibilityIdentifier("onboarding.error")
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
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture {
                if store.lastError != nil {
                    store.retryPendingEvidence()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onboarding.guide")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
