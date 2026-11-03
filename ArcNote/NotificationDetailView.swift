import CoreFlow
import SwiftUI

struct NotificationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let notification: CommunityNotification

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bell")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(ChoraiTheme.ink)
                        .frame(width: 48, height: 48)
                        .background(ChoraiTheme.raisedSurface, in: Circle())
                    VStack(alignment: .leading, spacing: 8) {
                        Text(notification.kind == .system ? "System" : "Notification")
                            .font(.body.weight(.semibold))
                        Text(relativeTime(notification.createdAt))
                            .font(.subheadline)
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                    }
                    Spacer()
                }
                Text(notification.displayText)
                    .font(.body)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .adaptiveContentGutter()
            .padding(.vertical, 24)
        }
        .choraiPageBackground()
        .accessibilityIdentifier("notification.detail.loaded")
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .navigationTitle("Notification")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
