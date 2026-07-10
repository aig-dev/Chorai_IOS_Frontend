import Foundation

public protocol ContentReportServing: Sendable {
    func createReport(
        _ request: ContentReportRequest
    ) async throws -> ContentReportReceipt
}
