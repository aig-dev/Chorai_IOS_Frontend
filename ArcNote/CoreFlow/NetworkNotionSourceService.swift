import Combine
import CoreFlow
import Foundation

struct NotionAuthorizationValues: Equatable {
    let url: URL
    let state: String
}

struct NotionPageSyncProjection: Equatable {
    let pageID: String
    let assetID: String?
    let status: String
    let lastSyncedAt: String?
    let errorMessage: String?
    let retryCount: UInt8
}

struct NetworkNotionSourceService: CoreNotionSourceServing, @unchecked Sendable {
    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func status() async throws -> NotionConnectionStatus {
        do {
            return Self.mapStatus(
                try await firstValue(
                    network.getNotionStatus()
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
            return try Self.mapAuthorization(
                try await firstValue(
                    network.getNotionAuthorizationURL()
                )
            )
            .url
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
                    network.getNotionPages(query: query)
                )
            )
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func enqueue(pageIDs: [String]) async throws -> NotionImportReceipt {
        do {
            let response = try await firstValue(
                network.enqueueNotionImport(pageIDs: pageIDs)
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
                    network.getNotionImportJob(id: id)
                )
            )
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func disconnect() async throws {
        do {
            let response = try await firstValue(
                network.disconnectNotion()
            )
            try Self.validateDisconnect(response)
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

    static func mapAuthorization(
        _ response: NotionConnectResponse
    ) throws -> NotionAuthorizationValues {
        guard let url = URL(string: response.authURL) else {
            throw NotionSourceError.requestFailed
        }
        return NotionAuthorizationValues(url: url, state: response.state)
    }

    static func mapPageStatuses(
        _ response: NotionStatusResponse
    ) -> [NotionPageSyncProjection] {
        response.pages.map {
            NotionPageSyncProjection(
                pageID: $0.notionPageID,
                assetID: $0.assetID,
                status: $0.status,
                lastSyncedAt: $0.lastSyncedAt,
                errorMessage: $0.errorMessage,
                retryCount: $0.retryCount
            )
        }
    }

    static func validateDisconnect(
        _ response: NotionDisconnectResponse
    ) throws {
        guard response.disconnected else {
            throw NotionSourceError.requestFailed
        }
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
        return NotionImportJob(
            id: response.jobID,
            status: NotionImportJobStatus(rawValue: response.status),
            imported: response.imported,
            updated: response.updated,
            skipped: response.skipped,
            failures: response.failed.map {
                NotionPageFailure(pageID: $0.pageID, reason: $0.reason)
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

    private static func mapNetworkError(_ error: Error) -> NotionSourceError {
        if let error = error as? NotionSourceError {
            return error
        }
        return .requestFailed
    }
}
