public enum LibraryCardReadabilityPolicy {
    public static func veilOpacity(
        reduceTransparency: Bool,
        increasedContrast: Bool
    ) -> Double {
        if reduceTransparency {
            return 0.74
        }
        if increasedContrast {
            return 0.70
        }
        return 0.58
    }

    public static func metadataOpacity(
        hasBackground: Bool,
        increasedContrast: Bool
    ) -> Double {
        if increasedContrast {
            return 1
        }
        return hasBackground ? 0.90 : 0.70
    }

    public static func tagSurfaceOpacity(hasBackground: Bool) -> Double {
        hasBackground ? 0.42 : 0.20
    }

    public static func engagementOpacity(
        hasBackground: Bool,
        increasedContrast: Bool
    ) -> Double {
        if increasedContrast {
            return 1
        }
        return hasBackground ? 0.90 : 0.80
    }
}
