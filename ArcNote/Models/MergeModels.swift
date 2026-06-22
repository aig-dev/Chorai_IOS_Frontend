import Foundation
import Combine

// MARK: 选择的卡片模型
struct SelectedCard {
    let id: String
    let content: String
}

// MARK: Go merge API DTOs
struct MergeSourceRef: Codable {
    let assetId: String
    let versionId: String?
}

struct MergeJobContext: Codable {
    let client: String
    let surface: String
}

struct MergeCardsRequest: Codable {
    let sources: [MergeSourceRef]
    let capability: String
    let idemKey: String
    let context: MergeJobContext

    init(selectedCards: [SelectedCard]) {
        self.sources = selectedCards.map { MergeSourceRef(assetId: $0.id, versionId: nil) }
        self.capability = "auto"
        self.idemKey = "ios-merge-\(UUID().uuidString)"
        self.context = MergeJobContext(client: "ios", surface: "merge_preview")
    }
}

struct MergeJobResponse: Codable {
    let jobId: String
    let status: String
    let capability: String
    let selectedCap: String?
    let planScore: Double?
    let artifactId: String?
    let failStage: String?
    let errorCode: String?
}

struct MergeCardDocumentDTO: Codable {
    let title: String?
    let subtitle: String?
    let blocks: [MergeBlockNodeDTO]
}

struct MergeBlockNodeDTO: Codable {
    let type: String
    let content: [MergeInlineContentDTO]?
    let children: [MergeBlockNodeDTO]?
}

struct MergeInlineContentDTO: Codable {
    let type: String?
    let text: String?
}

struct MergeArtifactResponse: Codable {
    let artifactId: String
    let jobId: String
    let capabilityId: String
    let outputKind: String
    let doc: MergeCardDocumentDTO
}

struct CommitMergeJobRequest: Codable {
    let idemKey: String
    let target: NewCardCommitTarget
}

struct NewCardCommitTarget: Codable {
    let targetType: String
    let titleOverride: String?

    init(titleOverride: String?) {
        self.targetType = "new_card"
        self.titleOverride = titleOverride
    }
}

struct MergeCommitResponse: Codable {
    let commitId: String
    let status: String
    let targetType: String
    let assetId: String?
    let versionId: String?
    let activityId: String?
    let logId: String?
    let errorCode: String?
}

extension MergeArtifactResponse {
    func toPreviewResponse() -> MergePreviewResponse {
        let now = ISO8601DateFormatter().string(from: Date())
        let plainText = doc.plainText()
        let title = doc.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newCard = NewCard(
            id: artifactId,
            title: title?.isEmpty == false ? title! : "Merged Insight",
            content: plainText.isEmpty ? "Merged insight is ready." : plainText,
            contentHash: "",
            isPublic: false,
            tags: [],
            createdAt: now,
            updatedAt: now,
            favoriteCount: 0,
            viewCount: 0,
            likeCount: 0,
            commentCount: 0,
            isFavorited: false,
            isPinned: false,
            isLiked: false,
            pinnedAt: nil,
            author: [:],
            linkedCards: LinkedCards(outgoing: [], incoming: []),
            rate: 0,
            isFollowingAuthor: false
        )

        return MergePreviewResponse(
            success: true,
            message: "Merge artifact ready",
            data: MergeCardsData(newCard: newCard, remainingCredit: 0, jobId: jobId)
        )
    }
}

extension MergeCardDocumentDTO {
    func plainText() -> String {
        let parts = blocks.flatMap { $0.plainTextLines() }
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

extension MergeBlockNodeDTO {
    func plainTextLines() -> [String] {
        let ownText = content?
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        if let ownText, !ownText.isEmpty {
            lines.append(ownText)
        }
        lines.append(contentsOf: children?.flatMap { $0.plainTextLines() } ?? [])
        return lines
    }
}

// MARK: 新卡片模型
struct NewCard {
    let id: String
    let title: String
    let content: String
    let contentHash: String
    let isPublic: Bool
    let tags: [String]
    let createdAt: String
    let updatedAt: String
    let favoriteCount: Int
    let viewCount: Int
    let likeCount: Int
    let commentCount: Int
    let isFavorited: Bool
    let isPinned: Bool
    let isLiked: Bool
    let pinnedAt: String?
    let author: [String: String] // 空对象
    let linkedCards: LinkedCards
    let rate: Int
    let isFollowingAuthor: Bool
    
}

// MARK: 链接卡片模型
struct LinkedCards {
    let outgoing: [String]
    let incoming: [String]
}

// MARK: 合并卡片响应数据模型
struct MergeCardsData {
    let newCard: NewCard
    let remainingCredit: Int
    let jobId: String?
}

// MARK: 合并预览响应模型
struct MergePreviewResponse {
    let success: Bool
    let message: String
    let data: MergeCardsData
}

// MARK: 合并卡片管理器
class MergeCardsManager: ObservableObject {
    static let shared = MergeCardsManager()
    
    @Published var isMerging: Bool = false
    @Published var mergeResult: MergeCardsData?
    @Published var error: NetworkError?
    
    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // 合并卡片预览
    func mergeCards(selectedCards: [SelectedCard], completion: @escaping (Result<MergePreviewResponse, NetworkError>) -> Void) {
        guard authManager.currentUser != nil else {
            print("用户未登录，无法合并卡片")
            completion(.failure(.unauthorized))
            return
        }

        guard selectedCards.count >= 2 else {
            completion(.failure(.serverError(400, "At least two cards are required to merge")))
            return
        }
        
        isMerging = true
        error = nil
        
        let request = MergeCardsRequest(selectedCards: selectedCards)
        
        networkManager.mergeCards(request: request) { [weak self] result in
            DispatchQueue.main.async {
                self?.isMerging = false
                switch result {
                case .success(let response):
                    print("卡片合并成功: \(response.message)")
                    completion(.success(response))
                case .failure(let error):
                    print("卡片合并失败: \(error.localizedDescription)")
                    self?.error = error
                    completion(.failure(error))
                }
            }
        }
    }
    
    // 清空合并结果
    func clearMergeResult() {
        mergeResult = nil
        error = nil
    }
}
