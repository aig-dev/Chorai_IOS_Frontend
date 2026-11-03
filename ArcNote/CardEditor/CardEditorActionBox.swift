import SwiftUI
import UIKit

private enum CardEditorActionIdentity {
    static let background = "cardEditorBackgroundButton"
    static let spark = "cardEditorActionSpark"
    static let merge = "cardEditorActionMerge"
    static let share = "cardEditorActionShare"
    static let link = "cardEditorActionLink"
    static let root = "cardEditorActionRoot"
    static let remove = "cardEditorActionRemove"
    static let pin = "cardEditorActionPin"
}


struct CardEditorMenuActions {
    let isPinned: Bool
    let prepare: () -> Void
    let background: () -> Void
    let spark: () -> Void
    let merge: () -> Void
    let share: () -> Void
    let link: () -> Void
    let root: () -> Void
    let remove: () -> Void
    let togglePin: () -> Void
}

/// UIKit supplies an explicit event before menu presentation. SwiftUI Menu's
/// gesture recognizers do not reliably forward the press to the editor host.
struct CardEditorNativeMenuButton: UIViewRepresentable {
    let actions: CardEditorMenuActions
    @ObservedObject var bodyModel: BlockNoteCardEditorModel
    let isEnabled: Bool
    let onPrepare: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)),
            for: .normal
        )
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        button.accessibilityLabel = "More note actions"
        button.accessibilityIdentifier = "cardEditorMoreButton"
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.menuWillPresent(_:)),
            for: .menuActionTriggered
        )
        updateCoordinator(context.coordinator)
        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak coordinator = context.coordinator] completion in
                completion(coordinator?.elements?() ?? [])
            }
        ])
        updateUIView(button, context: context)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        updateCoordinator(context.coordinator)
        button.isEnabled = isEnabled
        button.tintColor = UIColor(ChoraiTheme.ink)
    }

    private func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.prepare = {
            onPrepare()
            actions.prepare()
        }
        coordinator.elements = menuElements
    }

    private func menuElements() -> [UIMenuElement] {
        [
            UIMenu(options: .displayInline, children: [
                action("Spark", icon: "sparkles", identifier: CardEditorActionIdentity.spark, actions.spark),
                action("Merge", icon: "arrow.triangle.merge", identifier: CardEditorActionIdentity.merge, actions.merge),
                action("Share", icon: "square.and.arrow.up", identifier: CardEditorActionIdentity.share, actions.share)
            ]),
            UIMenu(options: .displayInline, children: [
                action("Link", icon: "link", identifier: CardEditorActionIdentity.link, actions.link),
                action("Root", icon: "point.3.connected.trianglepath.dotted", identifier: CardEditorActionIdentity.root, actions.root),
                action("Background", icon: "photo", identifier: CardEditorActionIdentity.background, actions.background),
                action(actions.isPinned ? "Unpin" : "Pin", icon: actions.isPinned ? "pin.slash" : "pin", identifier: CardEditorActionIdentity.pin, actions.togglePin)
            ]),
            UIMenu(options: .displayInline, children: [
                action("Undo", icon: "arrow.uturn.backward", identifier: "cardEditorActionUndo", attributes: bodyModel.canPerform(.undo) ? [] : .disabled) { bodyModel.perform(.undo) },
                action("Redo", icon: "arrow.uturn.forward", identifier: "cardEditorActionRedo", attributes: bodyModel.canPerform(.redo) ? [] : .disabled) { bodyModel.perform(.redo) }
            ]),
            UIMenu(options: .displayInline, children: [
                action("Remove", icon: "trash", identifier: CardEditorActionIdentity.remove, attributes: .destructive, actions.remove)
            ])
        ]
    }

    private func action(
        _ title: String,
        icon: String,
        identifier: String,
        attributes: UIMenuElement.Attributes = [],
        _ perform: @escaping () -> Void
    ) -> UIAction {
        let action = UIAction(
            title: title, image: UIImage(systemName: icon),
            identifier: UIAction.Identifier(identifier), attributes: attributes
        ) { _ in
            actions.prepare()
            perform()
        }
        action.accessibilityIdentifier = identifier
        return action
    }

    @MainActor
    final class Coordinator: NSObject {
        var prepare: (() -> Void)?
        var elements: (() -> [UIMenuElement])?

        @objc func menuWillPresent(_ button: UIButton) {
            guard button.isEnabled else { return }
            // UIControl.menuActionTriggered fires before its menu presents.
            // Finish the editor's state transition and synchronously resign the
            // native text responder before UIKit measures the available space.
            prepare?()
            button.window?.endEditing(true)
        }
    }
}

/// The writer footer keeps metadata secondary and exposes the existing editing
/// paths through a small native menu, with the same keyboard handoff as More.
struct CardEditorToolsMenuButton: UIViewRepresentable {
    let isTagEntryEnabled: Bool
    let isFormattingEnabled: Bool
    let onPrepare: () -> Void
    let onBeginTag: () -> Void
    let onFormat: () -> Void

    func makeCoordinator() -> CardEditorNativeMenuButton.Coordinator {
        CardEditorNativeMenuButton.Coordinator()
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(systemName: "slider.horizontal.3", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)),
            for: .normal
        )
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        button.accessibilityLabel = "Editing tools"
        button.accessibilityIdentifier = "cardEditorTools"
        button.addTarget(
            context.coordinator,
            action: #selector(CardEditorNativeMenuButton.Coordinator.menuWillPresent(_:)),
            for: .menuActionTriggered
        )
        updateUIView(button, context: context)
        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak coordinator = context.coordinator] completion in
                completion(coordinator?.elements?() ?? [])
            }
        ])
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.prepare = onPrepare
        context.coordinator.elements = menuElements
        button.isEnabled = isTagEntryEnabled || isFormattingEnabled
        button.tintColor = UIColor(ChoraiTheme.ink)
    }

    private func menuElements() -> [UIMenuElement] {
        let addTag = UIAction(
            title: "Add tag", image: UIImage(systemName: "tag"),
            identifier: UIAction.Identifier("cardEditorToolsAddTag"),
            attributes: isTagEntryEnabled ? [] : .disabled
        ) { _ in onBeginTag() }
        addTag.accessibilityIdentifier = "cardEditorToolsAddTag"
        let format = UIAction(
            title: "Format text", image: UIImage(systemName: "textformat"),
            identifier: UIAction.Identifier("cardEditorToolsFormat"),
            attributes: isFormattingEnabled ? [] : .disabled
        ) { _ in onFormat() }
        format.accessibilityIdentifier = "cardEditorToolsFormat"
        return [addTag, format]
    }
}

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
            rowCount: 3
        ) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 15) {
                    ActionBoxTile(
                        icon: .system("photo"),
                        text: "Background",
                        color: ChoraiTheme.accent,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: CardEditorActionIdentity.background
                    ) {
                        dismissThenPerform(onBackground)
                    }
                    ActionBoxTile(
                        icon: .system("sparkles"),
                        text: "Spark",
                        color: ChoraiTheme.gold,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: CardEditorActionIdentity.spark
                    ) {
                        dismissThenPerform(onSpark)
                    }
                    ActionBoxTile(
                        icon: .system("arrow.triangle.merge"),
                        text: "Merge",
                        color: ChoraiTheme.gold,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: CardEditorActionIdentity.merge
                    ) {
                        dismissThenPerform(onMerge)
                    }
                }

                HStack(spacing: 15) {
                    ActionBoxTile(
                        icon: .system("square.and.arrow.up"),
                        text: "Share",
                        color: ChoraiTheme.accent,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: CardEditorActionIdentity.share
                    ) {
                        dismissThenPerform(onShare)
                    }
                    ActionBoxTile(
                        icon: .system("link"),
                        text: "Link",
                        color: ChoraiTheme.accent,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: CardEditorActionIdentity.link
                    ) {
                        dismissThenPerform(onLink)
                    }
                    ActionBoxTile(
                        icon: .system("point.3.connected.trianglepath.dotted"),
                        text: "Root",
                        color: ChoraiTheme.accent,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: CardEditorActionIdentity.root
                    ) {
                        dismissThenPerform(onRoot)
                    }
                }

                HStack(spacing: 15) {
                    ActionBoxTile(
                        icon: .system("trash"),
                        text: "Remove",
                        color: ChoraiTheme.gold,
                        role: .destructive,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: CardEditorActionIdentity.remove
                    ) {
                        dismissThenPerform(onRemove)
                    }
                    ActionBoxTile(
                        icon: .system(isPinned ? "pin.slash" : "pin"),
                        text: isPinned ? "Unpin" : "Pin",
                        color: ChoraiTheme.gold,
                        isEnabled: isEnabled,
                        accessibilityIdentifier: CardEditorActionIdentity.pin
                    ) {
                        dismissThenPerform(onTogglePin)
                    }
                }
            }
            .accessibilityElement(children: .contain)
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
