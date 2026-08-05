import Combine
import CoreFlow
import Foundation

struct NetworkChoraProfileService: CoreChoraProfileServing, @unchecked Sendable {
    private let network: NetworkManager

    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func identity(humanActorID: String) async throws -> ChoraIdentity {
        async let profileValue = firstValue(
            network.getChoraAgentProfile()
        )
        async let usersValue = firstValue(
            network.getChoraAgentUsers()
        )
        async let ownProfileValue = firstValue(
            network.getChoraOwnProfile()
        )

        do {
            let (profile, users, ownProfile) = try await (
                profileValue,
                usersValue,
                ownProfileValue
            )
            return try Self.mapIdentity(
                agentProfile: profile.data,
                agentUsers: users.data,
                ownProfile: ownProfile.data,
                expectedHumanActorID: humanActorID
            )
        } catch let error as ChoraProfileError {
            throw error
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func growth(agentActorID: String) async throws -> ChoraGrowthSnapshot? {
        do {
            let response = try await firstValue(
                network.getChoraGrowth(agentActorID: agentActorID)
            )
            return try Self.mapGrowth(
                response.growthView,
                expectedAgentActorID: agentActorID
            )
        } catch let error as ChoraProfileError {
            throw error
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func updateDisplayName(
        agentActorID: String,
        displayName: String
    ) async throws {
        do {
            let response = try await firstValue(
                network.updateChoraAgentDisplayName(
                    agentActorID: agentActorID,
                    displayName: displayName
                )
            )
            guard response.data.agentActorID == agentActorID,
                  response.data.actorID == agentActorID else {
                throw ChoraProfileError.agentActorChanged
            }
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func updatePreferredAddress(
        humanActorID: String,
        value: String?
    ) async throws {
        do {
            let response = try await firstValue(
                network.updateChoraPreferredAddress(
                    value ?? ""
                )
            )
            guard response.data.actorID == humanActorID else {
                throw ChoraProfileError.humanActorMismatch
            }
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    func updateAvatar(
        agentActorID: String,
        avatar: ChoraAvatarDraft
    ) async throws -> String {
        do {
            let response = try await firstValue(
                network.updateChoraAgentAvatar(
                    agentActorID: agentActorID,
                    data: avatar.data,
                    filename: avatar.filename,
                    mimeType: avatar.mimeType
                )
            )
            guard response.data.actorID == agentActorID else {
                throw ChoraProfileError.agentActorChanged
            }
            guard let avatarURL = Self.normalized(response.data.avatarURL) else {
                throw ChoraProfileError.requestFailed
            }
            return avatarURL
        } catch {
            throw Self.mapNetworkError(error)
        }
    }

    static func mapIdentity(
        agentProfile: ChoraAgentProfileResponse,
        agentUsers: ChoraAgentUsersResponse,
        ownProfile: ChoraOwnProfileResponse,
        expectedHumanActorID: String
    ) throws -> ChoraIdentity {
        let expectedHumanActorID = normalized(expectedHumanActorID)
        guard let expectedHumanActorID else {
            throw ChoraProfileError.invalidHumanActor
        }
        guard agentProfile.humanActorID == expectedHumanActorID,
              agentUsers.humanActorID == expectedHumanActorID,
              ownProfile.actorID == expectedHumanActorID else {
            throw ChoraProfileError.humanActorMismatch
        }

        let activeAgentActorID = agentProfile.activeAgentActorID
        guard !activeAgentActorID.isEmpty,
              let activeAgent = agentUsers.agentUsers.first(where: {
                  $0.agentActorID == activeAgentActorID
                      && $0.actorID == activeAgentActorID
              }) else {
            throw ChoraProfileError.missingAgentActor
        }
        guard activeAgentActorID != expectedHumanActorID else {
            throw ChoraProfileError.humanActorUsedAsAgent
        }

        return ChoraIdentity(
            humanActorID: expectedHumanActorID,
            agentActorID: activeAgentActorID,
            displayName: activeAgent.displayName,
            avatarURL: activeAgent.avatarURL,
            preferredAddress: ownProfile.preferredAddress
        )
    }

    static func mapGrowth(
        _ response: ChoraGrowthViewResponse,
        expectedAgentActorID: String
    ) throws -> ChoraGrowthSnapshot {
        guard response.actorID == expectedAgentActorID else {
            throw ChoraProfileError.agentActorChanged
        }
        guard let computedAt = ChoraContractDateParser.date(
            from: response.computedAt
        ) else {
            throw ChoraProfileError.requestFailed
        }
        let scores = response.dimensionScores
        return ChoraGrowthSnapshot(
            version: response.growthVersion,
            committedStage: ChoraGrowthStage(
                rawValue: response.committedStage
            ),
            dimensions: [
                .init(dimension: .curiosity, value: scores.curiosity),
                .init(dimension: .insight, value: scores.insight),
                .init(dimension: .creativity, value: scores.creativity),
                .init(dimension: .empathy, value: scores.empathy),
                .init(dimension: .judgment, value: scores.judgment),
                .init(dimension: .resonance, value: scores.resonance)
            ],
            computedAt: computedAt
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

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func mapNetworkError(_ error: Error) -> ChoraProfileError {
        if let error = error as? ChoraProfileError {
            return error
        }
        return .requestFailed
    }
}
