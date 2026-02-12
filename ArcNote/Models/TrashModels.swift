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
    let id: Int
    let title: String?
    let content: String
    let contentHash: String?
    let isPublic: Bool
    let tags: [String]
    let createdAt: String
    let updatedAt: String
    let likeCount: Int
    let isLiked: Bool
    let deletedAt: String
    let daysInTrash: Int
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
        case daysInTrash = "days_in_trash"
        case daysRemaining = "days_remaining"
    }
}

// MARK: 回收站列表响应模型
struct TrashListResponse: Codable {
    let success: Bool
    let message: String
    let data: [TrashCard]
    let total: Int
    let page: Int
    let perPage: Int
    
    enum CodingKeys: String, CodingKey {
        case success, message, data, total, page
        case perPage = "per_page"
    }
}

// MARK: 恢复卡片响应模型
struct RestoreCardResponse: Codable {
    let success: Bool
    let message: String
}

// MARK: 永久删除卡片响应模型
struct PermanentlyDeleteCardResponse: Codable {
    let success: Bool
    let message: String
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
        guard let userId = authManager.currentUser?.id else {
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
        
        networkManager.getTrashCards(userId: userId, page: currentPage, perPage: perPage) { [weak self] result in
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
    
    func restoreCard(cardId: Int, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录")
            completion(.failure(.unauthorized))
            return
        }
        
        networkManager.restoreCard(cardId: cardId, userId: userId) { [weak self] result in
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
    
    func permanentlyDeleteCard(cardId: Int, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        guard let userId = authManager.currentUser?.id else {
            print("用户未登录")
            completion(.failure(.unauthorized))
            return
        }
        
        networkManager.permanentlyDeleteCard(cardId: cardId, userId: userId) { [weak self] result in
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
