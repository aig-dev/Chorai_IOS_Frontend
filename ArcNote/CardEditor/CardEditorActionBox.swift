import SwiftUI

struct CardEditorActionBox: View {
    @Binding var isPresented: Bool
    let isEnabled: Bool
    let isPinned: Bool
    let onBackground: () -> Void
    let onSpark: () -> Void
    let onMerge: () -> Void
    let onShare: () -> Void
    let onLink: () -> Void
    let onRoot: () -> Void
    let onRemove: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        ActionBoxOverlay(
            isPresented: $isPresented,
            accessibilityLabel: "Card Actions",
            accessibilityIdentifier: "cardEditorActionsOverlay",
            closeAccessibilityIdentifier: "cardEditorActionsClose"
        ) {
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    ActionBoxTile(
                        icon: .system("photo"),
                        text: "Background",
                        color: .blue,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: "cardEditorBackgroundButton"
                    ) {
                        dismissThenPerform(onBackground)
                    }
                    ActionBoxTile(
                        icon: .asset("menu_spark"),
                        text: "Spark",
                        color: .red,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: "cardEditorActionSpark"
                    ) {
                        dismissThenPerform(onSpark)
                    }
                    ActionBoxTile(
                        icon: .asset("menu_merge"),
                        text: "Merge",
                        color: .orange,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: "cardEditorActionMerge"
                    ) {
                        dismissThenPerform(onMerge)
                    }
                }

                HStack(spacing: 15) {
                    ActionBoxEmptyTile()
                    ActionBoxTile(
                        icon: .asset("menu_share"),
                        text: "Share",
                        color: .green,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: "cardEditorActionShare"
                    ) {
                        dismissThenPerform(onShare)
                    }
                    ActionBoxTile(
                        icon: .asset("menu_link"),
                        text: "Link",
                        color: .pink,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: "cardEditorActionLink"
                    ) {
                        dismissThenPerform(onLink)
                    }
                }

                HStack(spacing: 15) {
                    ActionBoxTile(
                        icon: .asset("menu_root"),
                        text: "Root",
                        color: .teal,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: "cardEditorActionRoot"
                    ) {
                        dismissThenPerform(onRoot)
                    }
                    ActionBoxTile(
                        icon: .asset("menu_remove"),
                        text: "Remove",
                        color: .orange,
                        role: .destructive,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: "cardEditorActionRemove"
                    ) {
                        dismissThenPerform(onRemove)
                    }
                    ActionBoxTile(
                        icon: .asset(isPinned ? "unpin" : "menu_pin"),
                        text: isPinned ? "Unpin" : "Pin",
                        color: .orange,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: "cardEditorActionPin"
                    ) {
                        dismissThenPerform(onTogglePin)
                    }
                }
            }
            .accessibilityIdentifier("cardEditorActionGrid")
        }
    }

    private func dismissThenPerform(_ action: @escaping () -> Void) {
        isPresented = false
        DispatchQueue.main.async {
            action()
        }
    }
}
