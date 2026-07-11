public protocol CoreNotificationServing: Sendable {
    func notifications(page: Int, perPage: Int) async throws -> NotificationPage
    func markRead(notificationID: String) async throws
}
