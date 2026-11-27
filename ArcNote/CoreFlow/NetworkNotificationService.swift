import Combine
import CoreFlow
import Foundation

struct NotificationListItemResponse: Codable {
    let notificationID: String
    let sourceType: String
    let payloadRef: String
    let isRead: Bool
    let createdAt: String
    let displayText: String?
    let sourceActor: NotificationSourceActorResponse?
    let target: NotificationTargetResponse?

    enum CodingKeys: String, CodingKey {
        case notificationID = "notification_id"
        case sourceType = "source_type"
        case payloadRef = "payload_ref"
        case isRead = "is_read"
        case createdAt = "created_at"
        case displayText = "display_text"
        case sourceActor = "source_actor"
        case target
    }
}

struct NotificationSourceActorResponse: Codable {
    let actorID: String
    let username: String
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case actorID = "actor_id"
        case username
        case avatarURL = "avatar_url"
    }
}

struct NotificationTargetResponse: Codable {
    let type: String
    let id: String
}

struct NotificationInboxResponse: Codable {
    let success: Bool
    let message: String?
    let data: [NotificationListItemResponse]
    let meta: PaginationMeta
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case data
        case meta
        case unreadCount = "unread_count"
    }
}

struct NetworkNotificationService: CoreNotificationServing, Sendable {
    private let network: NetworkManager

    @MainActor
    init(network: NetworkManager = .shared) {
        self.network = network
    }

    func notifications(page: Int, perPage: Int) async throws -> NotificationPage {
        let response = try await firstValue(
            network.getNotificationInbox(
                GetNotificationsRequest(page: page, perPage: perPage),
                presentsError: false
            )
        )
        guard response.success else {
            throw NotificationInboxError.transport(
                code: "notification_list_rejected"
            )
        }
        return try Self.map(response: response)
    }

    func markRead(notificationID: String) async throws {
        let response = try await firstValue(
            network.markNotificationRead(
                notificationId: notificationID,
                presentsError: false
            )
        )
        guard response.success else {
            throw NotificationInboxError.transport(
                code: "notification_mark_read_rejected"
            )
        }
    }

    static func map(response: NotificationInboxResponse) throws -> NotificationPage {
        let items = try response.data.map { item in
            let kind = mapKind(item.sourceType)
            let displayText = firstNonblank(
                item.displayText,
                item.payloadRef,
                "New notification"
            )
            let sourceActor = mapSourceActor(item.sourceActor)
            let target = mapTarget(item.target, kind: kind)
            guard let createdAt = parseDate(item.createdAt) else {
                throw NotificationInboxError.contract(
                    code: "invalid_created_at"
                )
            }
            return CommunityNotification(
                id: item.notificationID,
                kind: kind,
                displayText: displayText,
                sourceActor: sourceActor,
                target: target,
                isRead: item.isRead,
                createdAt: createdAt
            )
        }
        return NotificationPage(
            items: items,
            page: response.meta.page,
            perPage: response.meta.perPage,
            total: response.meta.total,
            unreadCount: response.unreadCount
        )
    }

    @MainActor
    private func firstValue<T: Sendable>(
        _ publisher: @autoclosure @MainActor @Sendable () -> AnyPublisher<T, NetworkError>
    ) async throws -> T {
        do {
            guard let value = try await NetworkManager.firstValue(publisher()) else {
                throw NotificationInboxError.transport(code: "empty_response")
            }
            return value
        } catch let error as NotificationInboxError {
            throw error
        } catch let error as NetworkError {
            throw Self.mapNetworkError(error)
        } catch {
            throw NotificationInboxError.transport(code: "unknown")
        }
    }

    private static func mapKind(_ raw: String) -> CommunityNotificationKind {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "follow": .follow
        case "like": .like
        case "comment": .comment
        case "system": .system
        default: .legacy
        }
    }

    private static func mapSourceActor(
        _ response: NotificationSourceActorResponse?
    ) -> NotificationSourceActor? {
        guard let response,
              let actorID = normalized(response.actorID),
              let username = normalized(response.username) else {
            return nil
        }
        return NotificationSourceActor(
            actorID: actorID,
            username: username,
            avatarURL: normalized(response.avatarURL)
        )
    }

    private static func mapTarget(
        _ response: NotificationTargetResponse?,
        kind: CommunityNotificationKind
    ) -> CommunityNotificationTarget {
        guard kind.category == .activity,
              let response,
              let id = normalized(response.id) else {
            return .legacy
        }
        switch response.type.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() {
        case "ACTOR": return .actor(id)
        case "ASSET": return .asset(id)
        default: return .legacy
        }
    }

    private static func firstNonblank(
        _ values: String?...
    ) -> String {
        for value in values {
            if let normalized = normalized(value) { return normalized }
        }
        return "New notification"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func parseDate(_ raw: String) -> Date? {
        CardTimestamp.parse(raw)
    }

    private static func mapNetworkError(
        _ error: NetworkError
    ) -> NotificationInboxError {
        switch error {
        case .unauthorized:
            return .unauthorized
        case .forbidden:
            return .forbidden
        case .notFound:
            return .notFound
        case .api(let statusCode, let code, _, _):
            switch statusCode {
            case 401: return .unauthorized
            case 403: return .forbidden
            case 404: return .notFound
            default:
                return .transport(code: code ?? "api_\(statusCode)")
            }
        case .invalidURL:
            return .transport(code: "invalid_url")
        case .noData:
            return .transport(code: "no_data")
        case .decodingError:
            return .contract(code: "decoding")
        case .encodingError:
            return .transport(code: "encoding")
        case .serverError(let statusCode, _):
            return .transport(code: "server_\(statusCode)")
        case .networkError:
            return .transport(code: "network")
        case .timeout:
            return .transport(code: "timeout")
        case .unknown:
            return .transport(code: "unknown")
        }
    }
}
