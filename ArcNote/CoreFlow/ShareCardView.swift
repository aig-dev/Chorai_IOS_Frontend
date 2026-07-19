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
        ZStack {
            Image("home_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 18) {
                header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                action
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .adaptiveContentGutter()
            .padding(.top, 72)
            .padding(.bottom, 24)
        }
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

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("share-card.close")

            Spacer()

            Text("Share")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            ProgressView()
                .tint(.white)
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
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
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
                        ProgressView().tint(.white)
                    } else {
                        Image("menu_share")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                    Text("Share")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(
                    Capsule().fill(Color.white.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy)
            .accessibilityIdentifier("share-card.action")
        }
    }

    private func errorState(code: String) -> some View {
        VStack(spacing: 14) {
            Text("Share preview unavailable")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Your card is unchanged. Try again when the connection is ready.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
            Button("Try Again") {
                store.retry()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 96, minHeight: 40)
            .background(Capsule().fill(Color.white.opacity(0.12)))
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
