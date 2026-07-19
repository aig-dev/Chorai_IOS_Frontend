import SwiftUI
import UIKit
import Combine

struct EditProfileView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject private var userProfileManager = UserProfileManager.shared
    @State private var name = ""
    @State private var bio = ""
    @State private var location = ""
    @State private var birthday = ""
    @State private var selectedImage: UIImage? = nil
    @State private var showImagePicker = false
    @State private var isSaving = false
    @State private var cancellables = Set<AnyCancellable>()
    #if DEBUG
    @State private var saveStatus = "idle"
    @State private var avatarUploadStatus = "idle"
    @State private var avatarUploadError = ""
    #endif
    
    var body: some View {
        ZStack {
            // 头部叠加背景图
            // VStack(spacing: 0) {
            //     Image("user_bg")
            //         .resizable()
            //         .aspectRatio(contentMode: .fill)
            //         .frame(height: 280)
            //         .clipped()
                
            //     Spacer()
            // }
            // .ignoresSafeArea(.all, edges: .top)
            
            VStack(spacing: 0) {
                // 顶部导航栏
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Edit Profile")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("Save")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            saveUserProfile()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Save")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("edit-profile.save")
                        .accessibilityAction {
                            saveUserProfile()
                        }
                }
                .adaptiveContentGutter()
                .padding(.bottom, 20)
                .padding(.top, 10)
                
                // 主要内容
                VStack(spacing: 0) {
                    // 顶部间距，为头像留出空间
                    Spacer().frame(height: 30)
                    
                    // 编辑资料卡片 全屏宽度
                    ZStack(alignment: .topLeading) {
                        // 主卡片内容
                        VStack(spacing: 0) {
                            // 头像占位空间
                            HStack {
                                Spacer().frame(width: 60, height: 15) // 头像占位空间
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 15)
                        
                            // 编辑表单区域
                            VStack(alignment: .leading, spacing: 20) {
                                // My Name
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("My Name")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                                                            TextField("Enter your name", text: $name)
                                            .font(.system(size: 18, weight: .regular))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 20)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.white.opacity(0.1))
                                                    .cardHighlightEffect()
                                            )
                                            .accessibilityIdentifier("edit-profile.name")
                                }
                                
                                // Bio
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Bio")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    ZStack(alignment: .bottomTrailing) {
                                        TextEditor(text: $bio)
                                            .font(.system(size: 18, weight: .regular))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.white.opacity(0.1))
                                                    .cardHighlightEffect()
                                            )
                                            .frame(minHeight: 60, maxHeight: 120)
                                            .scrollContentBackground(.hidden)
                                            .accessibilityIdentifier("edit-profile.bio")
                                        
                                        Text("\(bio.count)/100")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(.gray)
                                            .padding(.trailing, 16)
                                            .padding(.bottom, 8)
                                    }
                                }
                                
                                // Location
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Location")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    TextField("Enter your location", text: $location)
                                        .font(.system(size: 18, weight: .regular))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 20)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.1))
                                                .cardHighlightEffect()
                                        )
                                        .accessibilityIdentifier("edit-profile.location")
                                }
                                
                                // Birthday
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Birthday")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    TextField("Add your birthday", text: $birthday)
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 20)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.1))
                                                .cardHighlightEffect()
                                        )
                                        .accessibilityIdentifier("edit-profile.birthday")
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 15)
                            .padding(.bottom, 20)
                            
                            Spacer()
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .background(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                                .cornerRadius(16)
                        )
                        
                        // 头像 骑在边框线上
                        HStack {
                            Spacer()
                            
                            Button(action: {
                                showImagePicker = true
                            }) {
                            ZStack {
                                    // 头像图片 优先显示选择的本地图片
                                    Group {
                                        if let selectedImage = selectedImage {
                                            Image(uiImage: selectedImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 60, height: 60)
                                                .clipShape(Circle())
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.white, lineWidth: 3)
                                                )
                                        } else {
                                AsyncImage(url: URL(string: userProfileManager.userProfile?.avatar ?? "")) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                                    .frame(width: 60, height: 60)
                                                    .clipShape(Circle())
                                                    .overlay(
                                                        Circle()
                                                            .stroke(Color.white, lineWidth: 3)
                                                    )
                                } placeholder: {
                                    Image("avatar")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 3)
                                )
                                            }
                                        }
                                    }
                                
                                // 相机图标
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Image(systemName: "camera")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                            .frame(width: 24, height: 24)
                                            .background(
                                                Circle()
                                                    .fill(Color.black.opacity(0.5))
                                            )
                                    }
                                }
                                .frame(width: 60, height: 60)
                                }
                            }
                            .offset(y: -30) // 向上偏移30，使头像中心在卡片上边框
                            .accessibilityIdentifier("edit-profile.avatar")
                            
                            Spacer()
                        }
                        .padding(.leading, 20)
                        .padding(.trailing, 20)
                    }
                }
                .adaptiveContentGutter()
                .padding(.top, 30)
            }
        }
        .background(
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
        .navigationBarHidden(true)
        .overlay(alignment: .topLeading) {
            VStack(spacing: 1) {
                Text("Edit profile loaded")
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("screen.edit-profile.loaded")

                if let profile = userProfileManager.userProfile {
                    Text(profile.id)
                        .font(.system(size: 1))
                        .foregroundColor(.white.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("edit-profile.profile-id")
                }

                #if DEBUG
                Text(saveStatus)
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("edit-profile.save-status")

                Text(avatarUploadStatus)
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("edit-profile.avatar-upload-status")

                Text(userProfileManager.userProfile?.avatar ?? "")
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("edit-profile.avatar-url")

                Text(avatarUploadError)
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("edit-profile.avatar-upload-error")

                Button(action: {
                    uploadAvatar(image: makeAvatarSmokeImage())
                }) {
                    Text("Avatar smoke upload")
                        .font(.system(size: 1))
                        .foregroundColor(.white.opacity(0.01))
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("edit-profile.avatar-smoke-upload")
                #endif
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .onAppear {
            loadUserProfile()
        }
        .onChange(of: userProfileManager.userProfile) { profile in
            if let profile = profile {
                name = profile.username
                bio = profile.bio ?? ""
                location = profile.location ?? ""
                birthday = profile.birthday ?? ""
            }
        }
        .onChange(of: selectedImage) { image in
            if let image = image {
                uploadAvatar(image: image)
            }
        }
    }
    
    // MARK: 加载用户资料
    private func loadUserProfile() {
        userProfileManager.fetchCurrentUserProfile()
        
        // 如果已经有用户资料，直接填充表单
        if let profile = userProfileManager.userProfile {
            name = profile.username
            bio = profile.bio ?? ""
            location = profile.location ?? ""
            birthday = profile.birthday ?? ""
        }
    }
    
    // MARK: 上传头像
    private func uploadAvatar(image: UIImage) {
        guard let userId = userProfileManager.userProfile?.id else {
            print("没有用户ID")
            return
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return
        }
        
        print("开始上传头像，userId: \(userId)")
        #if DEBUG
        avatarUploadStatus = "uploading"
        avatarUploadError = ""
        #endif
        
        NetworkManager.shared.uploadAvatar(imageData: imageData)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("头像上传失败: \(error.localizedDescription)")
                        #if DEBUG
                        self.avatarUploadStatus = "failure"
                        self.avatarUploadError = error.localizedDescription
                        #endif
                    } else {
                        print("头像上传完成")
                    }
                },
                receiveValue: { response in
                    print("头像上传成功")
                    self.userProfileManager.userProfile = response.data
                    #if DEBUG
                    self.avatarUploadStatus = "success"
                    self.avatarUploadError = ""
                    #endif
                }
            )
            .store(in: &cancellables)
    }

    #if DEBUG
    private func makeAvatarSmokeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96))
        return renderer.image { context in
            UIColor(red: 0.10, green: 0.42, blue: 0.86, alpha: 1).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            UIColor(red: 0.93, green: 0.86, blue: 0.28, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 24, y: 24, width: 48, height: 48))
        }
    }
    #endif
    
    // MARK: 保存用户资料
    private func saveUserProfile() {
        guard !isSaving else {
            return
        }
        isSaving = true
        #if DEBUG
        saveStatus = "attempted"
        #endif
        userProfileManager.updateUserProfile(
            username: name,
            bio: bio,
            location: location,
            birthday: birthday
        ) { result in
            switch result {
            case .success:
                print("用户资料保存成功")
                #if DEBUG
                saveStatus = "success"
                #endif
                isSaving = false
                presentationMode.wrappedValue.dismiss()
            case .failure(let error):
                print("用户资料保存失败: \(error.localizedDescription)")
                #if DEBUG
                saveStatus = "failure"
                #endif
                isSaving = false
            }
        }
    }
}

// MARK: - 图片选择器
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

#Preview {
    EditProfileView()
}
