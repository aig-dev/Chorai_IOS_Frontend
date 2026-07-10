import XCTest
@testable import CoreFlow

@MainActor
final class ShareCardStoreTests: XCTestCase {
    func testLoadFetchesPreviewAndImageWithoutPinningArtifact() async {
        let service = MockCoreShareService()
        service.previewResult = .success(preview())
        service.imageResult = .success(Data("png".utf8))
        let store = ShareCardStore(cardID: "ast_1", service: service)

        store.load()
        await waitForShareStore { store.phase == .ready }

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.preview?.artifact.id, "shr_1")
        XCTAssertEqual(store.imageData, Data("png".utf8))
        XCTAssertEqual(service.previewCardIDs, ["ast_1"])
        XCTAssertEqual(service.imageRequests, [.init(cardID: "ast_1", artifactID: "shr_1")])
        XCTAssertTrue(service.pinRequests.isEmpty)
    }

    func testPrepareNativeSharePinsArtifactAndPublishesPayload() async {
        let service = MockCoreShareService()
        service.previewResult = .success(preview())
        service.imageResult = .success(Data("png".utf8))
        service.pinResult = .success(
            ShareArtifactPin(
                noteID: "ast_1",
                noteVersionID: "ver_1",
                artifactID: "shr_1",
                artifactKind: "vertical-card"
            )
        )
        let store = ShareCardStore(cardID: "ast_1", service: service)

        store.load()
        await waitForShareStore { store.phase == .ready }
        store.prepareNativeShare()
        await waitForShareStore {
            store.phase == .ready && store.nativeSharePayload != nil
        }

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(service.pinRequests, [.init(cardID: "ast_1", artifactID: "shr_1")])
        XCTAssertEqual(store.nativeSharePayload?.artifactID, "shr_1")
        XCTAssertEqual(store.nativeSharePayload?.imageData, Data("png".utf8))
    }

    func testUnavailableNativeShareDoesNotPin() async {
        let service = MockCoreShareService()
        service.previewResult = .success(preview(canNativeShare: false))
        service.imageResult = .success(Data("png".utf8))
        let store = ShareCardStore(cardID: "ast_1", service: service)

        store.load()
        await waitForShareStore { store.phase == .ready }
        store.prepareNativeShare()

        XCTAssertEqual(
            store.phase,
            .failed(.actionUnavailable(code: "native_share_unavailable"))
        )
        XCTAssertTrue(service.pinRequests.isEmpty)
        XCTAssertNil(store.nativeSharePayload)
    }

    func testRetryAfterPreviewFailureLoadsCanonicalArtifact() async {
        let service = MockCoreShareService()
        service.previewResults = [
            .failure(.transport(code: "offline")),
            .success(preview())
        ]
        service.imageResult = .success(Data("png".utf8))
        let store = ShareCardStore(cardID: "ast_1", service: service)

        store.load()
        await waitForShareStore {
            store.phase == .failed(.transport(code: "offline"))
        }
        XCTAssertEqual(store.phase, .failed(.transport(code: "offline")))

        store.retry()
        await waitForShareStore { store.phase == .ready }

        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(service.previewCardIDs, ["ast_1", "ast_1"])
    }

    private func preview(canNativeShare: Bool = true) -> ShareCardPreview {
        ShareCardPreview(
            noteID: "ast_1",
            noteVersionID: "ver_1",
            artifactKind: "vertical-card",
            artifact: ShareArtifact(
                id: "shr_1",
                kind: "vertical-card",
                imageURL: "/api/cards/ast_1/share-artifacts/shr_1/image",
                contentType: "image/png",
                width: 1080,
                height: 1350,
                status: "ready"
            ),
            actions: ShareActions(
                canDownload: true,
                canNativeShare: canNativeShare,
                canCopyLink: true,
                canShareToX: true
            )
        )
    }

    private func waitForShareStore(
        timeoutIterations: Int = 500,
        _ predicate: @escaping () -> Bool
    ) async {
        for _ in 0..<timeoutIterations {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for Share store state")
    }
}

private final class MockCoreShareService: CoreShareServing, @unchecked Sendable {
    struct Request: Equatable {
        let cardID: String
        let artifactID: String
    }

    var previewResult: Result<ShareCardPreview, CoreShareError> =
        .failure(.transport(code: "missing_preview_fixture"))
    var previewResults: [Result<ShareCardPreview, CoreShareError>] = []
    var imageResult: Result<Data, CoreShareError> =
        .failure(.transport(code: "missing_image_fixture"))
    var pinResult: Result<ShareArtifactPin, CoreShareError> =
        .failure(.transport(code: "missing_pin_fixture"))

    private(set) var previewCardIDs: [String] = []
    private(set) var imageRequests: [Request] = []
    private(set) var pinRequests: [Request] = []

    func preview(cardID: String) async throws -> ShareCardPreview {
        previewCardIDs.append(cardID)
        if !previewResults.isEmpty {
            return try previewResults.removeFirst().get()
        }
        return try previewResult.get()
    }

    func artifactImage(cardID: String, artifactID: String) async throws -> Data {
        imageRequests.append(.init(cardID: cardID, artifactID: artifactID))
        return try imageResult.get()
    }

    func pinArtifact(cardID: String, artifactID: String) async throws -> ShareArtifactPin {
        pinRequests.append(.init(cardID: cardID, artifactID: artifactID))
        return try pinResult.get()
    }
}
