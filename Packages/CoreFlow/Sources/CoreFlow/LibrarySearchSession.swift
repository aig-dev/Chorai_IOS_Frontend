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
