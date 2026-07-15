import SwiftUI
import UIKit

enum CardEditorBackgroundSource: Equatable {
    case none
    case local(Data)
    case remote(URL)
}

struct CardEditorBackground<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let background: CardEditorBackgroundSource
    @ViewBuilder let content: () -> Content

    init(
        background: CardEditorBackgroundSource,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.background = background
        self.content = content
    }

    private var veilOpacity: Double {
        reduceTransparency || contrast == .increased ? 0.55 : 0.50
    }

    var body: some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                backgroundLayer
            }
            .clipShape(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .clipped()
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(ZenVisualTokens.cardBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    private var backgroundLayer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(ZenVisualTokens.cardFill)

            if background != .none {
                backgroundImage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .accessibilityHidden(true)

                Color.black
                    .opacity(veilOpacity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Background contrast veil")
                    .accessibilityIdentifier("cardEditorBodyBackgroundVeil")
                    .allowsHitTesting(false)

                backgroundMarker(
                    identifier: "cardEditorBodyBackground",
                    label: "Writing surface background"
                )

                switch background {
                case .local:
                    backgroundMarker(
                        identifier: "cardEditorPendingBackgroundImage",
                        label: "Pending background image"
                    )
                case .remote:
                    backgroundMarker(
                        identifier: "cardEditorBackgroundImage",
                        label: "Saved background image"
                    )
                case .none:
                    EmptyView()
                }
            }
        }
        .clipped()
    }

    private func backgroundMarker(
        identifier: String,
        label: String
    ) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var backgroundImage: some View {
        switch background {
        case .none:
            EmptyView()

        case let .local(data):
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZenVisualTokens.background
            }

        case let .remote(url):
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    ZenVisualTokens.background
                @unknown default:
                    ZenVisualTokens.background
                }
            }
        }
    }
}
