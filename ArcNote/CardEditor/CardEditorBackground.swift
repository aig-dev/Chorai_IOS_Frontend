import CoreFlow
import SwiftUI
import UIKit

enum CardEditorBackgroundSource: Equatable {
    case none
    case local(Data)
    case remote(CardEditorBackgroundImage.Request)
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

        case let .remote(request):
            CardEditorRemoteBackground(request: request)
        }
    }
}

@MainActor
struct CardEditorRemoteBackground: View {
    let request: CardEditorBackgroundImage.Request
    @StateObject private var loader: CardEditorBackgroundImage

    init(request: CardEditorBackgroundImage.Request, loader: CardEditorBackgroundImage = CardEditorBackgroundImage()) {
        self.request = request
        _loader = StateObject(wrappedValue: loader)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = loader.image(for: request) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZenVisualTokens.background
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: request) { await loader.load(request) }
    }
}

/// One visible background owns its decoded image. A replacement or retired
/// account/session cannot publish a response from an earlier request.
@MainActor
final class CardEditorBackgroundImage: ObservableObject {
    struct Request: Equatable, Hashable {
        let url: URL
        let scope: NoteStoreScope
        let sessionGeneration: UInt64
        let canLoad: Bool

        init(url: URL, scope: NoteStoreScope, sessionGeneration: UInt64, canLoad: Bool = true) {
            self.url = url; self.scope = scope
            self.sessionGeneration = sessionGeneration; self.canLoad = canLoad
        }
    }

    @Published private var decoded: UIImage?
    private var accepted: Request?
    private var active: UUID?
    private let currentSession: @MainActor () -> (NoteStoreScope?, UInt64)
    private let download: @MainActor (NoteStoreScope, URL) async throws -> Data
    private let prepare: @Sendable (Data) -> UIImage?

    init(
        currentSession: @escaping @MainActor () -> (NoteStoreScope?, UInt64) = {
            let auth = AuthManager.shared
            return (auth.canEnterProduct ? auth.currentNoteScope : nil, auth.sessionGeneration)
        },
        load: @escaping @MainActor (NoteStoreScope, URL) async throws -> Data = { scope, url in
            try await NetworkManager.shared.noteSyncDownload(scope: scope, url: url)
        },
        prepare: @escaping @Sendable (Data) -> UIImage? = { UIImage(data: $0)?.preparingForDisplay() }
    ) {
        self.currentSession = currentSession
        self.download = load
        self.prepare = prepare
    }

    func image(for request: Request) -> UIImage? {
        accepted == request && isCurrent(request) ? decoded : nil
    }

    func load(_ request: Request) async {
        guard !Task.isCancelled, isCurrent(request) else { return }
        let work = UUID()
        active = work; accepted = nil; decoded = nil
        defer { if active == work { active = nil } }
        do {
            let bytes = try await download(request.scope, request.url)
            try Task.checkCancellation()
            guard active == work, isCurrent(request) else { return }
            let prepare = self.prepare
            let image = await Task.detached(priority: .userInitiated) { prepare(bytes) }.value
            try Task.checkCancellation()
            guard active == work, isCurrent(request), let image else { return }
            accepted = request
            decoded = image
        } catch {
            // Preserve the existing neutral loading/failure surface. No stale
            // image or unauthenticated fallback is eligible for display.
        }
    }

    private func isCurrent(_ request: Request) -> Bool {
        let (scope, generation) = currentSession()
        return request.canLoad && scope == request.scope && generation == request.sessionGeneration
    }
}
