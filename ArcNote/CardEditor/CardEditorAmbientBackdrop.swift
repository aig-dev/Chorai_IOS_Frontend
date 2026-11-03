import SwiftUI

struct CardEditorAmbientBackdrop: View {
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    private let upperLightCenter = UnitPoint(x: 0.82, y: 0.18)
    private let lowerLightCenter = UnitPoint(x: 0.16, y: 0.70)

    var body: some View {
        ZStack {
            ZenVisualTokens.background

            if !reduceTransparency {
                GeometryReader { proxy in
                    let sceneExtent = max(proxy.size.width, proxy.size.height)

                    ZStack {
                        RadialGradient(
                            colors: [
                                ChoraiTheme.gold
                                    .opacity(0.035),
                                Color.clear,
                            ],
                            center: upperLightCenter,
                            startRadius: 0,
                            endRadius: sceneExtent * 0.58
                        )

                        RadialGradient(
                            colors: [
                                ChoraiTheme.accent
                                    .opacity(0.025),
                                Color.clear,
                            ],
                            center: lowerLightCenter,
                            startRadius: 0,
                            endRadius: sceneExtent * 0.54
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
