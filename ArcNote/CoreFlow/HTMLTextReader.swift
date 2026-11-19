import Combine
import CoreFlow
import SwiftUI

/// Converts snapshots already supplied by the owning screen, including public
/// and anonymous content. It cannot fetch or authorize any note data.
@MainActor
final class HTMLTextReader: ObservableObject {
    struct Request: Equatable {
        let input: LibraryCardPreviewInput
        let token: LibraryCardPreviewCache.ReadToken
    }

    static let shared = HTMLTextReader()
    @Published private(set) var invalidationGeneration: UInt64 = 0
    private let cache: LibraryCardPreviewCache
    // Content equality supplies the version; this identity stays stable across
    // view recreation so a repeated supplied snapshot can reuse its result.
    private let snapshotID = UUID()
    private var subscriptions = Set<AnyCancellable>()

    init(cache: LibraryCardPreviewCache? = nil, notifications: NotificationCenter = .default) {
        self.cache = cache ?? LibraryCardPreviewCache(parse: { LegacyHTMLTextFormatter.presentation($0.content) })
        notifications.publisher(for: .cardReadSessionDidChange).sink { [weak self] _ in
            self?.cache.invalidateAll()
            self?.invalidationGeneration &+= 1
        }.store(in: &subscriptions)
        notifications.publisher(for: UIApplication.didReceiveMemoryWarningNotification).sink { [weak self] _ in
            self?.cache.removeCachedPreviews()
        }.store(in: &subscriptions)
    }

    func request(cardID: String, html: String) -> Request {
        Request(input: LibraryCardPreviewInput(cardID: cardID, contentHash: nil, snapshotID: snapshotID,
                                               content: html, contentJSON: nil), token: cache.token(for: cardID))
    }

    func read(_ request: Request) async -> String? {
        guard cache.isCurrent(request.token), !Task.isCancelled else { return nil }
        let value = await cache.read(request.input, token: request.token)
        guard cache.isCurrent(request.token), !Task.isCancelled else { return nil }
        return value?.plainText
    }
}

struct HTMLTextValue<Content: View>: View {
    let cardID: String
    let html: String
    @ObservedObject var reader: HTMLTextReader
    @ViewBuilder let content: (String) -> Content
    @State private var loaded: Loaded?

    private struct Loaded {
        let request: HTMLTextReader.Request
        let text: String
    }

    var body: some View {
        let request = reader.request(cardID: cardID, html: html)
        content(loaded?.request == request ? loaded?.text ?? "" : "")
            .task(id: request) {
                guard loaded?.request != request,
                      let text = await reader.read(request), !Task.isCancelled else { return }
                loaded = Loaded(request: request, text: text)
            }
            .onChange(of: request) { value in
                if loaded?.request != value { loaded = nil }
            }
            .onDisappear { loaded = nil }
    }
}
