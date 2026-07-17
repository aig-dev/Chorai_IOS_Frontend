import SwiftUI

enum CardEditorGlassStyle: Equatable {
    case writingPlane
    case chrome
}

struct CardEditorGlassSurface<SurfaceShape: Shape>: View {
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorSchemeContrast)
    private var contrast

    let shape: SurfaceShape
    let style: CardEditorGlassStyle

    init(
        shape: SurfaceShape,
        style: CardEditorGlassStyle
    ) {
        self.shape = shape
        self.style = style
    }

    var body: some View {
        ZStack {
            material
            edge
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var edge: some View {
        switch style {
        case .writingPlane:
            shape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(
                            contrast == .increased ? 0.40 : 0.24
                        ),
                        Color.white.opacity(
                            contrast == .increased ? 0.12 : 0.03
                        ),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: contrast == .increased ? 1.2 : 0.8
            )

        case .chrome:
            shape.stroke(
                contrast == .increased
                    ? Color.white.opacity(0.34)
                    : Color.white.opacity(0.16),
                lineWidth: contrast == .increased ? 1.4 : 0.8
            )
        }
    }

    @ViewBuilder
    private var material: some View {
        if reduceTransparency {
            shape.fill(ZenVisualTokens.background.opacity(0.97))
        } else if #available(iOS 26.0, *) {
            switch style {
            case .writingPlane:
                shape
                    .fill(Color.clear)
                    .glassEffect(.clear.interactive(), in: shape)

            case .chrome:
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular.interactive(), in: shape)
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}
