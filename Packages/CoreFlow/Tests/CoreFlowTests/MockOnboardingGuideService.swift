import Combine
@testable import CoreFlow

final class MockOnboardingGuideService: OnboardingGuideServing {
    var statusResults: [Result<OnboardingStatusSnapshot, OnboardingGuideError>] = []
    var startResults: [Result<OnboardingGuideSession, OnboardingGuideError>] = []
    var currentResults: [Result<OnboardingGuideSession, OnboardingGuideError>] = []
    var respondResults: [Result<OnboardingGuideSession, OnboardingGuideError>] = []
    var completeResults: [Result<OnboardingGuideSession, OnboardingGuideError>] = []
    var skipResults: [Result<OnboardingGuideSession, OnboardingGuideError>] = []

    private(set) var statusRequestCount = 0
    private(set) var startFlowVersions: [Int] = []
    private(set) var currentRequestCount = 0
    private(set) var responses: [(sessionID: String, input: OnboardingGuideInput)] = []
    private(set) var completedSessionIDs: [String] = []
    private(set) var skippedSessionIDs: [String] = []

    func status() -> AnyPublisher<OnboardingStatusSnapshot, OnboardingGuideError> {
        statusRequestCount += 1
        return pop(&statusResults).publisher.eraseToAnyPublisher()
    }

    func start(flowVersion: Int) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        startFlowVersions.append(flowVersion)
        return pop(&startResults).publisher.eraseToAnyPublisher()
    }

    func current() -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        currentRequestCount += 1
        return pop(&currentResults).publisher.eraseToAnyPublisher()
    }

    func respond(
        sessionID: String,
        input: OnboardingGuideInput
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        responses.append((sessionID, input))
        return pop(&respondResults).publisher.eraseToAnyPublisher()
    }

    func complete(
        sessionID: String
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        completedSessionIDs.append(sessionID)
        return pop(&completeResults).publisher.eraseToAnyPublisher()
    }

    func skip(
        sessionID: String
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        skippedSessionIDs.append(sessionID)
        return pop(&skipResults).publisher.eraseToAnyPublisher()
    }

    private func pop<T>(
        _ values: inout [Result<T, OnboardingGuideError>]
    ) -> Result<T, OnboardingGuideError> {
        values.isEmpty ? .failure(.unknown) : values.removeFirst()
    }
}

final class InMemoryOnboardingGuidePersistence: OnboardingGuidePersisting {
    private var pending: [String: [OnboardingGuideEvidence]] = [:]
    private var recorded: [String: OnboardingGuideEvidence] = [:]

    func pendingEvidence(actorID: String, sessionID: String) -> [OnboardingGuideEvidence] {
        pending[key(actorID, sessionID)] ?? []
    }

    func savePendingEvidence(
        _ evidence: [OnboardingGuideEvidence],
        actorID: String,
        sessionID: String
    ) {
        pending[key(actorID, sessionID)] = evidence
    }

    func recordedCardEvidence(
        actorID: String,
        sessionID: String
    ) -> OnboardingGuideEvidence? {
        recorded[key(actorID, sessionID)]
    }

    func saveRecordedCardEvidence(
        _ evidence: OnboardingGuideEvidence,
        actorID: String,
        sessionID: String
    ) {
        recorded[key(actorID, sessionID)] = evidence
    }

    func clear(actorID: String, sessionID: String) {
        pending[key(actorID, sessionID)] = nil
        recorded[key(actorID, sessionID)] = nil
    }

    private func key(_ actorID: String, _ sessionID: String) -> String {
        "\(actorID)#\(sessionID)"
    }
}

final class DeferredOnboardingGuideService: OnboardingGuideServing {
    let statusSnapshot: OnboardingStatusSnapshot
    let currentSession: OnboardingGuideSession
    let responseSubjects: [PassthroughSubject<OnboardingGuideSession, OnboardingGuideError>]
    private(set) var responses: [(String, OnboardingGuideInput)] = []

    init(
        status: OnboardingStatusSnapshot,
        current: OnboardingGuideSession,
        responseCount: Int
    ) {
        statusSnapshot = status
        currentSession = current
        responseSubjects = (0..<responseCount).map { _ in
            PassthroughSubject<OnboardingGuideSession, OnboardingGuideError>()
        }
    }

    func status() -> AnyPublisher<OnboardingStatusSnapshot, OnboardingGuideError> {
        Just(statusSnapshot)
            .setFailureType(to: OnboardingGuideError.self)
            .eraseToAnyPublisher()
    }

    func start(flowVersion: Int) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        Fail(error: .unknown).eraseToAnyPublisher()
    }

    func current() -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        Just(currentSession)
            .setFailureType(to: OnboardingGuideError.self)
            .eraseToAnyPublisher()
    }

    func respond(
        sessionID: String,
        input: OnboardingGuideInput
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        responses.append((sessionID, input))
        let index = responses.count - 1
        guard responseSubjects.indices.contains(index) else {
            return Fail(error: .unknown).eraseToAnyPublisher()
        }
        return responseSubjects[index].eraseToAnyPublisher()
    }

    func complete(
        sessionID: String
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        Fail(error: .unknown).eraseToAnyPublisher()
    }

    func skip(
        sessionID: String
    ) -> AnyPublisher<OnboardingGuideSession, OnboardingGuideError> {
        Fail(error: .unknown).eraseToAnyPublisher()
    }
}
