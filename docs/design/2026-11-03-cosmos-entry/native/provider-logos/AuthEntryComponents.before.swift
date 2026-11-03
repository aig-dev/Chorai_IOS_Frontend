import SwiftUI

/// Shared presentation only. Each screen retains its existing service/state owner.
struct AuthEntryHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.headline).foregroundStyle(ChoraiTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).foregroundStyle(ChoraiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

struct AuthPrimaryButton: View {
    let title: String
    var isLoading = false
    var enabled = true
    let identifier: String
    let action: () -> Void

    private var usesAccent: Bool { enabled || isLoading }

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(ChoraiTheme.onAccent) }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(usesAccent ? ChoraiTheme.onAccent : ChoraiTheme.secondaryInk)
            .background(usesAccent ? ChoraiTheme.accent : ChoraiTheme.raisedSurface, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isLoading)
        .accessibilityLabel(isLoading ? "Working" : title)
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
                provider("Google", identifier: "auth.google", action: google)
                provider("Apple", identifier: "auth.apple", action: apple)
            }
        }
        .disabled(disabled)
    }
    private func provider(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Capsule())
                .background(ChoraiTheme.background, in: Capsule())
                .overlay(Capsule().stroke(ChoraiTheme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(ChoraiTheme.ink)
        .accessibilityLabel("Continue with \(title)")
        .accessibilityIdentifier(identifier)
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
