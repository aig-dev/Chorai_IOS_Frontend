//
//  ToggleCardModels.swift
//  ArcNote
//
//  Created by AI Assistant on 2025-01-27.
//

import Foundation

// MARK: 切换卡片可见性响应数据模型
struct ToggleCardVisibilityData: Codable {
    let id: Int
    let isPublic: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case isPublic = "is_public"
    }
}

// MARK: 切换卡片可见性响应模型
struct ToggleCardVisibilityResponse: Codable {
    let success: Bool
    let message: String
    let data: ToggleCardVisibilityData
}

// MARK: 切换卡片置顶状态响应数据模型
struct ToggleCardPinData: Codable {
    let cardId: Int
    let isPinned: Bool
    let pinnedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case isPinned = "is_pinned"
        case pinnedAt = "pinned_at"
    }
}

// MARK: 切换卡片置顶状态响应模型
struct ToggleCardPinResponse: Codable {
    let success: Bool
    let message: String
    let data: ToggleCardPinData
}
