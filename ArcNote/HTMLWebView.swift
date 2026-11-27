import SwiftUI
import WebKit
import CoreFlow
import BlockNoteEditor
import ImageIO
import UniformTypeIdentifiers

struct AdaptiveHTMLWebView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let htmlContent: String
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let webView = ChoraiHTMLAppearance.makeWebView()
        webView.navigationDelegate = context.coordinator
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        guard context.coordinator.loadedContent != htmlContent else { return }
        context.coordinator.loadedContent = htmlContent
        webView.loadHTMLString(
            ChoraiHTMLAppearance.document(content: htmlContent),
            baseURL: nil
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: AdaptiveHTMLWebView
        var loadedContent: String?
        private var contentSizeObservation: NSKeyValueObservation?

        init(_ parent: AdaptiveHTMLWebView) { self.parent = parent }

        isolated deinit { contentSizeObservation?.invalidate() }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateHeight(webView)
            // Images may finish after navigation. Observe rendered size rather
            // than reloading the document each time SwiftUI measures its height.
            contentSizeObservation = webView.scrollView.observe(\.contentSize, options: [.new]) { [weak self, weak webView] _, _ in
                guard let webView else { return }
                MainActor.assumeIsolated { self?.updateHeight(webView) }
            }
        }

        private func updateHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript("Math.ceil(Math.max(document.body.scrollHeight, document.body.getBoundingClientRect().height))") { [weak self] result, _ in
                guard let self, let value = result as? NSNumber else { return }
                let measured = max(CGFloat(value.doubleValue), 50)
                guard abs(self.parent.height - measured) > 0.5 else { return }
                DispatchQueue.main.async { [weak self] in self?.parent.height = measured }
            }
        }
    }
}

private enum ChoraiHTMLAppearance {
    @MainActor
    static func makeWebView() -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        return webView
    }

    static func document(content: String) -> String {
        """
        <!DOCTYPE html>
        <html><head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        :root { color-scheme: light dark; --ink:#153b37; --muted:#586d64; --surface:#f0f0ea; --edge:#d9dfd7; --gold:#846838; }
        @media (prefers-color-scheme: dark) {
            :root { --ink:#bfdbcf; --muted:#a2b5ac; --surface:#35363b; --edge:#4c514f; --gold:#d6b378; }
        }
        html, body { margin:0; padding:0; background:transparent; width:100%; }
        /* Contain heading/paragraph margins so the measured body includes the
           last line. Collapsed margins can otherwise fall outside scrollHeight. */
        body { display:flow-root; }
        body { font:-apple-system-body; line-height:1.65; color:CanvasText; overflow-wrap:anywhere; -webkit-text-size-adjust:100%; }
        html { font:-apple-system-body; } body { font-family:ui-serif,'New York','Songti SC',Georgia,serif; font-size:1.235294rem; line-height:1.6; } p { margin-bottom:24px; }
        p { margin:0 0 16px; padding:0; }
        ul, ol { margin:12px 0; padding-left:24px; }
        li { margin:5px 0; }
        h1, h2, h3, h4, h5, h6 { margin:22px 0 12px; color:inherit; font-family:ui-serif,Georgia,serif; line-height:1.25; }
        h1 { font-size:1.75em; } h2 { font-size:1.45em; } h3 { font-size:1.2em; }
        blockquote { margin:16px 0; padding:8px 16px; border-left:3px solid var(--gold); color:var(--muted); }
        code { background:var(--surface); border-radius:4px; padding:2px 4px; font-family:ui-monospace,monospace; font-size:0.88em; }
        pre { box-sizing:border-box; max-width:100%; overflow-x:auto; padding:16px; border-radius:12px; background:var(--surface); }
        pre code { padding:0; background:transparent; }
        a { color:var(--ink); text-decoration:underline; }
        img, video { display:block; max-width:100%; height:auto; border-radius:12px; margin:16px 0; }
        table { display:block; overflow-x:auto; max-width:100%; border-collapse:collapse; margin:16px 0; }
        th, td { border:1px solid var(--edge); padding:8px; text-align:left; }
        th { background:var(--surface); }
        hr { border:0; border-top:1px solid var(--edge); margin:20px 0; }
        p { margin-bottom:24px; } body > :first-child { margin-top:0; }
        </style></head><body>\(content)</body></html>
        """
    }
}

/// Structured NOTE bodies use the shipped renderer in read-only mode. The
/// summary remains a fallback; it cannot replace authored blocks or images.
struct NoteReaderDocument: View {
    let card: CardDetail
    @ObservedObject private var auth = AuthManager.shared
    @StateObject private var media = NoteReaderMedia()
    @State private var shown: (NoteReaderMedia.Request, BlockNoteCardEditorModel)?
    @State private var legacyHeight: CGFloat = 200

    var body: some View {
        let request = NoteReaderMedia.Request(content: card.content, contentJSON: card.contentJSON,
            assetID: card.id, documentVersionID: card.noteDocumentVersionID,
            scope: auth.canEnterProduct ? auth.currentNoteScope : nil, generation: auth.sessionGeneration)
        Group {
            if auth.cardReadSession == nil {
                EmptyView()
            } else if card.contentJSON == nil {
                AdaptiveHTMLWebView(htmlContent: card.content, height: $legacyHeight).frame(height: legacyHeight)
            } else if let (accepted, model) = shown, accepted == request {
                BlockNoteCardEditor(model: model)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .task(id: request) {
            guard !Task.isCancelled else { return }
            shown = nil
            guard auth.cardReadSession != nil else { media.retire(); return }
            guard let document = await media.prepare(request), !Task.isCancelled else { return }
            shown = (request, BlockNoteCardEditorModel(document: document, editable: false,
                                                       localImageSource: media.source))
        }
        .onDisappear { media.retire(); shown = nil }
    }
}

/// Only this API's exact NOTE content endpoint is eligible for credentialed
/// preview downloads. Other image URLs retain the ordinary unauthenticated path.
enum NoteReaderMediaURL {
    nonisolated static func target(_ url: URL, assetID: String, origin: URL) -> URL? {
        guard !assetID.isEmpty, url.scheme == origin.scheme, url.host == origin.host,
              url.port == origin.port, url.user == nil, url.password == nil, url.fragment == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.queryItems == [URLQueryItem(name: "asset_id", value: assetID)] else { return nil }
        let segments = url.path.split(separator: "/")
        guard segments.count == 5 else { return nil }
        let ref = String(segments[3])
        guard canonical(ref), url.path == APIEnvironment.mediaContentPath(ref),
              parts.percentEncodedPath == url.path else { return nil }
        return url
    }

    nonisolated static func canonical(_ ref: String) -> Bool {
        ref.range(of: #"^med_[0-9a-f]{16}$"#, options: .regularExpression) != nil
    }

    nonisolated static func target(ref: String, assetID: String, origin: URL) -> URL? {
        guard canonical(ref), var parts = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = APIEnvironment.mediaContentPath(ref)
        parts.queryItems = [URLQueryItem(name: "asset_id", value: assetID)]
        parts.fragment = nil
        guard let url = parts.url else { return nil }
        return target(url, assetID: assetID, origin: origin)
    }
}

@MainActor
final class NoteReaderMedia: ObservableObject {
    struct Request: Equatable, Sendable {
        let content: String
        let contentJSON: String?
        let assetID: String
        let documentVersionID: String?
        let scope: NoteStoreScope?
        let generation: UInt64
    }
    private struct Prepared: Sendable {
        let document: BlockNoteInitialDocument
        let resources: [URL: URL]
    }
    private let currentSession: @MainActor () -> (NoteStoreScope?, UInt64)
    private let download: @MainActor (NoteStoreScope, URL) async throws -> Data
    private var active: UUID?
    private var request: Request?
    private var resources: [URL: URL] = [:]

    init(currentSession: @escaping @MainActor () -> (NoteStoreScope?, UInt64) = {
        let auth = AuthManager.shared
        return (auth.canEnterProduct ? auth.currentNoteScope : nil, auth.sessionGeneration)
    }, download: @escaping @MainActor (NoteStoreScope, URL) async throws -> Data = { scope, url in
        try await NetworkManager.shared.noteSyncDownload(scope: scope, url: url)
    }) {
        self.currentSession = currentSession; self.download = download
    }

    var source: BlockNoteLocalImageSource {
        .init(scheme: "chorai-note-media") { [weak self] url in
            guard let self else { throw CancellationError() }
            return try await self.load(url)
        }
    }

    func prepare(_ request: Request) async -> BlockNoteInitialDocument? {
        // A canceled task may start after its replacement. It must not retire
        // the replacement's mapping before noticing its cancellation.
        // The owning CardDetailManager and cardReadSession retain already
        // delivered text during verification/degraded connectivity. A missing
        // network scope yields no protected media mapping, not a lost body.
        guard !Task.isCancelled, isCurrent(request) else { return nil }
        retire()
        let id = UUID(); active = id; self.request = request
        let prepared = await Task.detached(priority: .userInitiated) { Self.project(request, id: id) }.value
        guard !Task.isCancelled, active == id, isCurrent(request) else { return nil }
        resources = prepared.resources
        return prepared.document
    }

    nonisolated private static func project(_ request: Request, id: UUID) -> Prepared {
        var references = Set<String>()
        func collect(_ blocks: [[String: Any]]) {
            for block in blocks {
                if block["type"] as? String == "image", let props = block["props"] as? [String: Any],
                   let ref = props["mediaRef"] as? String, NoteReaderMediaURL.canonical(ref) { references.insert(ref) }
                if let children = block["children"] as? [[String: Any]] { collect(children) }
            }
        }
        if let raw = request.contentJSON, let value = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) {
            if let blocks = value as? [[String: Any]] { collect(blocks) }
            else if let envelope = value as? [String: Any], let blocks = envelope["blocks"] as? [[String: Any]] { collect(blocks) }
        }
        var urls: [String: String] = [:], resources: [URL: URL] = [:]
        let origin = request.scope.flatMap { URL(string: $0.environmentID) }
        for ref in references {
            var parts = URLComponents(); parts.scheme = "chorai-note-media"
            parts.host = id.uuidString.lowercased(); parts.path = "/" + ref
            guard let local = parts.url else { continue }
            // Even while network admission is unavailable, canonical images
            // cannot fall back to an uncredentialed URL from the document.
            urls[ref] = local.absoluteString
            if let origin, let target = NoteReaderMediaURL.target(ref: ref, assetID: request.assetID, origin: origin) {
                resources[local] = target
            }
        }
        return Prepared(document: .init(contentJSON: request.contentJSON, fallbackMarkdown: request.content,
                                        displayURLsByMediaReference: urls), resources: resources)
    }

    func load(_ url: URL) async throws -> (data: Data, mimeType: String) {
        try Task.checkCancellation()
        guard let id = active, let request, isCurrent(request), let scope = request.scope,
              let target = resources[url] else { throw URLError(.noPermissionsToReadFile) }
        let bytes = try await download(scope, target)
        try Task.checkCancellation()
        guard active == id, isCurrent(request), !bytes.isEmpty, bytes.count <= 25 * 1024 * 1024 else { throw CancellationError() }
        let mime = await Task.detached(priority: .userInitiated) { () -> String? in
            guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let type = CGImageSourceGetType(source), let mime = UTType(type as String)?.preferredMIMEType,
                  ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(mime) else { return nil }
            return mime
        }.value
        try Task.checkCancellation()
        guard active == id, isCurrent(request), let mime else { throw URLError(.cannotDecodeContentData) }
        return (bytes, mime)
    }

    func retire() { active = nil; request = nil; resources = [:] }

    private func isCurrent(_ request: Request) -> Bool {
        let (scope, generation) = currentSession()
        return scope == request.scope && generation == request.generation
    }
}

struct NoteMediaPreview<Content: View>: View {
    let url: URL
    let cardID: String
    @ViewBuilder let content: (AsyncImagePhase) -> Content
    @ObservedObject private var auth = AuthManager.shared
    @StateObject private var loader = CardEditorBackgroundImage()
    @State private var finished: CardEditorBackgroundImage.Request?

    var body: some View {
        if let scope = auth.currentNoteScope, let origin = URL(string: scope.environmentID),
           let target = NoteReaderMediaURL.target(url, assetID: cardID, origin: origin) {
            let request = CardEditorBackgroundImage.Request(url: target, scope: scope,
                sessionGeneration: auth.sessionGeneration, canLoad: auth.canEnterProduct)
            content(phase(for: request))
                .task(id: request) {
                    guard !Task.isCancelled else { return }
                    finished = nil
                    await loader.load(request)
                    guard !Task.isCancelled else { return }
                    finished = request
                }
        } else {
            AsyncImage(url: url, content: content)
        }
    }

    private func phase(for request: CardEditorBackgroundImage.Request) -> AsyncImagePhase {
        if let image = loader.image(for: request) { return .success(Image(uiImage: image)) }
        return finished == request ? .failure(URLError(.cannotLoadFromNetwork)) : .empty
    }
}
