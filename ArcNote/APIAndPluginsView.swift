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

                    Text("API & Plugins")
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
                        Text("Your Personal Notes API")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ChoraiTheme.ink)

                        // Your Personal Notes API Section
                        VStack(alignment: .leading, spacing: 16) {
                            // API URL
                            HStack(spacing: 12) {
                                Text(AttributedString("https://arcnote.com/api..."))
                                    .font(.subheadline.weight(.regular))
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 30)
                                            .fill(ChoraiTheme.surface)
                                    )
                                    .textSelection(.disabled)


                                Button("Copy Link") {
                                    // 复制链接功能
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(ChoraiTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(ChoraiTheme.surface)
                                        // 左上角高光
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(ChoraiTheme.separator, lineWidth: 1)
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
                                                .stroke(ChoraiTheme.separator, lineWidth: 1)
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
                                                .stroke(ChoraiTheme.separator, lineWidth: 1)
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
                                                .stroke(ChoraiTheme.separator, lineWidth: 1)
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
                                .font(.subheadline.weight(.regular))
                                .foregroundColor(ChoraiTheme.ink) +
                            Text("Upgrade to PRO")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.orange)
                                .underline(color: .orange) +
                            Text(" to use.")
                                .font(.subheadline.weight(.regular))
                                .foregroundColor(ChoraiTheme.ink))
                            .onTapGesture {
                                // 升级到PRO功能
                            }

                            Text("Up to 100 notes per day via API.")
                                .font(.subheadline.weight(.regular))
                                .foregroundColor(ChoraiTheme.ink)

                            Button("Reset API Key") {
                                // 重置API密钥功能
                            }
                            .font(.body.weight(.medium))
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
                                .fill(ChoraiTheme.surface)
                                .cardHighlightEffect()
                        )

                        Text("Plugin Management")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ChoraiTheme.ink)

                        // Plugin Management Section
                        VStack(alignment: .leading, spacing: 20) {
                            // Official Plugins
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Official Plugins")
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(ChoraiTheme.ink)

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
                                .fill(ChoraiTheme.surface)
                                .cardHighlightEffect()
                        )

                        Text("Community Plugins")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ChoraiTheme.ink)

                        // Plugin Management Section
                        VStack(alignment: .leading, spacing: 20) {

                            // Community Plugins
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Official Plugins")
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(ChoraiTheme.ink)

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
                                .fill(ChoraiTheme.surface)
                                .cardHighlightEffect()
                        )

                                                    // Browse More Plugins Button
                            Button("Browse More Plugins") {
                                // 浏览更多插件功能
                            }
                            .font(.body.weight(.medium))
                            .foregroundColor(ChoraiTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 30)
                                    .fill(ChoraiTheme.surface)
                                    // 左上角高光
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 30)
                                            .stroke(ChoraiTheme.separator, lineWidth: 1)
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
                                            .stroke(ChoraiTheme.separator, lineWidth: 1)
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
                                            .stroke(ChoraiTheme.separator, lineWidth: 1)
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
                                            .stroke(ChoraiTheme.separator, lineWidth: 1)
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
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ChoraiTheme.ink)

                        // Developers Section
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Have your own plugin? ")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)

                                Button("Submit it here") {
                                    // 提交插件功能
                                }
                                .font(.body.weight(.medium))
                                .foregroundColor(.orange)
                                .overlay(
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundColor(.orange)
                                        .offset(y: 8)
                                )
                            }

                            Text("Develop Your Own")
                                .font(.body.weight(.semibold))
                                .foregroundColor(ChoraiTheme.ink)

                            // API Example
                            VStack(alignment: .leading, spacing: 8) {
                                Text("post https://arcnote.com/api/v1/no")
                                    .font(.caption.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Text("content-type:application/json")
                                    .font(.caption.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Text("{")
                                    .font(.caption.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Text("  \"content\":\"hello, #arcnote\"")
                                    .font(.caption.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                                Text("}")
                                    .font(.caption.weight(.regular))
                                    .foregroundColor(ChoraiTheme.ink)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(ChoraiTheme.raisedSurface)
                            )

                            Button("View API Documentation") {
                                // 查看API文档功能
                            }
                            .font(.body.weight(.medium))
                            .foregroundColor(.orange)
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.orange)
                                    .offset(y: 8)
                            )
                        }
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
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(ChoraiTheme.ink)
                    .multilineTextAlignment(.leading)

                Text(description)
                    .font(.caption.weight(.regular))
                    .foregroundColor(ChoraiTheme.secondaryInk)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $isEnabled)
                .toggleStyle(SwitchToggleStyle(tint: ChoraiTheme.accent))
                .fixedSize()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    APIAndPluginsView()
}
