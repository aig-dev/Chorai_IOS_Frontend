import CoreFlow
import SwiftUI

struct CoreTabBar: View {
    private enum Metrics {
        static let selectedIconFrame: CGFloat = 35
        static let unselectedIconFrame: CGFloat = 26
        static let selectedIconScale: CGFloat = 1.1
        static let labelFontSize: CGFloat = 12
        static let tabSpacing: CGFloat = 4
        static let horizontalContentInset: CGFloat = 20
    }

    @Binding var selectedTab: CoreTab

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 0) {
            tab(.flow, label: "Explore", image: "tab_explore", activeImage: "tab_explore_active", identifier: "flow")
            tab(.library, label: "Home", image: "tab_home", activeImage: "tab_home_active", identifier: "library")
            tab(.chat, label: "Chat", image: "tab_chat", activeImage: "tab_chat_active", identifier: "chat")
        }
        .frame(height: ZenVisualTokens.tabHeight)
        .padding(.horizontal, Metrics.horizontalContentInset)
        .background(tabBackground)
        .padding(.top, 8)
    }

    private var tabBackground: some View {
        ZStack {
            if reduceTransparency {
                Capsule().fill(Color(red: 0.07, green: 0.055, blue: 0.12))
            } else {
                Capsule().fill(.ultraThinMaterial.opacity(0.55))
                Capsule()
                    .fill(Color(red: 0.21, green: 0.13, blue: 0.29))
                    .opacity(0.8)
            }
            Capsule()
                .stroke(
                    Color.white.opacity(contrast == .increased ? 0.42 : 0.3),
                    lineWidth: 1
                )
        }
    }

    private func tab(
        _ tab: CoreTab,
        label: String,
        image: String,
        activeImage: String,
        identifier: String
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: Metrics.tabSpacing) {
                Image(selectedTab == tab ? activeImage : image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: selectedTab == tab
                            ? Metrics.selectedIconFrame
                            : Metrics.unselectedIconFrame,
                        height: selectedTab == tab
                            ? Metrics.selectedIconFrame
                            : Metrics.unselectedIconFrame
                    )
                    .scaleEffect(
                        selectedTab == tab ? Metrics.selectedIconScale : 1
                    )
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.7),
                        value: selectedTab == tab
                    )

                Text(label)
                    .font(
                        .system(
                            size: Metrics.labelFontSize,
                            weight: selectedTab == tab ? .semibold : .medium
                        )
                    )
                    .foregroundColor(
                        selectedTab == tab ? .white : .white.opacity(0.7)
                    )
                    .animation(
                        .easeInOut(duration: 0.3),
                        value: selectedTab == tab
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(selectedTab == tab ? "Selected" : "")
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .accessibilityIdentifier("tab.\(identifier)")
    }
}
