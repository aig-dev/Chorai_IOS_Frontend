import Combine
import Foundation

@MainActor
public final class CoreFlowCoordinator: ObservableObject {
    @Published public var selectedTab: CoreTab = .flow
    @Published public private(set) var libraryRefreshID = UUID()
    @Published public private(set) var lastMergedCardID: String?

    public init() {}

    public func noteCreated() {
        libraryRefreshID = UUID()
    }

    public func mergeCompleted(cardID: String) {
        lastMergedCardID = cardID
        libraryRefreshID = UUID()
    }
}
