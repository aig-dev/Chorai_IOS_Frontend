import SwiftUI
import UIKit

private struct ActionBoxTileSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = ActionBoxLayoutMetrics.standardTileSize
}

private extension EnvironmentValues {
    var actionBoxTileSize: CGFloat {
        get { self[ActionBoxTileSizeKey.self] }
        set { self[ActionBoxTileSizeKey.self] = newValue }
    }
}

private enum ActionBoxLayoutMetrics {
    static let standardTileSize: CGFloat = 90
    static let minimumTileSize: CGFloat = 44
    static let tileSpacing: CGFloat = 15
    static let contentTopPadding: CGFloat = 16
    static let contentBottomPadding: CGFloat = 16
    static let surfaceScale: CGFloat = 0.9

    static func tileSize(
        surfaceSide: CGFloat,
        rowCount: Int
    ) -> CGFloat {
        let safeRowCount = max(rowCount, 1)
        let totalSpacing = CGFloat(safeRowCount - 1) * tileSpacing
        let availableHeight = surfaceSide
            - contentTopPadding
            - contentBottomPadding
            - totalSpacing
        return max(
            minimumTileSize,
            min(standardTileSize, availableHeight / CGFloat(safeRowCount))
        )
    }
}

enum ActionBoxIcon {
    case asset(String)
    case system(String)
}

struct ActionBoxOverlay<Content: View>: View {
    @Binding var isPresented: Bool
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let rowCount: Int
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateContent = false
    @State private var canDismissFromBackdrop = false

    init(
        isPresented: Binding<Bool>,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        rowCount: Int,
        @ViewBuilder content: () -> Content
    ) {
        _isPresented = isPresented
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.rowCount = rowCount
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = max(
                0,
                geometry.size.height
                    - geometry.safeAreaInsets.top
                    - geometry.safeAreaInsets.bottom
            )
            let surfaceSide = min(
                geometry.size.width * ActionBoxLayoutMetrics.surfaceScale,
                availableHeight * ActionBoxLayoutMetrics.surfaceScale
            )
            let preferredSurfaceY = geometry.size.height / 2.2
            let minimumSurfaceY = geometry.safeAreaInsets.top + surfaceSide / 2
            let maximumSurfaceY = geometry.size.height
                - geometry.safeAreaInsets.bottom
                - surfaceSide / 2
            let surfaceY = min(
                max(preferredSurfaceY, minimumSurfaceY),
                maximumSurfaceY
            )
            let tileSize = ActionBoxLayoutMetrics.tileSize(
                surfaceSide: surfaceSide,
                rowCount: rowCount
            )

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

                VStack(spacing: 0) {
                    Spacer(
                        minLength: ActionBoxLayoutMetrics.contentTopPadding
                    )

                    content
                        .environment(\.actionBoxTileSize, tileSize)

                    Spacer(
                        minLength: ActionBoxLayoutMetrics.contentBottomPadding
                    )
                }
                .frame(
                    width: surfaceSide,
                    height: surfaceSide
                )
                .background(actionBoxBackground)
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .cornerRadius(20)
                .clipped()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("\(accessibilityIdentifier).surface")
                .position(
                    x: geometry.size.width / 2,
                    y: surfaceY
                )
                .opacity(animateContent ? 1 : 0)
                .scaleEffect(animateContent ? 1 : 0.8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) {
            dismiss()
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
            DispatchQueue.main.async {
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
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
            DispatchQueue.main.async {
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
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

    @Environment(\.actionBoxTileSize) private var tileSize
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
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
            }
            .frame(width: tileSize, height: tileSize)
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
