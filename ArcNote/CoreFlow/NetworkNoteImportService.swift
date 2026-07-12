import Combine
import CoreFlow
import Foundation

struct NetworkNoteImportService: CoreNoteImportServing, @unchecked Sendable {
    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func enqueue(
        files: [NoteImportFile],
        clientRequestID: String
    ) async throws -> NoteImportReceipt {
        var scopedURLs: [URL] = []
        for file in files where file.url.startAccessingSecurityScopedResource() {
            scopedURLs.append(file.url)
        }
        defer {
            for url in scopedURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let parts = files.map {
            NoteImportUploadPart(
                url: $0.url,
                filename: $0.filename,
                mimeType: Self.mimeType(for: $0.format),
                sourceKey: $0.sourceKey,
                label: $0.label
            )
        }

        do {
            let result = try await firstValue(
                network.enqueueNoteImport(
                    parts: parts,
                    clientRequestID: clientRequestID,
                    presentsError: false
                )
            )
            switch result {
            case .response(let response):
                return Self.mapReceipt(response)
            case .undecodableSuccess(let statusCode):
                throw NoteImportServiceError.ambiguous(
                    .undecodableSuccess(statusCode: statusCode)
                )
            }
        } catch let error as NoteImportServiceError {
            throw error
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func jobs(limit: Int) async throws -> [NoteImportJobSummary] {
        do {
            let response = try await firstValue(
                network.getNoteImportJobs(
                    limit: limit,
                    presentsError: false
                )
            )
            return try Self.mapJobs(response)
        } catch let error as NoteImportServiceError {
            throw error
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func job(id: String) async throws -> NoteImportJobDetail {
        do {
            let response = try await firstValue(
                network.getNoteImportJob(
                    id: id,
                    presentsError: false
                )
            )
            return try Self.mapJob(response)
        } catch let error as NoteImportServiceError {
            throw error
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func cancel(id: String) async throws {
        do {
            _ = try await firstValue(
                network.cancelNoteImportJob(
                    id: id,
                    presentsError: false
                )
            )
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    static func mapReceipt(
        _ response: NoteImportEnqueueResponse
    ) -> NoteImportReceipt {
        NoteImportReceipt(
            jobID: response.jobID,
            clientRequestID: response.clientRequestID,
            status: NoteImportJobStatus(rawValue: response.status),
            totalFiles: response.totalFiles,
            acceptedFiles: response.acceptedFiles,
            rejectedFiles: response.rejectedFiles
        )
    }

    static func mapJobs(
        _ response: NoteImportJobListResponse
    ) throws -> [NoteImportJobSummary] {
        try response.jobs.map { value in
            NoteImportJobSummary(
                jobID: value.jobID,
                clientRequestID: value.clientRequestID,
                status: NoteImportJobStatus(rawValue: value.status),
                soulStatus: NoteImportSoulStatus(rawValue: value.soulStatus),
                soulStatusReason: value.soulStatusReason,
                totalFiles: value.totalFiles,
                importedCount: value.importedCount,
                updatedCount: value.updatedCount,
                skippedCount: value.skippedCount,
                failedCount: value.failedCount,
                createdAt: try requiredDate(value.createdAt, field: "created_at"),
                completedAt: try optionalDate(value.completedAt, field: "completed_at"),
                cancelRequestedAt: try optionalDate(
                    value.cancelRequestedAt,
                    field: "cancel_requested_at"
                ),
                cancelledAt: try optionalDate(
                    value.cancelledAt,
                    field: "cancelled_at"
                )
            )
        }
    }

    static func mapJob(
        _ value: NoteImportJobDetailResponse
    ) throws -> NoteImportJobDetail {
        NoteImportJobDetail(
            jobID: value.jobID,
            clientRequestID: value.clientRequestID,
            status: NoteImportJobStatus(rawValue: value.status),
            soulStatus: NoteImportSoulStatus(rawValue: value.soulStatus),
            soulStatusReason: value.soulStatusReason,
            totalFiles: value.totalFiles,
            importedCount: value.importedCount,
            updatedCount: value.updatedCount,
            skippedCount: value.skippedCount,
            failedCount: value.failedCount,
            errorMessage: value.errorMessage,
            createdAt: try requiredDate(value.createdAt, field: "created_at"),
            completedAt: try optionalDate(value.completedAt, field: "completed_at"),
            cancelRequestedAt: try optionalDate(
                value.cancelRequestedAt,
                field: "cancel_requested_at"
            ),
            cancelledAt: try optionalDate(
                value.cancelledAt,
                field: "cancelled_at"
            ),
            items: try value.items.map { item in
                NoteImportJobItem(
                    sourceKey: item.sourceKey,
                    originalFilename: item.originalFilename,
                    label: item.label ?? "",
                    originalFormat: NoteImportFormat(
                        rawValue: item.originalFormat
                    ),
                    assetID: item.assetID,
                    assetVersionID: item.assetVersionID,
                    status: NoteImportItemStatus(rawValue: item.status),
                    errorMessage: item.errorMessage,
                    processedAt: try optionalDate(
                        item.processedAt,
                        field: "processed_at"
                    )
                )
            }
        )
    }

    private func firstValue<Output>(
        _ publisher: AnyPublisher<Output, NetworkError>
    ) async throws -> Output {
        var iterator = publisher.values.makeAsyncIterator()
        guard let value = try await iterator.next() else {
            throw NetworkError.noData
        }
        return value
    }

    private static func mimeType(for format: NoteImportFormat) -> String {
        switch format {
        case .html: "text/html"
        default: "text/markdown"
        }
    }

    private static func requiredDate(
        _ value: String,
        field: String
    ) throws -> Date {
        guard let date = ChoraContractDateParser.date(from: value) else {
            throw NoteImportServiceError.contract(code: "invalid_\(field)")
        }
        return date
    }

    private static func optionalDate(
        _ value: String?,
        field: String
    ) throws -> Date? {
        guard let value else { return nil }
        return try requiredDate(value, field: field)
    }

    private static func mapNetworkError(
        _ error: Error
    ) -> NoteImportServiceError {
        if let error = error as? NoteImportServiceError {
            return error
        }
        guard let error = error as? NetworkError else {
            return .requestFailed(code: "unknown")
        }
        switch error {
        case .timeout:
            return .ambiguous(.timeout)
        case .networkError(let underlying):
            if let urlError = underlying as? URLError,
               urlError.code == .networkConnectionLost {
                return .ambiguous(.connectionLost)
            }
            return .requestFailed(code: "network")
        case .decodingError:
            return .contract(code: "decoding")
        case .api(_, let code, _):
            return .requestFailed(code: code)
        case .serverError(let status, _):
            return .requestFailed(code: "server_\(status)")
        case .unauthorized:
            return .requestFailed(code: "unauthorized")
        case .forbidden:
            return .requestFailed(code: "forbidden")
        case .notFound:
            return .requestFailed(code: "not_found")
        case .invalidURL:
            return .contract(code: "invalid_url")
        case .noData:
            return .contract(code: "empty_response")
        case .encodingError:
            return .contract(code: "encoding")
        case .unknown:
            return .requestFailed(code: "unknown")
        }
    }
}
