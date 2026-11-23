import SwiftUI

enum CardEditorBackgroundActionContext: Equatable {
    case visible(canRestoreOriginal: Bool)
    case removed(canRestoreBackground: Bool)
    case pending(canCancel: Bool, canReplace: Bool)
}

enum CardEditorBackgroundAction: Equatable {
    case choosePhoto
    case remove
    case restore
    case close
}

private struct CardEditorBackgroundActionDialog: ViewModifier {
    @Binding var isPresented: Bool
    let context: CardEditorBackgroundActionContext
    let onSelect: (CardEditorBackgroundAction) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Background",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            switch context {
            case let .visible(canRestoreOriginal):
                Button("Replace Background") {
                    onSelect(.choosePhoto)
                }
                .accessibilityIdentifier("cardEditorReplaceBackgroundButton")

                if canRestoreOriginal {
                    Button("Restore Original Background") {
                        onSelect(.restore)
                    }
                    .accessibilityIdentifier("cardEditorRestoreBackgroundButton")
                }

                Button("Remove Background", role: .destructive) {
                    onSelect(.remove)
                }
                .accessibilityIdentifier("cardEditorRemoveBackgroundButton")

            case let .pending(canCancel, canReplace):
                if canReplace {
                    Button("Replace Background") { onSelect(.choosePhoto) }
                        .accessibilityIdentifier("cardEditorReplaceBackgroundButton")
                }
                if canCancel {
                    Button("Cancel Background Change") { onSelect(.restore) }
                        .accessibilityIdentifier("cardEditorRestoreBackgroundButton")
                }
                Button("Close Note") { onSelect(.close) }
                    .accessibilityIdentifier("cardEditorCloseWithPendingBackground")

            case let .removed(canRestoreBackground):
                Button("Choose New Background") {
                    onSelect(.choosePhoto)
                }
                .accessibilityIdentifier("cardEditorReplaceBackgroundButton")

                if canRestoreBackground {
                    Button("Restore Background") {
                        onSelect(.restore)
                    }
                    .accessibilityIdentifier("cardEditorRestoreBackgroundButton")
                }
            }

            Button("Cancel", role: .cancel) {}
        }
    }
}

extension View {
    func cardEditorBackgroundActionDialog(
        isPresented: Binding<Bool>,
        context: CardEditorBackgroundActionContext,
        onSelect: @escaping (CardEditorBackgroundAction) -> Void
    ) -> some View {
        modifier(
            CardEditorBackgroundActionDialog(
                isPresented: isPresented,
                context: context,
                onSelect: onSelect
            )
        )
    }
}
