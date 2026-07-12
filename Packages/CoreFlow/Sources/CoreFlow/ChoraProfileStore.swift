import Combine
import Foundation

@MainActor
public final class ChoraProfileStore: ObservableObject {
    @Published public private(set) var identity: ChoraIdentity?
    @Published public private(set) var growth: ChoraGrowthSnapshot?
    @Published public private(set) var phase: ChoraProfilePhase = .idle
    @Published public private(set) var growthPhase: ChoraGrowthPhase = .idle
    @Published public private(set) var displayNameDraft = ""
    @Published public private(set) var preferredAddressDraft: String?
    @Published public private(set) var avatarDraft: ChoraAvatarDraft?
    @Published public private(set) var isSaving = false
    @Published public private(set) var fieldErrors: [ChoraProfileField: ChoraProfileError] = [:]

    public var changedFields: Set<ChoraProfileField> {
        guard let identity else { return [] }
        var fields: Set<ChoraProfileField> = []
        if displayNameDraft != identity.displayName {
            fields.insert(.displayName)
        }
        if preferredAddressDraft != identity.preferredAddress {
            fields.insert(.preferredAddress)
        }
        if avatarDraft != nil {
            fields.insert(.avatar)
        }
        return fields
    }

    private let service: any CoreChoraProfileServing
    private var humanActorID: String?
    private var generation = UUID()
    private var growthTask: Task<Void, Never>?

    public init(service: any CoreChoraProfileServing) {
        self.service = service
    }

    public func load(humanActorID rawHumanActorID: String) async {
        invalidateGeneration()
        humanActorID = nil
        identity = nil
        growth = nil
        displayNameDraft = ""
        preferredAddressDraft = nil
        avatarDraft = nil
        fieldErrors = [:]
        isSaving = false
        phase = .idle
        growthPhase = .idle
        let requestedHuman = rawHumanActorID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !requestedHuman.isEmpty else {
            humanActorID = nil
            phase = .failed(.invalidHumanActor)
            return
        }

        humanActorID = requestedHuman
        phase = .loading
        let currentGeneration = generation

        do {
            let loaded = try await service.identity(humanActorID: requestedHuman)
            guard generation == currentGeneration,
                  humanActorID == requestedHuman else {
                return
            }
            try Self.validateIdentity(
                loaded,
                requestedHuman: requestedHuman,
                expectedAgent: nil
            )
            publishIdentity(loaded, replacingDrafts: true)
            phase = .ready
            startGrowth(
                humanActorID: requestedHuman,
                agentActorID: loaded.agentActorID,
                generation: currentGeneration
            )
        } catch {
            guard generation == currentGeneration,
                  humanActorID == requestedHuman else {
                return
            }
            phase = .failed(Self.map(error))
        }
    }

    public func setDisplayNameDraft(_ value: String) {
        displayNameDraft = value
        fieldErrors[.displayName] = nil
    }

    public func setPreferredAddressDraft(_ value: String?) {
        preferredAddressDraft = value
        fieldErrors[.preferredAddress] = nil
    }

    public func setAvatarDraft(_ value: ChoraAvatarDraft?) {
        avatarDraft = value
        fieldErrors[.avatar] = nil
    }

    public func save() async {
        guard !isSaving,
              let identity,
              let requestedHuman = humanActorID else {
            return
        }
        let fields = changedFields
        guard !fields.isEmpty else { return }

        isSaving = true
        fieldErrors = [:]
        let currentGeneration = generation
        let expectedAgent = identity.agentActorID
        let displayName = displayNameDraft
        let preferredAddress = preferredAddressDraft
        let avatar = avatarDraft
        var mutationErrors: [ChoraProfileField: ChoraProfileError] = [:]

        if fields.contains(.displayName) {
            do {
                try await service.updateDisplayName(
                    agentActorID: expectedAgent,
                    displayName: displayName
                )
            } catch {
                mutationErrors[.displayName] = Self.map(error)
            }
        }
        if fields.contains(.preferredAddress) {
            do {
                try await service.updatePreferredAddress(preferredAddress)
            } catch {
                mutationErrors[.preferredAddress] = Self.map(error)
            }
        }
        if fields.contains(.avatar), let avatar {
            do {
                try await service.updateAvatar(
                    agentActorID: expectedAgent,
                    avatar: avatar
                )
            } catch {
                mutationErrors[.avatar] = Self.map(error)
            }
        }

        guard generation == currentGeneration,
              humanActorID == requestedHuman,
              self.identity?.agentActorID == expectedAgent else {
            return
        }

        do {
            let canonical = try await service.identity(
                humanActorID: requestedHuman
            )
            guard generation == currentGeneration,
                  humanActorID == requestedHuman,
                  self.identity?.agentActorID == expectedAgent else {
                return
            }
            try Self.validateIdentity(
                canonical,
                requestedHuman: requestedHuman,
                expectedAgent: expectedAgent
            )
            self.identity = canonical
            if fields.contains(.displayName), mutationErrors[.displayName] == nil {
                displayNameDraft = canonical.displayName
            }
            if fields.contains(.preferredAddress), mutationErrors[.preferredAddress] == nil {
                preferredAddressDraft = canonical.preferredAddress
            }
            if fields.contains(.avatar), mutationErrors[.avatar] == nil {
                avatarDraft = nil
            }
            fieldErrors = mutationErrors
        } catch {
            let reloadError = Self.map(error)
            for field in fields where mutationErrors[field] == nil {
                mutationErrors[field] = reloadError
            }
            fieldErrors = mutationErrors
        }
        isSaving = false
    }

    private func startGrowth(
        humanActorID: String,
        agentActorID: String,
        generation: UUID
    ) {
        growthTask?.cancel()
        growth = nil
        growthPhase = .loading
        growthTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await service.growth(agentActorID: agentActorID)
                guard self.generation == generation,
                      self.humanActorID == humanActorID,
                      self.identity?.agentActorID == agentActorID else {
                    return
                }
                growth = loaded
                growthPhase = loaded == nil ? .unavailable(.requestFailed) : .ready
            } catch {
                guard self.generation == generation,
                      self.humanActorID == humanActorID,
                      self.identity?.agentActorID == agentActorID else {
                    return
                }
                growth = nil
                growthPhase = .unavailable(Self.map(error))
            }
        }
    }

    private func publishIdentity(
        _ loaded: ChoraIdentity,
        replacingDrafts: Bool
    ) {
        identity = loaded
        guard replacingDrafts else { return }
        displayNameDraft = loaded.displayName
        preferredAddressDraft = loaded.preferredAddress
        avatarDraft = nil
    }

    private func invalidateGeneration() {
        generation = UUID()
        growthTask?.cancel()
    }

    private static func validateIdentity(
        _ identity: ChoraIdentity,
        requestedHuman: String,
        expectedAgent: String?
    ) throws {
        guard identity.humanActorID == requestedHuman else {
            throw ChoraProfileError.humanActorMismatch
        }
        let normalizedAgent = identity.agentActorID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedAgent.isEmpty else {
            throw ChoraProfileError.missingAgentActor
        }
        guard normalizedAgent != requestedHuman else {
            throw ChoraProfileError.humanActorUsedAsAgent
        }
        if let expectedAgent, identity.agentActorID != expectedAgent {
            throw ChoraProfileError.agentActorChanged
        }
    }

    private static func map(_ error: Error) -> ChoraProfileError {
        (error as? ChoraProfileError) ?? .requestFailed
    }
}
