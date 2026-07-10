import Combine
import Foundation

@MainActor
public final class CoreFlowCoordinator: ObservableObject {
    @Published public var selectedTab: CoreTab = .flow
    @Published public var isCapturePresented = false
    @Published public private(set) var libraryRefreshID = UUID()
    @Published public private(set) var lastCreatedCardID: String?
    @Published public private(set) var recordAcknowledgementID: String?

    public init() {}

    public func presentCapture() {
        isCapturePresented = true
    }

    public func dismissCapture() {
        isCapturePresented = false
    }

    public func captureCompleted(_ card: CreatedCard) {
        lastCreatedCardID = card.id
        recordAcknowledgementID = card.id
        libraryRefreshID = UUID()
        isCapturePresented = false
    }

    public func clearRecordAcknowledgement(cardID: String) {
        guard recordAcknowledgementID == cardID else { return }
        recordAcknowledgementID = nil
    }
}
