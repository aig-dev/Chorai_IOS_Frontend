import CoreFlow
import SwiftUI

struct NotificationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let notification: CommunityNotification

    var body: some View {
        ZStack {
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("Notification")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 24, height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle().fill(Color.gray.opacity(0.3))
                                Image(systemName: "bell")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 48, height: 48)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(notification.kind == .system ? "System" : "Notification")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(relativeTime(notification.createdAt))
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            Spacer()
                        }

                        Text(notification.displayText)
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.9))
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
        }
        .accessibilityIdentifier("notification.detail.loaded")
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
