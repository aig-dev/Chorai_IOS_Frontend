//
//  TrashModels.swift
//  ArcNote
//
//  Created by AI Assistant on 2025-01-27.
//

import Foundation
import Combine
import CoreFlow

// MARK: 回收站卡片数据模型
struct TrashCard: Codable, Identifiable {
    let id: String
    let title: String?
    let content: String
    let contentHash: String
    let isPublic: Bool
    let tags: [String]
    let createdAt: String
    let updatedAt: String
    let likeCount: Int
    let isLiked: Bool
    let deletedAt: String
    let daysRemaining: Int
    var syncToken: String? = nil
    var isPurgePending = false

    enum CodingKeys: String, CodingKey {
        case id, title, content, tags
        case contentHash = "content_hash"
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case likeCount = "like_count"
        case isLiked = "is_liked"
        case deletedAt = "deleted_at"
        case daysRemaining = "days_remaining"
        case syncToken = "sync_token"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        isPublic = try container.decode(Bool.self, forKey: .isPublic)
        tags = try container.decode([String].self, forKey: .tags)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        isLiked = try container.decode(Bool.self, forKey: .isLiked)
        deletedAt = try container.decode(String.self, forKey: .deletedAt)
        daysRemaining = try container.decode(Int.self, forKey: .daysRemaining)
        syncToken = try container.decodeIfPresent(String.self, forKey: .syncToken)
    }
}

// MARK: 回收站列表响应模型
struct TrashListResponse: Codable {
    let success: Bool
    let message: String?
    let data: [TrashCard]
    let meta: PaginationMeta

    var total: Int { meta.total }
    var page: Int { meta.page }
    var perPage: Int { meta.perPage }

    enum CodingKeys: String, CodingKey {
        case success, message, data, meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        data = try container.decode([TrashCard].self, forKey: .data)
        meta = try container.decode(PaginationMeta.self, forKey: .meta)
    }
}

extension TrashCard {
    init(localNote note: OfflineNote) {
        let formatter = ISO8601DateFormatter()
        id = NoteLibraryStore.identifier(note)
        title = note.body.title
        content = note.body.content.replacingOccurrences(
            of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        contentHash = ""
        isPublic = note.isPublic
        tags = note.body.tags
        createdAt = formatter.string(from: note.createdAt)
        updatedAt = formatter.string(from: note.updatedAt)
        deletedAt = updatedAt
        likeCount = 0
        isLiked = false
        daysRemaining = max(0, 30 - max(0, Int(Date().timeIntervalSince(note.updatedAt) / 86_400)))
        syncToken = note.baseSyncToken
        isPurgePending = note.pendingPurge != nil
    }
}

// MARK: 回收站管理器
@MainActor
class TrashManager: ObservableObject {
    static let shared = TrashManager()
    @Published var trashCards: [TrashCard] = []
    @Published var isLoading = false
    @Published var hasMoreData = false
    @Published var currentPage = 1
    @Published var error: NetworkError?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        LocalNotesController.shared.library.$notes.sink { [weak self] notes in
            self?.present(notes)
        }.store(in: &cancellables)
    }

    private func present(_ notes: [OfflineNote]) {
        trashCards = notes.filter { $0.desiredLifecycle == .trashed }
            .sorted { $0.updatedAt > $1.updatedAt }.map(TrashCard.init(localNote:))
    }

    func loadTrashCards(refresh: Bool = false) {
        error = nil
        present(LocalNotesController.shared.library.notes)
        LocalNotesController.shared.refreshAccess()
        Task {
            isLoading = true
            defer { isLoading = false }
            await LocalNotesController.shared.library.synchronize(forceRetry: refresh)
        }
    }

    func loadMoreTrashCards() {}
    func refreshTrashCards() { loadTrashCards(refresh: true) }

    func restoreCard(cardId: String, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        Task {
            do {
                try await LocalNotesController.shared.setLifecycle(identifier: cardId, lifecycle: .active)
                completion(.success(true))
            } catch { completion(.failure(.networkError(error))) }
        }
    }

    // A manual retry confirms the retained request; no background erase queue.
    func permanentlyDeleteCard(cardId: String, baseSyncToken: String?, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        let library = LocalNotesController.shared.library
        let generation = AuthManager.shared.sessionGeneration
        guard let scope = library.scope, let baseSyncToken else {
            completion(.failure(.forbidden)); return
        }
        Task {
            do {
                let attempt = try await library.beginPurge(identifier: cardId, baseSyncToken: baseSyncToken, scope: scope)
                guard AuthManager.shared.sessionGeneration == generation else { throw CancellationError() }
                let receipt: NotePurgeWriteReceipt
                do { receipt = try await NetworkManager.shared.permanentlyDeleteNote(attempt) }
                catch let error as NetworkError {
                    guard AuthManager.shared.sessionGeneration == generation else { throw CancellationError() }
                    if case .api(let status, let reason, _) = error, let reason {
                        let removed = try await library.rejectPurge(attempt, status: status, reason: reason)
                        guard AuthManager.shared.sessionGeneration == generation else { throw CancellationError() }
                        if removed { completion(.success(true)); return }
                    }
                    throw error
                }
                guard AuthManager.shared.sessionGeneration == generation else { throw CancellationError() }
                try await library.confirmPurge(attempt, receipt: receipt)
                guard AuthManager.shared.sessionGeneration == generation else { throw CancellationError() }
                completion(.success(true))
            } catch {
                completion(.failure((error as? NetworkError) ?? .networkError(error)))
            }
        }
    }
}
