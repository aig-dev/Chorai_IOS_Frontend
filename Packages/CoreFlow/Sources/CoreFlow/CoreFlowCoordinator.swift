import Combine
import Foundation

public struct LibrarySelectionRequest: Equatable, Sendable {
    public let id: UUID
    public let scope: LibrarySearchScope

    fileprivate init(scope: LibrarySearchScope) {
        self.id = UUID()
        self.scope = scope
    }
}

@MainActor
public final class CoreFlowCoordinator: ObservableObject {
    @Published public var selectedTab: CoreTab = .flow
    @Published public private(set) var libraryRefreshID = UUID()
    @Published public private(set) var lastMergedCardID: String?
    @Published public private(set) var librarySelectionRequest: LibrarySelectionRequest?

    public init() {}

    public func openLibrary(scope: LibrarySearchScope) {
        // TabView may mount Home only after selectedTab changes. Keep the request
        // as state so its delivery does not depend on a live notification observer.
        librarySelectionRequest = LibrarySelectionRequest(scope: scope)
        selectedTab = .library
    }

    public func noteCreated() {
        libraryRefreshID = UUID()
    }

    public func mergeCompleted(cardID: String) {
        lastMergedCardID = cardID
        libraryRefreshID = UUID()
    }
}
