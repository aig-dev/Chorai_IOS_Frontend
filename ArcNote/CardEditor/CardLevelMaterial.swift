import CoreFlow
import SwiftUI

extension CardLevelStyle {
    var materialAccentColor: Color? {
        guard let accentComponents else { return nil }

        return Color(
            red: accentComponents.red,
            green: accentComponents.green,
            blue: accentComponents.blue
        )
    }

    fileprivate var accentComponents: (
        red: Double,
        green: Double,
        blue: Double
    )? {
        guard
            let hex = accentHex,
            hex.count == 7,
            hex.first == "#",
            let value = Int(hex.dropFirst(), radix: 16)
        else {
            return nil
        }

        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}

struct CardLevelMaterial<SurfaceShape: Shape>: View {
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorSchemeContrast)
    private var contrast

    let style: CardLevelStyle
    let shape: SurfaceShape
    let usesAssetBase: Bool

    init(
        style: CardLevelStyle,
        shape: SurfaceShape,
        usesAssetBase: Bool = true
    ) {
        self.style = style
        self.shape = shape
        self.usesAssetBase = usesAssetBase
    }

    var body: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(opaqueSurfaceColor)
            } else {
                if usesAssetBase {
                    Image(style.materialAssetName)
                        .resizable()
                        .scaledToFill()
                        .clipShape(shape)

                    shape.fill(
                        Color.black.opacity(
                            contrast == .increased ? 0.68 : 0.58
                        )
                    )
                }

                cornerAmbience
            }

            shape.stroke(
                edgeColor,
                lineWidth: contrast == .increased ? 1.5 : 1
            )
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var cornerAmbience: some View {
        GeometryReader { proxy in
            let extent = max(proxy.size.width, proxy.size.height)

            ZStack {
                RadialGradient(
                    colors: [accentColor.opacity(0.16), Color.clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: extent * 0.62
                )

                RadialGradient(
                    colors: [accentColor.opacity(0.10), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: extent * 0.58
                )
            }
        }
        .clipShape(shape)
    }

    private var edgeColor: Color {
        if style.accentHex == nil {
            return Color.white.opacity(contrast == .increased ? 0.58 : 0.28)
        }
        return accentColor.opacity(contrast == .increased ? 1 : 0.78)
    }

    private var accentColor: Color {
        style.materialAccentColor ?? Color(
            red: 0.72,
            green: 0.74,
            blue: 0.78
        )
    }

    private var opaqueSurfaceColor: Color {
        let accent = style.accentComponents ?? (0.72, 0.74, 0.78)
        return Color(
            red: 0.018 + accent.red * 0.09,
            green: 0.018 + accent.green * 0.09,
            blue: 0.022 + accent.blue * 0.09
        )
    }
}
