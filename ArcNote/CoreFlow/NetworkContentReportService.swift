import Combine
import CoreFlow
import Foundation

struct ContentReportWireRequest: Codable {
    let targetType: String
    let targetId: String
    let reasonCode: String
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case targetType = "target_type"
        case targetId = "target_id"
        case reasonCode = "reason_code"
        case detail
    }
}

struct ContentReportWireResponse: Codable {
    let reportId: String
    let status: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case reportId = "report_id"
        case status
        case updatedAt = "updated_at"
    }
}

struct ContentReportWireEnvelope: Codable {
    let data: ContentReportWireResponse
}

struct NetworkContentReportService: ContentReportServing, Sendable {
    private let network: NetworkManager

    @MainActor
    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func createReport(
        _ request: ContentReportRequest
    ) async throws -> ContentReportReceipt {
        do {
            let response = try await firstValue(
                network.createContentReport(
                    ContentReportWireRequest(
                        targetType: request.targetType,
                        targetId: request.targetID,
                        reasonCode: request.reasonCode,
                        detail: request.detail
                    )
                )
            ).data
            guard !response.reportId.isEmpty,
                  !response.status.isEmpty else {
                throw ContentReportError.invalidResponse(
                    code: "report_response_invalid"
                )
            }
            return ContentReportReceipt(
                reportID: response.reportId,
                status: response.status,
                updatedAt: response.updatedAt
            )
        } catch {
            throw Self.mapError(error)
        }
    }

    @MainActor
    private func firstValue<Output: Sendable>(
        _ publisher: @autoclosure @MainActor @Sendable () -> AnyPublisher<Output, NetworkError>
    ) async throws -> Output {
        guard let value = try await NetworkManager.firstValue(publisher()) else {
            throw NetworkError.noData
        }
        return value
    }

    private static func mapError(_ error: Error) -> ContentReportError {
        if let reportError = error as? ContentReportError {
            return reportError
        }
        guard let networkError = error as? NetworkError else {
            return .transport(code: "report_unknown")
        }

        switch networkError {
        case .decodingError:
            return .invalidResponse(code: "report_decoding")
        case .api(_, let code, _):
            return .transport(code: code?.lowercased() ?? "report_api")
        case .unauthorized:
            return .transport(code: "report_unauthorized")
        case .forbidden:
            return .transport(code: "report_forbidden")
        case .notFound:
            return .transport(code: "report_not_found")
        case .timeout:
            return .transport(code: "report_timeout")
        case .networkError:
            return .transport(code: "report_offline")
        case .invalidURL:
            return .transport(code: "report_invalid_url")
        case .noData:
            return .transport(code: "report_no_data")
        case .encodingError:
            return .transport(code: "report_encoding")
        case .serverError(let statusCode, _):
            return .transport(code: "report_server_\(statusCode)")
        case .unknown:
            return .transport(code: "report_unknown")
        }
    }
}
