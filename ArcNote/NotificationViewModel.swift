import Foundation

/// Transport query retained here because the project file already groups this
/// source with notification API models. UI state lives in NotificationInboxStore.
struct GetNotificationsRequest: Codable {
    let page: Int
    let perPage: Int

    enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
    }
}
