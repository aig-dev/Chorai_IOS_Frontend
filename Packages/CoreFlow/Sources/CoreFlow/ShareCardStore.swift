import Combine
import Foundation

@MainActor
public final class ShareCardStore: ObservableObject {
    @Published public private(set) var phase: ShareCardPhase = .idle
    @Published public private(set) var preview: ShareCardPreview?
    @Published public private(set) var imageData: Data?
    @Published public private(set) var nativeSharePayload: NativeSharePayload?

    public var isBusy: Bool {
        phase == .loading || phase == .preparingNativeShare
    }

    private let cardID: String
    private let service: any CoreShareServing
    private var operationTask: Task<Void, Never>?

    public init(cardID: String, service: any CoreShareServing) {
        self.cardID = cardID
        self.service = service
    }

    public func load() {
        guard !isBusy else { return }
        operationTask?.cancel()
        nativeSharePayload = nil
        phase = .loading
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let preview = try await service.preview(cardID: cardID)
                guard !Task.isCancelled else { return }
                let imageData = try await service.artifactImage(
                    cardID: cardID,
                    artifactID: preview.artifact.id
                )
                guard !Task.isCancelled else { return }
                self.preview = preview
                self.imageData = imageData
                self.phase = .ready
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(Self.mapError(error))
            }
        }
    }

    public func retry() {
        load()
    }

    public func prepareNativeShare() {
        guard
            phase == .ready,
            let preview,
            let imageData
        else { return }

        guard preview.actions.canNativeShare else {
            phase = .failed(
                .actionUnavailable(code: "native_share_unavailable")
            )
            return
        }

        phase = .preparingNativeShare
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await service.pinArtifact(
                    cardID: cardID,
                    artifactID: preview.artifact.id
                )
                guard !Task.isCancelled else { return }
                nativeSharePayload = NativeSharePayload(
                    artifactID: preview.artifact.id,
                    imageData: imageData
                )
                phase = .ready
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(Self.mapError(error))
            }
        }
    }

    public func consumeNativeSharePayload() {
        nativeSharePayload = nil
    }

    private static func mapError(_ error: Error) -> CoreShareError {
        if let shareError = error as? CoreShareError {
            return shareError
        }
        return .transport(code: "share_request_failed")
    }
}
