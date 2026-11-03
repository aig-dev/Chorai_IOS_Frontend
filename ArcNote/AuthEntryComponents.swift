import SwiftUI

/// Shared presentation only. Each screen retains its existing service/state owner.
struct AuthEntryHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.title2.weight(.semibold)).tracking(-0.4)
                .foregroundStyle(ChoraiTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).foregroundStyle(ChoraiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

struct AuthPrimaryButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    var isLoading = false
    var enabled = true
    var loadingTitle: String? = nil
    let identifier: String
    let action: () -> Void

    private var usesAccent: Bool { enabled || isLoading }
    private var visualLoadingTitle: String {
        dynamicTypeSize.isAccessibilitySize ? title : (loadingTitle ?? title)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                HStack(spacing: 9) {
                    Group {
                        if isLoading {
                            ProgressView().tint(ChoraiTheme.onAccent)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 20, height: 20)
                    Text(visualLoadingTitle)
                }
                .opacity(isLoading ? 1 : 0)
            }
            // Both labels participate in layout, preventing a loading-state height jump.
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
            .font(.body.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(usesAccent ? ChoraiTheme.onAccent : ChoraiTheme.color(light: 0x5A675E, dark: 0xA7B2AB))
            .background(usesAccent ? ChoraiTheme.accent : ChoraiTheme.color(light: 0xE4E7E0, dark: 0x3C403D), in: Capsule())
        }
        .buttonStyle(AuthPressButtonStyle())
        .disabled(!enabled || isLoading)
        .accessibilityLabel(isLoading ? (loadingTitle ?? title) : title)
        .accessibilityValue(isLoading ? "In progress" : "")
        .accessibilityIdentifier(identifier)
    }
}

struct AuthProviderButtons: View {
    let google: () -> Void
    let apple: () -> Void
    var disabled = false
    var body: some View {
        VStack(spacing: 12) {
            Text("or continue with").font(.caption).foregroundStyle(ChoraiTheme.secondaryInk)
            HStack(spacing: 12) {
                provider("Google", logo: Image("auth-google-logo"), identifier: "auth.google", action: google)
                provider("Apple", logo: Image(systemName: "apple.logo"), identifier: "auth.apple", action: apple)
            }
        }
        .disabled(disabled)
    }
    private func provider(_ title: String, logo: Image, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                logo
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color.primary)
                    .accessibilityHidden(true)
                Text(title).font(.subheadline.weight(.semibold))
            }
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Capsule())
                .background(ChoraiTheme.background, in: Capsule())
                .overlay(Capsule().stroke(ChoraiTheme.separator, lineWidth: 1))
        }
        .buttonStyle(AuthPressButtonStyle())
        .foregroundStyle(ChoraiTheme.ink)
        .accessibilityLabel("Continue with \(title)")
        .accessibilityIdentifier(identifier)
    }
}

/// One quiet press response throughout entry; reduced motion keeps only the tint change.
struct AuthPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.16), value: configuration.isPressed)
    }
}

struct AuthProgress: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let step: Int
    var total = 6
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(ChoraiTheme.separator)
                .overlay(alignment: .leading) {
                    Capsule().fill(ChoraiTheme.accent)
                        .frame(width: geometry.size.width * CGFloat(step) / CGFloat(max(total, 1)))
                }
        }
        .frame(width: 72, height: 5)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: step)
        .accessibilityLabel("Account setup")
        .accessibilityValue("Step \(step) of \(total)")
    }
}

extension View {
    func authEntryPage() -> some View {
        foregroundStyle(ChoraiTheme.ink)
            .tint(ChoraiTheme.accent)
            .background(ChoraiTheme.background.ignoresSafeArea())
    }
}
