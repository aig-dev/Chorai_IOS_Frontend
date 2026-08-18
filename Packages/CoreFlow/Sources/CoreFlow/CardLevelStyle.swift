public struct CardLevelStyle: Equatable, Sendable {
    public enum Tier: String, Codable, Sendable {
        case basic
        case notable
        case valuable
        case significant
        case exceptional
        case definitive
    }

    public let tier: Tier
    public let label: String
    public let accentHex: String?
    public let materialAssetName: String

    public init(rate: Int) {
        switch rate {
        case ..<3:
            tier = .basic
            label = "Basic"
            accentHex = nil
            materialAssetName = "merge_bg_basic"
        case 3..<9:
            tier = .notable
            label = "Notable"
            accentHex = "#00FF66"
            materialAssetName = "merge_bg_green"
        case 9..<27:
            tier = .valuable
            label = "Valuable"
            accentHex = "#0371FF"
            materialAssetName = "merge_bg_blue"
        case 27..<81:
            tier = .significant
            label = "Significant"
            accentHex = "#9627D2"
            materialAssetName = "merge_bg_purple"
        case 81..<243:
            tier = .exceptional
            label = "Exceptional"
            accentHex = "#D97800"
            materialAssetName = "merge_bg_yellow"
        default:
            tier = .definitive
            label = "Definitive"
            accentHex = "#FF5E00"
            materialAssetName = "merge_bg_red"
        }
    }
}
