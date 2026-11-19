import CoreFlow
import SwiftUI
import UIKit

struct ChoraIdentitySection: View {
    @ObservedObject var store: ChoraProfileStore
    let humanActorID: String
    @State private var selectedImage: UIImage?
    @State private var showsImagePicker = false
    @State private var preparationTask: Task<Void, Never>?
    @State private var preparationGeneration = UUID()
    @State private var isPreparingImage = false
    @State private var preparationError: String?

    var body: some View {
        ChoraSectionSurface(title: "Identity", identifier: "chora.identity.section", openLayout: true) {
            switch store.phase {
            case .idle, .loading:
                ChoraLoadingRow(text: "Loading Chora identity…", identifier: "chora.identity.loading")
            case .failed:
                ChoraInlineError(text: "Chora’s identity couldn’t be loaded.", identifier: "chora.identity.error") {
                    Task { await store.load(humanActorID: humanActorID) }
                }
            case .ready: form
            }
        }
        .sheet(isPresented: $showsImagePicker) { ImagePicker(selectedImage: $selectedImage) }
        .onChange(of: selectedImage) { image in
            prepareAvatar(image)
        }
        .onDisappear { cancelPreparation() }
        .onChange(of: humanActorID) { _ in cancelPreparation(); selectedImage = nil }
        .onReceive(NotificationCenter.default.publisher(for: .cardReadSessionDidChange)) { _ in
            cancelPreparation()
            selectedImage = nil
        }
        .onChange(of: store.avatarDraft) { draft in
            if draft == nil, !isPreparingImage {
                selectedImage = nil
            }
        }
    }

    private func cancelPreparation() {
        preparationGeneration = UUID()
        preparationTask?.cancel()
        preparationTask = nil
        isPreparingImage = false
    }

    private func prepareAvatar(_ image: UIImage?) {
        cancelPreparation()
        guard let image else { return }
        let generation = preparationGeneration
        let authSession = AuthManager.shared.sessionGeneration
        let owner = humanActorID
        let identity = store.identity
        isPreparingImage = true
        store.setAvatarDraft(nil)
        preparationError = nil
        preparationTask = Task {
            defer {
                if preparationGeneration == generation {
                    isPreparingImage = false
                    preparationTask = nil
                }
            }
            do {
                let value = try await CardImagePreparation.shared.jpeg(image, quality: 0.88, filename: "chora-avatar.jpg")
                guard !Task.isCancelled, generation == preparationGeneration,
                      authSession == AuthManager.shared.sessionGeneration,
                      store.identity == identity, store.identity?.humanActorID == owner else { return }
                store.setAvatarDraft(.init(data: value.data, filename: value.filename, mimeType: value.mimeType))
            } catch is CancellationError {
            } catch {
                guard generation == preparationGeneration else { return }
                preparationError = "The photo couldn’t be prepared. Choose another image."
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Button { showsImagePicker = true } label: {
                    avatar.frame(width: 72, height: 72).clipShape(Circle())
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.caption.weight(.semibold))
                                .padding(6)
                                .foregroundStyle(ChoraiTheme.ink)
                                .background(ChoraiTheme.surface, in: Circle())
                        }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Chora avatar. Choose a photo")
                .accessibilityValue(resolvedAvatarValue ?? "Brand default avatar")
                .accessibilityIdentifier("chora.identity.avatar")
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.identity?.displayName ?? "Chora").font(.system(.title2, design: .serif).weight(.semibold)).foregroundColor(ChoraiTheme.ink)
                    Text("Your bound companion").font(.subheadline).foregroundColor(ChoraiTheme.secondaryInk)
                }
                Spacer()
            }
            ChoraField(label: "Display name", placeholder: "Chora", text: .init(get: { store.displayNameDraft }, set: store.setDisplayNameDraft), identifier: "chora.identity.displayName")
            ChoraField(label: "Preferred address", placeholder: "How Chora addresses you", text: .init(get: { store.preferredAddressDraft ?? "" }, set: { store.setPreferredAddressDraft($0.isEmpty ? nil : $0) }), identifier: "chora.identity.preferredAddress")
            ForEach(errors, id: \.0) { field, message in
                Text(message).font(.footnote).foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chora.identity.error.\(field)")
            }
            if let preparationError {
                Text(preparationError).font(.footnote).foregroundColor(.red)
            }
            ChoraActionButton(title: isPreparingImage ? "Preparing…" : (store.isSaving ? "Saving…" : "Save")) {
                store.save()
            }
            .disabled(isPreparingImage || store.isSaving || store.changedFields.isEmpty)
            .accessibilityIdentifier("chora.identity.save")
        }
    }

    @ViewBuilder private var avatar: some View {
        if let selectedImage { Image(uiImage: selectedImage).resizable().aspectRatio(contentMode: .fill) }
        else if let avatarURL {
            AsyncImage(url: avatarURL) { phase in
                if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                else { ChoraiDefaultAvatar() }
            }
        } else { ChoraiDefaultAvatar() }
    }

    private var resolvedAvatarValue: String? {
        guard let value = store.identity?.avatarURL?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != "avatar",
              !Self.isBackendDefaultAvatar(value) else {
            return nil
        }
        return value
    }

    private var avatarURL: URL? {
        guard let resolvedAvatarValue else { return nil }
        return URL(string: APIConfiguration.resourceURLString(resolvedAvatarValue))
    }

    private static func isBackendDefaultAvatar(_ value: String) -> Bool {
        URL(string: value)?.path == "/uploads/avatars/default.png"
            || value == "/uploads/avatars/default.png"
    }

    private var errors: [(String, String)] {
        var result: [(String, String)] = []
        if store.fieldErrors[.displayName] != nil { result.append(("displayName", "Display name wasn’t saved.")) }
        if store.fieldErrors[.preferredAddress] != nil { result.append(("preferredAddress", "Preferred address wasn’t saved.")) }
        if store.fieldErrors[.avatar] != nil { result.append(("avatar", "Avatar wasn’t saved.")) }
        return result
    }
}

struct ChoraGrowthSection: View {
    @ObservedObject var store: ChoraProfileStore
    let humanActorID: String

    var body: some View {
        ChoraSectionSurface(title: "Growth", identifier: "chora.growth.section", openLayout: true) {
            switch store.growthPhase {
            case .idle, .loading: ChoraLoadingRow(text: "Loading Growth…", identifier: "chora.growth.loading")
            case .unavailable:
                ChoraInlineError(text: "Growth is unavailable right now.", identifier: "chora.growth.unavailable") { store.retryGrowth() }
            case .ready:
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("Stage").foregroundColor(ChoraiTheme.secondaryInk); Spacer(); Text(store.growth?.committedStage.displayName ?? "Unavailable").font(.body.weight(.semibold)).foregroundColor(ChoraiTheme.ink).accessibilityIdentifier("chora.growth.stage") }
                    ForEach(ChoraGrowthDimension.canonicalRenderOrder, id: \.rawValue) { dimension in
                        ChoraGrowthBar(dimension: dimension, value: store.growth?.dimensions.first { $0.dimension == dimension }?.displayValue)
                    }
                }
            }
        }
    }
}
