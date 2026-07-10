import Combine
import Foundation

@MainActor
public final class QuickCaptureStore: ObservableObject {
    @Published public var text = "" {
        didSet {
            guard !isRestoring, let actorID else { return }
            draftStore.save(text, for: actorID)
        }
    }
    @Published public private(set) var phase: CapturePhase = .idle

    public var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && phase != .saving
    }

    private let service: CoreFlowServing
    private let draftStore: CaptureDraftPersisting
    private var actorID: String?
    private var isRestoring = false
    private var createCancellable: AnyCancellable?

    public init(
        service: CoreFlowServing,
        draftStore: CaptureDraftPersisting
    ) {
        self.service = service
        self.draftStore = draftStore
    }

    public func load(actorID: String) {
        if let currentActorID = self.actorID,
           currentActorID != actorID {
            createCancellable?.cancel()
            createCancellable = nil
        }

        self.actorID = actorID
        isRestoring = true
        text = draftStore.text(for: actorID)
        isRestoring = false
        phase = .idle
    }

    public func save(onCreated: @escaping (CreatedCard) -> Void) {
        guard let actorID, canSave else { return }

        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .saving
        createCancellable = service.createPrivateCard(content: content)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self,
                          self.actorID == actorID,
                          case .failure(let error) = completion else {
                        return
                    }

                    self.phase = .failed(Self.message(for: error))
                },
                receiveValue: { [weak self] card in
                    guard let self,
                          self.actorID == actorID else {
                        return
                    }

                    self.isRestoring = true
                    self.text = ""
                    self.isRestoring = false
                    self.draftStore.remove(for: actorID)
                    self.phase = .idle
                    onCreated(card)
                }
            )
    }

    public func discard() {
        guard phase != .saving, let actorID else { return }

        isRestoring = true
        text = ""
        isRestoring = false
        draftStore.remove(for: actorID)
        phase = .idle
    }

    private static func message(for error: CoreFlowError) -> String {
        switch error {
        case .unauthorized:
            return "Your session expired. Your draft is safe."
        case .offline, .timeout:
            return "Couldn't save. Your draft is safe."
        case .decoding, .server, .unknown:
            return "Something went wrong. Your draft is safe."
        }
    }
}
