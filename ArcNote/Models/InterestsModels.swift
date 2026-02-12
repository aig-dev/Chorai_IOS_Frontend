//
//  InterestsModels.swift
//  ArcNote
//
//  Created by 海了个螺 on 2025/7/23.
//

import Foundation
import Combine

// MARK: 兴趣类别数据模型
struct InterestCategory: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let nameEn: String
    let description: String?
    let icon: String?
    let color: String?
    let isTrending: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case nameEn = "name_en"
        case description, icon, color
        case isTrending = "is_trending"
    }
}

// MARK: 兴趣类别响应模型
struct InterestsResponse: Codable {
    let success: Bool
    let message: String
    let data: [InterestCategory]
}

// MARK: 保存用户兴趣请求模型
struct SaveUserInterestsRequest: Codable {
    let userId: Int
    let interestIds: [Int]
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case interestIds = "interest_ids"
    }
}

// MARK: 保存用户兴趣响应模型
struct SaveUserInterestsResponse: Codable {
    let success: Bool
    let message: String
}

// MARK: 兴趣类别管理器
class InterestsManager: ObservableObject {
    @Published var interests: [InterestCategory] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?
    @Published var saveSuccess = false
    
    private let networkManager = NetworkManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: 获取兴趣类别
    func loadInterests() {
        
        isLoading = true
        error = nil
        
        networkManager.getInterests()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.error = error.localizedDescription
                        print("获取失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.interests = response.data
                    print("获取成功")
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 保存用户兴趣
    func saveUserInterests(userId: Int, interestIds: [Int]) {
        isSaving = true
        error = nil
        saveSuccess = false
        
        let request = SaveUserInterestsRequest(userId: userId, interestIds: interestIds)
        
        networkManager.saveUserInterests(request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isSaving = false
                    if case .failure(let error) = completion {
                        self?.error = error.localizedDescription
                        print("保存失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.saveSuccess = true
                    print("保存成功: \(response.message)")
                }
            )
            .store(in: &cancellables)
    }
}
