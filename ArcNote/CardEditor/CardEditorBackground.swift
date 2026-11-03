import SwiftUI
import UIKit

enum CardEditorBackgroundSource: Equatable {
    case none
    case local(Data)
    case remote(URL)
}

struct CardEditorBackground<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
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

    private var paneShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var veilOpacity: Double {
        if reduceTransparency {
            return 0.58
        }
        if contrast == .increased {
            return 0.34
        }
        return 0.22
    }

    private var paneShadowOpacity: Double {
        contrast == .increased ? 0.30 : 0.20
    }

    @ViewBuilder
    var body: some View {
        if background == .none {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            content()
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipShape(paneShape)
            .background {
                backgroundLayer
                    .clipShape(paneShape)
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            if background != .none {
                backgroundImage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .accessibilityHidden(true)

                (colorScheme == .dark ? Color.black : Color.white)
                    .opacity(colorScheme == .dark ? veilOpacity : 0.72)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }

            CardEditorGlassSurface(
                shape: paneShape,
                style: .writingPlane
            )
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
