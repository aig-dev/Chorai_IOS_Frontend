import SwiftUI

enum ActionBoxIcon {
    case asset(String)
    case system(String)
}

struct ActionBoxOverlay<Content: View>: View {
    @Binding var isPresented: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let closeAccessibilityIdentifier: String
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateContent = false
    @State private var canDismissFromBackdrop = false

    init(
        isPresented: Binding<Bool>,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        closeAccessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) {
        _isPresented = isPresented
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.closeAccessibilityIdentifier = closeAccessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .opacity(animateContent ? 0.5 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard canDismissFromBackdrop else { return }
                        dismiss()
                    }
                    .accessibilityHidden(true)

                ZStack {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: dismiss) {
                                Image(systemName: "xmark")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close")
                            .accessibilityIdentifier(closeAccessibilityIdentifier)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                        Spacer()
                    }

                    content
                        .padding(.top, 44)
                        .padding(.horizontal, 0)
                }
                .background(actionBoxBackground)
                .cornerRadius(20)
                .frame(
                    width: geometry.size.width * 0.9,
                    height: geometry.size.width * 0.9
                )
                .clipped()
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2.2
                )
                .opacity(animateContent ? 1 : 0)
                .scaleEffect(animateContent ? 1 : 0.8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
        .onAppear {
            if reduceMotion {
                animateContent = true
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    animateContent = true
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            canDismissFromBackdrop = true
        }
        .onDisappear {
            canDismissFromBackdrop = false
        }
    }

    private func dismiss() {
        canDismissFromBackdrop = false

        guard !reduceMotion else {
            animateContent = false
            isPresented = false
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            animateContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isPresented = false
        }
    }

    private var actionBoxBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial.opacity(1))
            .overlay(topLeftHighlight)
            .overlay(bottomRightHighlight)
            .overlay(topEdgeHighlight)
            .overlay(bottomEdgeHighlight)
    }

    private var topLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }

    private var bottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }

    private var topEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }

    private var bottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
}

struct ActionBoxTile: View {
    let icon: ActionBoxIcon
    let text: String
    let color: Color
    let role: ButtonRole?
    let isEnabled: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .caption) private var scaledLabelSize: CGFloat = 14

    init(
        icon: ActionBoxIcon,
        text: String,
        color: Color,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.text = text
        self.color = color
        self.role = role
        self.isEnabled = isEnabled
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            VStack(spacing: 6) {
                iconView
                    .frame(width: 38, height: 33)
                    .foregroundColor(color)

                Text(text)
                    .font(.system(size: min(scaledLabelSize, 18), weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 84, height: 84)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        Color(
                            red: 177 / 255,
                            green: 177 / 255,
                            blue: 177 / 255,
                            opacity: 10 / 100
                        )
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(text)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case let .asset(name):
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case let .system(name):
            Image(systemName: name)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct ActionBoxEmptyTile: View {
    var body: some View {
        Color.clear
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)
    }
}
