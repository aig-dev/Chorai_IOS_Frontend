import Foundation
import Combine

// MARK: 更新卡片请求模型
struct UpdateCardRequest: Codable {
    let userId: Int
    let title: String?
    let content: String
    let tags: [String]?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case title, content, tags
    }
}

// MARK: 发布笔记管理器
class PublishNoteManager: ObservableObject {
    static let shared = PublishNoteManager()
    
    @Published var isPublishing = false
    @Published var publishError: String?
    
    private let networkManager = NetworkManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: 发布笔记
    func publishNote(title: String, content: String, tags: [String], userId: Int = 7, isPublic: Bool = true) {
        isPublishing = true
        publishError = nil
        
        let request = CreateCardRequest(
            userId: userId,
            title: title,
            content: content,
            tags: tags,
            isPublic: isPublic
        )
        
        networkManager.createCard(request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isPublishing = false
                    if case .failure(let error) = completion {
                        self?.publishError = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    self?.isPublishing = false
                    // 发布成功，发送通知关闭弹窗和Merge页面
                    NotificationCenter.default.post(name: .notePublished, object: response.data)
                    NotificationCenter.default.post(name: .exitMergePage, object: nil)
                }
            )
            .store(in: &cancellables)
    }
}

// MARK: 通知名称
extension Notification.Name {
    static let notePublished = Notification.Name("notePublished")
    static let exitMergePage = Notification.Name("exitMergePage")
}
