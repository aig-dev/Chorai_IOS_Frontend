import SwiftUI

// MARK: 高光效果扩展
extension View {
    func cardHighlightEffect() -> some View {
        overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ChoraiTheme.separator, lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
}

struct AccountDetailsView: View {
    @Environment(\.presentationMode) var presentationMode

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

                    Text("Account Details")
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
//                        Text("Basic")
//                            .font(.headline.weight(.semibold))
//                            .foregroundColor(ChoraiTheme.ink)
//
//                        // Basic Section
//                        VStack(alignment: .leading, spacing: 16) {
//
//                            // Username
//                            HStack {
//                                Text("Username:")
//                                    .font(.body.weight(.regular))
//                                    .foregroundColor(ChoraiTheme.secondaryInk)
//                                Spacer()
//                                TextField("Luffy", text: .constant("Luffy"))
//                                    .font(.body.weight(.medium))
//                                    .foregroundColor(ChoraiTheme.ink)
//                                    .multilineTextAlignment(.leading)
//                                    .textFieldStyle(PlainTextFieldStyle())
//                                    .padding(.horizontal, 12)
//                                    .padding(.vertical, 8)
//                                    .background(
//                                        RoundedRectangle(cornerRadius: 8)
//                                            .stroke(ChoraiTheme.separator, lineWidth: 1)
//                                    )
//                            }
//
//                            // Membership
//                            HStack {
//                                Text("Membership:")
//                                    .font(.body.weight(.regular))
//                                    .foregroundColor(ChoraiTheme.secondaryInk)
////                                Spacer()
//                                HStack(spacing: 8) {
//                                    Text("PRO Expired")
//                                        .font(.body.weight(.medium))
//                                        .foregroundColor(ChoraiTheme.ink)
//                                    Spacer()
//                                    Button("Renew") {
//                                        // 续费功能
//                                    }
//                                    .font(.subheadline.weight(.medium))
//                                    .foregroundColor(ChoraiTheme.accent)
//                                }
//                            }
//
//                            // Storage
//                            HStack(alignment: .center, spacing: 8) {
//                                Text("Storage:")
//                                    .font(.body.weight(.regular))
//                                    .foregroundColor(ChoraiTheme.secondaryInk)
//                                VStack(alignment: .center, spacing: 5){
//                                    // 进度条
//                                    GeometryReader { geometry in
//                                        ZStack(alignment: .leading) {
//                                            RoundedRectangle(cornerRadius: 4)
//                                                .fill(Color.gray.opacity(0.3))
//                                                .frame(height: 8)
//
//                                            RoundedRectangle(cornerRadius: 4)
//                                                .fill(ChoraiTheme.gold)
//                                                .frame(width: geometry.size.width * 0.1, height: 8) // 10% 使用量
//                                        }
//                                    }
//                                    .frame(height: 8)
//
//                                    Text("0.0M/500M")
//                                        .font(.subheadline.weight(.regular))
//                                        .foregroundColor(ChoraiTheme.ink)
//                                }
//
//                            }
//
//                            // PRO Expiration Notice
//                            VStack(alignment: .leading, spacing: 8) {
//                                Text("If PRO is not renewed 30 days after expiration, only the most recent 500MB of files will be retained.")
//                                    .font(.subheadline.weight(.regular))
//                                    .foregroundColor(ChoraiTheme.ink)
//                                    .multilineTextAlignment(.leading)
//
//                                Button("Learn More") {
//                                    // 了解更多功能
//                                }
//                                .font(.subheadline.weight(.medium))
//                                .foregroundColor(ChoraiTheme.accent)
//                            }
//
//                            // PRO Benefits
//                            Text("Renew PRO now to enjoy 20GB storage +original image uploads.")
//                                .font(.subheadline.weight(.regular))
//                                .foregroundColor(ChoraiTheme.ink)
//                                .multilineTextAlignment(.leading)
//                        }
//                        .padding(20)
//                        .background(
//                            RoundedRectangle(cornerRadius: 16)
//                                .fill(ChoraiTheme.surface)
//                                .cardHighlightEffect()
//                        )
                        Text("Account Security")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(ChoraiTheme.ink)
                        // Account Security Section
                        VStack(alignment: .leading, spacing: 16) {


                            // Mobile
                            HStack {
                                Text("Mobile")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                Spacer()
                                Text("133***7225")
                                    .font(.body.weight(.medium))
                                    .foregroundColor(ChoraiTheme.ink)
                                    .multilineTextAlignment(.center)
                                Spacer()
                                Button("Change") {
                                    // 更改手机号功能
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(ChoraiTheme.accent)
                            }

                            Divider()
                                .background(ChoraiTheme.surface)
                                .padding(.leading, 0)

                            // Email
                            HStack {
                                Text("Email")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                Spacer()
                                Text("Test@gmail.com")
                                    .font(.body.weight(.medium))
                                    .foregroundColor(ChoraiTheme.ink)
                                    .multilineTextAlignment(.center)
                                Spacer()
                                Button("Unbind") {
                                    // 解绑邮箱功能
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.red)
                            }

                            Divider()
                                .background(ChoraiTheme.surface)
                                .padding(.leading, 0)

                            // Password
                            HStack {
                                Text("Password")
                                    .font(.body.weight(.regular))
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                Spacer()
                                Text("..........")
                                    .font(.body.weight(.medium))
                                    .foregroundColor(ChoraiTheme.ink)
                                    .multilineTextAlignment(.center)
                                Spacer()
                                Button("Change") {
                                    // 更改密码功能
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(ChoraiTheme.accent)
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(ChoraiTheme.surface)
                                .cardHighlightEffect()
                        )

//                        Text("Data Sync")
//                            .font(.headline.weight(.semibold))
//                            .foregroundColor(ChoraiTheme.ink)
//                        // Data Sync Section
//                        VStack(alignment: .leading, spacing: 16) {
//
//                            // Import Data
//                            HStack {
//                                Text("Import Data")
//                                    .font(.body.weight(.regular))
//                                    .foregroundColor(ChoraiTheme.secondaryInk)
//                                Spacer()
//                                    .frame(width: 20)
//                                Button("Import") {
//                                    // 导入数据功能
//                                }
//                                .font(.subheadline.weight(.medium))
//                                .foregroundColor(ChoraiTheme.accent)
//                                Spacer()
//                            }
//
//                            Divider()
//                                .background(ChoraiTheme.surface)
//                                .padding(.leading, 0)
//
//                            // Export Data
//                            HStack {
//                                Text("Export Data")
//                                    .font(.body.weight(.regular))
//                                    .foregroundColor(ChoraiTheme.secondaryInk)
//                                Spacer()
//                                    .frame(width: 20)
//                                Button("Export As...") {
//                                    // 导出数据功能
//                                }
//                                .font(.subheadline.weight(.medium))
//                                .foregroundColor(ChoraiTheme.accent)
//                                Spacer()
//                            }
//
//                            Divider()
//                                .background(ChoraiTheme.surface)
//                                .padding(.leading, 0)
//
//                            // Label Rebuild
//                            HStack {
//                                Text("Label Rebuild")
//                                    .font(.body.weight(.regular))
//                                    .foregroundColor(ChoraiTheme.secondaryInk)
//                                Spacer()
//                                    .frame(width: 20)
//                                Button("Rebuild") {
//                                    // 标签重建功能
//                                }
//                                .font(.subheadline.weight(.medium))
//                                .foregroundColor(ChoraiTheme.accent)
//                                Spacer()
//                            }
//
//                            Divider()
//                                .background(ChoraiTheme.surface)
//                                .padding(.leading, 0)
//
//                            // Network Test
//                            HStack {
//                                Text("Network Test")
//                                    .font(.body.weight(.regular))
//                                    .foregroundColor(ChoraiTheme.secondaryInk)
//                                Spacer()
//                                    .frame(width: 20)
//                                Button("Test connectivity with Arcnote") {
//                                    // 网络测试功能
//                                }
//                                .font(.subheadline.weight(.medium))
//                                .foregroundColor(ChoraiTheme.accent)
//                                Spacer()
//                            }
//                        }
//                        .padding(20)
//                        .background(
//                            RoundedRectangle(cornerRadius: 16)
//                                .fill(ChoraiTheme.surface)
//                                .cardHighlightEffect()
//                        )

                        // 底部隐私声明
                        Text("We never sell your data or run ads. Your subscription powers our continued")
                            .font(.caption.weight(.regular))
                            .foregroundColor(ChoraiTheme.secondaryInk)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 20)
                            .padding(.bottom, 40)
                    }

                    .adaptiveContentGutter()
                }
            }
        }
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .navigationBarHidden(true)
    }
}

#Preview {
    AccountDetailsView()
}
