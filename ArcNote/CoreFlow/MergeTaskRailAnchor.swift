import SwiftUI

@MainActor
final class MergeTaskRailAnchorStore: ObservableObject {
    @Published private(set) var newNoteFrame: CGRect?

    func update(newNoteFrame: CGRect) {
        guard !newNoteFrame.isNull,
              !newNoteFrame.isInfinite,
              newNoteFrame.width > 0,
              newNoteFrame.height > 0,
              self.newNoteFrame != newNoteFrame else {
            return
        }
        self.newNoteFrame = newNoteFrame
    }
}

struct MergeTaskRailAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(
        value: inout Anchor<CGRect>?,
        nextValue: () -> Anchor<CGRect>?
    ) {
        if let nextValue = nextValue() {
            value = nextValue
        }
    }
}
