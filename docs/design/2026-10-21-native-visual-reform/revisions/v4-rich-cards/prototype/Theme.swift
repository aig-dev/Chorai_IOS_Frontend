import SwiftUI
import UIKit

/// Design-study choices, shared across every screen and presentation.
enum PrototypeTheme: String, CaseIterable, Identifiable, Sendable {
    case original
    case greenGold = "green-gold"
    case purple
    case blue
    case clay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: "Original Warm White"
        case .greenGold: "College Green & Gold"
        case .purple: "Twilight Violet"
        case .blue: "Deep Sea Blue"
        case .clay: "Clay & Paper"
        }
    }

    var dynamicTint: Color {
        Color(uiColor: UIColor { traits in
            Self.uiColor(self.tokens(dark: traits.userInterfaceStyle == .dark).ink)
        })
    }

    struct Tokens {
        let background: UInt32
        let surface: UInt32
        let ink: UInt32
        let onTint: UInt32
        let accent: UInt32
    }

    func tokens(dark: Bool) -> Tokens {
        switch (self, dark) {
        case (.original, false):
            Tokens(background: 0xFAF9F6, surface: 0xFFFFFC, ink: 0x153B37, onTint: 0xFFFFFF, accent: 0x153B37)
        case (.original, true):
            Tokens(background: 0x242329, surface: 0x2C2C31, ink: 0xBFDBCF, onTint: 0x153B37, accent: 0xBFDBCF)
        case (.greenGold, false):
            // W&M green and accessible dark gold; warm paper is specific to Chorai.
            Tokens(background: 0xF6F5EE, surface: 0xFEFDFA, ink: 0x004E38, onTint: 0xFFFFFF, accent: 0x846838)
        case (.greenGold, true):
            Tokens(background: 0x15261F, surface: 0x1E332A, ink: 0xB6D7C5, onTint: 0x123424, accent: 0xD6B378)
        case (.purple, false):
            Tokens(background: 0xF5F1FA, surface: 0xFDFCFF, ink: 0x64458F, onTint: 0xFFFFFF, accent: 0x795B96)
        case (.purple, true):
            Tokens(background: 0x221E2B, surface: 0x302839, ink: 0xD3C2EF, onTint: 0x332348, accent: 0xC3A3E4)
        case (.blue, false):
            Tokens(background: 0xF1F5F8, surface: 0xFCFEFF, ink: 0x27577C, onTint: 0xFFFFFF, accent: 0x446A8B)
        case (.blue, true):
            Tokens(background: 0x19252F, surface: 0x243541, ink: 0xB6D2EB, onTint: 0x203B52, accent: 0x92C1E8)
        case (.clay, false):
            Tokens(background: 0xF8F2EC, surface: 0xFFFCF8, ink: 0x944D36, onTint: 0xFFFFFF, accent: 0x885D45)
        case (.clay, true):
            Tokens(background: 0x2A211E, surface: 0x3A2D28, ink: 0xE6B59B, onTint: 0x492C20, accent: 0xD9AD88)
        }
    }

    static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
}

private struct PrototypeThemeKey: EnvironmentKey {
    static let defaultValue: PrototypeTheme = .greenGold
}

private struct PrototypeThemeSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<PrototypeTheme> = .constant(.greenGold)
}

extension EnvironmentValues {
    var prototypeTheme: PrototypeTheme {
        get { self[PrototypeThemeKey.self] }
        set { self[PrototypeThemeKey.self] = newValue }
    }

    var prototypeThemeSelection: Binding<PrototypeTheme> {
        get { self[PrototypeThemeSelectionKey.self] }
        set { self[PrototypeThemeSelectionKey.self] = newValue }
    }
}

struct Palette {
    let dark: Bool
    var theme: PrototypeTheme = .greenGold

    private var tokens: PrototypeTheme.Tokens { theme.tokens(dark: dark) }
    private func color(_ hex: UInt32) -> Color { Color(uiColor: PrototypeTheme.uiColor(hex)) }

    var background: Color { color(tokens.background) }
    var surface: Color { color(tokens.surface) }
    var ink: Color { color(tokens.ink) }
    var onTint: Color { color(tokens.onTint) }
    var accent: Color { color(tokens.accent) }
    var rule: Color { theme == .original ? Color.primary.opacity(dark ? 0.12 : 0.09) : ink.opacity(dark ? 0.16 : 0.12) }
}
