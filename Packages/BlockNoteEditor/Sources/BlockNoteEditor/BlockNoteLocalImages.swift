import Foundation
import WebKit

/// The host supplies note-scoped, verified bytes. The editor never receives
/// filesystem access or credentials for this local preview transport.
public struct BlockNoteLocalImageSource {
    public let scheme: String
    let load: @MainActor (URL) async throws -> (data: Data, mimeType: String)

    public init(scheme: String, load: @escaping @MainActor (URL) async throws -> (data: Data, mimeType: String)) {
        self.scheme = scheme
        self.load = load
    }
}

@MainActor
final class BlockNoteLocalImageHandler: NSObject, WKURLSchemeHandler {
    private let source: BlockNoteLocalImageSource
    private var requests: [ObjectIdentifier: (token: UUID, task: Task<Void, Never>)] = [:]
    private var closed = false

    var scheme: String { source.scheme }

    init(source: BlockNoteLocalImageSource) { self.source = source }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard !closed, let url = urlSchemeTask.request.url,
              url.scheme == source.scheme,
              urlSchemeTask.request.httpMethod == "GET" else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL)); return
        }
        let key = ObjectIdentifier(urlSchemeTask)
        let token = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let resource = try await self.source.load(url)
                guard !Task.isCancelled, !self.closed, self.requests[key]?.token == token else { return }
                guard !resource.data.isEmpty, resource.data.count <= 25 * 1024 * 1024,
                      resource.mimeType.hasPrefix("image/") else { throw URLError(.cannotDecodeContentData) }
                urlSchemeTask.didReceive(URLResponse(url: url, mimeType: resource.mimeType, expectedContentLength: resource.data.count, textEncodingName: nil))
                urlSchemeTask.didReceive(resource.data)
                urlSchemeTask.didFinish()
            } catch {
                guard !Task.isCancelled, !self.closed, self.requests[key]?.token == token else { return }
                urlSchemeTask.didFailWithError(error)
            }
            if self.requests[key]?.token == token { self.requests.removeValue(forKey: key) }
        }
        requests[key]?.task.cancel()
        requests[key] = (token, task)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        requests.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.task.cancel()
    }

    func close() {
        closed = true
        requests.values.forEach { $0.task.cancel() }
        requests.removeAll()
    }
}
