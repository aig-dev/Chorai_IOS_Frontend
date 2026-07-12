import Combine
import Foundation

@MainActor
public final class NotionSourceStore: ObservableObject {
    @Published public private(set) var actorID: String?
    @Published public private(set) var status: NotionConnectionStatus?
    @Published public private(set) var statusPhase: NotionSourcePhase = .idle
    @Published public private(set) var authorizationURL: URL?
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

    public var inlineError: NotionSourceError? {
        statusError ?? connectionError ?? pagesError ?? importError ?? disconnectError
    }

    private let service: any CoreNotionSourceServing
    private let sleeper: any NotionSourceSleeping
    private let clock: any NotionSourceClock
    private let pollInterval: TimeInterval
    private var generation = UUID()
    private var statusTask: Task<Void, Never>?
    private var statusOperationID: UUID?
    private var connectTask: Task<Void, Never>?
    private var connectOperationID: UUID?
    private var pagesTask: Task<Void, Never>?
    private var pagesOperationID: UUID?
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
        invalidateGeneration()
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
        guard let actorID else { return }
        statusTask?.cancel()
        let scope = generation
        let operationID = UUID()
        statusOperationID = operationID
        statusPhase = .loading
        statusError = nil
        let service = service
        statusTask = Task { [weak self, service] in
            defer { self?.finishStatus(operationID: operationID, generation: scope) }
            do {
                let canonical = try await service.status()
                guard self?.isCurrent(actorID: actorID, generation: scope) == true else {
                    return
                }
                self?.status = canonical
                self?.statusPhase = .ready
            } catch {
                guard self?.isCurrent(actorID: actorID, generation: scope) == true else {
                    return
                }
                self?.statusPhase = .failed
                self?.statusError = .requestFailed
            }
        }
    }

    public func connect() {
        guard connectTask == nil, let actorID else { return }
        let scope = generation
        let operationID = UUID()
        connectOperationID = operationID
        isConnecting = true
        authorizationURL = nil
        connectionError = nil
        let service = service
        connectTask = Task { [weak self, service] in
            defer { self?.finishConnect(operationID: operationID, generation: scope) }
            do {
                let url = try await service.authorizationURL(client: .ios)
                guard self?.isCurrent(actorID: actorID, generation: scope) == true else {
                    return
                }
                self?.authorizationURL = url
            } catch {
                guard self?.isCurrent(actorID: actorID, generation: scope) == true else {
                    return
                }
                self?.connectionError = .requestFailed
            }
        }
    }

    public func clearAuthorizationURL() {
        authorizationURL = nil
    }

    public func authorizationCompleted(_ result: NotionAuthorizationResult) {
        authorizationURL = nil
        switch result {
        case .cancelled:
            connectionError = nil
        case .success:
            connectionError = nil
            reloadStatus()
        case .failed:
            connectionError = .authorizationFailed
        }
    }

    public func searchPages(query: String?) {
        guard pagesTask == nil, let actorID else { return }
        let scope = generation
        let operationID = UUID()
        pagesOperationID = operationID
        pagesPhase = .loading
        pagesError = nil
        let service = service
        pagesTask = Task { [weak self, service] in
            defer { self?.finishPages(operationID: operationID, generation: scope) }
            do {
                let canonical = try await service.pages(query: query)
                guard self?.isCurrent(actorID: actorID, generation: scope) == true else {
                    return
                }
                self?.pages = canonical
                self?.pagesPhase = .ready
            } catch {
                guard self?.isCurrent(actorID: actorID, generation: scope) == true else {
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
        guard importTask == nil, let actorID else { return }
        guard !selectedPageIDs.isEmpty else {
            importError = .noPagesSelected
            return
        }
        let selected = selectedPageIDs
        let scope = generation
        let operationID = UUID()
        importOperationID = operationID
        isImporting = true
        importError = nil
        let service = service
        let sleeper = sleeper
        let clock = clock
        let pollInterval = pollInterval
        importTask = Task { [weak self, service, sleeper, clock] in
            defer { self?.finishImport(operationID: operationID, generation: scope) }
            do {
                let receipt = try await service.enqueue(pageIDs: selected)
                guard self?.isCurrent(actorID: actorID, generation: scope) == true else {
                    return
                }
                self?.importReceipt = receipt

                while !Task.isCancelled {
                    let canonical = try await service.job(id: receipt.jobID)
                    guard self?.isCurrent(actorID: actorID, generation: scope) == true else {
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
                guard self?.isCurrent(actorID: actorID, generation: scope) == true else {
                    return
                }
                self?.importError = .requestFailed
            }
        }
    }

    public func disconnect() {
        guard disconnectTask == nil, let actorID else { return }
        statusTask?.cancel()
        statusTask = nil
        statusOperationID = nil
        statusPhase = status == nil ? .idle : .ready
        statusError = nil
        let scope = generation
        let operationID = UUID()
        disconnectOperationID = operationID
        isDisconnecting = true
        disconnectError = nil
        let service = service
        disconnectTask = Task { [weak self, service] in
            defer { self?.finishDisconnect(operationID: operationID, generation: scope) }
            do {
                try await service.disconnect()
                guard self?.isCurrent(actorID: actorID, generation: scope) == true else {
                    return
                }
                let canonical = try await service.status()
                guard self?.isCurrent(actorID: actorID, generation: scope) == true else {
                    return
                }
                self?.status = canonical
                self?.statusPhase = .ready
                self?.statusError = nil
            } catch {
                guard self?.isCurrent(actorID: actorID, generation: scope) == true else {
                    return
                }
                self?.disconnectError = .requestFailed
            }
        }
    }

    private func finishStatus(operationID: UUID, generation: UUID) {
        guard self.generation == generation, statusOperationID == operationID else { return }
        statusTask = nil
        statusOperationID = nil
    }

    private func finishConnect(operationID: UUID, generation: UUID) {
        guard self.generation == generation, connectOperationID == operationID else { return }
        connectTask = nil
        connectOperationID = nil
        isConnecting = false
    }

    private func finishPages(operationID: UUID, generation: UUID) {
        guard self.generation == generation, pagesOperationID == operationID else { return }
        pagesTask = nil
        pagesOperationID = nil
    }

    private func finishImport(operationID: UUID, generation: UUID) {
        guard self.generation == generation, importOperationID == operationID else { return }
        importTask = nil
        importOperationID = nil
        isImporting = false
    }

    private func finishDisconnect(operationID: UUID, generation: UUID) {
        guard self.generation == generation, disconnectOperationID == operationID else { return }
        disconnectTask = nil
        disconnectOperationID = nil
        isDisconnecting = false
    }

    private func isCurrent(actorID: String, generation: UUID) -> Bool {
        !Task.isCancelled && self.actorID == actorID && self.generation == generation
    }

    private func invalidateGeneration() {
        generation = UUID()
        statusTask?.cancel()
        connectTask?.cancel()
        pagesTask?.cancel()
        importTask?.cancel()
        disconnectTask?.cancel()
        statusTask = nil
        connectTask = nil
        pagesTask = nil
        importTask = nil
        disconnectTask = nil
        statusOperationID = nil
        connectOperationID = nil
        pagesOperationID = nil
        importOperationID = nil
        disconnectOperationID = nil
    }

    private func resetPublishedState() {
        actorID = nil
        status = nil
        statusPhase = .idle
        authorizationURL = nil
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
