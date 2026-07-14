import Combine
import Foundation

@MainActor
public final class OnboardingGuideStore: ObservableObject {
    public static let canonicalFlowVersion = 1

    @Published public private(set) var phase: OnboardingGuidePhase = .idle
    @Published public private(set) var session: OnboardingGuideSession?
    @Published public private(set) var isSending = false
    @Published public private(set) var lastError: OnboardingGuideError?

    public var shouldGuideLibraryCreation: Bool {
        phase == .active && session?.state == State.elicitSignal
    }

    public var guideScene: OnboardingGuideScene? {
        guard phase == .active else {
            return nil
        }
        return session?.scene
    }

    private enum State {
        static let elicitSignal = "elicit_signal"
        static let deepenSignal = "deepen_signal"
        static let curatorIntro = "product_curator_intro"
        static let exploreCard = "product_explore_card"
        static let sparkIntro = "product_spark_intro"
        static let sparkResults = "product_spark_results"
        static let saveMaterial = "product_save_material"
        static let mergeIntro = "product_merge_intro"
        static let mergePreview = "product_merge_preview"
        static let libraryIntro = "product_library_intro"
        static let buildIgnite = "build_ignite"

        static let order: [String] = [
            elicitSignal,
            deepenSignal,
            curatorIntro,
            exploreCard,
            sparkIntro,
            sparkResults,
            saveMaterial,
            mergeIntro,
            mergePreview,
            libraryIntro,
            buildIgnite
        ]
    }

    private let service: OnboardingGuideServing
    private let persistence: OnboardingGuidePersisting
    private var actorID: String?
    private var pendingEvidence: [OnboardingGuideEvidence] = []
    private var cancellables = Set<AnyCancellable>()
    private var loadGeneration = UUID()

    public init(
        service: OnboardingGuideServing,
        persistence: OnboardingGuidePersisting
    ) {
        self.service = service
        self.persistence = persistence
    }

    public func load(actorID: String) {
        let trimmedActorID = actorID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedActorID.isEmpty else {
            reset()
            return
        }

        cancellables.removeAll()
        loadGeneration = UUID()
        let generation = loadGeneration
        self.actorID = trimmedActorID
        session = nil
        pendingEvidence = []
        phase = .loading
        isSending = false
        lastError = nil

        service.status()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self,
                      self.loadGeneration == generation,
                      case .failure(let error) = completion else {
                    return
                }
                self.failLoad(error)
            } receiveValue: { [weak self] status in
                guard let self, self.loadGeneration == generation else { return }
                if status.completed || !status.needsOnboarding {
                    self.phase = .completed
                } else if status.activeSessionID?.isEmpty == false {
                    self.loadCurrent(generation: generation)
                } else {
                    self.startCanonical(generation: generation)
                }
            }
            .store(in: &cancellables)
    }

    public func receive(_ evidence: OnboardingGuideEvidence) {
        guard phase == .active,
              let actorID,
              let session,
              session.flowVersion == Self.canonicalFlowVersion else {
            return
        }

        guard shouldQueue(evidence, for: session.state),
              !pendingEvidence.contains(evidence) else {
            return
        }
        pendingEvidence.append(evidence)
        persistPending(actorID: actorID, sessionID: session.sessionID)
        reconcileEvidence()
    }

    public func retryPendingEvidence() {
        guard !isSending else { return }
        lastError = nil
        if phase == .unavailable, let actorID {
            load(actorID: actorID)
        } else {
            reconcileEvidence()
        }
    }

    public func skip() {
        guard phase == .active,
              !isSending,
              let actorID,
              let session else {
            return
        }

        isSending = true
        lastError = nil
        service.skip(sessionID: session.sessionID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self else { return }
                self.isSending = false
                if case .failure(let error) = completion {
                    self.lastError = error
                }
            } receiveValue: { [weak self] skipped in
                guard let self else { return }
                self.session = skipped
                self.phase = .skipped
                self.pendingEvidence = []
                self.persistence.clear(
                    actorID: actorID,
                    sessionID: session.sessionID
                )
                self.lastError = nil
            }
            .store(in: &cancellables)
    }

    public func reset() {
        cancellables.removeAll()
        loadGeneration = UUID()
        actorID = nil
        pendingEvidence = []
        phase = .idle
        session = nil
        isSending = false
        lastError = nil
    }

    private func loadCurrent(generation: UUID) {
        service.current()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self,
                      self.loadGeneration == generation,
                      case .failure(let error) = completion else {
                    return
                }
                self.failLoad(error)
            } receiveValue: { [weak self] session in
                guard let self, self.loadGeneration == generation else { return }
                self.accept(session, reloadEvidence: true)
            }
            .store(in: &cancellables)
    }

    private func startCanonical(generation: UUID) {
        service.start(flowVersion: Self.canonicalFlowVersion)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self,
                      self.loadGeneration == generation,
                      case .failure(let error) = completion else {
                    return
                }
                self.failLoad(error)
            } receiveValue: { [weak self] session in
                guard let self, self.loadGeneration == generation else { return }
                self.accept(session, reloadEvidence: true)
            }
            .store(in: &cancellables)
    }

    private func accept(
        _ canonicalSession: OnboardingGuideSession,
        reloadEvidence: Bool
    ) {
        session = canonicalSession
        lastError = nil

        guard canonicalSession.flowVersion == Self.canonicalFlowVersion else {
            pendingEvidence = []
            phase = .deferred(flowVersion: canonicalSession.flowVersion)
            return
        }

        switch canonicalSession.status {
        case "completed":
            phase = .completed
            clearPersistence(for: canonicalSession)
        case "skipped":
            phase = .skipped
            clearPersistence(for: canonicalSession)
        default:
            phase = .active
            if reloadEvidence, let actorID {
                pendingEvidence = persistence.pendingEvidence(
                    actorID: actorID,
                    sessionID: canonicalSession.sessionID
                )
            }
            prunePastEvidence(currentState: canonicalSession.state)
            reconcileEvidence()
        }
    }

    private func reconcileEvidence() {
        guard phase == .active,
              !isSending,
              let actorID,
              let session else {
            return
        }

        if session.state == State.buildIgnite {
            complete(session: session, actorID: actorID)
            return
        }

        guard let index = pendingEvidence.firstIndex(
            where: { evidenceMatches($0, state: session.state) }
        ) else {
            return
        }

        let evidence = pendingEvidence[index]
        let input = responseInput(for: evidence)
        isSending = true
        lastError = nil
        service.respond(sessionID: session.sessionID, input: input)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self,
                      case .failure(let error) = completion else {
                    return
                }
                self.isSending = false
                self.lastError = error
            } receiveValue: { [weak self] next in
                guard let self else { return }
                self.pendingEvidence.removeAll { $0 == evidence }
                self.persistPending(actorID: actorID, sessionID: session.sessionID)
                self.isSending = false
                self.accept(next, reloadEvidence: false)
            }
            .store(in: &cancellables)
    }

    private func complete(
        session: OnboardingGuideSession,
        actorID: String
    ) {
        isSending = true
        lastError = nil
        service.complete(sessionID: session.sessionID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self else { return }
                self.isSending = false
                if case .failure(let error) = completion {
                    self.lastError = error
                }
            } receiveValue: { [weak self] completed in
                guard let self else { return }
                self.session = completed
                self.phase = .completed
                self.pendingEvidence = []
                self.persistence.clear(
                    actorID: actorID,
                    sessionID: session.sessionID
                )
                self.lastError = nil
            }
            .store(in: &cancellables)
    }

    private func shouldQueue(
        _ evidence: OnboardingGuideEvidence,
        for currentState: String
    ) -> Bool {
        if case .noteCreated = evidence {
            return currentState == State.elicitSignal
        }
        if case .libraryViewed = evidence {
            return currentState == State.libraryIntro
        }
        guard let expected = expectedState(for: evidence),
              let currentIndex = State.order.firstIndex(of: currentState),
              let expectedIndex = State.order.firstIndex(of: expected) else {
            return evidenceMatches(evidence, state: currentState)
        }
        return expectedIndex >= currentIndex
    }

    private func prunePastEvidence(currentState: String) {
        guard let currentIndex = State.order.firstIndex(of: currentState) else {
            return
        }
        pendingEvidence.removeAll { evidence in
            guard let expected = expectedState(for: evidence),
                  let expectedIndex = State.order.firstIndex(of: expected) else {
                return false
            }
            return expectedIndex < currentIndex
        }
        if let actorID, let session {
            persistPending(actorID: actorID, sessionID: session.sessionID)
        }
    }

    private func evidenceMatches(
        _ evidence: OnboardingGuideEvidence,
        state: String
    ) -> Bool {
        if case .noteCreated = evidence {
            return state == State.elicitSignal
        }
        return expectedState(for: evidence) == state
    }

    private func expectedState(
        for evidence: OnboardingGuideEvidence
    ) -> String? {
        switch evidence {
        case .noteCreated:
            return State.elicitSignal
        case .deepenChoice:
            return State.deepenSignal
        case .flowViewed:
            return State.curatorIntro
        case .flowCardSaved, .flowCardDismissed:
            return State.exploreCard
        case .sparkStarted:
            return State.sparkIntro
        case .sparkResultsViewed:
            return State.sparkResults
        case .sparkResultSaved:
            return State.saveMaterial
        case .mergeStarted:
            return State.mergeIntro
        case .mergeCommitted:
            return State.mergePreview
        case .libraryViewed:
            return State.libraryIntro
        }
    }

    private func responseInput(
        for evidence: OnboardingGuideEvidence
    ) -> OnboardingGuideInput {
        switch evidence {
        case .noteCreated(_, let content):
            return .text(content)
        case .deepenChoice(let id):
            return .choice(id)
        case .flowViewed:
            return .choice("activation:flow.viewed")
        case .flowCardSaved:
            return .choice("activation:explore.card_saved")
        case .flowCardDismissed:
            return .choice("activation:explore.card_dismissed")
        case .sparkStarted:
            return .choice("activation:spark.started")
        case .sparkResultsViewed:
            return .choice("activation:spark.results_viewed")
        case .sparkResultSaved:
            return .choice("activation:spark.result_saved")
        case .mergeStarted:
            return .choice("activation:merge.started")
        case .mergeCommitted:
            return .choice("activation:merge.committed")
        case .libraryViewed:
            return .choice("activation:library.viewed")
        }
    }

    private func persistPending(actorID: String, sessionID: String) {
        persistence.savePendingEvidence(
            pendingEvidence,
            actorID: actorID,
            sessionID: sessionID
        )
    }

    private func clearPersistence(for session: OnboardingGuideSession) {
        pendingEvidence = []
        if let actorID {
            persistence.clear(actorID: actorID, sessionID: session.sessionID)
        }
    }

    private func failLoad(_ error: OnboardingGuideError) {
        lastError = error
        phase = .unavailable
    }
}
