import CoreFlow
import SwiftUI

struct CoreTabBar: View {
    @Binding var selectedTab: CoreTab

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 0) {
            tab(.flow, label: "Flow", image: "rectangle.stack", identifier: "flow")
            tab(.library, label: "Library", image: "books.vertical", identifier: "library")
            tab(.chat, label: "Chat", image: "bubble.left.and.bubble.right", identifier: "chat")
        }
        .frame(height: ZenVisualTokens.tabHeight)
        .background(tabBackground)
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [Color.clear, ZenVisualTokens.background.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var tabBackground: some View {
        ZStack {
            if reduceTransparency {
                Capsule().fill(Color(red: 0.07, green: 0.055, blue: 0.12))
            } else {
                Capsule().fill(.ultraThinMaterial.opacity(0.55))
            }
            Capsule()
                .stroke(
                    Color.white.opacity(contrast == .increased ? 0.42 : 0.14),
                    lineWidth: 1
                )
        }
    }

    private func tab(
        _ tab: CoreTab,
        label: String,
        image: String,
        identifier: String
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: image)
                    .font(.system(size: 17, weight: selectedTab == tab ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
            }
            .foregroundStyle(.white.opacity(selectedTab == tab ? 1 : 0.55))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.\(identifier)")
    }
}
