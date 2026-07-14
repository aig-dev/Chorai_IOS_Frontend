import Combine
import Foundation

@MainActor
public final class PrivacySettingsStore: ObservableObject {
    @Published public private(set) var actorID: String?
    @Published public private(set) var settings: PrivacySettings?
    @Published public private(set) var phase: PrivacySettingsPhase = .idle
    @Published public private(set) var savingSetting: PrivacySetting?
    @Published public private(set) var failedUpdate: PrivacyUpdateIntent?
    @Published public private(set) var updateError: PrivacySettingsError?

    private let service: any CorePrivacySettingsServing
    private var generation = UUID()

    public init(service: any CorePrivacySettingsServing) {
        self.service = service
    }

    public func load(actorID rawActorID: String) async {
        generation = UUID()
        settings = nil
        savingSetting = nil
        failedUpdate = nil
        updateError = nil

        guard let actorID = Self.normalized(rawActorID) else {
            self.actorID = nil
            phase = .failed(.invalidActor)
            return
        }

        self.actorID = actorID
        phase = .loading
        let requestedGeneration = generation

        do {
            let value = try await service.privacySettings(actorID: actorID)
            guard isCurrent(actorID: actorID, generation: requestedGeneration) else {
                return
            }
            settings = value
            phase = .ready
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(actorID: actorID, generation: requestedGeneration) else {
                return
            }
            phase = .failed(Self.map(error))
        }
    }

    public func retryLoad() async {
        guard let actorID else {
            phase = .failed(.invalidActor)
            return
        }
        await load(actorID: actorID)
    }

    public func set(_ setting: PrivacySetting, enabled: Bool) async {
        guard phase == .ready,
              savingSetting == nil,
              let actorID,
              let previous = settings,
              previous.value(for: setting) != enabled else {
            return
        }

        let requestedGeneration = generation
        settings = previous.setting(setting, to: enabled)
        savingSetting = setting
        failedUpdate = nil
        updateError = nil

        do {
            let canonical = try await service.updatePrivacySetting(
                actorID: actorID,
                setting: setting,
                enabled: enabled
            )
            guard isCurrent(actorID: actorID, generation: requestedGeneration) else {
                return
            }
            settings = canonical
            savingSetting = nil
        } catch is CancellationError {
            guard isCurrent(actorID: actorID, generation: requestedGeneration) else {
                return
            }
            settings = previous
            savingSetting = nil
        } catch {
            guard isCurrent(actorID: actorID, generation: requestedGeneration) else {
                return
            }
            settings = previous
            savingSetting = nil
            failedUpdate = PrivacyUpdateIntent(setting: setting, enabled: enabled)
            updateError = Self.map(error)
        }
    }

    public func retryFailedUpdate() async {
        guard let failedUpdate else { return }
        await set(failedUpdate.setting, enabled: failedUpdate.enabled)
    }

    private func isCurrent(actorID: String, generation: UUID) -> Bool {
        self.actorID == actorID && self.generation == generation
    }

    private static func normalized(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func map(_ error: Error) -> PrivacySettingsError {
        if let error = error as? PrivacySettingsError { return error }
        return .requestFailed(message: nil)
    }
}
