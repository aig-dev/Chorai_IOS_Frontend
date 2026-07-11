import Foundation

public struct InterestSelectionOption: Identifiable, Equatable, Sendable {
    public let value: String
    public let isSelected: Bool

    public var id: String { value.lowercased() }

    public init(value: String, isSelected: Bool) {
        self.value = value
        self.isSelected = isSelected
    }
}

public enum InterestSelectionOperation: Equatable, Sendable {
    case load
    case save
}

public enum InterestSelectionError: Error, Equatable, Sendable {
    case invalidActor
    case transport(code: String)
}

public enum InterestSelectionPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case saving
    case saved
    case skipped
    case failed(InterestSelectionOperation, InterestSelectionError)
}
