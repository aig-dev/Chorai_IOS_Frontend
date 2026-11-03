import SwiftUI

struct PreferencesView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var contentRecommendations = false
    @State private var smartTagging = true
    @State private var linkNotifications = true
    @State private var followNotifications = true
    @State private var mentionNotifications = true
    @State private var aiTaskNotifications = true
    @State private var appUpdatesNotifications = true

    var body: some View {
        ZStack {
            // 背景图片
            ChoraiBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部导航栏
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.medium))
                            .foregroundColor(ChoraiTheme.ink)
                    .frame(minWidth: 44, minHeight: 44)
                    }

                    Spacer()

                    Text("Preferences")
                        .font(.title2.weight(.bold))
                        .foregroundColor(ChoraiTheme.ink)

                    Spacer()

                    // 占位符保持对称
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.medium))
                        .foregroundColor(.clear)
                    .frame(minWidth: 44, minHeight: 44)
                }
                .adaptiveContentGutter()
                .padding(.top, 12)
                .padding(.bottom, 30)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Recommendation Settings")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ChoraiTheme.ink)

                        // Recommendation Settings Section
                        VStack(alignment: .leading, spacing: 0) {
                            // Content Recommendations
                            HStack {
                                Text("Content Recommendations")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                Toggle("", isOn: $contentRecommendations)
                                    .toggleStyle(SwitchToggleStyle(tint: ChoraiTheme.accent))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                            Divider()
                                .background(ChoraiTheme.surface)
                                .padding(.leading, 0)

                            // Content Type
                            HStack {
                                Text("Content Type")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("Top Content")
                                        .font(.body.weight(.regular))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                            Divider()
                                .background(ChoraiTheme.surface)
                                .padding(.leading, 0)

                            // Source
                            HStack {
                                Text("Source")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("All Sources")
                                        .font(.body.weight(.regular))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                            Divider()
                                .background(ChoraiTheme.surface)
                                .padding(.leading, 0)

                            // Frequency
                            HStack {
                                Text("Frequency")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("Daily")
                                        .font(.body.weight(.regular))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(ChoraiTheme.surface)
                                .cardHighlightEffect()
                        )

                        Text("AI Settings")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ChoraiTheme.ink)

                        // AI Settings Section
                        VStack(alignment: .leading, spacing: 0) {
                            // API Key Management
                            HStack {
                                Text("API Key Management")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                            Divider()
                                .background(ChoraiTheme.surface)
                                .padding(.leading, 0)

                            // Default AI Model
                            HStack {
                                Text("Default AI Model")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("Auto")
                                        .font(.body.weight(.regular))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                            Divider()
                                .background(ChoraiTheme.surface)
                                .padding(.leading, 0)

                            // Smart Tagging
                            HStack {
                                Text("Smart Tagging")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                Toggle("", isOn: $smartTagging)
                                    .toggleStyle(SwitchToggleStyle(tint: ChoraiTheme.accent))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                            Divider()
                                .background(ChoraiTheme.surface)
                                .padding(.leading, 0)

                            // AI Data & Privacy
                            HStack {
                                Text("AI Data & Privacy")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("View Settings")
                                        .font(.body.weight(.regular))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(ChoraiTheme.surface)
                                .cardHighlightEffect()
                        )

                        Text("Notification Management")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ChoraiTheme.ink)

                        // Notification Management Section
                        VStack(alignment: .leading, spacing: 0) {
                            // Link Notifications
                            HStack {
                                Text("Link Notifications")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                Toggle("", isOn: $linkNotifications)
                                    .toggleStyle(SwitchToggleStyle(tint: ChoraiTheme.accent))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                            Divider()
                                .background(ChoraiTheme.surface)
                                .padding(.leading, 0)

                            // Follow & Interaction Notifications
                            HStack {
                                Text("Follow & Interaction Notifications")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                Toggle("", isOn: $followNotifications)
                                    .toggleStyle(SwitchToggleStyle(tint: ChoraiTheme.accent))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                            Divider()
                                .background(ChoraiTheme.surface)
                                .padding(.leading, 0)

                            // Mention Notifications
                            HStack {
                                Text("Mention(@Mention) Notifications")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                Toggle("", isOn: $mentionNotifications)
                                    .toggleStyle(SwitchToggleStyle(tint: ChoraiTheme.accent))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                            Divider()
                                .background(ChoraiTheme.surface)
                                .padding(.leading, 0)

                            // AI Task Notifications
                            HStack {
                                Text("AI Task Notifications")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                Toggle("", isOn: $aiTaskNotifications)
                                    .toggleStyle(SwitchToggleStyle(tint: ChoraiTheme.accent))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                            Divider()
                                .background(ChoraiTheme.surface)
                                .padding(.leading, 0)

                            // App Updates & Announcements
                            HStack {
                                Text("App Updates & Announcements")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                Toggle("", isOn: $appUpdatesNotifications)
                                    .toggleStyle(SwitchToggleStyle(tint: ChoraiTheme.accent))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                            Divider()
                                .background(ChoraiTheme.surface)
                                .padding(.leading, 0)

                            // Global Quiet Hours
                            HStack {
                                Text("Global Quiet Hours")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("22:00-07:00")
                                        .font(.body.weight(.regular))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(ChoraiTheme.surface)
                                .cardHighlightEffect()
                        )
                    }
                    .adaptiveContentGutter()
                    .padding(.bottom, 50)
                }
            }
        }
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .navigationBarHidden(true)
    }
}

#Preview {
    PreferencesView()
}
