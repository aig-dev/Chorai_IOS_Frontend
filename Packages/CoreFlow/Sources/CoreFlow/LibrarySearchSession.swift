import Foundation

public enum LibrarySearchScope: Equatable, Sendable {
    case notes
    case collect

    public var apiSearchType: String {
        switch self {
        case .notes:
            "own"
        case .collect:
            "favorited"
        }
    }
}

public enum LibrarySortField: Equatable, Sendable {
    case updatedAt
    case createdAt
    case rate

    public var apiName: String {
        switch self {
        case .updatedAt:
            "updated_at"
        case .createdAt:
            "created_at"
        case .rate:
            "rate"
        }
    }
}

public enum LibrarySortOrder: Equatable, Sendable {
    case ascending
    case descending

    public var apiName: String {
        switch self {
        case .ascending:
            "asc"
        case .descending:
            "desc"
        }
    }
}

public struct LibrarySortDescriptor: Equatable, Sendable {
    public let field: LibrarySortField
    public let order: LibrarySortOrder

    public init(field: LibrarySortField, order: LibrarySortOrder) {
        self.field = field
        self.order = order
    }
}

public enum LibrarySortOption: String, CaseIterable, Identifiable, Sendable {
    case latestEdited = "Latest Edited"
    case latestAdded = "Latest Added"
    case rarityHighLow = "Rarity-High Low"
    case rarityLowHigh = "Rarity-Low High"

    public var id: String { rawValue }

    public var descriptor: LibrarySortDescriptor {
        switch self {
        case .latestEdited:
            LibrarySortDescriptor(field: .updatedAt, order: .descending)
        case .latestAdded:
            LibrarySortDescriptor(field: .createdAt, order: .descending)
        case .rarityHighLow:
            LibrarySortDescriptor(field: .rate, order: .descending)
        case .rarityLowHigh:
            LibrarySortDescriptor(field: .rate, order: .ascending)
        }
    }
}

public struct LibrarySearchSortKey: Sendable {
    public let id: String
    public let rate: Int
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: String,
        rate: Int,
        createdAt: String,
        updatedAt: String,
        parseDate: (String) -> Date?
    ) {
        self.id = id
        self.rate = rate
        self.createdAt = parseDate(createdAt)
        self.updatedAt = parseDate(updatedAt)
    }

    /// Create one parser on the queue preparing a batch of results.
    public static func makeDateParser() -> (String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        return { fractional.date(from: $0) ?? whole.date(from: $0) }
    }

    public func precedes(_ other: Self, by descriptor: LibrarySortDescriptor) -> Bool {
        let comparison: ComparisonResult
        switch descriptor.field {
        case .updatedAt:
            comparison = (updatedAt ?? .distantPast).compare(other.updatedAt ?? .distantPast)
        case .createdAt:
            comparison = (createdAt ?? .distantPast).compare(other.createdAt ?? .distantPast)
        case .rate:
            if rate == other.rate { return id < other.id }
            comparison = rate < other.rate ? .orderedAscending : .orderedDescending
        }
        if comparison == .orderedSame { return id < other.id }
        return comparison == (descriptor.order == .ascending ? .orderedAscending : .orderedDescending)
    }
}

/// The selected sort may change while the current request is preparing its results.
public struct LibrarySearchRequest: Sendable {
    private var active: (id: UUID, sort: LibrarySortOption)?

    public init() {}

    public mutating func begin(sort: LibrarySortOption) -> UUID {
        let id = UUID()
        active = (id, sort)
        return id
    }

    public mutating func selectSort(_ sort: LibrarySortOption) {
        active?.sort = sort
    }

    public func sort(for id: UUID) -> LibrarySortOption? {
        guard let active, active.id == id else { return nil }
        return active.sort
    }

    public mutating func clear() {
        active = nil
    }
}

public struct LibrarySearchSession: Equatable, Sendable {
    public private(set) var isActive = false
    public private(set) var scope: LibrarySearchScope?
    public private(set) var draftQuery = ""
    public private(set) var submittedQuery: String?

    public init() {}

    public mutating func enter(scope: LibrarySearchScope) {
        isActive = true
        self.scope = scope
        draftQuery = ""
        submittedQuery = nil
    }

    public mutating func updateDraft(_ value: String) {
        draftQuery = value
        if normalized(value).isEmpty {
            submittedQuery = nil
        }
    }

    @discardableResult
    public mutating func submit() -> String? {
        let query = normalized(draftQuery)
        submittedQuery = query.isEmpty ? nil : query
        return submittedQuery
    }

    public mutating func clear() {
        draftQuery = ""
        submittedQuery = nil
    }

    public mutating func exit() {
        self = LibrarySearchSession()
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
