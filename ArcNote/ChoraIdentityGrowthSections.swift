import CoreFlow
import SwiftUI
import UIKit

struct ChoraIdentitySection: View {
    @ObservedObject var store: ChoraProfileStore
    let humanActorID: String
    @State private var selectedImage: UIImage?
    @State private var showsImagePicker = false

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
            guard let data = image?.jpegData(compressionQuality: 0.88) else { return }
            store.setAvatarDraft(.init(data: data, filename: "chora-avatar.jpg", mimeType: "image/jpeg"))
        }
        .onChange(of: store.avatarDraft) { draft in
            if draft == nil {
                selectedImage = nil
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
            ChoraActionButton(title: store.isSaving ? "Saving…" : "Save") {
                store.save()
            }
            .disabled(store.isSaving || store.changedFields.isEmpty)
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
