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
    private var activeSaveID: UUID?
    private var activeSaveTask: Task<Void, Never>?

    public init(service: any CoreChoraProfileServing) {
        self.service = service
    }

    deinit {
        growthTask?.cancel()
        activeSaveTask?.cancel()
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
        if activeSaveTask == nil {
            isSaving = false
        }
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
        let displayName = displayNameDraft
        let preferredAddress = preferredAddressDraft
        let avatar = avatarDraft
        let saveID = UUID()
        activeSaveID = saveID
        let task = Task { [weak self] in
            guard let self else { return }
            await performSave(
                fields: fields,
                requestedHuman: requestedHuman,
                expectedAgent: identity.agentActorID,
                generation: currentGeneration,
                saveID: saveID,
                displayName: displayName,
                preferredAddress: preferredAddress,
                avatar: avatar
            )
        }
        activeSaveTask = task
        await task.value
    }

    private func performSave(
        fields: Set<ChoraProfileField>,
        requestedHuman: String,
        expectedAgent: String,
        generation: UUID,
        saveID: UUID,
        displayName: String,
        preferredAddress: String?,
        avatar: ChoraAvatarDraft?
    ) async {
        defer { finishSave(saveID: saveID) }
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
            guard isCurrentSave(
                saveID: saveID,
                requestedHuman: requestedHuman,
                expectedAgent: expectedAgent,
                generation: generation
            ) else { return }
        }
        if fields.contains(.preferredAddress) {
            do {
                try await service.updatePreferredAddress(preferredAddress)
            } catch {
                mutationErrors[.preferredAddress] = Self.map(error)
            }
            guard isCurrentSave(
                saveID: saveID,
                requestedHuman: requestedHuman,
                expectedAgent: expectedAgent,
                generation: generation
            ) else { return }
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
            guard isCurrentSave(
                saveID: saveID,
                requestedHuman: requestedHuman,
                expectedAgent: expectedAgent,
                generation: generation
            ) else { return }
        }

        guard isCurrentSave(
            saveID: saveID,
            requestedHuman: requestedHuman,
            expectedAgent: expectedAgent,
            generation: generation
        ) else { return }

        do {
            let canonical = try await service.identity(
                humanActorID: requestedHuman
            )
            guard isCurrentSave(
                saveID: saveID,
                requestedHuman: requestedHuman,
                expectedAgent: expectedAgent,
                generation: generation
            ) else { return }
            try Self.validateIdentity(
                canonical,
                requestedHuman: requestedHuman,
                expectedAgent: expectedAgent
            )
            self.identity = canonical
            if fields.contains(.displayName),
               displayNameDraft == displayName,
               mutationErrors[.displayName] == nil {
                displayNameDraft = canonical.displayName
            }
            if fields.contains(.preferredAddress),
               preferredAddressDraft == preferredAddress,
               mutationErrors[.preferredAddress] == nil {
                preferredAddressDraft = canonical.preferredAddress
            }
            if fields.contains(.avatar),
               avatarDraft == avatar,
               mutationErrors[.avatar] == nil {
                avatarDraft = nil
            }
            fieldErrors = currentErrors(
                from: mutationErrors,
                displayName: displayName,
                preferredAddress: preferredAddress,
                avatar: avatar
            )
        } catch {
            let reloadError = Self.map(error)
            for field in fields where mutationErrors[field] == nil {
                mutationErrors[field] = reloadError
            }
            fieldErrors = currentErrors(
                from: mutationErrors,
                displayName: displayName,
                preferredAddress: preferredAddress,
                avatar: avatar
            )
        }
    }

    private func currentErrors(
        from errors: [ChoraProfileField: ChoraProfileError],
        displayName: String,
        preferredAddress: String?,
        avatar: ChoraAvatarDraft?
    ) -> [ChoraProfileField: ChoraProfileError] {
        errors.filter { field, _ in
            switch field {
            case .displayName:
                displayNameDraft == displayName
            case .preferredAddress:
                preferredAddressDraft == preferredAddress
            case .avatar:
                avatarDraft == avatar
            }
        }
    }

    private func isCurrentSave(
        saveID: UUID,
        requestedHuman: String,
        expectedAgent: String,
        generation: UUID
    ) -> Bool {
        !Task.isCancelled &&
            activeSaveID == saveID &&
            self.generation == generation &&
            humanActorID == requestedHuman &&
            identity?.agentActorID == expectedAgent
    }

    private func finishSave(saveID: UUID) {
        guard activeSaveID == saveID else { return }
        activeSaveID = nil
        activeSaveTask = nil
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
        let service = service
        growthTask = Task { [weak self, service] in
            do {
                let loaded = try await service.growth(agentActorID: agentActorID)
                guard let self,
                      !Task.isCancelled,
                      self.generation == generation,
                      self.humanActorID == humanActorID,
                      self.identity?.agentActorID == agentActorID else {
                    return
                }
                growth = loaded
                growthPhase = loaded == nil
                    ? .unavailable(.noSnapshot)
                    : .ready
            } catch {
                guard let self,
                      !Task.isCancelled,
                      self.generation == generation,
                      self.humanActorID == humanActorID,
                      self.identity?.agentActorID == agentActorID else {
                    return
                }
                growth = nil
                growthPhase = .unavailable(.requestFailed(Self.map(error)))
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
        activeSaveTask?.cancel()
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
