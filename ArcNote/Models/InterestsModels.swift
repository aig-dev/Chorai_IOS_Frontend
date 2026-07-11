//
//  InterestsModels.swift
//  ArcNote
//
//  Created by 海了个螺 on 2025/7/23.
//

import Foundation

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
