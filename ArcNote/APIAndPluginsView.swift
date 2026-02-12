import SwiftUI

struct APIAndPluginsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var desktopWidget = true
    @State private var sendText = true
    @State private var kindleImport = true
    @State private var twitterIntegration = true
    @State private var linkedinIntegration = true
    @State private var calendarIntegration = true
    @State private var wereadImport = true
    @State private var browserExtension = true
    

    
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
                    
                    Text("API & Plugins")
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
                        Text("Your Personal Notes API")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        // Your Personal Notes API Section
                        VStack(alignment: .leading, spacing: 16) {
                            // API URL
                            HStack(spacing: 12) {
                                Text(AttributedString("https://arcnote.com/api..."))
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 30)
                                            .fill(Color.white.opacity(0.05))
                                    )
                                    .textSelection(.disabled)

                                
                                Button("Copy Link") {
                                    // 复制链接功能
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(.ultraThinMaterial.opacity(0.1))
                                        // 左上角高光
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                                .offset(x: 0, y: 0)
                                                .mask(
                                                    RoundedRectangle(cornerRadius: 20)
                                                        .fill(
                                                            RadialGradient(
                                                                colors: [Color.white, Color.clear],
                                                                center: .topLeading,
                                                                startRadius: 10,
                                                                endRadius: 35
                                                            )
                                                        )
                                                )
                                        )
                                        // 右下角高光
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                                .offset(x: 0, y: 0)
                                                .mask(
                                                    RoundedRectangle(cornerRadius: 20)
                                                        .fill(
                                                            RadialGradient(
                                                                colors: [Color.white, Color.clear],
                                                                center: .bottomTrailing,
                                                                startRadius: 10,
                                                                endRadius: 35
                                                            )
                                                        )
                                                )
                                        )
                                        // 上面边缘高光
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                .offset(x: 0, y: -1)
                                                .mask(
                                                    RoundedRectangle(cornerRadius: 20)
                                                        .fill(
                                                            LinearGradient(
                                                                colors: [Color.white, Color.clear],
                                                                startPoint: .top,
                                                                endPoint: UnitPoint(x: 0, y: 0.05)
                                                            )
                                                        )
                                                )
                                        )
                                        // 下面边缘高光
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                .offset(x: -1, y: 1)
                                                .mask(
                                                    RoundedRectangle(cornerRadius: 20)
                                                        .fill(
                                                            LinearGradient(
                                                                colors: [Color.white, Color.clear],
                                                                startPoint: .bottom,
                                                                endPoint: UnitPoint(x: 1, y: 0.05)
                                                            )
                                                        )
                                                )
                                        )
                                )
                                .fixedSize()
                                
                            }
                            
                            // PRO Member Notice
                            (Text("PRO Member Exclusive Feature. ")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.white) +
                            Text("Upgrade to PRO")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.orange)
                                .underline(color: .orange) +
                            Text(" to use.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.white))
                            .onTapGesture {
                                // 升级到PRO功能
                            }
                            
                            Text("Up to 100 notes per day via API.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.white)
                            
                            Button("Reset API Key") {
                                // 重置API密钥功能
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(red: 0.82, green: 0.40, blue: 0.15))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color(red: 0.93, green: 0.35, blue: 0.35).opacity(0.04))
                            )
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                                .cardHighlightEffect()
                        )
                        
                        Text("Plugin Management")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        // Plugin Management Section
                        VStack(alignment: .leading, spacing: 20) {
                            // Official Plugins
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Official Plugins")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                // Desktop Widget
                                PluginRow(
                                    iconName: "plugins_1",
                                    title: "Add Desktop Widget for Quick NOTES",
                                    description: "Quickly Add Desktop Widget forQuick Notes",
                                    isEnabled: $desktopWidget
                                )
                                
                                // Send Text
                                PluginRow(
                                    iconName: "plugins_2",
                                    title: "Send Selected Text from iOS to Arcnote",
                                    description: "Quickly save interesting content.",
                                    isEnabled: $sendText
                                )
                                
                                // Kindle Import
                                PluginRow(
                                    iconName: "plugins_3",
                                    title: "Import from Kindle to Arcnote",
                                    description: "Sync your reading notes.",
                                    isEnabled: $kindleImport
                                )
                                
                                // Twitter Integration
                                PluginRow(
                                    iconName: "plugins_4",
                                    title: "X(Twitter) Integration",
                                    description: "Share notes to X with oneclick.",
                                    isEnabled: $twitterIntegration
                                )
                                
                                // LinkedIn Integration
                                PluginRow(
                                    iconName: "plugins_5",
                                    title: "Linkedin Integration Share",
                                    description: "professional content toyour network.",
                                    isEnabled: $linkedinIntegration
                                )
                                
                                // Calendar Integration
                                PluginRow(
                                    iconName: "plugins_6",
                                    title: "Calendar/Task AppIntegration",
                                    description: "Associate notes with calendarevents and tasks",
                                    isEnabled: $calendarIntegration
                                )
                            }
                            
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                                .cardHighlightEffect()
                        )
                        
                        Text("Community Plugins")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        // Plugin Management Section
                        VStack(alignment: .leading, spacing: 20) {
                            
                            // Community Plugins
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Official Plugins")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                // WeRead Import
                                PluginRow(
                                    iconName: "plugins_7",
                                    title: "WeRead, Dedao, RSS Import",
                                    description: "Sync content from multiplechannels.",
                                    isEnabled: $wereadImport
                                )
                                
                                // Browser Extension
                                PluginRow(
                                    iconName: "plugins_8",
                                    title: "Browser Extension",
                                    description: "Save web content with oneclick.",
                                    isEnabled: $browserExtension
                                )
                            }
                            
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                                .cardHighlightEffect()
                        )
                        
                                                    // Browse More Plugins Button
                            Button("Browse More Plugins") {
                                // 浏览更多插件功能
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 30)
                                    .fill(.ultraThinMaterial.opacity(0.1))
                                    // 左上角高光
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 30)
                                            .stroke(Color.white, lineWidth: 2)
                                            .offset(x: 0, y: 0)
                                            .mask(
                                                RoundedRectangle(cornerRadius: 30)
                                                    .fill(
                                                        RadialGradient(
                                                            colors: [Color.white, Color.clear],
                                                            center: .topLeading,
                                                            startRadius: 10,
                                                            endRadius: 35
                                                        )
                                                    )
                                            )
                                    )
                                    // 右下角高光
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 30)
                                            .stroke(Color.white, lineWidth: 2)
                                            .offset(x: 0, y: 0)
                                            .mask(
                                                RoundedRectangle(cornerRadius: 30)
                                                    .fill(
                                                        RadialGradient(
                                                            colors: [Color.white, Color.clear],
                                                            center: .bottomTrailing,
                                                            startRadius: 10,
                                                            endRadius: 35
                                                        )
                                                    )
                                            )
                                    )
                                    // 上面边缘高光
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 30)
                                            .stroke(Color.white, lineWidth: 1)
                                            .offset(x: 0, y: -1)
                                            .mask(
                                                RoundedRectangle(cornerRadius: 30)
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [Color.white, Color.clear],
                                                            startPoint: .top,
                                                            endPoint: UnitPoint(x: 0, y: 0.05)
                                                        )
                                                    )
                                            )
                                    )
                                    // 下面边缘高光
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 30)
                                            .stroke(Color.white, lineWidth: 1)
                                            .offset(x: -1, y: 1)
                                            .mask(
                                                RoundedRectangle(cornerRadius: 30)
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [Color.white, Color.clear],
                                                            startPoint: .bottom,
                                                            endPoint: UnitPoint(x: 1, y: 0.05)
                                                        )
                                                    )
                                            )
                                    )
                            )
                        
                        Text("Developers")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        // Developers Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Have your own plugin? ")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white)
                                
                                Button("Submit it here") {
                                    // 提交插件功能
                                }
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.orange)
                                .overlay(
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundColor(.orange)
                                        .offset(y: 8)
                                )
                            }
                            
                            Text("Develop Your Own")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            
                            // API Example
                            VStack(alignment: .leading, spacing: 8) {
                                Text("post https://arcnote.com/api/v1/no")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white)
                                Text("content-type:application/json")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white)
                                Text("{")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white)
                                Text("  \"content\":\"hello, #arcnote\"")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white)
                                Text("}")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.3))
                            )
                            
                            Button("View API Documentation") {
                                // 查看API文档功能
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.orange)
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.orange)
                                    .offset(y: 8)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 50)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

struct PluginRow: View {
    let iconName: String
    let title: String
    let description: String
    @Binding var isEnabled: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                
                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Toggle("", isOn: $isEnabled)
                .toggleStyle(SwitchToggleStyle(tint: .purple))
                .fixedSize()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    APIAndPluginsView()
} 
