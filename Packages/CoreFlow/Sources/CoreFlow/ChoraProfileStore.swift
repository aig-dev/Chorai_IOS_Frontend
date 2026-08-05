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
    private let saveOperationStart: @MainActor @Sendable () async -> Void
    private var humanActorID: String?
    private var generation = UUID()
    private var growthTask: Task<Void, Never>?
    private var activeSaveID: UUID?
    private var activeSaveTask: Task<Void, Never>?

    public init(service: any CoreChoraProfileServing) {
        self.service = service
        saveOperationStart = {}
    }

    init(
        service: any CoreChoraProfileServing,
        saveOperationStart: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.service = service
        self.saveOperationStart = saveOperationStart
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

    public func retryGrowth() {
        guard let humanActorID,
              let agentActorID = identity?.agentActorID else {
            return
        }
        startGrowth(
            humanActorID: humanActorID,
            agentActorID: agentActorID,
            generation: generation
        )
    }

    public func save() {
        guard !isSaving,
              let identity,
              let requestedHuman = humanActorID else {
            return
        }
        let fields = changedFields
        guard !fields.isEmpty else { return }

        isSaving = true
        fieldErrors = [:]
        let snapshot = SaveSnapshot(
            fields: fields,
            requestedHuman: requestedHuman,
            expectedAgent: identity.agentActorID,
            generation: generation,
            saveID: UUID(),
            displayName: displayNameDraft,
            preferredAddress: preferredAddressDraft,
            avatar: avatarDraft
        )
        activeSaveID = snapshot.saveID
        let service = service
        let saveOperationStart = saveOperationStart
        let task = Task { @MainActor [
            weak self,
            service,
            saveOperationStart,
            snapshot
        ] in
            defer { self?.finishSave(saveID: snapshot.saveID) }
            await saveOperationStart()
            guard self?.isCurrentSave(snapshot) == true else { return }
            var mutationErrors: [
                ChoraProfileField: ChoraProfileError
            ] = [:]
            var uploadedAvatarURL: String?

            if snapshot.fields.contains(.displayName) {
                do {
                    try await service.updateDisplayName(
                        agentActorID: snapshot.expectedAgent,
                        displayName: snapshot.displayName
                    )
                } catch {
                    mutationErrors[.displayName] = Self.map(error)
                }
                guard self?.isCurrentSave(snapshot) == true else { return }
            }
            if snapshot.fields.contains(.preferredAddress) {
                do {
                    try await service.updatePreferredAddress(
                        humanActorID: snapshot.requestedHuman,
                        value: snapshot.preferredAddress
                    )
                } catch {
                    mutationErrors[.preferredAddress] = Self.map(error)
                }
                guard self?.isCurrentSave(snapshot) == true else { return }
            }
            if snapshot.fields.contains(.avatar), let avatar = snapshot.avatar {
                do {
                    uploadedAvatarURL = try await service.updateAvatar(
                        agentActorID: snapshot.expectedAgent,
                        avatar: avatar
                    )
                } catch {
                    mutationErrors[.avatar] = Self.map(error)
                }
                guard self?.isCurrentSave(snapshot) == true else { return }
            }

            guard self?.isCurrentSave(snapshot) == true else { return }
            do {
                let canonical = try await service.identity(
                    humanActorID: snapshot.requestedHuman
                )
                guard self?.isCurrentSave(snapshot) == true else { return }
                try Self.validateIdentity(
                    canonical,
                    requestedHuman: snapshot.requestedHuman,
                    expectedAgent: snapshot.expectedAgent
                )
                self?.publishCanonical(
                    canonical,
                    uploadedAvatarURL: uploadedAvatarURL,
                    mutationErrors: mutationErrors,
                    snapshot: snapshot
                )
            } catch {
                guard self?.isCurrentSave(snapshot) == true else { return }
                let reloadError = Self.map(error)
                for field in snapshot.fields
                where mutationErrors[field] == nil {
                    mutationErrors[field] = reloadError
                }
                self?.publishErrors(
                    mutationErrors,
                    snapshot: snapshot
                )
            }
        }
        activeSaveTask = task
    }

    private struct SaveSnapshot: Sendable {
        let fields: Set<ChoraProfileField>
        let requestedHuman: String
        let expectedAgent: String
        let generation: UUID
        let saveID: UUID
        let displayName: String
        let preferredAddress: String?
        let avatar: ChoraAvatarDraft?
    }

    private func publishCanonical(
        _ canonical: ChoraIdentity,
        uploadedAvatarURL: String?,
        mutationErrors: [ChoraProfileField: ChoraProfileError],
        snapshot: SaveSnapshot
    ) {
        var resolvedIdentity = canonical
        if snapshot.fields.contains(.avatar),
           mutationErrors[.avatar] == nil,
           let uploadedAvatarURL {
            resolvedIdentity = ChoraIdentity(
                humanActorID: canonical.humanActorID,
                agentActorID: canonical.agentActorID,
                displayName: canonical.displayName,
                avatarURL: uploadedAvatarURL,
                preferredAddress: canonical.preferredAddress
            )
        }
        identity = resolvedIdentity
        if snapshot.fields.contains(.displayName),
           displayNameDraft == snapshot.displayName,
           mutationErrors[.displayName] == nil {
            displayNameDraft = resolvedIdentity.displayName
        }
        if snapshot.fields.contains(.preferredAddress),
           preferredAddressDraft == snapshot.preferredAddress,
           mutationErrors[.preferredAddress] == nil {
            preferredAddressDraft = resolvedIdentity.preferredAddress
        }
        if snapshot.fields.contains(.avatar),
           avatarDraft == snapshot.avatar,
           mutationErrors[.avatar] == nil {
            avatarDraft = nil
        }
        publishErrors(mutationErrors, snapshot: snapshot)
    }

    private func publishErrors(
        _ errors: [ChoraProfileField: ChoraProfileError],
        snapshot: SaveSnapshot
    ) {
        fieldErrors = currentErrors(
            from: errors,
            displayName: snapshot.displayName,
            preferredAddress: snapshot.preferredAddress,
            avatar: snapshot.avatar
        )
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

    private func isCurrentSave(_ snapshot: SaveSnapshot) -> Bool {
        !Task.isCancelled &&
            activeSaveID == snapshot.saveID &&
            generation == snapshot.generation &&
            humanActorID == snapshot.requestedHuman &&
            identity?.agentActorID == snapshot.expectedAgent
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
