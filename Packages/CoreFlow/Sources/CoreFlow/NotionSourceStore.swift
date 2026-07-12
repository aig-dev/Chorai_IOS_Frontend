import Combine
import Foundation

@MainActor
public final class NotionSourceStore: ObservableObject {
    @Published public private(set) var actorID: String?
    @Published public private(set) var status: NotionConnectionStatus?
    @Published public private(set) var statusPhase: NotionSourcePhase = .idle
    @Published public private(set) var authorizationRequest: NotionAuthorizationRequest?
    @Published public private(set) var pages: [NotionPage] = []
    @Published public private(set) var pagesPhase: NotionSourcePhase = .idle
    @Published public private(set) var selectedPageIDs: [String] = []
    @Published public private(set) var importReceipt: NotionImportReceipt?
    @Published public private(set) var importJob: NotionImportJob?
    @Published public private(set) var lastImportPolledAt: Date?
    @Published public private(set) var isConnecting = false
    @Published public private(set) var isImporting = false
    @Published public private(set) var isDisconnecting = false
    @Published public private(set) var statusError: NotionSourceError?
    @Published public private(set) var connectionError: NotionSourceError?
    @Published public private(set) var pagesError: NotionSourceError?
    @Published public private(set) var importError: NotionSourceError?
    @Published public private(set) var disconnectError: NotionSourceError?

    public var authorizationURL: URL? { authorizationRequest?.url }

    public var inlineError: NotionSourceError? {
        statusError ?? connectionError ?? pagesError ?? importError ?? disconnectError
    }

    private struct AuthorizationBinding: Sendable {
        let request: NotionAuthorizationRequest
        let actorID: String
        let actorGeneration: UUID
        let connectionGeneration: UUID
    }

    private let service: any CoreNotionSourceServing
    private let sleeper: any NotionSourceSleeping
    private let clock: any NotionSourceClock
    private let pollInterval: TimeInterval
    private var actorGeneration = UUID()
    private var connectionGeneration = UUID()
    private var sourceGeneration = UUID()
    private var authorizationBinding: AuthorizationBinding?
    private var statusTask: Task<Void, Never>?
    private var statusOperationID: UUID?
    private var connectTask: Task<Void, Never>?
    private var connectOperationID: UUID?
    private var pagesTask: Task<Void, Never>?
    private var pagesOperationID: UUID?
    private var activePageQuery: String?
    private var importTask: Task<Void, Never>?
    private var importOperationID: UUID?
    private var disconnectTask: Task<Void, Never>?
    private var disconnectOperationID: UUID?

    public init(
        service: any CoreNotionSourceServing,
        sleeper: any NotionSourceSleeping = SystemNotionSourceSleeper(),
        clock: any NotionSourceClock = SystemNotionSourceClock(),
        pollInterval: TimeInterval = 0.75
    ) {
        self.service = service
        self.sleeper = sleeper
        self.clock = clock
        self.pollInterval = pollInterval
    }

    deinit {
        statusTask?.cancel()
        connectTask?.cancel()
        pagesTask?.cancel()
        importTask?.cancel()
        disconnectTask?.cancel()
    }

    public func load(actorID rawActorID: String) {
        invalidateActorGeneration()
        resetPublishedState()
        let normalized = rawActorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            statusPhase = .failed
            statusError = .invalidActor
            return
        }
        actorID = normalized
        reloadStatus()
    }

    public func reloadStatus() {
        guard disconnectTask == nil, !isDisconnecting, let actorID else { return }
        cancelStatusOperation()
        cancelConnectOperation(clearAuthorization: true)
        connectionGeneration = UUID()
        startStatusReload(
            actorID: actorID,
            actorGeneration: actorGeneration,
            connectionGeneration: connectionGeneration
        )
    }

    public func connect() {
        guard disconnectTask == nil,
              !isDisconnecting,
              connectTask == nil,
              authorizationBinding == nil,
              let actorID else {
            return
        }
        cancelStatusOperation()
        connectionGeneration = UUID()
        let actorScope = actorGeneration
        let connectionScope = connectionGeneration
        let operationID = UUID()
        connectOperationID = operationID
        isConnecting = true
        authorizationRequest = nil
        connectionError = nil
        let service = service
        connectTask = Task { [weak self, service] in
            defer {
                self?.finishConnect(
                    operationID: operationID,
                    actorGeneration: actorScope,
                    connectionGeneration: connectionScope
                )
            }
            do {
                let url = try await service.authorizationURL(client: .ios)
                guard self?.isCurrentConnect(
                    operationID: operationID,
                    actorID: actorID,
                    actorGeneration: actorScope,
                    connectionGeneration: connectionScope
                ) == true else {
                    return
                }
                let request = NotionAuthorizationRequest(id: operationID, url: url)
                self?.authorizationBinding = AuthorizationBinding(
                    request: request,
                    actorID: actorID,
                    actorGeneration: actorScope,
                    connectionGeneration: connectionScope
                )
                self?.authorizationRequest = request
            } catch {
                guard self?.isCurrentConnect(
                    operationID: operationID,
                    actorID: actorID,
                    actorGeneration: actorScope,
                    connectionGeneration: connectionScope
                ) == true else {
                    return
                }
                self?.connectionError = .requestFailed
            }
        }
    }

    public func clearAuthorizationURL() {
        authorizationRequest = nil
    }

    public func authorizationCompleted(
        id: UUID,
        result: NotionAuthorizationResult
    ) {
        guard disconnectTask == nil,
              !isDisconnecting,
              let binding = authorizationBinding,
              binding.request.id == id,
              binding.actorID == actorID,
              binding.actorGeneration == actorGeneration,
              binding.connectionGeneration == connectionGeneration else {
            return
        }
        authorizationBinding = nil
        authorizationRequest = nil
        connectionGeneration = UUID()
        let completionGeneration = connectionGeneration
        switch result {
        case .cancelled:
            connectionError = nil
        case .failed:
            connectionError = .authorizationFailed
        case .success:
            connectionError = nil
            cancelStatusOperation()
            startStatusReload(
                actorID: binding.actorID,
                actorGeneration: binding.actorGeneration,
                connectionGeneration: completionGeneration
            )
        }
    }

    public func searchPages(query: String?) {
        guard disconnectTask == nil, !isDisconnecting, let actorID else { return }
        if pagesTask != nil {
            guard activePageQuery != query else { return }
            cancelPagesOperation()
        }
        let actorScope = actorGeneration
        let sourceScope = sourceGeneration
        let operationID = UUID()
        pagesOperationID = operationID
        activePageQuery = query
        pagesPhase = .loading
        pagesError = nil
        let service = service
        pagesTask = Task { [weak self, service] in
            defer {
                self?.finishPages(
                    operationID: operationID,
                    actorGeneration: actorScope,
                    sourceGeneration: sourceScope
                )
            }
            do {
                let canonical = try await service.pages(query: query)
                guard self?.isCurrentPages(
                    operationID: operationID,
                    actorID: actorID,
                    actorGeneration: actorScope,
                    sourceGeneration: sourceScope
                ) == true else {
                    return
                }
                self?.pages = canonical
                self?.pagesPhase = .ready
            } catch {
                guard self?.isCurrentPages(
                    operationID: operationID,
                    actorID: actorID,
                    actorGeneration: actorScope,
                    sourceGeneration: sourceScope
                ) == true else {
                    return
                }
                self?.pagesPhase = .failed
                self?.pagesError = .requestFailed
            }
        }
    }

    public func setSelectedPageIDs(_ pageIDs: [String]) {
        var seen: Set<String> = []
        selectedPageIDs = pageIDs.filter { seen.insert($0).inserted }
    }

    public func startImport() {
        guard disconnectTask == nil,
              !isDisconnecting,
              importTask == nil,
              let actorID else {
            return
        }
        guard !selectedPageIDs.isEmpty else {
            importError = .noPagesSelected
            return
        }
        let selected = selectedPageIDs
        let actorScope = actorGeneration
        let sourceScope = sourceGeneration
        let operationID = UUID()
        importOperationID = operationID
        isImporting = true
        importError = nil
        let service = service
        let sleeper = sleeper
        let clock = clock
        let pollInterval = pollInterval
        importTask = Task { [weak self, service, sleeper, clock] in
            defer {
                self?.finishImport(
                    operationID: operationID,
                    actorGeneration: actorScope,
                    sourceGeneration: sourceScope
                )
            }
            do {
                let receipt = try await service.enqueue(pageIDs: selected)
                guard self?.isCurrentImport(
                    operationID: operationID,
                    actorID: actorID,
                    actorGeneration: actorScope,
                    sourceGeneration: sourceScope
                ) == true else {
                    return
                }
                self?.importReceipt = receipt

                while !Task.isCancelled {
                    let canonical = try await service.job(id: receipt.jobID)
                    guard self?.isCurrentImport(
                        operationID: operationID,
                        actorID: actorID,
                        actorGeneration: actorScope,
                        sourceGeneration: sourceScope
                    ) == true else {
                        return
                    }
                    self?.importJob = canonical
                    self?.lastImportPolledAt = clock.now()
                    if canonical.status.isKnownTerminal { return }
                    try await sleeper.sleep(for: pollInterval)
                }
            } catch is CancellationError {
                return
            } catch {
                guard self?.isCurrentImport(
                    operationID: operationID,
                    actorID: actorID,
                    actorGeneration: actorScope,
                    sourceGeneration: sourceScope
                ) == true else {
                    return
                }
                self?.importError = .requestFailed
            }
        }
    }

    public func disconnect() {
        guard disconnectTask == nil, let actorID else { return }
        connectionGeneration = UUID()
        sourceGeneration = UUID()
        let actorScope = actorGeneration
        let connectionScope = connectionGeneration
        cancelStatusOperation()
        cancelConnectOperation(clearAuthorization: true)
        cancelPagesOperation()
        cancelImportOperation()
        statusPhase = status == nil ? .idle : .ready
        statusError = nil
        let operationID = UUID()
        disconnectOperationID = operationID
        isDisconnecting = true
        disconnectError = nil
        let service = service
        disconnectTask = Task { [weak self, service] in
            defer {
                self?.finishDisconnect(
                    operationID: operationID,
                    actorGeneration: actorScope,
                    connectionGeneration: connectionScope
                )
            }
            do {
                try await service.disconnect()
                guard self?.isCurrentDisconnect(
                    operationID: operationID,
                    actorID: actorID,
                    actorGeneration: actorScope,
                    connectionGeneration: connectionScope
                ) == true else {
                    return
                }
                let canonical = try await service.status()
                guard self?.isCurrentDisconnect(
                    operationID: operationID,
                    actorID: actorID,
                    actorGeneration: actorScope,
                    connectionGeneration: connectionScope
                ) == true else {
                    return
                }
                self?.status = canonical
                self?.statusPhase = .ready
                self?.statusError = nil
            } catch {
                guard self?.isCurrentDisconnect(
                    operationID: operationID,
                    actorID: actorID,
                    actorGeneration: actorScope,
                    connectionGeneration: connectionScope
                ) == true else {
                    return
                }
                self?.disconnectError = .requestFailed
            }
        }
    }

    private func startStatusReload(
        actorID: String,
        actorGeneration actorScope: UUID,
        connectionGeneration connectionScope: UUID
    ) {
        let operationID = UUID()
        statusOperationID = operationID
        statusPhase = .loading
        statusError = nil
        let service = service
        statusTask = Task { [weak self, service] in
            defer {
                self?.finishStatus(
                    operationID: operationID,
                    actorGeneration: actorScope,
                    connectionGeneration: connectionScope
                )
            }
            do {
                let canonical = try await service.status()
                guard self?.isCurrentStatus(
                    operationID: operationID,
                    actorID: actorID,
                    actorGeneration: actorScope,
                    connectionGeneration: connectionScope
                ) == true else {
                    return
                }
                self?.status = canonical
                self?.statusPhase = .ready
            } catch {
                guard self?.isCurrentStatus(
                    operationID: operationID,
                    actorID: actorID,
                    actorGeneration: actorScope,
                    connectionGeneration: connectionScope
                ) == true else {
                    return
                }
                self?.statusPhase = .failed
                self?.statusError = .requestFailed
            }
        }
    }

    private func isCurrentBase(actorID: String, actorGeneration: UUID) -> Bool {
        !Task.isCancelled && self.actorID == actorID && self.actorGeneration == actorGeneration
    }

    private func isCurrentStatus(
        operationID: UUID,
        actorID: String,
        actorGeneration: UUID,
        connectionGeneration: UUID
    ) -> Bool {
        isCurrentBase(actorID: actorID, actorGeneration: actorGeneration) &&
            self.connectionGeneration == connectionGeneration &&
            statusOperationID == operationID &&
            disconnectTask == nil
    }

    private func isCurrentConnect(
        operationID: UUID,
        actorID: String,
        actorGeneration: UUID,
        connectionGeneration: UUID
    ) -> Bool {
        isCurrentBase(actorID: actorID, actorGeneration: actorGeneration) &&
            self.connectionGeneration == connectionGeneration &&
            connectOperationID == operationID &&
            disconnectTask == nil
    }

    private func isCurrentPages(
        operationID: UUID,
        actorID: String,
        actorGeneration: UUID,
        sourceGeneration: UUID
    ) -> Bool {
        isCurrentBase(actorID: actorID, actorGeneration: actorGeneration) &&
            self.sourceGeneration == sourceGeneration &&
            pagesOperationID == operationID &&
            disconnectTask == nil
    }

    private func isCurrentImport(
        operationID: UUID,
        actorID: String,
        actorGeneration: UUID,
        sourceGeneration: UUID
    ) -> Bool {
        isCurrentBase(actorID: actorID, actorGeneration: actorGeneration) &&
            self.sourceGeneration == sourceGeneration &&
            importOperationID == operationID &&
            disconnectTask == nil
    }

    private func isCurrentDisconnect(
        operationID: UUID,
        actorID: String,
        actorGeneration: UUID,
        connectionGeneration: UUID
    ) -> Bool {
        isCurrentBase(actorID: actorID, actorGeneration: actorGeneration) &&
            self.connectionGeneration == connectionGeneration &&
            disconnectOperationID == operationID
    }

    private func finishStatus(
        operationID: UUID,
        actorGeneration: UUID,
        connectionGeneration: UUID
    ) {
        guard self.actorGeneration == actorGeneration,
              self.connectionGeneration == connectionGeneration,
              statusOperationID == operationID else {
            return
        }
        statusTask = nil
        statusOperationID = nil
    }

    private func finishConnect(
        operationID: UUID,
        actorGeneration: UUID,
        connectionGeneration: UUID
    ) {
        guard self.actorGeneration == actorGeneration,
              self.connectionGeneration == connectionGeneration,
              connectOperationID == operationID else {
            return
        }
        connectTask = nil
        connectOperationID = nil
        isConnecting = false
    }

    private func finishPages(
        operationID: UUID,
        actorGeneration: UUID,
        sourceGeneration: UUID
    ) {
        guard self.actorGeneration == actorGeneration,
              self.sourceGeneration == sourceGeneration,
              pagesOperationID == operationID else {
            return
        }
        pagesTask = nil
        pagesOperationID = nil
        activePageQuery = nil
    }

    private func finishImport(
        operationID: UUID,
        actorGeneration: UUID,
        sourceGeneration: UUID
    ) {
        guard self.actorGeneration == actorGeneration,
              self.sourceGeneration == sourceGeneration,
              importOperationID == operationID else {
            return
        }
        importTask = nil
        importOperationID = nil
        isImporting = false
    }

    private func finishDisconnect(
        operationID: UUID,
        actorGeneration: UUID,
        connectionGeneration: UUID
    ) {
        guard self.actorGeneration == actorGeneration,
              self.connectionGeneration == connectionGeneration,
              disconnectOperationID == operationID else {
            return
        }
        disconnectTask = nil
        disconnectOperationID = nil
        isDisconnecting = false
    }

    private func cancelStatusOperation() {
        statusTask?.cancel()
        statusTask = nil
        statusOperationID = nil
    }

    private func cancelConnectOperation(clearAuthorization: Bool) {
        connectTask?.cancel()
        connectTask = nil
        connectOperationID = nil
        isConnecting = false
        guard clearAuthorization else { return }
        authorizationBinding = nil
        authorizationRequest = nil
    }

    private func cancelPagesOperation() {
        pagesTask?.cancel()
        pagesTask = nil
        pagesOperationID = nil
        activePageQuery = nil
        pagesPhase = pages.isEmpty ? .idle : .ready
    }

    private func cancelImportOperation() {
        importTask?.cancel()
        importTask = nil
        importOperationID = nil
        isImporting = false
    }

    private func invalidateActorGeneration() {
        actorGeneration = UUID()
        connectionGeneration = UUID()
        sourceGeneration = UUID()
        cancelStatusOperation()
        cancelConnectOperation(clearAuthorization: true)
        cancelPagesOperation()
        cancelImportOperation()
        disconnectTask?.cancel()
        disconnectTask = nil
        disconnectOperationID = nil
    }

    private func resetPublishedState() {
        actorID = nil
        status = nil
        statusPhase = .idle
        authorizationBinding = nil
        authorizationRequest = nil
        pages = []
        pagesPhase = .idle
        selectedPageIDs = []
        importReceipt = nil
        importJob = nil
        lastImportPolledAt = nil
        isConnecting = false
        isImporting = false
        isDisconnecting = false
        statusError = nil
        connectionError = nil
        pagesError = nil
        importError = nil
        disconnectError = nil
    }
}
