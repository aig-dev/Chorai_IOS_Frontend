import CoreFlow
import SwiftUI

/// Embedded hosts use this compact control; the product root uses system TabView.
struct CoreTabBar: View {
    @Binding var selectedTab: CoreTab

    var body: some View {
        HStack(spacing: 4) {
            tab(.flow, label: "Explore", symbol: "safari", identifier: "flow")
            tab(.library, label: "Home", symbol: "square.stack", identifier: "library")
            tab(.chat, label: "Chat", symbol: "bubble.left.and.bubble.right", identifier: "chat")
        }
        .padding(6)
        .choraiGlassSurface(cornerRadius: 32)
        .padding(.top, 8)
    }

    private func tab(_ tab: CoreTab, label: String, symbol: String, identifier: String) -> some View {
        Button { selectedTab = tab } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(label).font(.caption2.weight(selectedTab == tab ? .semibold : .regular))
            }
            .foregroundStyle(selectedTab == tab ? ChoraiTheme.ink : ChoraiTheme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selectedTab == tab ? ChoraiTheme.selection : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(selectedTab == tab ? "Selected" : "")
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .accessibilityIdentifier("tab.\(identifier)")
    }
}
