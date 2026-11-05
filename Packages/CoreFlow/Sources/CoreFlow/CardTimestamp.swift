import Foundation

/// Presentation helpers for card timestamps returned by the API.
public enum CardTimestamp {
    /// Returns the calendar-date portion of a valid RFC3339 timestamp.
    ///
    /// Keeping the date portion from the source string avoids changing the visible
    /// day when a reader's device is in a different time zone from the timestamp.
    public static func dateOnly(from value: String) -> String {
        guard parse(value) != nil,
              let separator = value.firstIndex(of: "T") else {
            return value
        }

        return String(value[..<separator])
    }

    static func parse(_ value: String) -> Date? {
        fractional.date(from: value) ?? standard.date(from: value)
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standard = ISO8601DateFormatter()
}
