import CoreFlow
import SwiftUI

extension CardLevelStyle {
    var materialAccentColor: Color? { ChoraiCardLevel(rate: representativeRate).color }
    var representativeRate: Int {
        switch tier {
        case .basic: 1; case .notable: 3; case .valuable: 9
        case .significant: 27; case .exceptional: 81; case .definitive: 243
        }
    }
}

struct CardLevelMaterial<SurfaceShape: Shape>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let style: CardLevelStyle
    let shape: SurfaceShape
    let usesAssetBase: Bool

    init(style: CardLevelStyle, shape: SurfaceShape, usesAssetBase: Bool = true) {
        self.style = style
        self.shape = shape
        self.usesAssetBase = usesAssetBase
    }

    var body: some View {
        ZStack {
            shape.fill(ChoraiTheme.surface)
            shape.stroke(style.materialAccentColor?.opacity(contrast == .increased ? 1 : 0.55) ?? ChoraiTheme.separator,
                         lineWidth: contrast == .increased ? 1.5 : 1)
            ChoraiLevelBrush(rate: style.representativeRate)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
