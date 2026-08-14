public enum LibraryCardRateStyle: Equatable, Sendable {
    case neutral
    case green
    case blue
    case purple
    case amber
    case orangeRed

    public init(rate: Int) {
        switch rate {
        case ..<3: self = .neutral
        case 3..<9: self = .green
        case 9..<27: self = .blue
        case 27..<81: self = .purple
        case 81..<243: self = .amber
        default: self = .orangeRed
        }
    }

    public var accentHex: String? {
        switch self {
        case .neutral: return nil
        case .green: return "#00FF66"
        case .blue: return "#0371FF"
        case .purple: return "#9627D2"
        case .amber: return "#D97800"
        case .orangeRed: return "#FF5E00"
        }
    }
}
