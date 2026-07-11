import Foundation

public protocol CoreInterestSelectionServing: Sendable {
    func fetchOptions() async throws -> [String]
    func fetchSelection() async throws -> [String]
    func save(domains: [String]) async throws -> [String]
}
