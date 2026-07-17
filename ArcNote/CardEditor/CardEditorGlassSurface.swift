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
                contrast == .increased
                    ? Color.white.opacity(0.42)
                    : Color.white.opacity(0.25),
                lineWidth: contrast == .increased ? 1.2 : 0.8
            )
            .mask(
                LinearGradient(
                    colors: [
                        Color.white,
                        Color.white.opacity(
                            contrast == .increased ? 0.56 : 0.34
                        ),
                        Color.white.opacity(contrast == .increased ? 0.14 : 0.02),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
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
                    .mask {
                        ZStack {
                            shape.fill(Color.white).padding(1.4)

                            shape.stroke(
                                LinearGradient(
                                    stops: [
                                        .init(
                                            color: Color.white.opacity(1.0),
                                            location: 0.0
                                        ),
                                        .init(
                                            color: Color.white.opacity(0.72),
                                            location: 0.46
                                        ),
                                        .init(
                                            color: Color.white.opacity(
                                                contrast == .increased ? 0.28 : 0.08
                                            ),
                                            location: 0.86
                                        ),
                                        .init(
                                            color: Color.white.opacity(
                                                contrast == .increased ? 0.18 : 0.02
                                            ),
                                            location: 1.0
                                        ),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 2.8
                            )
                        }
                    }

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
