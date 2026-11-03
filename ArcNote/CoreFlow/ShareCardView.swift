import CoreFlow
import SwiftUI
import UIKit

struct ShareCardView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: ShareCardStore

    init(cardID: String) {
        _store = StateObject(
            wrappedValue: ShareCardStore(
                cardID: cardID,
                service: NetworkCoreShareService()
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Share this note as an image.")
                        .font(.body)
                    Text("Choose where to send it using the iOS share sheet. Sharing does not change this note’s privacy.")
                        .font(.footnote)
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                    action
                }
                .listRowBackground(ChoraiTheme.surface)

                Section("Preview") {
                    content
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
                .listRowBackground(ChoraiTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(ChoraiTheme.background)
            .foregroundStyle(ChoraiTheme.ink)
            .tint(ChoraiTheme.ink)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("share-card.close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            store.load()
        }
        .sheet(item: nativeSharePayload) { payload in
            NativeShareController(items: nativeItems(payload))
        }
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                Text("Share card")
                    .font(.system(size: 1))
                    .foregroundStyle(.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("screen.share-card")
                if let preview = store.preview {
                    Text(preview.artifact.id)
                        .font(.system(size: 1))
                        .foregroundStyle(.white.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("share-card.artifact-id")
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var nativeSharePayload: Binding<NativeSharePayload?> {
        Binding(
            get: { store.nativeSharePayload },
            set: { value in
                if value == nil {
                    store.consumeNativeSharePayload()
                }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            ProgressView()
                .tint(ChoraiTheme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("share-card.loading")
        case .ready, .preparingNativeShare:
            if let data = store.imageData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(ChoraiTheme.separator, lineWidth: 1)
                    }
                    .accessibilityLabel("Share card preview")
                    .accessibilityIdentifier("share-card.preview")
            } else {
                errorState(code: "share_image_invalid")
            }
        case .failed(let error):
            errorState(code: error.code)
        }
    }

    @ViewBuilder
    private var action: some View {
        if store.preview != nil,
           store.phase == .ready || store.phase == .preparingNativeShare {
            Button {
                store.prepareNativeShare()
            } label: {
                HStack(spacing: 8) {
                    if store.phase == .preparingNativeShare {
                        ProgressView().tint(ChoraiTheme.ink)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                    Text("Share")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(ChoraiTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .disabled(store.isBusy)
            .accessibilityIdentifier("share-card.action")
        }
    }

    private func errorState(code: String) -> some View {
        VStack(spacing: 14) {
            Text("Share preview unavailable")
                .font(.headline)
                .foregroundStyle(ChoraiTheme.ink)
            Text("Your card is unchanged. Try again when the connection is ready.")
                .font(.footnote)
                .foregroundStyle(ChoraiTheme.secondaryInk)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                store.retry()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(ChoraiTheme.ink)
            .frame(minWidth: 96, minHeight: 40)
            .background(Capsule().fill(ChoraiTheme.surface))
            .accessibilityIdentifier("share-card.retry")
            Text(code)
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("share-card.error-code")
            Text("Share error")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("share-card.error")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func nativeItems(_ payload: NativeSharePayload) -> [Any] {
        guard let image = UIImage(data: payload.imageData) else { return [] }
        return [image]
    }
}

private struct NativeShareController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
