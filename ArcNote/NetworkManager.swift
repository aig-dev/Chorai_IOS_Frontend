import Foundation
import Alamofire
import Combine
import UIKit

// MARK: 网络管理器
class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    
    // MARK: 配置
    private let baseURL: String
    private let session: Session
    private var authToken: String?
    
    // MARK: 发布者
    @Published var isConnected: Bool = true
    @Published var isLoading: Bool = false
    
    // MARK: 订阅管理
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: 初始化
    private init() {
        // 根据环境设置基础URL
        #if DEBUG
        self.baseURL = "https://production.zhizuo.site"
        #else
        self.baseURL = "https://production.zhizuo.site"
        #endif
        
        // 配置Alamofire Session
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        
        configuration.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        let serverTrustPolicy = ServerTrustManager(allHostsMustBeEvaluated: false, evaluators: [:])
        self.session = Session(configuration: configuration, serverTrustManager: serverTrustPolicy)
        
        // 监听网络状态
        startNetworkMonitoring()
    }
    
    // MARK: 认证相关
    func setAuthToken(_ token: String) {
        self.authToken = token
    }
    
    func clearAuthToken() {
        self.authToken = nil
    }
    
    // MARK: 通用请求方法
    private func request<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .get,
        parameters: Parameters? = nil,
        encoding: ParameterEncoding = JSONEncoding.default,
        headers: HTTPHeaders? = nil,
        responseType: T.Type
    ) -> AnyPublisher<T, NetworkError> {
        
        return Future<T, NetworkError> { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknown))
                return
            }
            
            let url = "\(self.baseURL)\(endpoint)"
            
            print("请求URL: \(url)")
            print("请求方法: \(method.rawValue)")
            if let parameters = parameters {
                print("请求参数: \(parameters)")
            }
            
            // 构建请求头
            var requestHeaders = HTTPHeaders()
            if let token = self.authToken {
                requestHeaders.add(.authorization(bearerToken: token))
                print("认证Token: \(token)")
            }
            if let customHeaders = headers {
                for header in customHeaders {
                    requestHeaders.add(header)
                }
                print("自定义请求头: \(customHeaders)")
            }
            
            // 显示加载状态
            DispatchQueue.main.async {
                self.isLoading = true
            }
            
            // 发送请求
            self.session.request(
                url,
                method: method,
                parameters: parameters,
                encoding: encoding,
                headers: requestHeaders
            )
            .validate()
            .responseData { response in
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                
                if let httpResponse = response.response {
                    print("响应状态码: \(httpResponse.statusCode)")
                    print("响应头: \(httpResponse.allHeaderFields)")
                }
                
                switch response.result {
                case .success(let data):
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("响应数据: \(responseString)")
                    }
                    
                    do {
                        let decodedResponse = try JSONDecoder().decode(T.self, from: data)
                        print("解码成功: \(type(of: decodedResponse))")
                        promise(.success(decodedResponse))
                    } catch {
                        print("解码错误: \(error)")
                        promise(.failure(.decodingError))
                    }
                    
                case .failure(let error):
                    var responseMessage: String?
                    if let data = response.data {
                        if let responseString = String(data: data, encoding: .utf8) {
                            print("请求失败响应数据: \(responseString)")
                        }
                        responseMessage = self.extractMessage(from: data)
                    }
                    if let httpResponse = response.response {
                        print("请求失败状态码: \(httpResponse.statusCode)")
                    }
                    print("请求失败错误: \(error)")
                    
                    if let message = responseMessage, !message.isEmpty {
                        self.presentErrorAlert(message: message)
                    }
                    
                    let networkError = self.handleError(error, response: response.response)
                    promise(.failure(networkError))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    private func extractMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else { return nil }
        
        if let message = json["message"] as? String {
            return message
        }
        
        if
            let dataDict = json["data"] as? [String: Any],
            let message = dataDict["message"] as? String
        {
            return message
        }
        
        return nil
    }
    
    private func presentErrorAlert(message: String) {
        DispatchQueue.main.async {
            guard
                let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first,
                let window = windowScene.windows.first,
                let root = window.rootViewController
            else { return }
            
            let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            
            var topController = root
            while let presented = topController.presentedViewController {
                topController = presented
            }
            
            topController.present(alert, animated: true, completion: nil)
        }
    }
    
    // MARK: 带包装响应的请求方法
    private func requestWithWrapper<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .get,
        parameters: Parameters? = nil,
        encoding: ParameterEncoding = JSONEncoding.default,
        headers: HTTPHeaders? = nil,
        responseType: T.Type
    ) -> AnyPublisher<T, NetworkError> {
        return Future<T, NetworkError> { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknown))
                return
            }
            
            let url = "\(self.baseURL)\(endpoint)"
            
            print("请求URL: \(url)")
            print("请求方法: \(method.rawValue)")
            if let parameters = parameters {
                print("请求参数: \(parameters)")
            }
            
            var requestHeaders = HTTPHeaders()
            if let token = self.authToken {
                requestHeaders.add(.authorization(bearerToken: token))
                print("认证Token: \(token)")
            }
            if let customHeaders = headers {
                for header in customHeaders {
                    requestHeaders.add(header)
                }
                print("自定义请求头: \(customHeaders)")
            }
            
            DispatchQueue.main.async {
                self.isLoading = true
            }
            
            self.session.request(
                url,
                method: method,
                parameters: parameters,
                encoding: encoding,
                headers: requestHeaders
            )
            .validate()
            .responseData { response in
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                
                if let httpResponse = response.response {
                    print("响应状态码: \(httpResponse.statusCode)")
                    print("响应头: \(httpResponse.allHeaderFields)")
                }
                
                switch response.result {
                case .success(let data):
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("响应数据: \(responseString)")
                    }
                    do {
                        let wrapped = try JSONDecoder().decode(NetworkResponse<T>.self, from: data)
                        if wrapped.success {
                            if let wrappedData = wrapped.data {
                                promise(.success(wrappedData))
                            } else {
                                promise(.failure(.noData))
                            }
                        } else {
                            promise(.failure(.serverError(0, wrapped.message)))
                        }
                    } catch {
                        do {
                            let direct = try JSONDecoder().decode(T.self, from: data)
                            promise(.success(direct))
                        } catch {
                            print("解码错误: \(error)")
                            promise(.failure(.decodingError))
                        }
                    }
                case .failure(let error):
                    let networkError = self.handleError(error, response: response.response)
                    promise(.failure(networkError))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: 错误处理
    private func handleError(_ error: AFError, response: HTTPURLResponse?) -> NetworkError {
        if let statusCode = response?.statusCode {
            switch statusCode {
            case 401:
                return .unauthorized
            case 403:
                return .forbidden
            case 404:
                return .notFound
            case 400...499:
                return .serverError(statusCode, "Client Error")
            case 500...599:
                return .serverError(statusCode, "Service Error")
            default:
                return .serverError(statusCode, "Unknown Error")
            }
        }
        
        switch error {
        case .sessionTaskFailed(let error):
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    return .timeout
                case .notConnectedToInternet:
                    return .networkError(error)
                default:
                    return .networkError(error)
                }
            }
            return .networkError(error)
        default:
            return .networkError(error)
        }
    }
    
    // MARK: 网络状态监控
    private func startNetworkMonitoring() {
        let reachabilityManager = NetworkReachabilityManager()
        reachabilityManager?.startListening { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .reachable:
                    self?.isConnected = true
                case .notReachable, .unknown:
                    self?.isConnected = false
                }
            }
        }
    }
}

// MARK: 公开的请求方法
extension NetworkManager {
    
    // MARK: 认证相关API
    func login(email: String, password: String) -> AnyPublisher<AuthResponse, NetworkError> {
        let parameters: Parameters = [
            "email": email,
            "password": password
        ]
        
        return request(
            endpoint: "/api/auth/login",
            method: .post,
            parameters: parameters,
            responseType: AuthResponse.self
        )
    }
    
    func register(username: String, email: String, password: String, verificationCode: String? = nil) -> AnyPublisher<AuthResponse, NetworkError> {
        var parameters: Parameters = [
            "username": username,
            "email": email,
            "password": password
        ]
        
        if let verificationCode = verificationCode {
            parameters["verification_code"] = verificationCode
        }
        
        return request(
            endpoint: "/api/auth/register",
            method: .post,
            parameters: parameters,
            responseType: AuthResponse.self
        )
    }
    
    func sendVerificationCode(email: String) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "email": email
        ]
        
        return request(
            endpoint: "/api/auth/send-verification-code",
            method: .post,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func refreshToken() -> AnyPublisher<AuthResponse, NetworkError> {
        return request(
            endpoint: "/api/auth/refresh",
            method: .post,
            responseType: AuthResponse.self
        )
    }
    
    func appleLogin(identityToken: String, authorizationCode: String? = nil, userInfo: [String: Any]? = nil) -> AnyPublisher<AuthResponse, NetworkError> {
        var parameters: Parameters = [
            "identity_token": identityToken
        ]
        
        if let authorizationCode = authorizationCode {
            parameters["authorization_code"] = authorizationCode
        }
        if let userInfo = userInfo {
            // 将 userInfo 转换为可序列化的格式
            do {
                let userInfoData = try JSONSerialization.data(withJSONObject: userInfo)
                if let userInfoString = String(data: userInfoData, encoding: .utf8) {
                    parameters["user_info"] = userInfoString
                }
            } catch {
                print("无法序列化 userInfo: \(error)")
            }
        }
        
        return request(
            endpoint: "/api/auth/apple-login",
            method: .post,
            parameters: parameters,
            responseType: AuthResponse.self
        )
    }
    
    func googleLogin(idToken: String) -> AnyPublisher<AuthResponse, NetworkError> {
        let parameters: Parameters = [
            "id_token": idToken
        ]
        
        return request(
            endpoint: "/api/auth/google-login",
            method: .post,
            parameters: parameters,
            responseType: AuthResponse.self
        )
    }
    
    func verifyToken() -> AnyPublisher<AuthResponse, NetworkError> {
        return request(
            endpoint: "/api/auth/verify-token",
            method: .get,
            responseType: AuthResponse.self
        )
    }
    
    // MARK: 卡片相关API
    func getCards(userId: Int, page: Int = 1, perPage: Int = 20, tags: String? = nil, search: String? = nil, sortBy: String? = nil, sortOrder: String? = nil) -> AnyPublisher<UserCardsListResponse, NetworkError> {
        var parameters: Parameters = [
            "user_id": userId,
            "page": page,
            "per_page": perPage
        ]
        
        if let tags = tags { parameters["tags"] = tags }
        if let search = search { parameters["search"] = search }
        if let sortBy = sortBy { parameters["sort_by"] = sortBy }
        if let sortOrder = sortOrder { parameters["sort_order"] = sortOrder }
        
        return request(
            endpoint: "/api/cards",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: UserCardsListResponse.self
        )
    }
    
    func getCard(id: Int, userId: Int) -> AnyPublisher<CardResponse, NetworkError> {
        let parameters: Parameters = [
            "viewer_user_id": userId
        ]
        return requestWithWrapper(
            endpoint: "/api/cards/\(id)",
            method: .get,
            parameters: parameters,
            responseType: CardResponse.self
        )
    }
    
    func createCard(_ cardRequest: CreateCardRequest) -> AnyPublisher<CardResponse, NetworkError> {
        var parameters: Parameters = [
            "user_id": cardRequest.userId,
            "title": cardRequest.title ?? "",
            "content": cardRequest.content,
            "tags": cardRequest.tags ?? []
        ]
        
        if let isPublic = cardRequest.isPublic {
            parameters["is_public"] = isPublic
        }
        
        return request(
            endpoint: "/api/cards",
            method: .post,
            parameters: parameters,
            responseType: CardResponse.self
        )
    }
    
    func updateCard(id: Int, request: UpdateCardRequest) -> AnyPublisher<CardResponse, NetworkError> {
        var parameters: Parameters = [
            "user_id": request.userId
        ]
        
        if let title = request.title { parameters["title"] = title }
        parameters["content"] = request.content
        if let tags = request.tags { parameters["tags"] = tags }
        
        return requestWithWrapper(
            endpoint: "/api/cards/\(id)",
            method: .put,
            parameters: parameters,
            responseType: CardResponse.self
        )
    }
    
    func deleteCard(id: Int) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        return request(
            endpoint: "/api/cards/\(id)",
            method: .delete,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func searchCards(_ request: SearchRequest) -> AnyPublisher<SearchResponse, NetworkError> {
        var parameters: Parameters = [
            "user_id": request.userId,
            "query": request.query,
            "page": request.page ?? 1,
            "per_page": request.perPage ?? 20
        ]
        
        if let searchType = request.searchType { parameters["search_type"] = searchType }
        if let scope = request.scope { parameters["scope"] = scope }
        if let sortBy = request.sortBy { parameters["sort_by"] = sortBy }
        if let sortOrder = request.sortOrder { parameters["sort_order"] = sortOrder }
        if let tags = request.tags { parameters["tags"] = tags }
        if let dateFrom = request.dateFrom { parameters["date_from"] = dateFrom }
        if let dateTo = request.dateTo { parameters["date_to"] = dateTo }
        
        return requestWithWrapper(
            endpoint: "/api/cards/search",
            method: .get,
            parameters: parameters,
            responseType: SearchResponse.self
        )
    }
    
    func searchCardsPost(_ request: SearchRequest) -> AnyPublisher<SearchResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "query": request.query,
            "search_type": request.searchType ?? "all",
            "scope": request.scope ?? "my",
            "sort_by": request.sortBy ?? "relevance",
            "sort_order": request.sortOrder ?? "desc",
            "tags": request.tags ?? [],
            "date_from": request.dateFrom as Any,
            "date_to": request.dateTo as Any,
            "page": request.page ?? 1,
            "per_page": request.perPage ?? 20
        ]
        
        return requestWithWrapper(
            endpoint: "/api/cards/search",
            method: .post,
            parameters: parameters,
            responseType: SearchResponse.self
        )
    }
    
    func batchDeleteCards(_ request: BatchRequest) -> AnyPublisher<BatchResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "card_ids": request.cardIds
        ]
        
        return requestWithWrapper(
            endpoint: "/api/cards/batch/delete",
            method: .post,
            parameters: parameters,
            responseType: BatchResponse.self
        )
    }
    
    func batchPermanentDeleteCards(_ request: BatchRequest) -> AnyPublisher<BatchResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "card_ids": request.cardIds
        ]
        
        return requestWithWrapper(
            endpoint: "/api/cards/batch/permanent-delete",
            method: .post,
            parameters: parameters,
            responseType: BatchResponse.self
        )
    }
    
    func batchRestoreCards(_ request: BatchRequest) -> AnyPublisher<BatchResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "card_ids": request.cardIds
        ]
        
        return requestWithWrapper(
            endpoint: "/api/cards/batch/restore",
            method: .post,
            parameters: parameters,
            responseType: BatchResponse.self
        )
    }

    func cleanupExpiredTrash() -> AnyPublisher<CleanupResponse, NetworkError> {
        return requestWithWrapper(
            endpoint: "/api/cards/trash/cleanup",
            method: .post,
            responseType: CleanupResponse.self
        )
    }
    
    func permanentlyDeleteCard(cardId: Int, userId: Int) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return request(
            endpoint: "/api/cards/trash/\(cardId)/permanent",
            method: .delete,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func restoreCard(cardId: Int, request: RestoreRequest) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId
        ]
        
        return self.request(
            endpoint: "/api/cards/trash/\(cardId)/restore",
            method: .post,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    
    func mergeCardsIdeas(_ request: MergeCardsRequest) -> AnyPublisher<CardResponse, NetworkError> {
        // 将 SelectedCard 数组转换为 JSON 字符串
        let selectedCardsString: String
        do {
            let selectedCardsData = try JSONEncoder().encode(request.selectedCards)
            selectedCardsString = String(data: selectedCardsData, encoding: .utf8) ?? "[]"
        } catch {
            return Fail(error: NetworkError.encodingError)
                .eraseToAnyPublisher()
        }
        
        let parameters: Parameters = [
            "user_id": request.userId,
            "selected_cards": selectedCardsString
        ]
        
        return requestWithWrapper(
            endpoint: "/api/cards/merge-ideas",
            method: .post,
            parameters: parameters,
            responseType: CardResponse.self
        )
    }
    
    // MARK: 生成相关卡片
    func generateRelatedCards(_ request: GenerateRelatedCardsRequest) -> AnyPublisher<GenerateRelatedCardsResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "card_id": request.cardId,
            "count": request.count
        ]
        
        return self.request(
            endpoint: "/api/cards/generate-related",
            method: .post,
            parameters: parameters,
            responseType: GenerateRelatedCardsResponse.self
        )
    }
    
    // MARK: 获取合并历史
    func getMergeHistory(cardId: Int, userId: Int, type: String? = nil) -> AnyPublisher<MergeHistoryResponse, NetworkError> {
        var parameters: Parameters = [
            "user_id": userId
        ]
        
        if let type = type {
            parameters["type"] = type
        } else {
        }
        
        
        return self.request(
            endpoint: "/api/cards/\(cardId)/merge-history",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: MergeHistoryResponse.self
        )
    }
    
    // MARK: 更新卡片
    func updateCard(cardId: Int, request: UpdateCardRequest) -> AnyPublisher<NetworkResponse<CardResponse>, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "title": request.title ?? "",
            "content": request.content,
            "tags": request.tags ?? []
        ]
        
        return self.request(
            endpoint: "/api/cards/\(cardId)",
            method: .put,
            parameters: parameters,
            responseType: NetworkResponse.self
        )
    }
    
    // MARK: 获取对话列表
    func getConversations() -> AnyPublisher<ConversationsResponse, NetworkError> {
        return self.request(
            endpoint: "/api/chats/conversations",
            method: .get,
            responseType: ConversationsResponse.self
        )
    }
    
    // MARK: 发起会话
    func createConversation(request: CreateConversationRequest) -> AnyPublisher<CreateConversationResponse, NetworkError> {
        let parameters: Parameters = [
            "participant_id": request.participantId
        ]
        
        return self.request(
            endpoint: "/api/chats/conversations",
            method: .post,
            parameters: parameters,
            responseType: CreateConversationResponse.self
        )
    }
    
    // MARK: 获取聊天详情
    func getConversationDetail(conversationId: Int) -> AnyPublisher<ChatDetailResponse, NetworkError> {
        return self.request(
            endpoint: "/api/chats/conversations/\(conversationId)",
            method: .get,
            responseType: ChatDetailResponse.self
        )
    }
    
    // MARK: 获取消息列表
    func getMessages(conversationId: Int, page: Int = 1, perPage: Int = 20) -> AnyPublisher<MessagesListResponse, NetworkError> {
        
        let parameters: Parameters = [
            "page": page,
            "per_page": perPage
        ]
        
        return self.request(
            endpoint: "/api/chats/conversations/\(conversationId)/messages",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: MessagesListResponse.self
        )
    }
    
    // MARK: - 发送消息
    func sendMessage(conversationId: Int, request: SendMessageRequest) -> AnyPublisher<SendMessageResponse, NetworkError> {
        var parameters: Parameters = [
            "content": request.content
        ]
        
        if let attachedCardId = request.attachedCardId {
            parameters["attached_card_id"] = attachedCardId
        }
        
        return self.request(
            endpoint: "/api/chats/conversations/\(conversationId)/messages",
            method: .post,
            parameters: parameters,
            responseType: SendMessageResponse.self
        )
    }
    
    // MARK: - 获取兴趣类别
    func getInterests() -> AnyPublisher<InterestsResponse, NetworkError> {
        return self.request(
            endpoint: "/api/utils/interests/categories",
            method: .get,
            responseType: InterestsResponse.self
        )
    }
    
    // MARK: - 保存用户兴趣
    func saveUserInterests(request: SaveUserInterestsRequest) -> AnyPublisher<SaveUserInterestsResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "interest_ids": request.interestIds
        ]
        
        return self.request(
            endpoint: "/api/utils/interests/user",
            method: .post,
            parameters: parameters,
            responseType: SaveUserInterestsResponse.self
        )
    }
    
    func getRecommendedCards(userId: Int? = nil, limit: Int = 10, page: Int = 1) -> AnyPublisher<CardsListResponse, NetworkError> {
        var parameters: Parameters = [
            "limit": limit,
            "page": page
        ]
        
        if let userId = userId {
            parameters["user_id"] = userId
        }
        
        return request(
            endpoint: "/api/cards/recommended",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: CardsListResponse.self
        )
    }
    
    func updateCardVisibility(cardId: Int, request: UpdateVisibilityRequest) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "is_public": request.isPublic
        ]
        
        return self.request(
            endpoint: "/api/cards/\(cardId)/visibility",
            method: .put,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    

    
    // MARK: - 卡片点赞相关API
    func likeCard(cardId: Int, userId: Int) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return request(
            endpoint: "/api/cards/\(cardId)/like",
            method: .post,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func unlikeCard(cardId: Int, userId: Int) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return request(
            endpoint: "/api/cards/\(cardId)/like",
            method: .delete,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    // MARK: - 收藏相关API
    func favoriteCard(cardId: Int, userId: Int) -> AnyPublisher<NetworkResponse<FavoriteResponseData>, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId,
            "card_id": cardId
        ]
        
        return request(
            endpoint: "/api/favorites",
            method: .post,
            parameters: parameters,
            responseType: NetworkResponse<FavoriteResponseData>.self
        )
    }
    
    func unfavoriteCard(cardId: Int, userId: Int) -> AnyPublisher<NetworkResponse<UnfavoriteResponseData>, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return request(
            endpoint: "/api/favorites/\(cardId)",
            method: .delete,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: NetworkResponse<UnfavoriteResponseData>.self
        )
    }

    
    func deleteComment(commentId: Int) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        return request(
            endpoint: "/api/cards/comments/\(commentId)",
            method: .delete,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func deleteReply(replyId: Int) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        return request(
            endpoint: "/api/cards/replies/\(replyId)",
            method: .delete,
            responseType: NetworkResponse<String>.self
        )
    }
    

    
    // MARK: 卡片链接相关API
    func getUserAllLinks(userId: Int, limit: Int = 50) -> AnyPublisher<LinkResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId,
            "limit": limit
        ]
        
        return requestWithWrapper(
            endpoint: "/api/cards/links",
            method: .get,
            parameters: parameters,
            responseType: LinkResponse.self
        )
    }
    
    func getCardLinks(cardId: Int, userId: Int) -> AnyPublisher<LinkResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return requestWithWrapper(
            endpoint: "/api/cards/\(cardId)/links",
            method: .get,
            parameters: parameters,
            responseType: LinkResponse.self
        )
    }
    
    // MARK: - 获取用户所有卡片
    func getUserAllCards(userId: Int, searchType: String = "all", search: String = "", limit: Int = 20, cardId: Int? = nil) -> AnyPublisher<UserAllCardsResponse, NetworkError> {
        var parameters: Parameters = [
            "search_type": searchType,
            "search": search,
            "limit": limit,
            "user_id": userId
        ]
        
        if let cardId = cardId {
            parameters["card_id"] = cardId
        }
        
        return request(
            endpoint: "/api/cards/user-all-cards",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: UserAllCardsResponse.self
        )
    }
    
    func createCardLink(cardId: Int, reques: LinkRequest) -> AnyPublisher<LinkResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": reques.userId,
            "linked_card_id": reques.linkedCardId
        ]
        
        return request(
            endpoint: "/api/cards/\(cardId)/links",
            method: .post,
            parameters: parameters,
            responseType: LinkResponse.self
        )
    }
    
    func removeCardLink(cardId: Int, linkedCardId: Int, userId: Int) -> AnyPublisher<LinkResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return requestWithWrapper(
            endpoint: "/api/cards/\(cardId)/links/\(linkedCardId)",
            method: .delete,
            parameters: parameters,
            responseType: LinkResponse.self
        )
    }
    
    // MARK: 卡片Pin相关API
    func getUserPinnedCards(userId: Int, limit: Int = 50) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId,
            "limit": limit
        ]
        
        return requestWithWrapper(
            endpoint: "/api/cards/pins",
            method: .get,
            parameters: parameters,
            responseType: NetworkResponse.self
        )
    }
    
    func pinCard(cardId: Int, userId: Int) -> AnyPublisher<PinResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return requestWithWrapper(
            endpoint: "/api/cards/\(cardId)/pin",
            method: .post,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: PinResponse.self
        )
    }
    
    func unpinCard(cardId: Int, userId: Int) -> AnyPublisher<PinResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return requestWithWrapper(
            endpoint: "/api/cards/\(cardId)/pin",
            method: .delete,
            parameters: parameters,
            responseType: PinResponse.self
        )
    }
    
    // MARK: 标签相关API
    func getTags() -> AnyPublisher<[Tag], NetworkError> {
        return requestWithWrapper(
            endpoint: "/api/tags",
            method: .get,
            responseType: [Tag].self
        )
    }
    
    // MARK: 用户相关API
    func getUserProfile(userId: Int) -> AnyPublisher<UserResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return requestWithWrapper(
            endpoint: "/api/users/profile",
            method: .get,
            parameters: parameters,
            responseType: UserResponse.self
        )
    }
    
    func updateUserProfile(userId: Int, request: UpdateProfileRequest) -> AnyPublisher<UserResponse, NetworkError> {
        var parameters: Parameters = [
            "user_id": userId
        ]
        
        if let username = request.username { parameters["username"] = username }
        if let avatar = request.avatar { parameters["avatar"] = avatar }
        if let bio = request.bio { parameters["bio"] = bio }
        if let location = request.location { parameters["location"] = location }
        if let birthday = request.birthday { parameters["birthday"] = birthday }
        
        return requestWithWrapper(
            endpoint: "/api/users/profile",
            method: .put,
            parameters: parameters,
            responseType: UserResponse.self
        )
    }
    
    func changePassword(userId: Int, request: ChangePasswordRequest) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId,
            "old_password": request.oldPassword,
            "new_password": request.newPassword
        ]
        
        return self.request(
            endpoint: "/api/users/change-password",
            method: .post,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func getCurrentUser() -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        return request(
            endpoint: "/api/utils/user/current",
            method: .get,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func uploadAvatar(userId: Int, imageData: Data) -> AnyPublisher<AvatarUploadResponse, NetworkError> {
        return Future<AvatarUploadResponse, NetworkError> { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknown))
                return
            }
            
            let url = "\(self.baseURL)/api/users/avatar?user_id=\(userId)"
            
            var headers = HTTPHeaders()
            if let token = self.authToken {
                headers.add(.authorization(bearerToken: token))
            }
            
            DispatchQueue.main.async {
                self.isLoading = true
            }
            
            self.session.upload(
                multipartFormData: { multipartFormData in
                    multipartFormData.append(imageData, withName: "avatar", fileName: "avatar.jpg", mimeType: "image/jpeg")
                },
                to: url,
                method: .post,
                headers: headers
            )
            .validate()
            .responseData { response in
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                
                switch response.result {
                case .success(let data):
                    do {
                        let uploadResponse = try JSONDecoder().decode(AvatarUploadResponse.self, from: data)
                        promise(.success(uploadResponse))
                    } catch {
                        promise(.failure(.decodingError))
                    }
                case .failure(let error):
                    let networkError = self.handleError(error, response: response.response)
                    promise(.failure(networkError))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    func deleteAvatar(userId: Int) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return request(
            endpoint: "/api/users/avatar",
            method: .delete,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func deleteUser(userId: Int) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId,
            "reason": "Confirmed delete"
        ]
        
        return request(
            endpoint: "/api/user/delete",
            method: .post,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func updateCardVisibility(cardId: Int, userId: Int, isPublic: Bool) -> AnyPublisher<NetworkResponse<CardDetail>, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId,
            "is_public": isPublic
        ]
        
        return request(
            endpoint: "/api/cards/\(cardId)/visibility",
            method: .put,
            parameters: parameters,
            responseType: NetworkResponse<CardDetail>.self
        )
    }
    
    func getUserCredit(userId: Int) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return request(
            endpoint: "/api/users/credit",
            method: .get,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func getUserStats(userId: Int) -> AnyPublisher<StatsResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return requestWithWrapper(
            endpoint: "/api/users/stats",
            method: .get,
            parameters: parameters,
            responseType: StatsResponse.self
        )
    }
    
    func getTopUsers(limit: Int = 10) -> AnyPublisher<TopUsersResponse, NetworkError> {
        let parameters: Parameters = [
            "limit": limit
        ]
        
        return requestWithWrapper(
            endpoint: "/api/users/top",
            method: .get,
            parameters: parameters,
            responseType: TopUsersResponse.self
        )
    }
    
    
    func getFavorites(userId: Int, page: Int = 1, perPage: Int = 20) -> AnyPublisher<FavoritesResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId,
            "page": page,
            "per_page": perPage
        ]
        
        return requestWithWrapper(
            endpoint: "/api/favorites",
            method: .get,
            parameters: parameters,
            responseType: FavoritesResponse.self
        )
    }
    
    func getFavoriteCount(userId: Int) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return request(
            endpoint: "/api/favorites/count",
            method: .get,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func checkFavoriteStatus(cardIds: String, userId: Int) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "card_ids": cardIds,
            "user_id": userId
        ]
        
        return request(
            endpoint: "/api/favorites/status",
            method: .get,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func getPopularCards(limit: Int = 10) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "limit": limit
        ]
        
        return request(
            endpoint: "/api/favorites/popular",
            method: .get,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func addUserFavourite(_ request: UserFavouriteRequest) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "userid": request.userid,
            "originid": request.originid,
            "favouriteid": request.favouriteid
        ]
        
        return self.request(
            endpoint: "/api/favorites/user-favourites",
            method: .post,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func getFavouriteRelatedCards(favouriteId: Int) -> AnyPublisher<RelatedCardsResponse, NetworkError> {
        return requestWithWrapper(
            endpoint: "/api/favorites/favourites/\(favouriteId)/related",
            method: .get,
            responseType: RelatedCardsResponse.self
        )
    }
    
    // MARK: 关注相关API
    func followUser(_ request: FollowRequest) -> AnyPublisher<FollowResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "target_user_id": request.targetUserId
        ]
        
        return requestWithWrapper(
            endpoint: "/api/follows/follow",
            method: .post,
            parameters: parameters,
            responseType: FollowResponse.self
        )
    }
    
    func unfollowUser(_ request: FollowRequest) -> AnyPublisher<FollowResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "target_user_id": request.targetUserId
        ]
        
        return requestWithWrapper(
            endpoint: "/api/follows/unfollow",
            method: .post,
            parameters: parameters,
            responseType: FollowResponse.self
        )
    }
    
    func getFollowersList(userId: Int, currentUserId: Int? = nil, page: Int = 1, perPage: Int = 20) -> AnyPublisher<FollowListResponse, NetworkError> {
        var parameters: Parameters = [
            "page": page,
            "per_page": perPage
        ]
        
        if let currentUserId = currentUserId {
            parameters["current_user_id"] = currentUserId
        }
        
        return requestWithWrapper(
            endpoint: "/api/follows/followers/\(userId)",
            method: .get,
            parameters: parameters,
            responseType: FollowListResponse.self
        )
    }
    
    func getFollowingList(userId: Int, currentUserId: Int? = nil, page: Int = 1, perPage: Int = 20) -> AnyPublisher<FollowListResponse, NetworkError> {
        var parameters: Parameters = [
            "page": page,
            "per_page": perPage
        ]
        
        if let currentUserId = currentUserId {
            parameters["current_user_id"] = currentUserId
        }
        
        return requestWithWrapper(
            endpoint: "/api/follows/following/\(userId)",
            method: .get,
            parameters: parameters,
            responseType: FollowListResponse.self
        )
    }
    
    func getMutualFollows(userId: Int, targetUserId: Int) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        return request(
            endpoint: "/api/follows/mutual/\(userId)/\(targetUserId)",
            method: .get,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func checkFollowStatus(_ request: FollowStatusRequest) -> AnyPublisher<FollowStatusResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "target_user_ids": request.targetUserIds
        ]
        
        return requestWithWrapper(
            endpoint: "/api/follows/status",
            method: .post,
            parameters: parameters,
            responseType: FollowStatusResponse.self
        )
    }
    
    // MARK: - 文件上传API
    func uploadFile(data: Data, filename: String, mimeType: String, userId: Int) -> AnyPublisher<UploadResponse, NetworkError> {
        return Future<UploadResponse, NetworkError> { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknown))
                return
            }
            
            let url = "\(self.baseURL)/utils/upload"
            
            print("文件上传URL: \(url)")
            print("文件名: \(filename)")
            print("文件大小: \(data.count) bytes")
            print("MIME类型: \(mimeType)")
            
            var headers = HTTPHeaders()
            if let token = self.authToken {
                headers.add(.authorization(bearerToken: token))
                print("认证Token: \(token)")
            }
            
            DispatchQueue.main.async {
                self.isLoading = true
            }
            
            self.session.upload(
                multipartFormData: { multipartFormData in
                    multipartFormData.append(data, withName: "file", fileName: filename, mimeType: mimeType)
                    multipartFormData.append(String(userId).data(using: .utf8)!, withName: "user_id")
                },
                to: url,
                headers: headers
            )
            .validate()
            .responseData { response in
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                
                if let httpResponse = response.response {
                    print("文件上传响应状态码: \(httpResponse.statusCode)")
                }
                
                switch response.result {
                case .success(let data):
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("文件上传响应数据: \(responseString)")
                    }
                    
                    do {
                        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
                        if uploadResponse.success {
                            promise(.success(uploadResponse))
                        } else {
                            print("文件上传失败: \(uploadResponse.message ?? "未知错误")")
                            promise(.failure(.serverError(0, uploadResponse.message)))
                        }
                    } catch {
                        promise(.failure(.decodingError))
                    }
                    
                case .failure(let error):
                    let networkError = self.handleError(error, response: response.response)
                    promise(.failure(networkError))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: 通知相关API
    func getNotifications(_ request: GetNotificationsRequest) -> AnyPublisher<NotificationsResponse, NetworkError> {
        let parameters: [String: Any] = [
            "page": request.page,
            "per_page": request.perPage,
            "unread_only": request.unreadOnly,
            "user_id": request.userId
        ]
        
        return self.request(
            endpoint: "/api/notifications",
            method: .post,
            parameters: parameters,
            responseType: NotificationsResponse.self
        )
    }
    
    func markAllNotificationsRead(_ request: MarkReadRequest) -> AnyPublisher<SuccessResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId
        ]
        
        return requestWithWrapper(
            endpoint: "/api/notifications/read-all",
            method: .post,
            parameters: parameters,
            responseType: SuccessResponse.self
        )
    }
    
    func getUnreadCount(_ request: MarkReadRequest) -> AnyPublisher<UnreadCountResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId
        ]
        
        return requestWithWrapper(
            endpoint: "/api/notifications/unread-count",
            method: .post,
            parameters: parameters,
            responseType: UnreadCountResponse.self
        )
    }
    
    func deleteNotification(notificationId: Int, request: DeleteNotificationRequest) -> AnyPublisher<SuccessResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId
        ]
        
        return requestWithWrapper(
            endpoint: "/api/notifications/\(notificationId)",
            method: .delete,
            parameters: parameters,
            responseType: SuccessResponse.self
        )
    }
    
    func markNotificationRead(notificationId: Int, request: MarkReadRequest) -> AnyPublisher<SuccessResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId
        ]
        
        return requestWithWrapper(
            endpoint: "/api/notifications/\(notificationId)/read",
            method: .post,
            parameters: parameters,
            responseType: SuccessResponse.self
        )
    }
    
    // MARK: 邀请码相关API
    func getInvitationCodeStats(_ request: GetCodeStatsRequest) -> AnyPublisher<SuccessResponse, NetworkError> {
        let parameters: Parameters = [
            "invitation_code": request.invitationCode
        ]
        
        return requestWithWrapper(
            endpoint: "/api/invitations/code-stats",
            method: .post,
            parameters: parameters,
            responseType: SuccessResponse.self
        )
    }
    
    func useInvitationCode(_ request: UseInvitationRequest) -> AnyPublisher<SuccessResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "invitation_code": request.invitationCode
        ]
        
        return requestWithWrapper(
            endpoint: "/api/invitations/use",
            method: .post,
            parameters: parameters,
            responseType: SuccessResponse.self
        )
    }
    
    func getUserGroup(_ request: GetUserGroupRequest) -> AnyPublisher<SuccessResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId
        ]
        
        return requestWithWrapper(
            endpoint: "/api/invitations/user-group",
            method: .post,
            parameters: parameters,
            responseType: SuccessResponse.self
        )
    }
    
    func validateInvitationCode(_ request: ValidateInvitationRequest) -> AnyPublisher<SuccessResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "invitation_code": request.invitationCode
        ]
        
        return requestWithWrapper(
            endpoint: "/api/invitations/validate",
            method: .post,
            parameters: parameters,
            responseType: SuccessResponse.self
        )
    }
    
    // MARK: 工具相关API
    func generateCaptcha(sessionId: String) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: Parameters = [
            "session_id": sessionId
        ]
        
        return request(
            endpoint: "/api/utils/captcha",
            method: .get,
            parameters: parameters,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func verifyCaptcha() -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        return request(
            endpoint: "/api/utils/captcha/verify",
            method: .post,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func getInterestCategories() -> AnyPublisher<InterestCategoriesResponse, NetworkError> {
        return requestWithWrapper(
            endpoint: "/api/utils/interests/categories",
            method: .get,
            responseType: InterestCategoriesResponse.self
        )
    }
    
    func getUserInterests() -> AnyPublisher<InterestCategoriesResponse, NetworkError> {
        return requestWithWrapper(
            endpoint: "/api/utils/interests/user",
            method: .get,
            responseType: InterestCategoriesResponse.self
        )
    }
    
    func saveUserInterests(_ request: UserInterestsRequest) -> AnyPublisher<UserInterestsResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "interest_ids": request.interestIds
        ]
        
        return requestWithWrapper(
            endpoint: "/api/utils/interests/user",
            method: .post,
            parameters: parameters,
            responseType: UserInterestsResponse.self
        )
    }
    
    func healthCheck() -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        return request(
            endpoint: "/api/utils/system/health",
            method: .get,
            responseType: NetworkResponse<String>.self
        )
    }
    
    func getSystemInfo() -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        return request(
            endpoint: "/api/utils/system/info",
            method: .get,
            responseType: NetworkResponse<String>.self
        )
    }
    
    // MARK: 评论相关API
    func getComments(cardId: Int, page: Int = 1, perPage: Int = 20, completion: @escaping (Result<CommentListResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "per_page": perPage,
            "page": page
        ]
        
        request(
            endpoint: "/api/cards/\(cardId)/comments",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: CommentListResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    func createComment(cardId: Int, request: CreateCommentRequest, completion: @escaping (Result<CreateCommentResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "content": request.content,
            "visibility": request.visibility
        ]
        
        self.request(
            endpoint: "/api/cards/\(cardId)/comments",
            method: .post,
            parameters: parameters,
            responseType: CreateCommentResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    func likeComment(commentId: Int, request: CommentLikeRequest, completion: @escaping (Result<CommentLikeResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "user_id": request.userId
        ]
        
        self.request(
            endpoint: "/api/cards/comments/\(commentId)/like",
            method: .post,
            parameters: parameters,
            responseType: CommentLikeResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    func createReply(commentId: Int, request: CreateReplyRequest, completion: @escaping (Result<CreateReplyResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "content": request.content,
            "visibility": request.visibility
        ]
        
        self.request(
            endpoint: "/api/cards/comments/\(commentId)/replies",
            method: .post,
            parameters: parameters,
            responseType: CreateReplyResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    func getUserProfile(userId: Int, completion: @escaping (Result<UserProfileResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        self.request(
            endpoint: "/api/users/profile",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: UserProfileResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    func getFavorites(userId: Int, page: Int = 1, perPage: Int = 20, sortBy: String? = nil, sortOrder: String? = nil, completion: @escaping (Result<FavoritesListResponse, NetworkError>) -> Void) {
        var parameters: Parameters = [
            "per_page": perPage,
            "page": page,
            "user_id": userId
        ]
        
        if let sortBy = sortBy { parameters["sort_by"] = sortBy }
        if let sortOrder = sortOrder { parameters["sort_order"] = sortOrder }
        
        self.request(
            endpoint: "/api/favorites",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: FavoritesListResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    func deleteCard(cardId: Int, userId: Int, completion: @escaping (Result<DeleteCardResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        self.request(
            endpoint: "/api/cards/\(cardId)",
            method: .delete,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: DeleteCardResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: 切换卡片可见性
    func toggleCardVisibility(cardId: Int, userId: Int, isPublic: Bool, completion: @escaping (Result<ToggleCardVisibilityResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "user_id": userId,
            "is_public": isPublic
        ]
        
        self.request(
            endpoint: "/api/cards/\(cardId)/visibility",
            method: .put,
            parameters: parameters,
            responseType: ToggleCardVisibilityResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: 切换卡片置顶状态
    func toggleCardPin(cardId: Int, userId: Int, completion: @escaping (Result<ToggleCardPinResponse, NetworkError>) -> Void) {
        self.request(
            endpoint: "/api/cards/\(cardId)/pin?user_id=\(userId)",
            method: .post,
            parameters: nil,
            encoding: URLEncoding.default,
            responseType: ToggleCardPinResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: 取消卡片置顶状态
    func unpinCard(cardId: Int, userId: Int, completion: @escaping (Result<ToggleCardPinResponse, NetworkError>) -> Void) {
 
        self.request(
            endpoint: "/api/cards/\(cardId)/pin?user_id=\(userId)",
            method: .delete,
            parameters: nil,
            encoding: URLEncoding.default,
            responseType: ToggleCardPinResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: 获取回收站卡片列表
    func getTrashCards(userId: Int, page: Int = 1, perPage: Int = 20, completion: @escaping (Result<TrashListResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "per_page": perPage,
            "page": page,
            "user_id": userId
        ]
        
        self.request(
            endpoint: "/api/cards/trash",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: TrashListResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: 恢复卡片
    func restoreCard(cardId: Int, userId: Int, completion: @escaping (Result<RestoreCardResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        self.request(
            endpoint: "/api/cards/trash/\(cardId)/restore",
            method: .post,
            parameters: parameters,
            responseType: RestoreCardResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: - 永久删除卡片
    func permanentlyDeleteCard(cardId: Int, userId: Int, completion: @escaping (Result<PermanentlyDeleteCardResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        self.request(
            endpoint: "/api/cards/trash/\(cardId)/permanent",
            method: .delete,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: PermanentlyDeleteCardResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: 更新用户资料
    func updateUserProfile(
        userId: Int,
        username: String,
        avatar: String,
        bio: String,
        location: String,
        birthday: String,
        completion: @escaping (Result<UserProfileResponse, NetworkError>) -> Void
    ) {
        let parameters: Parameters = [
            "username": username,
            "avatar": avatar,
            "bio": bio,
            "location": location,
            "birthday": birthday
        ]
        
        self.request(
            endpoint: "/api/users/profile?user_id=\(userId)",
            method: .put,
            parameters: parameters,
            responseType: UserProfileResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: 搜索卡片
    func searchCards(query: String, userId: Int, page: Int = 1, perPage: Int = 20, completion: @escaping (Result<SearchResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "per_page": perPage,
            "page": page,
            "sort_order": "desc",
            "sort_by": "relevance",
            "search_type": "all",
            "query": query,
            "user_id": userId
        ]
        
        self.request(
            endpoint: "/api/cards/global-search",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: SearchResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: 获取卡片详细信息
    func getCardDetail(cardId: Int, userId: Int? = nil, completion: @escaping (Result<CardDetailResponse, NetworkError>) -> Void) {
        var parameters: Parameters = [:]
        if let userId = userId {
            parameters["user_id"] = userId
        }
        let finalParameters: Parameters? = parameters.isEmpty ? nil : parameters

        self.request(
            endpoint: "/api/cards/\(cardId)",
            method: .get,
            parameters: finalParameters,
            encoding: URLEncoding.default,
            responseType: CardDetailResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: 合并卡片预览
    func mergeCards(request: MergeCardsRequest, completion: @escaping (Result<MergePreviewResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "user_id": request.userId,
            "selected_cards": request.selectedCards.map { card in
                [
                    "id": card.id,
                    "content": card.content
                ]
            }
        ]
        
        self.request(
            endpoint: "/api/cards/merge-ideas",
            method: .post,
            parameters: parameters,
            responseType: MergePreviewResponse.self
        )
        .sink(
            receiveCompletion: { completionResult in
                if case .failure(let error) = completionResult {
                    completion(.failure(error))
                }
            },
            receiveValue: { response in
                completion(.success(response))
            }
        )
        .store(in: &cancellables)
    }
    
    // MARK: 关注相关API
    
    /// 关注用户
    func followUser(userId: Int, targetUserId: Int) -> AnyPublisher<FollowResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId,
            "target_user_id": targetUserId
        ]
        
        return self.request(
            endpoint: "/api/follows/follow",
            method: .post,
            parameters: parameters,
            responseType: FollowResponse.self
        )
    }
    
    /// 取消关注用户
    func unfollowUser(userId: Int, targetUserId: Int) -> AnyPublisher<UnfollowResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId,
            "target_user_id": targetUserId
        ]
        
        return self.request(
            endpoint: "/api/follows/unfollow",
            method: .post,
            parameters: parameters,
            responseType: UnfollowResponse.self
        )
    }
    
    /// 检查关注状态
    func checkFollowStatus(userId: Int, targetUserIds: [Int]) -> AnyPublisher<FollowStatusResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId,
            "target_user_ids": targetUserIds
        ]
        
        return self.request(
            endpoint: "/api/follows/status",
            method: .post,
            parameters: parameters,
            responseType: FollowStatusResponse.self
        )
    }
    
    /// 拉黑用户
    func blockUser(userId: Int, blockedId: Int) -> AnyPublisher<BlockUserResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId,
            "blocked_id": blockedId
        ]
        
        return self.request(
            endpoint: "/api/user-blocks/block",
            method: .post,
            parameters: parameters,
            responseType: BlockUserResponse.self
        )
    }
    
    // MARK: Apple登录API
    
    /// Apple登录
    func appleLogin(loginRequest: AppleLoginRequest) -> AnyPublisher<AuthResponse, NetworkError> {
        let nameInfo: [String: Any] = [
            "firstName": loginRequest.userInfo.name.firstName,
            "lastName": loginRequest.userInfo.name.lastName
        ]
        
        let userInfo: [String: Any] = [
            "name": nameInfo
        ]
        
        let parameters: Parameters = [
            "identity_token": loginRequest.identityToken,
            "authorization_code": loginRequest.authorizationCode,
            "user_info": userInfo
        ]
        
        return self.request(
            endpoint: "/api/auth/apple-login",
            method: .post,
            parameters: parameters,
            responseType: AuthResponse.self
        )
    }
    
    // MARK: - 卡片链接API
    
    /// 获取卡片链接
    func getCardLinks(cardId: Int, userId: Int) -> AnyPublisher<CardLinksResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": userId
        ]
        
        return self.request(
            endpoint: "/api/cards/\(cardId)/links",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: CardLinksResponse.self
        )
    }
    
    // MARK: - 确认合并API
    
    /// 确认合并卡片
    func confirmMergeCards(request: ConfirmMergeRequest) -> AnyPublisher<ConfirmMergeResponse, NetworkError> {
        let parameters: Parameters = [
            "user_id": request.userId,
            "selected_cards": request.selectedCards.map { card in
                [
                    "id": card.id,
                    "content": card.content
                ]
            },
            "merged_content": request.mergedContent
        ]
        
        return self.request(
            endpoint: "/api/cards/merge-ideas/confirm",
            method: .post,
            parameters: parameters,
            responseType: ConfirmMergeResponse.self
        )
    }
    
    
    func markNotificationsAsRead(_ request: MarkNotificationsReadRequest) -> AnyPublisher<MarkNotificationsReadResponse, NetworkError> {
        let parameters: [String: Any] = [
            "user_id": request.userId
        ]
        
        return self.request(
            endpoint: "/api/notifications/read-all",
            method: .post,
            parameters: parameters,
            responseType: MarkNotificationsReadResponse.self
        )
    }
    
    func markNotificationAsRead(notificationId: Int, userId: Int) -> AnyPublisher<MarkNotificationsReadResponse, NetworkError> {
        let parameters: [String: Any] = [
            "user_id": userId
        ]
        
        return self.request(
            endpoint: "/api/notifications/\(notificationId)/read",
            method: .post,
            parameters: parameters,
            responseType: MarkNotificationsReadResponse.self
        )
    }
    
    func getUnreadCount(userId: Int) -> AnyPublisher<UnreadCountResponse, NetworkError> {
        let parameters: [String: Any] = [
            "user_id": userId
        ]
        
        return self.request(
            endpoint: "/api/notifications/unread-count",
            method: .post,
            parameters: parameters,
            
            responseType: UnreadCountResponse.self
        )
    }
    
    // MARK: 删除卡片关联
    func deleteCardLink(cardId: Int, linkId: Int, userId: Int) -> AnyPublisher<NetworkResponse<String>, NetworkError> {
        let parameters: [String: Any] = [
            "user_id": userId
        ]
        
        return self.request(
            endpoint: "/api/cards/\(cardId)/links/\(linkId)",
            method: .delete,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: NetworkResponse<String>.self
        )
    }
}

// MARK: Card Link Data Models
struct CardLink: Codable {
    let linkId: Int
    let linkedCardId: Int
    let title: String?
    let content: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case linkId = "link_id"
        case linkedCardId = "linked_card_id"
        case title
        case content
        case createdAt = "created_at"
    }
}

struct CardLinksResponse: Codable {
    let success: Bool
    let message: String
    let data: CardLinksData
}



// MARK: 确认合并数据模型
struct ConfirmMergeRequest: Codable {
    let userId: Int
    let selectedCards: [SelectedCard]
    let mergedContent: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case selectedCards = "selected_cards"
        case mergedContent = "merged_content"
    }
}

struct ConfirmMergeResponse: Codable {
    let message: String
    let newCard: NewCard
    let remainingCredit: Int
    
    enum CodingKeys: String, CodingKey {
        case message
        case newCard = "new_card"
        case remainingCredit = "remaining_credit"
    }
}
