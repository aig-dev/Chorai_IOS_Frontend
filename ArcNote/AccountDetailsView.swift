import SwiftUI

// MARK: 高光效果扩展
extension View {
    func cardHighlightEffect() -> some View {
        self
            .overlay(cardTopLeftHighlight)
            .overlay(cardBottomRightHighlight)
            .overlay(cardTopEdgeHighlight)
            .overlay(cardBottomEdgeHighlight)
    }
    
    private var cardTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var cardBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var cardTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var cardBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: -1, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
}

struct AccountDetailsView: View {
    @Environment(\.presentationMode) var presentationMode
    
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
                    
                    Text("Account Details")
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
//                        Text("Basic")
//                            .font(.system(size: 18, weight: .semibold))
//                            .foregroundColor(.white)
//                        
//                        // Basic Section
//                        VStack(alignment: .leading, spacing: 16) {
//                            
//                            // Username
//                            HStack {
//                                Text("Username:")
//                                    .font(.system(size: 16, weight: .regular))
//                                    .foregroundColor(.gray)
//                                Spacer()
//                                TextField("Luffy", text: .constant("Luffy"))
//                                    .font(.system(size: 16, weight: .medium))
//                                    .foregroundColor(.white)
//                                    .multilineTextAlignment(.leading)
//                                    .textFieldStyle(PlainTextFieldStyle())
//                                    .padding(.horizontal, 12)
//                                    .padding(.vertical, 8)
//                                    .background(
//                                        RoundedRectangle(cornerRadius: 8)
//                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
//                                    )
//                            }
//                            
//                            // Membership
//                            HStack {
//                                Text("Membership:")
//                                    .font(.system(size: 16, weight: .regular))
//                                    .foregroundColor(.gray)
////                                Spacer()
//                                HStack(spacing: 8) {
//                                    Text("PRO Expired")
//                                        .font(.system(size: 16, weight: .medium))
//                                        .foregroundColor(.white)
//                                    Spacer()
//                                    Button("Renew") {
//                                        // 续费功能
//                                    }
//                                    .font(.system(size: 14, weight: .medium))
//                                    .foregroundColor(.purple)
//                                }
//                            }
//                            
//                            // Storage
//                            HStack(alignment: .center, spacing: 8) {
//                                Text("Storage:")
//                                    .font(.system(size: 16, weight: .regular))
//                                    .foregroundColor(.gray)
//                                VStack(alignment: .center, spacing: 5){
//                                    // 进度条
//                                    GeometryReader { geometry in
//                                        ZStack(alignment: .leading) {
//                                            RoundedRectangle(cornerRadius: 4)
//                                                .fill(Color.gray.opacity(0.3))
//                                                .frame(height: 8)
//                                            
//                                            RoundedRectangle(cornerRadius: 4)
//                                                .fill(Color.purple)
//                                                .frame(width: geometry.size.width * 0.1, height: 8) // 10% 使用量
//                                        }
//                                    }
//                                    .frame(height: 8)
//                                    
//                                    Text("0.0M/500M")
//                                        .font(.system(size: 14, weight: .regular))
//                                        .foregroundColor(.white)
//                                }
//                                
//                            }
//                            
//                            // PRO Expiration Notice
//                            VStack(alignment: .leading, spacing: 8) {
//                                Text("If PRO is not renewed 30 days after expiration, only the most recent 500MB of files will be retained.")
//                                    .font(.system(size: 14, weight: .regular))
//                                    .foregroundColor(.white)
//                                    .multilineTextAlignment(.leading)
//                                
//                                Button("Learn More") {
//                                    // 了解更多功能
//                                }
//                                .font(.system(size: 14, weight: .medium))
//                                .foregroundColor(.purple)
//                            }
//                            
//                            // PRO Benefits
//                            Text("Renew PRO now to enjoy 20GB storage +original image uploads.")
//                                .font(.system(size: 14, weight: .regular))
//                                .foregroundColor(.white)
//                                .multilineTextAlignment(.leading)
//                        }
//                        .padding(20)
//                        .background(
//                            RoundedRectangle(cornerRadius: 16)
//                                .fill(Color.white.opacity(0.1))
//                                .cardHighlightEffect()
//                        )
                        Text("Account Security")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        // Account Security Section
                        VStack(alignment: .leading, spacing: 16) {
                            
                            
                            // Mobile
                            HStack {
                                Text("Mobile")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("133***7225")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                Spacer()
                                Button("Change") {
                                    // 更改手机号功能
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.purple)
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 0)
                            
                            // Email
                            HStack {
                                Text("Email")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("Test@gmail.com")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                Spacer()
                                Button("Unbind") {
                                    // 解绑邮箱功能
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.red)
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.leading, 0)
                            
                            // Password
                            HStack {
                                Text("Password")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("..........")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                Spacer()
                                Button("Change") {
                                    // 更改密码功能
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.purple)
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                                .cardHighlightEffect()
                        )

//                        Text("Data Sync")
//                            .font(.system(size: 18, weight: .semibold))
//                            .foregroundColor(.white)
//                        // Data Sync Section
//                        VStack(alignment: .leading, spacing: 16) {
//                            
//                            // Import Data
//                            HStack {
//                                Text("Import Data")
//                                    .font(.system(size: 16, weight: .regular))
//                                    .foregroundColor(.gray)
//                                Spacer()
//                                    .frame(width: 20)
//                                Button("Import") {
//                                    // 导入数据功能
//                                }
//                                .font(.system(size: 14, weight: .medium))
//                                .foregroundColor(.purple)
//                                Spacer()
//                            }
//                            
//                            Divider()
//                                .background(Color.white.opacity(0.2))
//                                .padding(.leading, 0)
//                            
//                            // Export Data
//                            HStack {
//                                Text("Export Data")
//                                    .font(.system(size: 16, weight: .regular))
//                                    .foregroundColor(.gray)
//                                Spacer()
//                                    .frame(width: 20)
//                                Button("Export As...") {
//                                    // 导出数据功能
//                                }
//                                .font(.system(size: 14, weight: .medium))
//                                .foregroundColor(.purple)
//                                Spacer()
//                            }
//                            
//                            Divider()
//                                .background(Color.white.opacity(0.2))
//                                .padding(.leading, 0)
//                            
//                            // Label Rebuild
//                            HStack {
//                                Text("Label Rebuild")
//                                    .font(.system(size: 16, weight: .regular))
//                                    .foregroundColor(.gray)
//                                Spacer()
//                                    .frame(width: 20)
//                                Button("Rebuild") {
//                                    // 标签重建功能
//                                }
//                                .font(.system(size: 14, weight: .medium))
//                                .foregroundColor(.purple)
//                                Spacer()
//                            }
//                            
//                            Divider()
//                                .background(Color.white.opacity(0.2))
//                                .padding(.leading, 0)
//                            
//                            // Network Test
//                            HStack {
//                                Text("Network Test")
//                                    .font(.system(size: 16, weight: .regular))
//                                    .foregroundColor(.gray)
//                                Spacer()
//                                    .frame(width: 20)
//                                Button("Test connectivity with Arcnote") {
//                                    // 网络测试功能
//                                }
//                                .font(.system(size: 14, weight: .medium))
//                                .foregroundColor(.purple)
//                                Spacer()
//                            }
//                        }
//                        .padding(20)
//                        .background(
//                            RoundedRectangle(cornerRadius: 16)
//                                .fill(Color.white.opacity(0.1))
//                                .cardHighlightEffect()
//                        )
                        
                        // 底部隐私声明
                        Text("We never sell your data or run ads. Your subscription powers our continued")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 20)
                            .padding(.bottom, 40)
                    }
                    
                    .padding(.horizontal, 20)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    AccountDetailsView()
} 
