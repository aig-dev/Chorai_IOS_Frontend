import Combine
import Foundation

@MainActor
public final class CoreFlowCoordinator: ObservableObject {
    @Published public var selectedTab: CoreTab = .flow
    @Published public private(set) var libraryRefreshID = UUID()
    @Published public private(set) var lastCreatedCardID: String?

    public init() {}

    public func mergeCompleted(cardID: String) {
        lastCreatedCardID = cardID
        libraryRefreshID = UUID()
    }
}
