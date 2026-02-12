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
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部导航栏
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Preferences")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // 占位符保持对称
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 30)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Recommendation Settings")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        // Recommendation Settings Section
                        VStack(alignment: .leading, spacing: 0) {
                            // Content Recommendations
                            HStack {
                                Text("Content Recommendations")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                Toggle("", isOn: $contentRecommendations)
                                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 0)
                            
                            // Content Type
                            HStack {
                                Text("Content Type")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("Top Content")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.gray)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 0)
                            
                            // Source
                            HStack {
                                Text("Source")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("All Sources")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.gray)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 0)
                            
                            // Frequency
                            HStack {
                                Text("Frequency")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("Daily")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.gray)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                                .cardHighlightEffect()
                        )
                        
                        Text("AI Settings")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        // AI Settings Section
                        VStack(alignment: .leading, spacing: 0) {
                            // API Key Management
                            HStack {
                                Text("API Key Management")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 0)
                            
                            // Default AI Model
                            HStack {
                                Text("Default AI Model")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("Auto")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.gray)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 0)
                            
                            // Smart Tagging
                            HStack {
                                Text("Smart Tagging")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                Toggle("", isOn: $smartTagging)
                                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 0)
                            
                            // AI Data & Privacy
                            HStack {
                                Text("AI Data & Privacy")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("View Settings")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.gray)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                                .cardHighlightEffect()
                        )
                        
                        Text("Notification Management")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        // Notification Management Section
                        VStack(alignment: .leading, spacing: 0) {
                            // Link Notifications
                            HStack {
                                Text("Link Notifications")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                Toggle("", isOn: $linkNotifications)
                                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 0)
                            
                            // Follow & Interaction Notifications
                            HStack {
                                Text("Follow & Interaction Notifications")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                Toggle("", isOn: $followNotifications)
                                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 0)
                            
                            // Mention Notifications
                            HStack {
                                Text("Mention(@Mention) Notifications")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                Toggle("", isOn: $mentionNotifications)
                                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 0)
                            
                            // AI Task Notifications
                            HStack {
                                Text("AI Task Notifications")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                Toggle("", isOn: $aiTaskNotifications)
                                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 0)
                            
                            // App Updates & Announcements
                            HStack {
                                Text("App Updates & Announcements")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                Toggle("", isOn: $appUpdatesNotifications)
                                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 0)
                            
                            // Global Quiet Hours
                            HStack {
                                Text("Global Quiet Hours")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                Spacer()
                                HStack(spacing: 8) {
                                    Text("22:00-07:00")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.gray)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                                .cardHighlightEffect()
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 50)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    PreferencesView()
} 
