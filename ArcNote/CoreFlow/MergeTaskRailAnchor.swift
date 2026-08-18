import SwiftUI

@MainActor
final class MergeTaskRailAnchorStore: ObservableObject {
    private struct CachedSlot: Equatable {
        let measurementContainerSize: CGSize
        let trailingInset: CGFloat
        let bottomInset: CGFloat
        let noteSize: CGSize

        func newNoteFrame(in containerSize: CGSize) -> CGRect {
            let measuredFrame = CGRect(
                x: measurementContainerSize.width
                    - trailingInset
                    - noteSize.width,
                y: measurementContainerSize.height
                    - bottomInset
                    - noteSize.height,
                width: noteSize.width,
                height: noteSize.height
            )
            return measuredFrame.offsetBy(
                dx: containerSize.width - measurementContainerSize.width,
                dy: containerSize.height - measurementContainerSize.height
            )
        }
    }

    @Published private var cachedSlot: CachedSlot?

    func update(newNoteFrame: CGRect, containerSize: CGSize) {
        guard !newNoteFrame.isNull,
              !newNoteFrame.isInfinite,
              newNoteFrame.width > 0,
              newNoteFrame.height > 0,
              containerSize.width.isFinite,
              containerSize.height.isFinite,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return
        }

        let slot = CachedSlot(
            measurementContainerSize: containerSize,
            trailingInset: containerSize.width - newNoteFrame.maxX,
            bottomInset: containerSize.height - newNoteFrame.maxY,
            noteSize: newNoteFrame.size
        )
        guard cachedSlot != slot else { return }
        cachedSlot = slot
    }

    func newNoteFrame(in containerSize: CGSize) -> CGRect? {
        guard containerSize.width.isFinite,
              containerSize.height.isFinite,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return nil
        }
        return cachedSlot?.newNoteFrame(in: containerSize)
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
