import Combine
import Foundation

@MainActor
public final class ContentReportStore: ObservableObject {
    @Published public private(set) var reason: ContentReportReason = .spam
    @Published public private(set) var detail = ""
    @Published public private(set) var phase: ContentReportPhase = .editing

    public var isSubmitting: Bool { phase == .submitting }

    private let targetType: ContentReportTargetType
    private let targetID: String
    private let service: any ContentReportServing
    private var submitTask: Task<Void, Never>?

    public init(
        targetType: ContentReportTargetType,
        targetID: String,
        service: any ContentReportServing
    ) {
        self.targetType = targetType
        self.targetID = targetID
        self.service = service
    }

    public func selectReason(_ reason: ContentReportReason) {
        guard !isSubmitting, !phase.isSubmitted else { return }
        self.reason = reason
    }

    public func updateDetail(_ detail: String) {
        guard !isSubmitting, !phase.isSubmitted else { return }
        self.detail = detail
    }

    public func submit() {
        guard !isSubmitting, !phase.isSubmitted else { return }
        let trimmedDetail = detail.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let request = ContentReportRequest(
            targetType: targetType.rawValue,
            targetID: targetID,
            reasonCode: reason.rawValue,
            detail: trimmedDetail.isEmpty ? nil : trimmedDetail
        )

        submitTask?.cancel()
        phase = .submitting
        submitTask = Task { [weak self] in
            guard let self else { return }
            do {
                let receipt = try await service.createReport(request)
                guard !Task.isCancelled else { return }
                phase = .submitted(receipt)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(Self.mapError(error))
            }
        }
    }

    public func retry() {
        submit()
    }

    private static func mapError(_ error: Error) -> ContentReportError {
        if let reportError = error as? ContentReportError {
            return reportError
        }
        return .transport(code: "report_request_failed")
    }
}
