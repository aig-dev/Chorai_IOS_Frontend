import Combine
import Foundation

@MainActor
public final class CreditLedgerStore: ObservableObject {
    @Published public private(set) var actorID: String?
    @Published public private(set) var entries: [CreditLedgerEntry] = []
    @Published public private(set) var phase: InvitationCreditListPhase = .idle
    @Published public private(set) var hasMore = false
    @Published public private(set) var paginationError: InvitationCreditError?

    private let service: any CoreInvitationCreditServing
    private let pageSize: Int
    private var cursor: String?
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
        entries = []
        cursor = nil
        hasMore = false
        paginationError = nil
        guard let actorID = Self.normalized(rawActorID) else {
            self.actorID = nil
            phase = .failed(.invalidActor)
            return
        }
        self.actorID = actorID
        phase = .loading
        await fetch(cursor: nil, replacing: true)
    }

    public func loadMore() async {
        guard activeRequestID == nil,
              hasMore,
              actorID != nil,
              cursor != nil else {
            return
        }
        phase = .loadingMore
        paginationError = nil
        await fetch(cursor: cursor, replacing: false)
    }

    public func retry() async {
        if paginationError != nil {
            await loadMore()
        } else if case .failed = phase, let actorID {
            await load(actorID: actorID)
        }
    }

    private func fetch(cursor requestedCursor: String?, replacing: Bool) async {
        guard let actorID, activeRequestID == nil else { return }
        let requestID = UUID()
        let requestedGeneration = generation
        activeRequestID = requestID
        defer {
            if activeRequestID == requestID { activeRequestID = nil }
        }

        do {
            let response = try await service.ledger(
                actorID: actorID,
                cursor: requestedCursor,
                limit: pageSize
            )
            guard isCurrent(actorID, generation: requestedGeneration, requestID: requestID) else {
                return
            }
            let nextCursor = response.cursor.flatMap(Self.normalized)
            guard !response.hasMore || nextCursor != nil else {
                publishFailure(
                    .contract(code: "missing_ledger_cursor"),
                    replacing: replacing
                )
                return
            }
            guard !response.hasMore || nextCursor != requestedCursor else {
                publishFailure(
                    .contract(code: "stagnant_ledger_cursor"),
                    replacing: replacing
                )
                return
            }

            entries = replacing
                ? Self.appendingUnique(existing: [], incoming: response.entries)
                : Self.appendingUnique(existing: entries, incoming: response.entries)
            cursor = nextCursor
            hasMore = response.hasMore
            paginationError = nil
            phase = entries.isEmpty ? .empty : .ready
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
        if replacing || entries.isEmpty {
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

    private static func appendingUnique(
        existing: [CreditLedgerEntry],
        incoming: [CreditLedgerEntry]
    ) -> [CreditLedgerEntry] {
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
