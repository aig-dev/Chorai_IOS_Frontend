import Foundation

public protocol CoreDiscoveryPathServing: Sendable {
    func discoveryPath(cardID: String) async throws -> DiscoveryPathSnapshot
}
