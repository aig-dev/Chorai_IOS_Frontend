//
//  TrashModels.swift
//  ArcNote
//
//  Created by AI Assistant on 2025-01-27.
//

import Foundation
import Combine

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

// MARK: 回收站管理器
class TrashManager: ObservableObject {
    static let shared = TrashManager()
    
    @Published var trashCards: [TrashCard] = []
    @Published var isLoading: Bool = false
    @Published var hasMoreData: Bool = true
    @Published var currentPage: Int = 1
    @Published var error: NetworkError?
    
    private let perPage: Int = 20
    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    func loadTrashCards(refresh: Bool = false) {
        guard authManager.currentUser != nil else {
            print("用户未登录")
            self.error = .unauthorized
            return
        }
        
        if refresh {
            currentPage = 1
            trashCards = []
            hasMoreData = true
        }
        
        guard !isLoading && hasMoreData else { return }
        
        isLoading = true
        error = nil
        
        networkManager.getTrashCards(page: currentPage, perPage: perPage) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let response):
                    if refresh {
                        self?.trashCards = response.data
                    } else {
                        self?.trashCards.append(contentsOf: response.data)
                    }
                    self?.currentPage = response.page
                    self?.hasMoreData = response.page < (response.total / response.perPage + (response.total % response.perPage > 0 ? 1 : 0))
                case .failure(let error):
                    self?.error = error
                    print("回收站列表获取失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func loadMoreTrashCards() {
        guard hasMoreData && !isLoading else { return }
        currentPage += 1
        loadTrashCards()
    }
    
    func refreshTrashCards() {
        loadTrashCards(refresh: true)
    }
    
    func restoreCard(cardId: String, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        guard authManager.currentUser != nil else {
            print("用户未登录")
            completion(.failure(.unauthorized))
            return
        }
        
        networkManager.restoreCard(cardId: cardId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if response.success {
                        // 从本地列表中移除卡片
                        self?.trashCards.removeAll { $0.id == cardId }
                        print("卡片恢复成功: cardId=\(cardId)")
                        completion(.success(true))
                    } else {
                        print("卡片恢复失败: \(response.message)")
                        completion(.failure(.serverError(500, response.message)))
                    }
                case .failure(let error):
                    print("卡片恢复失败: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }
    
    func permanentlyDeleteCard(cardId: String, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        guard authManager.currentUser != nil else {
            print("用户未登录")
            completion(.failure(.unauthorized))
            return
        }
        
        networkManager.permanentlyDeleteCard(cardId: cardId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if response.success {
                        // 从本地列表中移除卡片
                        self?.trashCards.removeAll { $0.id == cardId }
                        print("卡片永久删除成功: cardId=\(cardId)")
                        completion(.success(true))
                    } else {
                        print("卡片永久删除失败: \(response.message)")
                        completion(.failure(.serverError(500, response.message)))
                    }
                case .failure(let error):
                    print("卡片永久删除失败: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }
}
