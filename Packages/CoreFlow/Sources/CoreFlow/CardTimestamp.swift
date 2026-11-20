import Foundation
import os

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

    public static func parse(_ value: String) -> Date? {
        formatters.withLock { state in
            state.fractional.date(from: value) ?? state.standard.date(from: value)
        }
    }

    // The legacy parser's precision and accepted inputs are part of sync decoding.
    // Both non-Sendable formatters are created here, never escape this private lock,
    // and are accessed only inside withLock, which returns a Sendable Date value.
    private static let formatters = OSAllocatedUnfairLock(uncheckedState: {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (fractional: fractional, standard: ISO8601DateFormatter())
    }())
}
