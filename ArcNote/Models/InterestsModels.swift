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
    let id: String
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

    init(domain: String) {
        self.id = domain
        self.name = domain
        self.nameEn = domain
        self.description = nil
        self.icon = nil
        self.color = nil
        self.isTrending = false
    }
}

// MARK: 兴趣类别响应模型
struct InterestsResponse: Codable {
    let success: Bool
    let message: String?
    let data: [InterestCategory]

    enum CodingKeys: String, CodingKey {
        case success, message, data
    }

    enum DataKeys: String, CodingKey {
        case domains
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        let dataContainer = try container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        data = try dataContainer.decode([String].self, forKey: .domains).map(InterestCategory.init(domain:))
    }
}

// MARK: 保存用户兴趣请求模型
struct SaveUserInterestsRequest: Codable {
    let domains: [String]
    
    enum CodingKeys: String, CodingKey {
        case domains
    }
}

// MARK: 保存用户兴趣响应模型
struct SaveUserInterestsResponse: Codable {
    let success: Bool
    let message: String?
    let data: InterestDomainsData
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
    func saveUserInterests(domains: [String]) {
        isSaving = true
        error = nil
        saveSuccess = false
        
        let request = SaveUserInterestsRequest(domains: domains)
        
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
                    print("保存成功: \(response.message ?? "OK")")
                }
            )
            .store(in: &cancellables)
    }
}
