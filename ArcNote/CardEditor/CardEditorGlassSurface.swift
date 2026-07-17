import SwiftUI

struct CardEditorGlassSurface<SurfaceShape: Shape>: View {
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorSchemeContrast)
    private var contrast

    let shape: SurfaceShape
    let isInteractive: Bool

    init(shape: SurfaceShape, isInteractive: Bool = false) {
        self.shape = shape
        self.isInteractive = isInteractive
    }

    var body: some View {
        ZStack {
            material

            shape
                .stroke(
                    contrast == .increased
                        ? Color.white.opacity(0.34)
                        : Color.white.opacity(0.16),
                    lineWidth: contrast == .increased ? 1.4 : 0.8
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var material: some View {
        if reduceTransparency {
            shape.fill(ZenVisualTokens.background.opacity(0.97))
        } else if #available(iOS 26.0, *) {
            shape
                .fill(Color.clear)
                .glassEffect(.regular.interactive(isInteractive), in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}
