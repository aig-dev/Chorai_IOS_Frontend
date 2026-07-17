import SwiftUI

struct CardEditorAmbientBackdrop: View {
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    var body: some View {
        ZStack {
            ZenVisualTokens.background

            if !reduceTransparency {
                RadialGradient(
                    colors: [
                        Color(red: 0.44, green: 0.25, blue: 0.88)
                            .opacity(0.34),
                        Color.clear,
                    ],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 320
                )
                .offset(x: 72, y: -88)

                RadialGradient(
                    colors: [
                        Color(red: 0.14, green: 0.30, blue: 0.70)
                            .opacity(0.24),
                        Color.clear,
                    ],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: 360
                )
                .offset(x: -88, y: 120)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
