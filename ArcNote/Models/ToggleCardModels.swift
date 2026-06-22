//
//  ToggleCardModels.swift
//  ArcNote
//
//  Created by AI Assistant on 2025-01-27.
//

import Foundation

// MARK: 切换卡片可见性响应数据模型
struct ToggleCardVisibilityData: Codable {
    let id: String
    let isPublic: Bool
    
    enum CodingKeys: String, CodingKey {
        case asset
    }

    enum AssetKeys: String, CodingKey {
        case id = "asset_id"
        case visibility
    }

    init(id: String, isPublic: Bool) {
        self.id = id
        self.isPublic = isPublic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let asset = try container.nestedContainer(keyedBy: AssetKeys.self, forKey: .asset)
        id = try asset.decode(String.self, forKey: .id)
        isPublic = try asset.decode(String.self, forKey: .visibility) == "PUBLIC"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var asset = container.nestedContainer(keyedBy: AssetKeys.self, forKey: .asset)
        try asset.encode(id, forKey: .id)
        try asset.encode(isPublic ? "PUBLIC" : "PRIVATE", forKey: .visibility)
    }
}

// MARK: 切换卡片可见性响应模型
struct ToggleCardVisibilityResponse: Codable {
    let success: Bool
    let message: String?
    let data: ToggleCardVisibilityData
}

// MARK: 切换卡片置顶状态响应模型
typealias ToggleCardPinResponse = NetworkResponse<Card>
