public enum LibraryCardRateStyle: Equatable, Sendable {
    case neutral
    case green
    case blue
    case purple
    case amber
    case orangeRed

    public init(rate: Int) {
        switch rate {
        case 2: self = .green
        case 3: self = .blue
        case 4: self = .purple
        case 5: self = .amber
        case 6: self = .orangeRed
        default: self = .neutral
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
