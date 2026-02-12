import SwiftUI

struct UpgradeProView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var invitationCode = ""
    @FocusState private var isTextFieldFocused: Bool
    
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
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Upgrade to Arcnote Pro")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // 占位，保持标题居中
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 40)
                
                // 主要内容
                VStack(spacing: 32) {
                    // 解锁标题
                    VStack(spacing: 16) {
                        Text("Unlock All Premium Features")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        // 大脑图标
                        Image("brain")
                            .resizable()
                            .frame(width: 70, height: 70)
                    }
                    
                    // 邀请码输入区域
                    VStack(spacing: 16) {
                        Text("Invitation Code")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        TextField("Please enter your invitation code", text: $invitationCode)
                            .textFieldStyle(PlainTextFieldStyle())
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 30)
                                    .fill(.ultraThinMaterial.opacity(0.3))
                                    .roundedButtonHighlightEffect(cornerRadius: 30)
                            )
                            .focused($isTextFieldFocused)
                        
                        Button(action: {
                            // 处理邀请码验证
                            if !invitationCode.isEmpty {
                                // 这里可以添加邀请码验证逻辑
                                print("验证邀请码: \(invitationCode)")
                            }
                        }) {
                            Text("LET'S GO")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color(red: 81/255, green: 1.0, blue: 200/255)) // 51FFC8
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 30)
                                                .fill(Color(red: 0.318, green: 1.0, blue: 0.784).opacity(0.08))
                                        )
                                )
                        }
                        .disabled(invitationCode.isEmpty)
                        .opacity(invitationCode.isEmpty ? 1 : 1.0)
                    }
                    .padding(.horizontal, 20)
                    
                    // Pro会员权益
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Pro Member Benefits")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            BenefitItem(text: "Includes all Basic features, plus:")
                            BenefitItem(text: "Unlimited Synapse Credits")
                            BenefitItem(text: "Cross-device Cloud Sync")
                            BenefitItem(text: "Unlock All Widget Styles")
                            BenefitItem(text: "Exclusive API & Plugin Access")
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                    
                    // 支付信息
                    Text("Payment will be charged to your App Store account upon confirmation of purchase. Subscriptions automatically renew unless auto-renew is turned off at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

// MARK: - 权益项组件
struct BenefitItem: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image("checkmark")
                .resizable()
                .frame(width: 20, height: 20)
            
            Text(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white)
            
            Spacer()
        }
    }
}

#Preview {
    UpgradeProView()
} 
