import Foundation
import CoreFlow

/// One Library presentation owns its projection; no UI, network or disk state lives here.
actor HomeCardProjectionWorker {
    private struct Row {
        let card: UserCard
        let date: Date
    }
    private var rows: [Row] = []
    private var scope: NoteStoreScope?
    private var sortBy: String?
    private var ascending = false
    private let formatter = ISO8601DateFormatter()
    private let beforeWork: (@Sendable () async -> Void)?
    private let probe: (@Sendable () -> Void)?

    init(beforeWork: (@Sendable () async -> Void)? = nil, probe: (@Sendable () -> Void)? = nil) {
        self.beforeWork = beforeWork
        self.probe = probe
    }

    func reset(notes: [OfflineNote], scope: NoteStoreScope?, sortBy: String?, sortOrder: String?) async -> [UserCard] {
        await beforeWork?()
        probe?()
        self.scope = scope
        self.sortBy = sortBy
        ascending = sortOrder == "asc"
        guard scope != nil else { rows = []; return [] }
        rows = notes.filter { $0.desiredLifecycle == .active }.map(row).sorted(by: precedes)
        return rows.map(\.card)
    }

    func update(changed: [OfflineNote], removed: Set<String>) async -> [UserCard] {
        await beforeWork?()
        probe?()
        guard scope != nil else { return [] }
        let latest = Dictionary(changed.map { ($0.localID, $0) }, uniquingKeysWith: { _, new in new })
        let affected = Set(latest.keys).union(removed).map { "local-note:" + $0 }
        let ids = Set(affected)
        let unchanged = rows.filter { !ids.contains($0.card.id) }
        let replacements = latest.values.filter { $0.desiredLifecycle == .active && !removed.contains($0.localID) }
            .map(row).sorted(by: precedes)
        var merged: [Row] = []
        merged.reserveCapacity(unchanged.count + replacements.count)
        var old = 0, new = 0
        while old < unchanged.count && new < replacements.count {
            if precedes(replacements[new], unchanged[old]) { merged.append(replacements[new]); new += 1 }
            else { merged.append(unchanged[old]); old += 1 }
        }
        merged.append(contentsOf: unchanged[old...])
        merged.append(contentsOf: replacements[new...])
        rows = merged
        return rows.map(\.card)
    }

    private func row(_ note: OfflineNote) -> Row {
        let card = UserCard(id: NoteLibraryStore.identifier(note), title: note.body.title, content: note.body.content,
            contentJSON: note.body.contentJSON, backgroundMediaRef: note.backgroundMediaRef, contentHash: "",
            isPublic: note.isPublic, tags: note.body.tags, createdAt: formatter.string(from: note.createdAt),
            updatedAt: formatter.string(from: note.updatedAt), likeCount: 0, commentCount: nil, isLiked: false,
            isPinned: note.isPinned ?? false, pinnedAt: nil, isFavorited: nil, favoriteCount: nil, rate: 0,
            ownerActorId: scope?.actorID, isOwner: true,
            localPreviewIdentity: scope.map { .init(scope: $0, bodyRevision: note.bodyRevision) })
        return Row(card: card, date: sortBy == "created_at" ? note.createdAt : note.updatedAt)
    }

    private func precedes(_ lhs: Row, _ rhs: Row) -> Bool {
        if lhs.card.isPinned != rhs.card.isPinned { return lhs.card.isPinned }
        if lhs.date == rhs.date { return lhs.card.id < rhs.card.id }
        return ascending ? lhs.date < rhs.date : lhs.date > rhs.date
    }
}
