import Foundation
import Combine

struct SparkHistoryResponse: Codable {
    let items: [SparkHistoryItem]
    let total: Int
    let offset: Int
    let limit: Int
}

struct SparkHistoryItem: Codable, Identifiable {
    let activityId: String
    let parentActivityId: String?
    let sourceAssetId: String
    let chainDepth: Int
    let rootActivityId: String
    let resultCount: Int
    let creditsDeducted: Int
    let createdAt: String

    var id: String { activityId }

    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case parentActivityId = "parent_activity_id"
        case sourceAssetId = "source_asset_id"
        case chainDepth = "chain_depth"
        case rootActivityId = "root_activity_id"
        case resultCount = "result_count"
        case creditsDeducted = "credits_deducted"
        case createdAt = "created_at"
    }
}

// MARK: Spark 历史管理器
class SparkHistoryManager: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var historyItems: [SparkHistoryItem] = []

    private let networkManager = NetworkManager.shared
    private var cancellables = Set<AnyCancellable>()

    func fetchSparkHistory(cardId: String) {
        isLoading = true
        error = nil

        networkManager.getSparkHistory(cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.error = error.localizedDescription
                        print("加载 Spark history 失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.historyItems = response.data?.items ?? []
                }
            )
            .store(in: &cancellables)
    }
}
