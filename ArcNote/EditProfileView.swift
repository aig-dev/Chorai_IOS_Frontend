import SwiftUI
import UIKit
import Combine

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.adaptiveLayoutMetrics) private var layoutMetrics
    @ObservedObject private var userProfileManager = UserProfileManager.shared

    private let loadsProfileOnAppear: Bool
    private let onClose: (() -> Void)?

    @State private var name = ""
    @State private var bio = ""
    @State private var location = ""
    @State private var birthday = ""
    @State private var selectedAvatarImage: UIImage?
    @State private var selectedBackgroundImage: UIImage?
    @State private var imagePickerTarget: ProfileImageTarget?
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()

    #if DEBUG
    @State private var saveStatus = "idle"
    @State private var avatarUploadStatus = "idle"
    @State private var avatarUploadError = ""
    @State private var backgroundUploadStatus = "idle"
    @State private var backgroundUploadError = ""
    #endif

    init(
        loadsProfileOnAppear: Bool = true,
        onClose: (() -> Void)? = nil
    ) {
        self.loadsProfileOnAppear = loadsProfileOnAppear
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            ChoraiBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 18) {
                        profileMediaEditor
                        profileForm
                    }
                    .adaptiveContentGutter()
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { backButton }
            ToolbarItem(placement: .navigationBarTrailing) { saveButton }
        }
        .overlay(alignment: .topLeading) {
            testAnchors
        }
        .sheet(item: $imagePickerTarget) { target in
            ImagePicker(selectedImage: imageBinding(for: target))
        }
        .onAppear {
            loadUserProfile()
        }
        .onChange(of: userProfileManager.userProfile) { profile in
            guard !isSaving, let profile else { return }
            applyProfile(profile)
        }
        .onChange(of: bio) { updatedBio in
            if updatedBio.count > 100 {
                bio = String(updatedBio.prefix(100))
            }
        }
    }

    private var backButton: some View {
        Button(action: closeEditor) {
            Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .disabled(isSaving)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("edit-profile.back")
    }

    private var saveButton: some View {
        Button(action: saveUserProfile) {
            Group {
                if isSaving { ProgressView() }
                else { Text("Save").fontWeight(.semibold) }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .disabled(isSaving)
        .accessibilityLabel("Save")
        .accessibilityIdentifier("edit-profile.save")
    }

    private var profileMediaEditor: some View {
        Button {
            imagePickerTarget = .background
        } label: {
            ZStack(alignment: .bottomTrailing) {
                backgroundContent
                    .frame(maxWidth: .infinity)
                    .frame(height: 154)
                    .clipped()

                if hasBackgroundImage {
                    Image(systemName: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.58), in: Circle())
                        .overlay(Circle().stroke(ChoraiTheme.separator, lineWidth: 1))
                        .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ChoraiTheme.separator, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasBackgroundImage ? "Change background photo" : "Add background photo")
        .accessibilityHint("Opens your photo library")
        .accessibilityIdentifier("edit-profile.background")
        .overlay(alignment: .bottom) {
            avatarButton
                .offset(y: 36)
        }
        .padding(.bottom, 44)
    }

    @ViewBuilder
    private var backgroundContent: some View {
        if let selectedBackgroundImage {
            Image(uiImage: selectedBackgroundImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay(backgroundImageGradient)
        } else if let backgroundURL = profileResourceURL(userProfileManager.userProfile?.background) {
            AsyncImage(url: backgroundURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .overlay(backgroundImageGradient)
                case .empty:
                    backgroundLoadingSurface
                case .failure:
                    emptyBackgroundSurface
                @unknown default:
                    emptyBackgroundSurface
                }
            }
        } else {
            emptyBackgroundSurface
        }
    }

    private var emptyBackgroundSurface: some View {
        ZStack {
            LinearGradient(
                colors: [
                    ChoraiTheme.accent.opacity(0.12),
                    ChoraiTheme.gold.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 25, weight: .medium))
                Text("Add background photo")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(ChoraiTheme.ink)
        }
    }

    private var backgroundLoadingSurface: some View {
        ZStack {
            ChoraiTheme.surface
            ProgressView()
                .tint(ChoraiTheme.ink)
        }
    }

    private var backgroundImageGradient: some View {
        LinearGradient(
            colors: [.clear, Color.black.opacity(0.28)],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private var avatarButton: some View {
        Button {
            imagePickerTarget = .avatar
        } label: {
            ZStack(alignment: .bottomTrailing) {
                avatarContent
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(ChoraiTheme.separator, lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)

                Image(systemName: "camera.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.black.opacity(0.72), in: Circle())
                    .overlay(Circle().stroke(ChoraiTheme.separator, lineWidth: 1))
            }
            .frame(width: 80, height: 80)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change profile photo")
        .accessibilityHint("Opens your photo library")
        .accessibilityIdentifier("edit-profile.avatar")
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let selectedAvatarImage {
            Image(uiImage: selectedAvatarImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let avatarURL = profileResourceURL(userProfileManager.userProfile?.avatar) {
            AsyncImage(url: avatarURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Image("avatar")
            .resizable()
            .aspectRatio(contentMode: .fill)
    }

    private var profileForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            profileField(title: "My Name") {
                TextField("Enter your name", text: $name)
                    .textContentType(.name)
                    .accessibilityIdentifier("edit-profile.name")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Bio")
                    .profileFieldLabelStyle()

                ZStack(alignment: .bottomTrailing) {
                    TextEditor(text: $bio)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 82)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .profileInputSurface(reduceTransparency: reduceTransparency)
                        .accessibilityIdentifier("edit-profile.bio")

                    Text("\(bio.count)/100")
                        .font(.caption)
                        .foregroundColor(ChoraiTheme.secondaryInk)
                        .padding(.trailing, 14)
                        .padding(.bottom, 10)
                        .allowsHitTesting(false)
                }
            }

            profileField(title: "Location") {
                TextField("Enter your location", text: $location)
                    .textContentType(.addressCity)
                    .accessibilityIdentifier("edit-profile.location")
            }

            profileField(title: "Birthday") {
                TextField("YYYY-MM-DD", text: $birthday)
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("edit-profile.birthday")
            }

            if let saveErrorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(saveErrorMessage)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote.weight(.medium))
                .foregroundColor(.red)
                .accessibilityIdentifier("edit-profile.error")
            }
        }
        .padding(.vertical, 8)
    }

    private func profileField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .profileFieldLabelStyle()

            content()
                .font(.body)
                .foregroundColor(ChoraiTheme.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 54)
                .profileInputSurface(reduceTransparency: reduceTransparency)
        }
    }

    private var testAnchors: some View {
        VStack(spacing: 1) {
            Text("Edit profile loaded")
                .profileTestAnchor(identifier: "screen.edit-profile.loaded")

            if let profile = userProfileManager.userProfile {
                Text(profile.id)
                    .profileTestAnchor(identifier: "edit-profile.profile-id")
            }

            #if DEBUG
            Text(saveStatus)
                .profileTestAnchor(identifier: "edit-profile.save-status")
            Text(avatarUploadStatus)
                .profileTestAnchor(identifier: "edit-profile.avatar-upload-status")
            Text(userProfileManager.userProfile?.avatar ?? "")
                .profileTestAnchor(identifier: "edit-profile.avatar-url")
            Text(avatarUploadError)
                .profileTestAnchor(identifier: "edit-profile.avatar-upload-error")
            Text(backgroundUploadStatus)
                .profileTestAnchor(identifier: "edit-profile.background-upload-status")
            Text(userProfileManager.userProfile?.background ?? "")
                .profileTestAnchor(identifier: "edit-profile.background-url")
            Text(backgroundUploadError)
                .profileTestAnchor(identifier: "edit-profile.background-upload-error")

            Button(action: uploadAvatarSmokeImage) {
                Text("Avatar smoke upload")
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("edit-profile.avatar-smoke-upload")

            Button(action: stageBackgroundSmokeImage) {
                Text("Background smoke stage")
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("edit-profile.background-smoke-stage")
            #endif
        }
    }

    private var hasBackgroundImage: Bool {
        if selectedBackgroundImage != nil { return true }
        return !(userProfileManager.userProfile?.background ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func profileResourceURL(_ rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }
        return URL(string: APIConfiguration.resourceURLString(trimmedValue))
    }

    private func imageBinding(for target: ProfileImageTarget) -> Binding<UIImage?> {
        switch target {
        case .avatar:
            return $selectedAvatarImage
        case .background:
            return $selectedBackgroundImage
        }
    }

    private func loadUserProfile() {
        if loadsProfileOnAppear {
            userProfileManager.fetchCurrentUserProfile()
        }
        if let profile = userProfileManager.userProfile {
            applyProfile(profile)
        }
    }

    private func applyProfile(_ profile: UserProfile) {
        name = profile.username
        bio = profile.bio ?? ""
        location = profile.location ?? ""
        birthday = editableBirthday(profile.birthday)
    }

    private func editableBirthday(_ value: String?) -> String {
        guard let value else { return "" }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateOnly = String(trimmedValue.prefix(10))
        guard dateOnly.range(
            of: #"^\d{4}-\d{2}-\d{2}$"#,
            options: .regularExpression
        ) != nil else {
            return ""
        }
        return dateOnly
    }

    private func saveUserProfile() {
        guard !isSaving else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedBio = bio
        let savedLocation = location
        let savedBirthday = birthday
        guard !trimmedName.isEmpty else {
            saveErrorMessage = "Name can’t be empty."
            return
        }
        guard let currentProfile = userProfileManager.userProfile else {
            saveErrorMessage = "Your profile is still loading. Try again in a moment."
            return
        }

        let avatarData: Data?
        if let selectedAvatarImage {
            guard let data = selectedAvatarImage.jpegData(compressionQuality: 0.82) else {
                saveErrorMessage = "The profile photo couldn’t be prepared. Choose another image."
                return
            }
            avatarData = data
        } else {
            avatarData = nil
        }

        let backgroundData: Data?
        if let selectedBackgroundImage {
            guard let data = selectedBackgroundImage.jpegData(compressionQuality: 0.82) else {
                saveErrorMessage = "The background photo couldn’t be prepared. Choose another image."
                return
            }
            backgroundData = data
        } else {
            backgroundData = nil
        }

        isSaving = true
        saveErrorMessage = nil
        #if DEBUG
        saveStatus = "attempted"
        avatarUploadError = ""
        backgroundUploadError = ""
        #endif

        var publisher = Just(currentProfile)
            .setFailureType(to: NetworkError.self)
            .eraseToAnyPublisher()

        if let avatarData {
            #if DEBUG
            avatarUploadStatus = "uploading"
            #endif
            publisher = publisher
                .flatMap { _ in
                    NetworkManager.shared.uploadAvatar(imageData: avatarData)
                }
                .receive(on: DispatchQueue.main)
                .handleEvents(receiveOutput: { response in
                    userProfileManager.userProfile = response.data
                    selectedAvatarImage = nil
                    #if DEBUG
                    avatarUploadStatus = "success"
                    #endif
                })
                .map(\.data)
                .eraseToAnyPublisher()
        }

        if let backgroundData {
            #if DEBUG
            backgroundUploadStatus = "uploading"
            #endif
            publisher = publisher
                .flatMap { _ in
                    NetworkManager.shared.uploadProfileBackground(imageData: backgroundData)
                }
                .receive(on: DispatchQueue.main)
                .handleEvents(receiveOutput: { response in
                    userProfileManager.userProfile = response.data
                    selectedBackgroundImage = nil
                    #if DEBUG
                    backgroundUploadStatus = "success"
                    #endif
                })
                .map(\.data)
                .eraseToAnyPublisher()
        }

        publisher
            .flatMap { _ in
                NetworkManager.shared.updateUserProfilePublisher(
                    username: trimmedName,
                    bio: savedBio,
                    location: savedLocation,
                    birthday: savedBirthday
                )
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        isSaving = false
                        saveErrorMessage = error.localizedDescription
                        #if DEBUG
                        saveStatus = "failure"
                        if avatarUploadStatus == "uploading" {
                            avatarUploadStatus = "failure"
                            avatarUploadError = error.localizedDescription
                        }
                        if backgroundUploadStatus == "uploading" {
                            backgroundUploadStatus = "failure"
                            backgroundUploadError = error.localizedDescription
                        }
                        #endif
                    }
                },
                receiveValue: { response in
                    userProfileManager.userProfile = response.data
                    isSaving = false
                    #if DEBUG
                    saveStatus = "success"
                    #endif
                    closeEditor()
                }
            )
            .store(in: &cancellables)
    }

    private func closeEditor() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    #if DEBUG
    private func uploadAvatarSmokeImage() {
        guard let imageData = makeAvatarSmokeImage().jpegData(compressionQuality: 0.82) else {
            avatarUploadStatus = "failure"
            avatarUploadError = "Unable to prepare smoke image"
            return
        }

        avatarUploadStatus = "uploading"
        avatarUploadError = ""
        NetworkManager.shared.uploadAvatar(imageData: imageData)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        avatarUploadStatus = "failure"
                        avatarUploadError = error.localizedDescription
                    }
                },
                receiveValue: { response in
                    userProfileManager.userProfile = response.data
                    avatarUploadStatus = "success"
                }
            )
            .store(in: &cancellables)
    }

    private func makeAvatarSmokeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96))
        return renderer.image { context in
            UIColor(red: 0.10, green: 0.42, blue: 0.86, alpha: 1).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            UIColor(red: 0.93, green: 0.86, blue: 0.28, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 24, y: 24, width: 48, height: 48))
        }
    }

    private func stageBackgroundSmokeImage() {
        selectedBackgroundImage = makeBackgroundSmokeImage()
        backgroundUploadStatus = "staged"
        backgroundUploadError = ""
    }

    private func makeBackgroundSmokeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 160))
        return renderer.image { context in
            UIColor(red: 0.14, green: 0.18, blue: 0.46, alpha: 1).setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 320, height: 160))
            UIColor(red: 0.38, green: 0.72, blue: 0.88, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 196, y: 24, width: 92, height: 92))
        }
    }
    #endif
}

private enum ProfileImageTarget: String, Identifiable {
    case avatar
    case background

    var id: String { rawValue }
}

private extension View {
    func profileFieldLabelStyle() -> some View {
        font(.subheadline.weight(.semibold))
            .foregroundColor(ChoraiTheme.ink)
    }

    func profileInputSurface(reduceTransparency: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ChoraiTheme.raisedSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(ChoraiTheme.separator, lineWidth: 1)
                }
        )
    }

    func profileTestAnchor(identifier: String) -> some View {
        font(.system(size: 1))
            .foregroundColor(.white.opacity(0.01))
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(identifier)
    }
}

// MARK: - Image picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

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

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    EditProfileView()
}
