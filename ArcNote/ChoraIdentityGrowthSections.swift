import CoreFlow
import SwiftUI
import UIKit

struct ChoraIdentitySection: View {
    @ObservedObject var store: ChoraProfileStore
    let humanActorID: String
    @State private var selectedImage: UIImage?
    @State private var showsImagePicker = false

    var body: some View {
        ChoraSectionSurface(title: "Identity", identifier: "chora.identity.section") {
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
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Button { showsImagePicker = true } label: {
                    avatar.frame(width: 72, height: 72).clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Chora avatar. Choose a photo")
                .accessibilityIdentifier("chora.identity.avatar")
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.identity?.displayName ?? "Chora").font(.title3.weight(.semibold)).foregroundColor(.white)
                    Text("Your bound companion").font(.subheadline).foregroundColor(.white.opacity(0.58))
                }
                Spacer()
            }
            ChoraField(label: "Display name", placeholder: "Chora", text: .init(get: { store.displayNameDraft }, set: store.setDisplayNameDraft), identifier: "chora.identity.displayName")
            ChoraField(label: "Preferred address", placeholder: "How Chora addresses you", text: .init(get: { store.preferredAddressDraft ?? "" }, set: { store.setPreferredAddressDraft($0.isEmpty ? nil : $0) }), identifier: "chora.identity.preferredAddress")
            ForEach(errors, id: \.0) { field, message in
                Text(message).font(.footnote).foregroundColor(Color(red: 1, green: 0.56, blue: 0.58))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chora.identity.error.\(field)")
            }
            Button { store.save() } label: {
                HStack { if store.isSaving { ProgressView().tint(.white) }; Text(store.isSaving ? "Saving…" : "Save") }
                    .font(.body.weight(.medium)).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 30).fill(Color.white.opacity(0.12)).overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.white.opacity(0.24))))
            }
            .buttonStyle(.plain).disabled(store.isSaving || store.changedFields.isEmpty)
            .opacity(store.isSaving || store.changedFields.isEmpty ? 0.55 : 1)
            .accessibilityIdentifier("chora.identity.save")
        }
    }

    @ViewBuilder private var avatar: some View {
        if let selectedImage { Image(uiImage: selectedImage).resizable().aspectRatio(contentMode: .fill) }
        else if let value = store.identity?.avatarURL, let url = URL(string: APIConfiguration.resourceURLString(value)) {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) }
                else { Image("bot").resizable().aspectRatio(contentMode: .fill) }
            }
        } else { Image("bot").resizable().aspectRatio(contentMode: .fill) }
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
        ChoraSectionSurface(title: "Growth", identifier: "chora.growth.section") {
            switch store.growthPhase {
            case .idle, .loading: ChoraLoadingRow(text: "Loading Growth…", identifier: "chora.growth.loading")
            case .unavailable:
                ChoraInlineError(text: "Growth is unavailable right now.", identifier: "chora.growth.unavailable") { store.retryGrowth() }
            case .ready:
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("Stage").foregroundColor(.white.opacity(0.6)); Spacer(); Text(store.growth?.committedStage.displayName ?? "Unavailable").font(.body.weight(.semibold)).foregroundColor(.white).accessibilityIdentifier("chora.growth.stage") }
                    ForEach(ChoraGrowthDimension.canonicalRenderOrder, id: \.rawValue) { dimension in
                        ChoraGrowthBar(dimension: dimension, value: store.growth?.dimensions.first { $0.dimension == dimension }?.displayValue)
                    }
                }
            }
        }
    }
}
