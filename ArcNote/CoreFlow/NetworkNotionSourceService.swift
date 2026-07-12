import Combine
import CoreFlow
import Foundation

struct NetworkNotionSourceService: CoreNotionSourceServing, @unchecked Sendable {
    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func status() async throws -> NotionConnectionStatus {
        do {
            return Self.mapStatus(
                try await firstValue(
                    network.getNotionStatus(presentsError: false)
                )
            )
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func authorizationURL(client: NotionClient) async throws -> URL {
        guard client == .ios else {
            throw NotionSourceError.requestFailed
        }
        do {
            let response = try await firstValue(
                network.getNotionAuthorizationURL(
                    client: "ios",
                    presentsError: false
                )
            )
            guard let url = URL(string: response.authURL) else {
                throw NotionSourceError.requestFailed
            }
            return url
        } catch let error as NotionSourceError {
            throw error
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func pages(query: String?) async throws -> [NotionPage] {
        do {
            return Self.mapPages(
                try await firstValue(
                    network.getNotionPages(
                        query: query,
                        presentsError: false
                    )
                )
            )
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func enqueue(pageIDs: [String]) async throws -> NotionImportReceipt {
        do {
            let response = try await firstValue(
                network.enqueueNotionImport(
                    pageIDs: pageIDs,
                    presentsError: false
                )
            )
            return Self.mapReceipt(response, acceptedPageIDs: pageIDs)
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func job(id: String) async throws -> NotionImportJob {
        do {
            return Self.mapJob(
                try await firstValue(
                    network.getNotionImportJob(
                        id: id,
                        presentsError: false
                    )
                )
            )
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func disconnect() async throws {
        do {
            let response = try await firstValue(
                network.disconnectNotion(presentsError: false)
            )
            guard response.disconnected else {
                throw NotionSourceError.requestFailed
            }
        } catch let error as NotionSourceError {
            throw error
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    static func mapStatus(
        _ response: NotionStatusResponse
    ) -> NotionConnectionStatus {
        NotionConnectionStatus(
            state: response.connected ? .connected : .disconnected,
            workspaceID: response.workspaceID,
            workspaceName: nil
        )
    }

    static func mapPages(
        _ response: NotionPagesResponse
    ) -> [NotionPage] {
        response.pages.map {
            NotionPage(id: $0.pageID, title: $0.title)
        }
    }

    static func mapReceipt(
        _ response: NotionEnqueueResponse,
        acceptedPageIDs: [String]
    ) -> NotionImportReceipt {
        NotionImportReceipt(
            jobID: response.jobID,
            acceptedPageIDs: acceptedPageIDs
        )
    }

    static func mapJob(
        _ response: NotionImportJobResponse
    ) -> NotionImportJob {
        let failedCount = response.failed.count
        let completedCount = response.imported
            + response.updated
            + response.skipped
            + failedCount
        let status = response.status == "done"
            ? NotionImportJobStatus.completed
            : NotionImportJobStatus(rawValue: response.status)
        let failureReason = response.failed.isEmpty ? nil : response.failed
            .map { "\($0.pageID): \($0.reason)" }
            .joined(separator: "\n")
        return NotionImportJob(
            id: response.jobID,
            status: status,
            totalPages: completedCount,
            completedPages: completedCount,
            importedAssetIDs: [],
            failureReason: failureReason
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

    private static func mapNetworkError(_ error: Error) -> NotionSourceError {
        if let error = error as? NotionSourceError {
            return error
        }
        return .requestFailed
    }
}
