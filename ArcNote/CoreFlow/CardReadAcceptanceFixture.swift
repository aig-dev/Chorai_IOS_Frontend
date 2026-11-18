#if DEBUG
import Combine
import CoreFlow
import SwiftUI

/// Drives the real read coordinator and path decoder with locally controlled responses.
@MainActor
struct CardReadAcceptanceFixture: View {
    @State private var status = "Running"

    var body: some View {
        Text(status)
            .accessibilityIdentifier("fixture.community-card-reads.result")
            .task {
                do {
                    try await Self.verifySharedDetail()
                    try await Self.verifyOverlapWithDiscovery()
                    try await Self.verifyDiscoveryTransport()
                    status = "Passed"
                } catch {
                    status = "Failed: \(error)"
                }
            }
    }

    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(description: message) }
    }

    private final class DetailTransport {
        var session: UInt64 = 1
        private(set) var sessionReads = 0
        private(set) var requests: [PassthroughSubject<CardDetailResponse, NetworkError>] = []

        func currentSession() -> UInt64? {
            sessionReads += 1
            return session
        }

        func read(_ cardID: String) -> AnyPublisher<CardDetailResponse, NetworkError> {
            let request = PassthroughSubject<CardDetailResponse, NetworkError>()
            requests.append(request)
            return request.eraseToAnyPublisher()
        }

        func waitUntilStarted(_ count: Int) async throws {
            for _ in 0..<500 {
                if requests.count >= count { return }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            throw Failure(description: "Detail request did not start")
        }

        func waitForSessionRead(after count: Int) async throws {
            for _ in 0..<500 {
                if sessionReads > count { return }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            throw Failure(description: "The second reader did not start")
        }
    }

    private static func verifySharedDetail() async throws {
        let transport = DetailTransport()
        let reader = CardDetailReader(session: transport.currentSession, fetch: transport.read)
        let first = Task { try await reader.confirmed(cardID: "shared") }
        try await transport.waitUntilStarted(1)
        let priorReads = transport.sessionReads
        let second = Task { try await reader.confirmed(cardID: "shared") }
        try await transport.waitForSessionRead(after: priorReads)
        first.cancel()
        try await expectCancellation(first)
        try require(transport.requests.count == 1, "Overlapping reads issued more than one request")
        reader.didCommit(CardLikeState(cardID: "shared", isLiked: true, likeCount: 7))
        reader.didCommit(CardFavoriteState(cardID: "shared", isFavorited: true, favoriteCount: 9))
        transport.requests[0].send(try detail("shared", content: "Initial"))
        let initial = try await second.value
        try require(initial.likeCount == 7 && initial.isLiked, "GET rolled back the like receipt")
        try require(initial.favoriteCount == 9 && initial.isFavorited == true, "GET rolled back the favorite receipt")
        try require(reader.cached(cardID: "shared")?.content == "Initial", "Warm snapshot missing")

        let failing = Task { try await reader.confirmed(cardID: "shared") }
        try await transport.waitUntilStarted(2)
        transport.requests[1].send(completion: .failure(.timeout))
        guard case .failure(NetworkError.timeout) = await failing.result else {
            throw Failure(description: "Transient error was lost")
        }
        try require(reader.cached(cardID: "shared")?.content == "Initial", "Transient failure erased the warm snapshot")

        let beforeEdit = Task { try await reader.confirmed(cardID: "shared") }
        try await transport.waitUntilStarted(3)
        let afterEdit = Task { try await reader.confirmed(cardID: "shared", requiringNewRead: true) }
        try await transport.waitUntilStarted(4)
        transport.requests[3].send(try detail("shared", content: "Edited"))
        try require(try await afterEdit.value.content == "Edited", "Edited read did not issue a fresh request")
        transport.requests[2].send(completion: .failure(.forbidden))
        try await expectCancellation(beforeEdit)
        try require(reader.cached(cardID: "shared")?.content == "Edited", "Older error removed the edit")

        let revoked = Task { try await reader.confirmed(cardID: "shared") }
        try await transport.waitUntilStarted(5)
        NotificationCenter.default.post(name: .cardReadInvalidated, object: "shared")
        transport.requests[4].send(try detail("shared", content: "Revoked"))
        try await expectCancellation(revoked)
        try require(reader.cached(cardID: "shared") == nil, "Revocation allowed the old response to restore the card")

        let previousSession = Task { try await reader.confirmed(cardID: "shared") }
        try await transport.waitUntilStarted(6)
        transport.session += 1
        NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        let currentSession = Task { try await reader.confirmed(cardID: "shared") }
        try await transport.waitUntilStarted(7)
        transport.requests[5].send(try detail("shared", content: "Previous account"))
        transport.requests[6].send(try detail("shared", content: "Current account"))
        try await expectCancellation(previousSession)
        try require(try await currentSession.value.content == "Current account", "New account received the old result")
    }

    private static func expectCancellation(_ task: Task<CardDetail, any Error>) async throws {
        guard case .failure(is CancellationError) = await task.result else {
            throw Failure(description: "An invalidated or cancelled waiter finished with content")
        }
    }

    private static func verifyOverlapWithDiscovery() async throws {
        let transport = DetailTransport()
        let reader = CardDetailReader(session: transport.currentSession, fetch: transport.read)
        let detail = Task { try await reader.confirmed(cardID: "target") }
        try await transport.waitUntilStarted(1)
        let response = try path(ancestors: 0, format: .expanded(0))
        let service = NetworkDiscoveryPathService(reader: reader) { _ in
            Just(response).setFailureType(to: NetworkError.self).eraseToAnyPublisher()
        }
        let priorReads = transport.sessionReads
        let discovery = Task { try await service.discoveryPath(cardID: "target") }
        try await transport.waitForSessionRead(after: priorReads)
        transport.requests[0].send(try Self.detail("target", content: "Shared across surfaces"))
        let shown = try await detail.value
        let collected = try await discovery.value.collected
        try require(transport.requests.count == 1 && collected.content == shown.content,
                    "Detail and Discovery Path did not share their target read")
    }

    private static func verifyDiscoveryTransport() async throws {
        for count in [0, 5, 10, 20] {
            let snapshot = try await loadPath(
                ancestors: count, format: .expanded(count), expectedDetails: ["target"]
            )
            try require(snapshot.ancestors.count == count, "Wrong number of visible ancestors")
            if let last = snapshot.ancestors.first {
                try require(last.card.id == "ancestor-\(count - 1)", "Wrong path order")
                try require(last.card.authorActorID == "writer" && last.card.ownerActorID == "owner",
                            "Path confused author with owner")
            }
        }
        let partial = try await loadPath(ancestors: 5, format: .expanded(1), expectedDetails: ["target"])
        try require(partial.ancestors.map(\.id) == ["ancestor-0"], "Missing summaries launched legacy reads")
        let legacy = try await loadPath(
            ancestors: 2, format: .legacy, expectedDetails: ["target", "ancestor-0", "ancestor-1"]
        )
        try require(legacy.ancestors.map(\.id) == ["ancestor-1", "ancestor-0"], "Old server path was not preserved")
        let emptyLegacy = try await loadPath(
            ancestors: 0, format: .status(404), expectedDetails: ["target", "target"]
        )
        try require(emptyLegacy.ancestors.isEmpty, "Old 404 did not revalidate the target")
        for format in [PathFormat.expanded(0), .null, .duplicate, .extra, .wrongTarget, .status(401), .status(403), .status(503)] {
            do {
                _ = try await loadPath(ancestors: 2, format: format, expectedDetails: ["target"])
                throw Failure(description: "Unexpected content from incomplete, denied or malformed path")
            } catch is DiscoveryPathError {
                continue
            }
        }
        do {
            _ = try await loadPath(
                ancestors: 0, format: .status(404), expectedDetails: ["target", "target"], denySecondDetail: true
            )
            throw Failure(description: "Revoked target was rendered as a legacy empty path")
        } catch DiscoveryPathError.invalidCard {
            // A 404 on the new target check removes access to the target itself.
        }
    }

    private enum PathFormat {
        case expanded(Int), legacy, null, duplicate, extra, wrongTarget, status(Int)
    }

    private static func loadPath(
        ancestors: Int, format: PathFormat, expectedDetails: [String], denySecondDetail: Bool = false
    ) async throws -> DiscoveryPathSnapshot {
        var detailRequests: [String] = []
        var pathRequests: [String] = []
        let reader = CardDetailReader(session: { 1 }) { id in
            detailRequests.append(id)
            if denySecondDetail && detailRequests.count == 2 {
                return Fail(error: .notFound).eraseToAnyPublisher()
            }
            do {
                return Just(try detail(id, content: "Fixture text"))
                    .setFailureType(to: NetworkError.self).eraseToAnyPublisher()
            } catch {
                return Fail(error: .decodingError).eraseToAnyPublisher()
            }
        }
        let service = NetworkDiscoveryPathService(reader: reader) { id in
            pathRequests.append(id)
            if case .status(let status) = format {
                return Fail(error: .api(statusCode: status, code: nil, message: nil)).eraseToAnyPublisher()
            }
            do {
                let response = try path(ancestors: ancestors, format: format)
                return Just(response).setFailureType(to: NetworkError.self).eraseToAnyPublisher()
            } catch {
                return Fail(error: .decodingError).eraseToAnyPublisher()
            }
        }
        let outcome: Result<DiscoveryPathSnapshot, Error>
        do {
            outcome = .success(try await service.discoveryPath(cardID: "target"))
        } catch {
            outcome = .failure(error)
        }
        try require(detailRequests == expectedDetails && pathRequests == ["target"],
                    "Unexpected read sequence: \(detailRequests), \(pathRequests)")
        return try outcome.get()
    }

    private static let date = "2026-11-18T00:00:00Z"
    private static let author = ["author_id": "writer", "author_name": "A separate author"]

    private static func path(
        ancestors: Int, format: PathFormat
    ) throws -> NetworkResponse<DiscoveryPathData> {
        let nodes: [[String: Any]] = (0..<ancestors).map { index in
            ["asset_id": "ancestor-\(index)", "version_id": "version-\(index)",
             "activity_id": "activity-\(index)", "depth": index]
        }
        var data: [String: Any] = ["target_asset_id": "target", "path": nodes, "path_length": nodes.count]
        func summary(_ id: String) -> [String: Any] {
            ["asset_id": id, "owner_actor_id": "owner", "title": "", "content": "Fixture text",
             "created_at": date, "tags": [], "rate": 1, "author": author]
        }
        switch format {
        case .expanded(let count): data["ancestor_cards"] = (0..<count).map { summary("ancestor-\($0)") }
        case .legacy, .status: break
        case .null: data["ancestor_cards"] = NSNull()
        case .duplicate: data["ancestor_cards"] = [summary("ancestor-0"), summary("ancestor-0")]
        case .extra: data["ancestor_cards"] = [summary("outside-path")]
        case .wrongTarget:
            data["target_asset_id"] = "other"
            data["ancestor_cards"] = [summary("ancestor-0")]
        }
        let payload = try JSONSerialization.data(withJSONObject: ["success": true, "data": data])
        return try JSONDecoder().decode(NetworkResponse<DiscoveryPathData>.self, from: payload)
    }

    private static func detail(_ id: String, content: String) throws -> CardDetailResponse {
        let data: [String: Any] = [
            "id": id, "content": content, "content_hash": content, "created_at": date,
            "updated_at": date, "tags": [], "is_public": true, "is_pinned": false,
            "like_count": 0, "is_liked": false, "is_favorited": false, "favorite_count": 0,
            "comment_count": 0, "rate": 1, "author": author, "owner_actor_id": "owner"
        ]
        let payload = try JSONSerialization.data(withJSONObject: ["success": true, "data": data])
        return try JSONDecoder().decode(CardDetailResponse.self, from: payload)
    }
}
#endif
