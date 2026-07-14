import Combine
import Foundation

@MainActor
public final class InvitationHistoryStore: ObservableObject {
    @Published public private(set) var actorID: String?
    @Published public private(set) var items: [InvitationRecord] = []
    @Published public private(set) var phase: InvitationCreditListPhase = .idle
    @Published public private(set) var hasMore = false
    @Published public private(set) var paginationError: InvitationCreditError?

    private let service: any CoreInvitationCreditServing
    private let pageSize: Int
    private var currentPage = 0
    private var generation = UUID()
    private var activeRequestID: UUID?

    public init(
        service: any CoreInvitationCreditServing,
        pageSize: Int = 20
    ) {
        self.service = service
        self.pageSize = max(1, pageSize)
    }

    public func load(actorID rawActorID: String) async {
        generation = UUID()
        activeRequestID = nil
        items = []
        currentPage = 0
        hasMore = false
        paginationError = nil
        guard let actorID = Self.normalized(rawActorID) else {
            self.actorID = nil
            phase = .failed(.invalidActor)
            return
        }
        self.actorID = actorID
        phase = .loading
        await fetch(page: 1, replacing: true)
    }

    public func loadMore() async {
        guard activeRequestID == nil, hasMore, actorID != nil else { return }
        phase = .loadingMore
        paginationError = nil
        await fetch(page: currentPage + 1, replacing: false)
    }

    public func retry() async {
        if paginationError != nil {
            await loadMore()
        } else if case .failed = phase, let actorID {
            await load(actorID: actorID)
        }
    }

    private func fetch(page: Int, replacing: Bool) async {
        guard let actorID, activeRequestID == nil else { return }
        let requestID = UUID()
        let requestedGeneration = generation
        activeRequestID = requestID
        defer {
            if activeRequestID == requestID { activeRequestID = nil }
        }

        do {
            let response = try await service.invitations(
                actorID: actorID,
                page: page,
                limit: pageSize
            )
            guard isCurrent(actorID, generation: requestedGeneration, requestID: requestID) else {
                return
            }
            guard response.page == page,
                  response.limit > 0,
                  response.total >= 0 else {
                publishFailure(
                    .contract(code: "invalid_invitation_page"),
                    replacing: replacing
                )
                return
            }

            let merged = replacing
                ? Self.deduplicated(response.items)
                : Self.appendingUnique(existing: items, incoming: response.items)
            items = merged
            currentPage = response.page
            hasMore = response.hasMore
            paginationError = nil
            phase = items.isEmpty ? .empty : .ready
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(actorID, generation: requestedGeneration, requestID: requestID) else {
                return
            }
            publishFailure(Self.map(error), replacing: replacing)
        }
    }

    private func publishFailure(
        _ error: InvitationCreditError,
        replacing: Bool
    ) {
        if replacing || items.isEmpty {
            phase = .failed(error)
        } else {
            paginationError = error
            phase = .ready
        }
    }

    private func isCurrent(
        _ actorID: String,
        generation: UUID,
        requestID: UUID
    ) -> Bool {
        self.actorID == actorID
            && self.generation == generation
            && activeRequestID == requestID
    }

    private static func deduplicated(_ values: [InvitationRecord]) -> [InvitationRecord] {
        appendingUnique(existing: [], incoming: values)
    }

    private static func appendingUnique(
        existing: [InvitationRecord],
        incoming: [InvitationRecord]
    ) -> [InvitationRecord] {
        var seen = Set(existing.map(\.id))
        var result = existing
        for value in incoming where seen.insert(value.id).inserted {
            result.append(value)
        }
        return result
    }

    private static func normalized(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func map(_ error: Error) -> InvitationCreditError {
        if let error = error as? InvitationCreditError { return error }
        return .requestFailed(message: nil)
    }
}
