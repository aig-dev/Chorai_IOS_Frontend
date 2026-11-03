import CoreFlow
import SwiftUI
import UIKit

/// Appearance only. Domain thresholds and missing-rating decoding stay in CoreFlow.
struct ChoraiCardLevel {
    let style: CardLevelStyle
    init(rate: Int) { style = CardLevelStyle(rate: rate) }
    var index: Int {
        switch style.tier {
        case .basic: 0; case .notable: 1; case .valuable: 2
        case .significant: 3; case .exceptional: 4; case .definitive: 5
        }
    }
    var roman: String { ["I", "II", "III", "IV", "V", "VI"][index] }
    var hex: UInt32 { [0x9BA7AE, 0x57A781, 0x5294D9, 0xA881D4, 0xB39A55, 0xD66C61][index] }
    var color: Color { Color(uiColor: ChoraiTheme.uiColor(hex)) }
    var labelColor: Color {
        let r = UInt32(Double((hex >> 16) & 255) * 0.63)
        let g = UInt32(Double((hex >> 8) & 255) * 0.63)
        let b = UInt32(Double(hex & 255) * 0.63)
        return ChoraiTheme.color(light: (r << 16) | (g << 8) | b, dark: hex)
    }
    var crop: CGRect {
        let rects: [[CGFloat]] = [[48,188,441,300], [592,52,371,427], [1040,71,483,402], [50,496,446,465], [514,666,509,299], [1040,496,489,476]]
        let r = rects[index]
        return CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
    }
    var spriteWidth: CGFloat { index == 5 ? 67.2 : 60 }
    var spriteHeight: CGFloat { spriteWidth * crop.height / crop.width }
    var lift: CGFloat {
        let h = 60 * crop.height / crop.width
        return index == 3 ? h * 0.48 : index == 5 ? h * 0.64 : max(0, h - 7)
    }
    func spriteX(width: CGFloat) -> CGFloat {
        if index == 3 { return -8 }
        let inset: CGFloat = index == 5 ? -2 : index == 1 ? 8 : index == 4 ? 17 : 13
        return width - spriteWidth - inset
    }
}

struct ChoraiLevelBadge: View {
    let rate: Int?
    var compact = false
    @ScaledMetric(relativeTo: .title3) private var compactRomanSize = 20.0
    @ScaledMetric(relativeTo: .title3) private var romanSize = 24.0
    var body: some View {
        if let rate {
            let level = ChoraiCardLevel(rate: rate)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(level.roman).font(.system(size: compact ? compactRomanSize : romanSize, weight: .medium, design: .serif))
                Text(level.style.label).font(compact ? .caption.weight(.semibold) : .subheadline.weight(.medium))
            }
            .foregroundStyle(level.labelColor)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Card level \(level.roman), \(level.style.label)")
        }
    }
}

private enum ChoraiLevelArtwork {
    static let sprites: [Int: UIImage] = {
        var result: [Int: UIImage] = [:]
        for rate in [1, 3, 9, 27, 81, 243] {
            let level = ChoraiCardLevel(rate: rate)
            let name = level.index == 4 ? "chora-exceptional-green-gold" : "chora-perches"
            if let atlas = UIImage(named: name)?.cgImage,
               let crop = atlas.cropping(to: level.crop) {
                result[level.index] = UIImage(cgImage: crop)
            }
        }
        return result
    }()
}

struct ChoraiLevelBrush: View {
    let rate: Int
    var body: some View {
        GeometryReader { proxy in
            let scale = min(1, (proxy.size.width + 4) / 190)
            ChoraiCardLevel(rate: rate).color
                .frame(width: 190 * scale, height: 98 * scale)
                .mask(alignment: .topLeading) {
                    Image("chora-rim-brush").resizable()
                        .frame(width: 231 * scale, height: 231 * scale)
                        .offset(x: -18 * scale, y: -74 * scale)
                }
                .opacity(0.72)
                .position(x: proxy.size.width - 95 * scale + 2, y: 49 * scale - 2)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Reading uses the page itself; grade artwork remains a compact, passive identity.
struct ChoraiReadingIdentity: View {
    let rate: Int?
    var body: some View {
        if let rate {
            HStack(alignment: .center) {
                ChoraiLevelBadge(rate: rate)
                Spacer(minLength: 12)
                ZStack(alignment: .topTrailing) {
                    ChoraiLevelBrush(rate: rate)
                        .frame(width: 92, height: 46).clipped()
                    let level = ChoraiCardLevel(rate: rate)
                    if let image = ChoraiLevelArtwork.sprites[level.index] {
                        Image(uiImage: image).renderingMode(.original).resizable().scaledToFit()
                            .frame(width: min(88, level.spriteWidth), height: 46)
                            .padding(.trailing, 4)
                    }
                }
                .frame(width: 92, height: 46)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

private struct ChoraiCardLevelModifier: ViewModifier {
    let rate: Int?
    let showsChora: Bool
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        let level = rate.map(ChoraiCardLevel.init)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(ChoraiTheme.surface, in: shape)
            .overlay(shape.strokeBorder(level?.color.opacity(contrast == .increased ? 1 : 0.6) ?? ChoraiTheme.separator, lineWidth: contrast == .increased ? 1.5 : 1)
                .allowsHitTesting(false).accessibilityHidden(true))
            .overlay(alignment: .topLeading) {
                if let rate { ChoraiLevelBrush(rate: rate).clipShape(shape).allowsHitTesting(false).accessibilityHidden(true) }
            }
            .overlay(alignment: .topLeading) {
                if showsChora, let level, let image = ChoraiLevelArtwork.sprites[level.index] {
                    GeometryReader { proxy in
                        Image(uiImage: image).renderingMode(.original).resizable().scaledToFit()
                            .frame(width: level.spriteWidth, height: level.spriteHeight)
                            .offset(x: level.spriteX(width: proxy.size.width), y: -level.lift)
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .padding(.top, showsChora ? (level.map { $0.lift + 6 } ?? 0) : 0)
    }
}

extension View {
    func choraiCardLevel(rate: Int?, showsChora: Bool = false, cornerRadius: CGFloat = 17) -> some View {
        modifier(ChoraiCardLevelModifier(rate: rate, showsChora: showsChora, cornerRadius: cornerRadius))
    }
}
