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
        reduceTransparency || contrast == .increased ? 0.58 : 0.42
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
    }

    private var backgroundLayer: some View {
        ZStack {
            if background != .none {
                backgroundImage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .accessibilityHidden(true)
            }

            CardEditorGlassSurface(
                shape: RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                ),
                style: .writingPlane
            )

            if background != .none {
                Color.black
                    .opacity(veilOpacity)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .clipped()
        .accessibilityHidden(true)
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
