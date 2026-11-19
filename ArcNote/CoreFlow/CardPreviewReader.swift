import Combine
import CoreFlow
import SwiftUI

@MainActor
final class CardPreviewReader: ObservableObject {
    struct Scope: Equatable {
        enum Access: Equatable {
            case remote(UInt64)
            case local(NoteStoreScope)
        }
        let access: Access
        let token: LibraryCardPreviewCache.ReadToken
    }

    static let shared: CardPreviewReader = {
        let reader = CardPreviewReader(
            remoteSession: { AuthManager.shared.cardReadSession },
            localScope: {
                let auth = AuthManager.shared
                let scope = LocalNotesController.shared.library.scope
                return auth.canOpenLocalNotes && scope == auth.currentNoteScope ? scope : nil
            }
        )
        LocalNotesController.shared.library.$scope.removeDuplicates().dropFirst()
            .sink { [weak reader] _ in reader?.invalidateAll() }
            .store(in: &reader.subscriptions)
        return reader
    }()

    @Published private(set) var invalidationGeneration: UInt64 = 0
    private let remoteSession: () -> UInt64?
    private let localScope: () -> NoteStoreScope?
    private let cache: LibraryCardPreviewCache
    private var subscriptions = Set<AnyCancellable>()

    init(
        remoteSession: @escaping () -> UInt64?,
        localScope: @escaping () -> NoteStoreScope?,
        cache: LibraryCardPreviewCache? = nil,
        notifications: NotificationCenter = .default
    ) {
        self.remoteSession = remoteSession
        self.localScope = localScope
        self.cache = cache ?? LibraryCardPreviewCache()
        notifications.publisher(for: .cardReadSessionDidChange).sink { [weak self] _ in
            self?.invalidateAll()
        }.store(in: &subscriptions)
        notifications.publisher(for: .cardReadInvalidated).sink { [weak self] event in
            guard let self, let cardID = event.object as? String else { return }
            invalidationGeneration &+= 1
            self.cache.invalidate(cardID: cardID)
        }.store(in: &subscriptions)
        notifications.publisher(for: UIApplication.didReceiveMemoryWarningNotification).sink { [weak self] _ in
            self?.cache.removeCachedPreviews()
        }.store(in: &subscriptions)
    }

    func scope(for input: LibraryCardPreviewInput) -> Scope? {
        let access: Scope.Access
        if let expected = input.localScope {
            guard localScope() == expected else { return nil }
            access = .local(expected)
        } else {
            guard !input.cardID.hasPrefix("local-note:"), let session = remoteSession() else { return nil }
            access = .remote(session)
        }
        return Scope(access: access, token: cache.token(for: input.cardID, localScope: input.localScope))
    }

    func read(_ input: LibraryCardPreviewInput, scope: Scope) async -> LibraryCardPresentation? {
        guard self.scope(for: input) == scope else { return nil }
        let presentation = await cache.read(input, token: scope.token)
        guard !Task.isCancelled, self.scope(for: input) == scope else { return nil }
        return presentation
    }

    private func invalidateAll() {
        invalidationGeneration &+= 1
        cache.invalidateAll()
    }
}

private struct CardPreviewReaderKey: EnvironmentKey {
    static let defaultValue: CardPreviewReader? = nil
}

extension EnvironmentValues {
    var cardPreviewReader: CardPreviewReader? {
        get { self[CardPreviewReaderKey.self] }
        set { self[CardPreviewReaderKey.self] = newValue }
    }
}

#if DEBUG
extension CardPreviewReader {
    /// Synthetic fixture roots only; never installed on the product root.
    static let fixture = CardPreviewReader(
        remoteSession: { 1 }, localScope: { nil }, notifications: NotificationCenter()
    )
}
#endif

/// A stable input and authorization scope drive both loading and display eligibility.
struct CardPreviewValue<Content: View>: View {
    let input: LibraryCardPreviewInput?
    var priority: TaskPriority = .userInitiated
    @ViewBuilder let content: (LibraryCardPresentation?) -> Content
    @Environment(\.cardPreviewReader) private var overrideReader

    var body: some View {
        ObservedCardPreviewValue(input: input, priority: priority, content: content,
                                 reader: overrideReader ?? CardPreviewReader.shared)
    }
}

private struct ObservedCardPreviewValue<Content: View>: View {
    let input: LibraryCardPreviewInput?
    let priority: TaskPriority
    @ViewBuilder let content: (LibraryCardPresentation?) -> Content
    @ObservedObject var reader: CardPreviewReader
    @State private var loaded: Loaded?

    private struct Request: Equatable {
        let input: LibraryCardPreviewInput
        let scope: CardPreviewReader.Scope
    }
    private struct Loaded {
        let request: Request
        let presentation: LibraryCardPresentation
    }

    var body: some View {
        let request = input.flatMap { input in reader.scope(for: input).map { Request(input: input, scope: $0) } }
        content(loaded?.request == request ? loaded?.presentation : nil)
            .task(id: request, priority: priority) {
                guard let request else { loaded = nil; return }
                guard loaded?.request != request,
                      let presentation = await reader.read(request.input, scope: request.scope),
                      !Task.isCancelled else { return }
                loaded = Loaded(request: request, presentation: presentation)
            }
            .onChange(of: request) { value in
                if loaded?.request != value { loaded = nil }
            }
            .onDisappear { loaded = nil }
    }
}

struct CardPlainTextPreview: View {
    let card: FlowCard
    @State private var snapshotID = UUID()

    var body: some View {
        CardPreviewValue(input: LibraryCardPreviewInput(
            cardID: card.id, contentHash: card.contentHash, snapshotID: snapshotID,
            content: card.content, contentJSON: card.contentJSON
        )) { presentation in
            Text(presentation?.plainText ?? "")
        }
    }
}
