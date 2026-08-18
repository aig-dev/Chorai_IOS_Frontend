import Foundation
import Combine
import CoreFlow

// MARK: 选择的卡片模型
struct SelectedCard {
    let id: String
    let versionID: String
    let content: String
}

// MARK: Go merge API DTOs
struct MergeSourceRef: Codable {
    let assetId: String
    let versionId: String
}

struct MergeCardsRequest: Codable {
    let sources: [MergeSourceRef]
    let idemKey: String

    init(selectedCards: [SelectedCard]) {
        self.sources = selectedCards.map {
            MergeSourceRef(assetId: $0.id, versionId: $0.versionID)
        }
        self.idemKey = "ios-merge-\(UUID().uuidString)"
    }

    init(
        sources: [MergeSourceRef],
        idemKey: String
    ) {
        self.sources = sources
        self.idemKey = idemKey
    }
}

struct MergeJobResponse: Codable {
    let schemaVersion: String
    let jobId: String
    let status: String
    let route: String
    let surpriseKind: String
    let artifactId: String
}

typealias MergeCardDocumentDTO = CoreFlow.MergeCardDocumentDTO
typealias MergeBlockNodeDTO = CoreFlow.MergeBlockNodeDTO
typealias MergeArtifactResponse = CoreFlow.MergeArtifactResponseDTO
typealias MergeArtifactPresentationDTO = CoreFlow.MergeArtifactPresentation

struct MergeArtifactSaveRequestDTO {
    let baseRevision: Int
    let baseHash: String
    let idemKey: String
    let documentJSON: Data
    let tags: [String]

    init(
        baseRevision: Int,
        baseHash: String,
        idemKey: String,
        documentJSON: Data,
        tags: [String]
    ) throws {
        self.baseRevision = baseRevision
        self.baseHash = baseHash
        self.idemKey = idemKey
        let editable = try MergeArtifactEditorCodec.decode(
            cardDocumentJSON: documentJSON
        )
        self.documentJSON = try MergeArtifactEditorCodec.encode(
            blockNoteJSON: editable.blockNoteJSON,
            preserving: editable.preservationManifest
        )
        self.tags = tags
    }

    func canonicalBody() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        var body = Data(#"{"baseHash":"#.utf8)
        body.append(try encoder.encode(baseHash))
        body.append(Data(",\"baseRevision\":".utf8))
        body.append(Data(String(baseRevision).utf8))
        body.append(Data(",\"doc\":".utf8))
        body.append(documentJSON)
        body.append(Data(",\"idemKey\":".utf8))
        body.append(try encoder.encode(idemKey))
        body.append(Data(",\"tags\":".utf8))
        body.append(try encoder.encode(tags))
        body.append(Data("}".utf8))
        return body
    }
}

struct MergeArtifactSaveResponse: Codable {
    let schemaVersion: String
    let artifactId: String
    let revision: Int
    let docHash: String
    let presentationHash: String
    let presentation: MergeArtifactPresentationDTO
    let validationStatus: String
    let validationErrors: [String]
}

struct CommitMergeJobRequest: Codable {
    let revision: Int
    let artifactHash: String
    let idemKey: String
}

struct CancelMergeJobRequest: Codable {
    let idemKey: String
}

struct MergeCommitResponse: Codable {
    let schemaVersion: String
    let commitId: String
    let jobId: String
    let artifactId: String
    let revision: Int
    let artifactHash: String
    let projectionContract: String
    let noteAssetId: String
    let assetVersionId: String
    let noteDocumentVersionId: String
    let noteDocHash: String
    let activityId: String
    let actionLogId: String
}

struct MergeCapabilityDTO: Codable {
    let capabilityId: String
    let displayName: String?
    let outputKind: String
    let blockExport: Bool
    let slotCommit: Bool
    let enabled: Bool
    let rolloutStage: String?
}

struct MergeCapabilitiesResponse: Codable {
    let capabilities: [MergeCapabilityDTO]
}

extension MergeArtifactResponse {
    func toPreviewResponse() -> MergePreviewResponse {
        let now = ISO8601DateFormatter().string(from: Date())
        let plainText = document.plainText()
        let newCard = NewCard(
            id: artifactID,
            title: "Merged Insight",
            content: plainText.isEmpty ? "Merged insight is ready." : plainText,
            contentHash: "",
            isPublic: false,
            tags: presentation.tags,
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
            rate: presentation.rate,
            isFollowingAuthor: false
        )

        return MergePreviewResponse(
            success: true,
            message: "Merge artifact ready",
            data: MergeCardsData(newCard: newCard, remainingCredit: 0, jobId: jobID)
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
            .compactMap(\.textValue)
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
