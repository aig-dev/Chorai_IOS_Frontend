import Combine
import CoreFlow
import Foundation

protocol SecurityScopedResourceAccessing: Sendable {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

enum NoteImportFileMetadataError: Error {
    case unavailable
}

protocol NoteImportFileMetadataReading: Sendable {
    func byteCount(for file: NoteImportFile) throws -> Int64
}

struct CoordinatedNoteImportFileMetadataReader:
    NoteImportFileMetadataReading,
    Sendable
{
    func byteCount(for file: NoteImportFile) throws -> Int64 {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Int64, Error>?
        coordinator.coordinate(
            readingItemAt: file.url,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                let values = try coordinatedURL.resourceValues(
                    forKeys: [.fileSizeKey]
                )
                guard let fileSize = values.fileSize else {
                    throw NoteImportFileMetadataError.unavailable
                }
                result = .success(Int64(fileSize))
            } catch {
                result = .failure(error)
            }
        }
        if coordinationError != nil {
            throw NoteImportFileMetadataError.unavailable
        }
        guard let result else {
            throw NoteImportFileMetadataError.unavailable
        }
        return try result.get()
    }
}

struct DeclaredNoteImportFileMetadataReader:
    NoteImportFileMetadataReading,
    Sendable
{
    func byteCount(for file: NoteImportFile) throws -> Int64 {
        guard file.byteCount >= 0 else {
            throw NoteImportFileMetadataError.unavailable
        }
        return file.byteCount
    }
}

struct SystemSecurityScopedResourceAccessor:
    SecurityScopedResourceAccessing,
    Sendable
{
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

final class NoteImportUploadTermination: @unchecked Sendable {
    private let lock = NSLock()
    private var terminated = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        lock.lock()
        guard !terminated else {
            lock.unlock()
            return
        }
        terminated = true
        let currentWaiters = waiters
        waiters.removeAll()
        lock.unlock()
        currentWaiters.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if terminated {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}

protocol MultipartUploadHandling: Sendable {
    func cancel()
    func observeTermination(_ callback: @escaping @Sendable () -> Void)
}

enum MultipartUploadPublisherBuilder {
    static func publisher<Output>(
        handle: any MultipartUploadHandling,
        upstream: AnyPublisher<Output, NetworkError>,
        termination: NoteImportUploadTermination
    ) -> AnyPublisher<Output, NetworkError> {
        handle.observeTermination {
            termination.signal()
        }
        return upstream
            .handleEvents(receiveCancel: {
                handle.cancel()
            })
            .eraseToAnyPublisher()
    }
}

protocol NoteImportUploading: Sendable {
    func enqueue(
        parts: [NoteImportUploadPart],
        clientRequestID: String,
        termination: NoteImportUploadTermination
    ) -> AnyPublisher<NoteImportUploadTransportResult, NetworkError>
}

private final class NoteImportPublisherAwaitState<Output>:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Output, Error>?
    private var cancellable: AnyCancellable?
    private var result: Result<Output, Error>?

    func install(
        continuation: CheckedContinuation<Output, Error>
    ) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func install(cancellable: AnyCancellable) {
        lock.lock()
        if result != nil {
            lock.unlock()
            cancellable.cancel()
        } else {
            self.cancellable = cancellable
            lock.unlock()
        }
    }

    func resolve(_ result: Result<Output, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        let cancellation = CancellationError()
        result = .failure(cancellation)
        let continuation = continuation
        self.continuation = nil
        let cancellable = cancellable
        self.cancellable = nil
        lock.unlock()
        cancellable?.cancel()
        continuation?.resume(throwing: cancellation)
    }

    func finishWithoutValue(_ completion: Subscribers.Completion<NetworkError>) {
        switch completion {
        case .failure(let error):
            resolve(.failure(error))
        case .finished:
            resolve(.failure(NetworkError.noData))
        }
        lock.lock()
        cancellable = nil
        lock.unlock()
    }
}

struct NetworkNoteImportUploader: NoteImportUploading, @unchecked Sendable {
    let network: NetworkManager

    func enqueue(
        parts: [NoteImportUploadPart],
        clientRequestID: String,
        termination: NoteImportUploadTermination
    ) -> AnyPublisher<NoteImportUploadTransportResult, NetworkError> {
        network.enqueueNoteImport(
            parts: parts,
            clientRequestID: clientRequestID,
            termination: termination
        )
    }
}

struct NetworkNoteImportService: CoreNoteImportServing, @unchecked Sendable {
    private let resourceAccessor: any SecurityScopedResourceAccessing
    private let metadataReader: any NoteImportFileMetadataReading
    private let uploader: any NoteImportUploading
    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
        resourceAccessor = SystemSecurityScopedResourceAccessor()
        metadataReader = CoordinatedNoteImportFileMetadataReader()
        uploader = NetworkNoteImportUploader(network: network)
    }

    init(
        network: NetworkManager = .shared,
        resourceAccessor: any SecurityScopedResourceAccessing,
        uploader: any NoteImportUploading,
        metadataReader: any NoteImportFileMetadataReading =
            DeclaredNoteImportFileMetadataReader()
    ) {
        self.network = network
        self.resourceAccessor = resourceAccessor
        self.uploader = uploader
        self.metadataReader = metadataReader
    }

    func enqueue(
        files: [NoteImportFile],
        clientRequestID: String
    ) async throws -> NoteImportReceipt {
        var uniqueURLs: [URL] = []
        var seenURLs: Set<URL> = []
        for file in files where seenURLs.insert(file.url).inserted {
            uniqueURLs.append(file.url)
        }

        var acquiredURLs: [URL] = []
        for url in uniqueURLs {
            guard resourceAccessor.startAccessing(url) else {
                release(acquiredURLs)
                throw NoteImportServiceError.preflight(
                    code: "security_scope_denied"
                )
            }
            acquiredURLs.append(url)
        }
        defer { release(acquiredURLs) }

        var byteCounts: [URL: Int64] = [:]
        do {
            for file in files where byteCounts[file.url] == nil {
                byteCounts[file.url] = try metadataReader.byteCount(for: file)
            }
        } catch {
            throw NoteImportServiceError.preflight(
                code: "file_metadata_unavailable"
            )
        }
        for file in files where byteCounts[file.url] == 0 {
            throw NoteImportServiceError.selection(
                .emptyFile(filename: file.filename)
            )
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

        let termination = NoteImportUploadTermination()
        let result: Result<NoteImportUploadTransportResult, Error>
        do {
            result = .success(try await firstUploadValue(
                uploader.enqueue(
                    parts: parts,
                    clientRequestID: clientRequestID,
                    termination: termination
                )
            ))
        } catch {
            result = .failure(error)
        }
        await termination.wait()

        do {
            switch try result.get() {
            case .response(let response):
                return Self.mapReceipt(response)
            case .undecodableSuccess(let statusCode):
                throw NoteImportServiceError.ambiguous(
                    .undecodableSuccess(statusCode: statusCode)
                )
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as NoteImportServiceError {
            throw error
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    private func release(_ urls: [URL]) {
        for url in urls.reversed() {
            resourceAccessor.stopAccessing(url)
        }
    }

    private func firstUploadValue(
        _ publisher: AnyPublisher<
            NoteImportUploadTransportResult,
            NetworkError
        >
    ) async throws -> NoteImportUploadTransportResult {
        let state = NoteImportPublisherAwaitState<
            NoteImportUploadTransportResult
        >()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation: continuation)
                let cancellable = publisher.sink(
                    receiveCompletion: { completion in
                        state.finishWithoutValue(completion)
                    },
                    receiveValue: { value in
                        state.resolve(.success(value))
                    }
                )
                state.install(cancellable: cancellable)
            }
        } onCancel: {
            state.cancel()
        }
    }

    func jobs(limit: Int) async throws -> [NoteImportJobSummary] {
        do {
            let response = try await firstValue(
                network.getNoteImportJobs(
                    limit: limit
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
                    id: id
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
                    id: id
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
