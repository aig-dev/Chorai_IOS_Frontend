import Foundation
import Alamofire
import Combine
import CoreFlow
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
        self.baseURL = APIConfiguration.baseURL

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

    private func authorizedHeaders(extra customHeaders: HTTPHeaders? = nil) -> HTTPHeaders {
        var requestHeaders: HTTPHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]

        if let token = self.authToken, !token.isEmpty {
            requestHeaders.add(.authorization(bearerToken: token))
            print("认证Token: <redacted>")
        }

        if let customHeaders = customHeaders {
            for header in customHeaders {
                requestHeaders.update(header)
            }
            print("自定义请求头: \(customHeaders)")
        }

        return requestHeaders
    }

    private func encodedParameters<T: Encodable>(_ value: T) throws -> Parameters {
        let data = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? Parameters else {
            throw NetworkError.encodingError
        }
        return object
    }

    // MARK: 通用请求方法
    private func request<T: Codable>(
        endpoint: String,
        method: HTTPMethod = .get,
        parameters: Parameters? = nil,
        encoding: ParameterEncoding = JSONEncoding.default,
        headers: HTTPHeaders? = nil,
        responseType: T.Type,
        presentsError: Bool = true,
        suppressesPayloadLogging: Bool = false
    ) -> AnyPublisher<T, NetworkError> {

        return Future<T, NetworkError> { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknown))
                return
            }

            let url = "\(self.baseURL)\(endpoint)"

            print("请求URL: \(url)")
            print("请求方法: \(method.rawValue)")
            if let description = Self.payloadLogDescription(
                parameters: parameters,
                suppressesPayloadLogging: suppressesPayloadLogging
            ) {
                print("请求参数: \(description)")
            }

            let requestHeaders = self.authorizedHeaders(extra: headers)

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
                    if Self.shouldLogPayload(
                        suppressesPayloadLogging: suppressesPayloadLogging
                    ) {
                        self.logResponseData(data, label: "响应数据")
                    } else {
                        print("响应数据: <redacted>")
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
                    var apiError: GoAPIErrorPayload?
                    if let data = response.data {
                        if Self.shouldLogPayload(
                            suppressesPayloadLogging: suppressesPayloadLogging
                        ) {
                            self.logResponseData(data, label: "请求失败响应数据")
                        } else {
                            print("请求失败响应数据: <redacted>")
                        }
                        apiError = try? JSONDecoder().decode(GoAPIErrorEnvelope.self, from: data).error
                        if apiError == nil {
                            apiError = try? JSONDecoder().decode(
                                GoAPIErrorPayload.self,
                                from: data
                            )
                        }
                        responseMessage = apiError?.message ?? self.extractMessage(from: data)
                    }
                    if let httpResponse = response.response {
                        print("请求失败状态码: \(httpResponse.statusCode)")
                    }
                    print("请求失败错误: \(error)")

                    let statusCode = response.response?.statusCode
                    let isStaleUnauthorizedRequest = statusCode == 401
                        && self.authToken == nil
                    if presentsError,
                       !isStaleUnauthorizedRequest,
                       let message = responseMessage,
                       !message.isEmpty {
                        self.presentErrorAlert(message: message)
                    }

                    let networkError: NetworkError
                    if statusCode == 401 {
                        networkError = .unauthorized
                    } else if let statusCode, (400...599).contains(statusCode), let apiError {
                        networkError = .api(
                            statusCode: statusCode,
                            code: apiError.code,
                            message: apiError.message
                        )
                    } else {
                        networkError = self.handleError(error, response: response.response)
                    }
                    promise(.failure(networkError))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    static func payloadLogDescription(
        parameters: [String: Any]?,
        suppressesPayloadLogging: Bool
    ) -> String? {
        guard let parameters else { return nil }
        return suppressesPayloadLogging ? "<redacted>" : String(describing: parameters)
    }

    static func shouldLogPayload(
        suppressesPayloadLogging: Bool
    ) -> Bool {
        !suppressesPayloadLogging
    }

    private static func appendAccessPair(
        code: String?,
        key: String?,
        to parameters: inout Parameters
    ) {
        guard let pair = AuthAccessPair(code: code, idempotencyKey: key) else {
            return
        }
        pair.requestFields.forEach { field, value in
            parameters[field] = value
        }
    }

    private func requestData(
        endpoint: String,
        method: HTTPMethod = .get,
        parameters: Parameters? = nil,
        encoding: ParameterEncoding = URLEncoding.default,
        accept: String = "application/octet-stream",
        presentsError: Bool = true
    ) -> AnyPublisher<Data, NetworkError> {
        Future<Data, NetworkError> { [weak self] promise in
            guard let self else {
                promise(.failure(.unknown))
                return
            }

            var requestHeaders = self.authorizedHeaders()
            requestHeaders.update(
                HTTPHeader(name: "Accept", value: accept)
            )
            self.session.request(
                "\(self.baseURL)\(endpoint)",
                method: method,
                parameters: parameters,
                encoding: encoding,
                headers: requestHeaders
            )
            .validate()
            .responseData { response in
                switch response.result {
                case .success(let data):
                    promise(.success(data))
                case .failure(let error):
                    var apiError: GoAPIErrorPayload?
                    if let data = response.data {
                        apiError = try? JSONDecoder()
                            .decode(GoAPIErrorEnvelope.self, from: data)
                            .error
                        if apiError == nil {
                            apiError = try? JSONDecoder().decode(
                                GoAPIErrorPayload.self,
                                from: data
                            )
                        }
                    }

                    let statusCode = response.response?.statusCode
                    if presentsError, let message = apiError?.message {
                        self.presentErrorAlert(message: message)
                    }

                    if statusCode == 401 {
                        promise(.failure(.unauthorized))
                    } else if statusCode == 403 {
                        promise(.failure(.forbidden))
                    } else if statusCode == 404 {
                        promise(.failure(.notFound))
                    } else if let statusCode,
                              let apiError,
                              (400...599).contains(statusCode) {
                        promise(
                            .failure(
                                .api(
                                    statusCode: statusCode,
                                    code: apiError.code,
                                    message: apiError.message
                                )
                            )
                        )
                    } else {
                        promise(
                            .failure(
                                self.handleError(
                                    error,
                                    response: response.response
                                )
                            )
                        )
                    }
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

    private func logResponseData(_ data: Data, label: String) {
#if DEBUG
        guard let responseString = String(data: data, encoding: .utf8) else {
            print("\(label): <non-utf8 \(data.count) bytes>")
            return
        }

        let isSmokeRun = ProcessInfo.processInfo.environment["CHORAI_API_SMOKE"] == "1"
        let limit = isSmokeRun ? 1200 : 12000
        if responseString.count > limit {
            print("\(label): \(String(responseString.prefix(limit)))... <truncated \(data.count) bytes>")
        } else {
            print("\(label): \(responseString)")
        }
#else
        _ = data
        _ = label
#endif
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

        return self.request(
            endpoint: "/api/auth/login",
            method: .post,
            parameters: parameters,
            responseType: AuthResponse.self,
            suppressesPayloadLogging: true
        )
    }

    func register(
        username: String,
        email: String,
        password: String,
        verificationCode: String? = nil,
        accessCode: String? = nil,
        idempotencyKey: String? = nil
    ) -> AnyPublisher<AuthResponse, NetworkError> {
        var parameters: Parameters = [
            "username": username,
            "email": email,
            "password": password
        ]

        if let verificationCode = verificationCode {
            parameters["verification_code"] = verificationCode
        }
        Self.appendAccessPair(
            code: accessCode,
            key: idempotencyKey,
            to: &parameters
        )

        return self.request(
            endpoint: "/api/auth/register",
            method: .post,
            parameters: parameters,
            responseType: AuthResponse.self,
            suppressesPayloadLogging: true
        )
    }

    func sendVerificationCode(email: String) -> AnyPublisher<SendVerificationCodeResponse, NetworkError> {
        let parameters: Parameters = [
            "email": email
        ]

        return request(
            endpoint: "/api/auth/send-verification-code",
            method: .post,
            parameters: parameters,
            responseType: SendVerificationCodeResponse.self
        )
    }

    func googleLogin(
        idToken: String,
        accessCode: String? = nil,
        idempotencyKey: String? = nil
    ) -> AnyPublisher<AuthResponse, NetworkError> {
        var parameters: Parameters = [
            "id_token": idToken
        ]
        Self.appendAccessPair(
            code: accessCode,
            key: idempotencyKey,
            to: &parameters
        )

        return request(
            endpoint: "/api/auth/google-login",
            method: .post,
            parameters: parameters,
            responseType: AuthResponse.self,
            suppressesPayloadLogging: true
        )
    }

    func verifyToken(
        presentsError: Bool = true
    ) -> AnyPublisher<VerifyTokenResponse, NetworkError> {
        return request(
            endpoint: "/api/auth/verify-token",
            method: .get,
            responseType: VerifyTokenResponse.self,
            presentsError: presentsError
        )
    }

    func logoutCurrentSession(
        presentsError: Bool = false
    ) -> AnyPublisher<AuthActionResponse, NetworkError> {
        request(
            endpoint: "/api/auth/logout",
            method: .post,
            responseType: AuthActionResponse.self,
            presentsError: presentsError
        )
    }

    func getAccess() -> AnyPublisher<AccessResponse, NetworkError> {
        request(
            endpoint: APIEnvironment.AccessRoute.state,
            responseType: AccessResponse.self,
            presentsError: false
        )
    }

    func claimAccess(
        _ input: ClaimInput
    ) -> AnyPublisher<ClaimResponse, NetworkError> {
        let parameters: Parameters = [
            "access_code": input.accessCode,
            "idempotency_key": input.idempotencyKey,
        ]
        return request(
            endpoint: APIEnvironment.AccessRoute.claim,
            method: .post,
            parameters: parameters,
            responseType: ClaimResponse.self,
            presentsError: false,
            suppressesPayloadLogging: true
        )
    }

    func resolveCampaign() -> AnyPublisher<CampaignResponse, NetworkError> {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
        return request(
            endpoint: APIEnvironment.AccessRoute.campaign,
            parameters: ["platform": "ios", "version": version],
            encoding: URLEncoding.default,
            responseType: CampaignResponse.self,
            presentsError: false
        )
    }

    // MARK: 卡片相关API
    func getCards(page: Int = 1, perPage: Int = 20, tags: String? = nil, search: String? = nil, sortBy: String? = nil, sortOrder: String? = nil) -> AnyPublisher<UserCardsListResponse, NetworkError> {
        var parameters: Parameters = [
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

    func getPublicProfileCards(actorId: String, page: Int = 1, perPage: Int = 20) -> AnyPublisher<UserCardsListResponse, NetworkError> {
        let parameters: Parameters = [
            "page": page,
            "per_page": perPage
        ]

        return request(
            endpoint: "/api/v1/profile/\(actorId)/cards",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: UserCardsListResponse.self
        )
    }

    func getCard(id: String) -> AnyPublisher<CardResponse, NetworkError> {
        return request(
            endpoint: "/api/cards/\(id)",
            method: .get,
            responseType: CardResponse.self
        )
    }

    func createCard(
        _ cardRequest: CreateCardRequest,
        idempotencyKey: String? = nil
    ) -> AnyPublisher<CardResponse, NetworkError> {
        var parameters: Parameters = [
            "content": cardRequest.content,
            "tags": cardRequest.tags ?? []
        ]

        addCardEditingTitle(cardRequest.title, to: &parameters)

        if let isPublic = cardRequest.isPublic {
            parameters["is_public"] = isPublic
        }
        addStructuredEditorParameters(
            contentJSON: cardRequest.contentJSON,
            editorAtmosphere: cardRequest.editorAtmosphere,
            to: &parameters
        )

        return request(
            endpoint: "/api/cards",
            method: .post,
            parameters: parameters,
            headers: idempotencyKey.map { ["Idempotency-Key": $0] },
            responseType: CardResponse.self
        )
    }

    func updateCard(id: String, request: UpdateCardRequest) -> AnyPublisher<CardResponse, NetworkError> {
        var parameters: Parameters = [:]

        addCardEditingTitle(request.title, to: &parameters)
        parameters["content"] = request.content
        if let tags = request.tags { parameters["tags"] = tags }
        addStructuredEditorParameters(
            contentJSON: request.contentJSON,
            editorAtmosphere: request.editorAtmosphere,
            to: &parameters
        )

        return self.request(
            endpoint: "/api/cards/\(id)",
            method: .put,
            parameters: parameters,
            responseType: CardResponse.self
        )
    }

    func deleteCard(id: String) -> AnyPublisher<NetworkResponse<CardMessageData>, NetworkError> {
        return request(
            endpoint: "/api/cards/\(id)",
            method: .delete,
            responseType: NetworkResponse<CardMessageData>.self
        )
    }

    func searchCards(_ request: SearchRequest) -> AnyPublisher<SearchResponse, NetworkError> {
        var parameters: Parameters = [
            "search": request.query,
            "page": request.page ?? 1,
            "per_page": request.perPage ?? 20
        ]

        if let sortBy = request.sortBy { parameters["sort_by"] = sortBy }
        if let sortOrder = request.sortOrder { parameters["sort_order"] = sortOrder }
        if let tags = request.tags, !tags.isEmpty {
            parameters["tags"] = tags.joined(separator: ",")
        }

        return self.request(
            endpoint: "/api/cards",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: SearchResponse.self
        )
    }
    func permanentlyDeleteCard(cardId: String) -> AnyPublisher<NetworkResponse<CardMessageData>, NetworkError> {
        return request(
            endpoint: "/api/cards/trash/\(cardId)/permanent",
            method: .delete,
            responseType: NetworkResponse<CardMessageData>.self
        )
    }

    func restoreCard(cardId: String) -> AnyPublisher<NetworkResponse<CreateCardData>, NetworkError> {
        return self.request(
            endpoint: "/api/cards/trash/\(cardId)/restore",
            method: .post,
            responseType: NetworkResponse<CreateCardData>.self
        )
    }
    // MARK: 生成相关卡片
    func generateRelatedCards(cardId: String) -> AnyPublisher<GenerateRelatedCardsResponse, NetworkError> {
        return self.request(
            endpoint: "/api/v1/assets/\(cardId)/spark",
            method: .post,
            responseType: GenerateRelatedCardsResponse.self
        )
    }

    func triggerSpark(cardId: String, parentActivityId: String?) -> AnyPublisher<NetworkResponse<SparkRunData>, NetworkError> {
        let parameters = parentActivityId.map { ["parent_activity_id": $0] }

        return self.request(
            endpoint: "/api/v1/assets/\(cardId)/spark",
            method: .post,
            parameters: parameters,
            responseType: NetworkResponse<SparkRunData>.self,
            presentsError: false
        )
    }

    func getSparkCard(id: String) -> AnyPublisher<NetworkResponse<RelatedCard>, NetworkError> {
        return self.request(
            endpoint: "/api/cards/\(id)",
            method: .get,
            responseType: NetworkResponse<RelatedCard>.self,
            presentsError: false
        )
    }

    func getSparkHistory(cardId: String, offset: Int = 0, limit: Int = 20) -> AnyPublisher<NetworkResponse<SparkHistoryResponse>, NetworkError> {
        let parameters: Parameters = [
            "offset": offset,
            "limit": limit
        ]

        return self.request(
            endpoint: "/api/v1/assets/\(cardId)/spark/history",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: NetworkResponse<SparkHistoryResponse>.self,
            presentsError: false
        )
    }

    func getSparkMore(cardId: String, cursor: String? = nil, limit: Int = 20) -> AnyPublisher<NetworkResponse<SparkMoreResponse>, NetworkError> {
        var parameters: Parameters = [
            "limit": limit
        ]
        if let cursor = cursor, !cursor.isEmpty {
            parameters["cursor"] = cursor
        }

        return self.request(
            endpoint: "/api/v1/assets/\(cardId)/spark/more",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: NetworkResponse<SparkMoreResponse>.self,
            presentsError: false
        )
    }

    func getSparkActivityResults(activityId: String) -> AnyPublisher<NetworkResponse<SparkActivityResultsResponse>, NetworkError> {
        return self.request(
            endpoint: "/api/v1/spark/activities/\(activityId)/results",
            method: .get,
            encoding: URLEncoding.default,
            responseType: NetworkResponse<SparkActivityResultsResponse>.self,
            presentsError: false
        )
    }

    // MARK: 更新卡片
    func updateCard(cardId: String, request: UpdateCardRequest) -> AnyPublisher<CardResponse, NetworkError> {
        var parameters: Parameters = [
            "content": request.content,
            "tags": request.tags ?? []
        ]
        addCardEditingTitle(request.title, to: &parameters)
        addStructuredEditorParameters(
            contentJSON: request.contentJSON,
            editorAtmosphere: request.editorAtmosphere,
            to: &parameters
        )

        return self.request(
            endpoint: "/api/cards/\(cardId)",
            method: .put,
            parameters: parameters,
            responseType: CardResponse.self
        )
    }

    func updateCardForEditing(
        cardId: String,
        title: String?,
        content: String,
        contentJSON: String? = nil,
        editorAtmosphere: String? = nil,
        tags: [String],
        isPublic: Bool
    ) -> AnyPublisher<CardResponse, NetworkError> {
        var parameters: Parameters = [
            "content": content,
            "tags": tags,
            "is_public": isPublic
        ]
        addCardEditingTitle(title, to: &parameters)
        addStructuredEditorParameters(
            contentJSON: contentJSON,
            editorAtmosphere: editorAtmosphere,
            to: &parameters
        )

        return request(
            endpoint: "/api/cards/\(cardId)",
            method: .put,
            parameters: parameters,
            responseType: CardResponse.self,
            presentsError: false
        )
    }

    private func addCardEditingTitle(
        _ value: String?,
        to parameters: inout Parameters
    ) {
        guard let title = CardEditingTitle.normalized(value) else { return }
        parameters["title"] = title
    }

    private func addStructuredEditorParameters(
        contentJSON: String?,
        editorAtmosphere: String?,
        to parameters: inout Parameters
    ) {
        if let contentJSON,
           !contentJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parameters["content_json"] = contentJSON
        }
        if let editorAtmosphere {
            parameters["editor_atmosphere"] = editorAtmosphere
        }
    }

    func updateCardBackground(
        cardId: String,
        mediaRef: String
    ) -> AnyPublisher<CardResponse, NetworkError> {
        request(
            endpoint: "/api/cards/\(cardId)/background",
            method: .patch,
            parameters: ["background_media_ref": mediaRef],
            responseType: CardResponse.self,
            presentsError: false
        )
    }

    func clearCardBackground(
        cardId: String
    ) -> AnyPublisher<CardResponse, NetworkError> {
        request(
            endpoint: "/api/cards/\(cardId)/background",
            method: .delete,
            responseType: CardResponse.self,
            presentsError: false
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
            "participant_actor_id": request.participantId
        ]

        return self.request(
            endpoint: "/api/chats/conversations",
            method: .post,
            parameters: parameters,
            responseType: CreateConversationResponse.self
        )
    }

    // MARK: 获取聊天详情
    func getConversationDetail(conversationId: String) -> AnyPublisher<ChatDetailResponse, NetworkError> {
        return self.request(
            endpoint: "/api/chats/conversations/\(conversationId)",
            method: .get,
            responseType: ChatDetailResponse.self
        )
    }

    // MARK: 获取消息列表
    func getMessages(conversationId: String, page: Int = 1, perPage: Int = 20) -> AnyPublisher<MessagesListResponse, NetworkError> {

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
    func sendMessage(conversationId: String, request: SendMessageRequest) -> AnyPublisher<SendMessageResponse, NetworkError> {
        var parameters: Parameters = [
            "content": request.content,
            "message_type": "text"
        ]

        if let attachedCardId = request.attachedCardId {
            parameters["referenced_asset_id"] = attachedCardId
        }

        return self.request(
            endpoint: "/api/chats/conversations/\(conversationId)/messages",
            method: .post,
            parameters: parameters,
            headers: ["Idempotency-Key": UUID().uuidString],
            responseType: SendMessageResponse.self
        )
    }

    // MARK: - 获取兴趣类别
    func getInterests(
        presentsError: Bool = true
    ) -> AnyPublisher<InterestsResponse, NetworkError> {
        return self.request(
            endpoint: "/api/v1/profile/interests/options",
            method: .get,
            responseType: InterestsResponse.self,
            presentsError: presentsError
        )
    }

    // MARK: - 获取当前用户兴趣
    func getUserInterests(
        presentsError: Bool = true
    ) -> AnyPublisher<SaveUserInterestsResponse, NetworkError> {
        self.request(
            endpoint: "/api/v1/profile/interests",
            method: .get,
            responseType: SaveUserInterestsResponse.self,
            presentsError: presentsError
        )
    }

    // MARK: - 保存用户兴趣
    func saveUserInterests(
        request: SaveUserInterestsRequest,
        presentsError: Bool = true
    ) -> AnyPublisher<SaveUserInterestsResponse, NetworkError> {
        let parameters: Parameters = [
            "domains": request.domains
        ]

        return self.request(
            endpoint: "/api/v1/profile/interests",
            method: .put,
            parameters: parameters,
            responseType: SaveUserInterestsResponse.self,
            presentsError: presentsError
        )
    }

    func getRecommendedCards(limit: Int = 10, refreshToken: String? = nil) -> AnyPublisher<CardsListResponse, NetworkError> {
        var parameters: Parameters = [
            "limit": limit
        ]
        if let refreshToken = refreshToken, !refreshToken.isEmpty {
            parameters["refresh_token"] = refreshToken
        }

        return request(
            endpoint: "/api/v1/explore/recommended",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: CardsListResponse.self
        )
    }

    // MARK: - 卡片点赞相关API
    func likeCard(
        cardId: String,
        presentsError: Bool = true
    ) -> AnyPublisher<NetworkResponse<LikeResponseData>, NetworkError> {
        let parameters: Parameters = [
            "asset_id": cardId
        ]

        return request(
            endpoint: "/api/v1/actors/me/likes",
            method: .post,
            parameters: parameters,
            responseType: NetworkResponse<LikeResponseData>.self,
            presentsError: presentsError
        )
    }

    func unlikeCard(
        cardId: String,
        presentsError: Bool = true
    ) -> AnyPublisher<NetworkResponse<EmptyResponseData>, NetworkError> {
        return request(
            endpoint: "/api/v1/actors/me/likes/\(cardId)",
            method: .delete,
            responseType: NetworkResponse<EmptyResponseData>.self,
            presentsError: presentsError
        )
    }

    // MARK: - 收藏相关API
    func favoriteCard(
        cardId: String,
        sparkActivityId: String? = nil,
        presentsError: Bool = true
    ) -> AnyPublisher<NetworkResponse<FavoriteResponseData>, NetworkError> {
        var parameters: Parameters = ["asset_id": cardId]
        if let sparkActivityId, !sparkActivityId.isEmpty {
            parameters["spark_activity_id"] = sparkActivityId
        }

        return request(
            endpoint: "/api/v1/actors/me/favorites",
            method: .post,
            parameters: parameters,
            responseType: NetworkResponse<FavoriteResponseData>.self,
            presentsError: presentsError
        )
    }

    func unfavoriteCard(
        cardId: String,
        presentsError: Bool = true
    ) -> AnyPublisher<NetworkResponse<EmptyResponseData>, NetworkError> {
        return request(
            endpoint: "/api/v1/actors/me/favorites/\(cardId)",
            method: .delete,
            encoding: URLEncoding.default,
            responseType: NetworkResponse<EmptyResponseData>.self,
            presentsError: presentsError
        )
    }

    func getDiscoveryPath(
        cardId: String,
        presentsError: Bool = true
    ) -> AnyPublisher<NetworkResponse<DiscoveryPathData>, NetworkError> {
        request(
            endpoint: "/api/v1/actors/me/favorites/\(cardId)/discovery-path",
            method: .get,
            responseType: NetworkResponse<DiscoveryPathData>.self,
            presentsError: presentsError
        )
    }



    // MARK: 卡片链接相关API
    func getUserAllLinks(limit: Int = 50) -> AnyPublisher<NetworkResponse<ListMyLinksData>, NetworkError> {
        let parameters: Parameters = [
            "page": 1,
            "per_page": limit
        ]

        return request(
            endpoint: "/api/cards/links",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: NetworkResponse<ListMyLinksData>.self
        )
    }

    // MARK: - 获取用户所有卡片
    func getUserAllCards(searchType: String = "all", search: String = "", limit: Int = 20, cardId: String? = nil) -> AnyPublisher<UserAllCardsResponse, NetworkError> {
        var parameters: Parameters = [
            "search_type": searchType,
            "search": search,
            "limit": limit
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

    func createCardLink(
        cardId: String,
        reques: LinkRequest,
        presentsError: Bool = true
    ) -> AnyPublisher<LinkResponse, NetworkError> {
        let parameters: Parameters = [
            "linked_card_id": reques.linkedCardId,
            "link_type": "MANUAL"
        ]

        return request(
            endpoint: "/api/cards/\(cardId)/links",
            method: .post,
            parameters: parameters,
            responseType: LinkResponse.self,
            presentsError: presentsError
        )
    }

    func removeCardLink(cardId: String, linkedCardId: String) -> AnyPublisher<NetworkResponse<DeleteLinkData>, NetworkError> {
        return request(
            endpoint: "/api/cards/\(cardId)/links/\(linkedCardId)",
            method: .delete,
            responseType: NetworkResponse<DeleteLinkData>.self
        )
    }

    // MARK: 卡片Pin相关API
    func getUserPinnedCards(limit: Int = 50) -> AnyPublisher<CardsListResponse, NetworkError> {
        let parameters: Parameters = [
            "page": 1,
            "per_page": limit
        ]

        return request(
            endpoint: "/api/cards/pins",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: CardsListResponse.self
        )
    }

    func pinCard(cardId: String) -> AnyPublisher<PinResponse, NetworkError> {
        return request(
            endpoint: "/api/cards/\(cardId)/pin",
            method: .post,
            encoding: URLEncoding.default,
            responseType: PinResponse.self
        )
    }

    func unpinCard(cardId: String) -> AnyPublisher<PinResponse, NetworkError> {
        return request(
            endpoint: "/api/cards/\(cardId)/pin",
            method: .delete,
            responseType: PinResponse.self
        )
    }

    // MARK: 用户相关API
    func getCurrentUserProfile() -> AnyPublisher<UserProfileResponse, NetworkError> {
        return request(
            endpoint: "/api/v1/profile/me",
            method: .get,
            responseType: UserProfileResponse.self
        )
    }

    func getUserProfile(
        actorId: String,
        presentsError: Bool = true
    ) -> AnyPublisher<UserProfileResponse, NetworkError> {
        return request(
            endpoint: "/api/v1/profile/\(actorId)",
            method: .get,
            responseType: UserProfileResponse.self,
            presentsError: presentsError
        )
    }

    func uploadAvatar(imageData: Data) -> AnyPublisher<AvatarUploadResponse, NetworkError> {
        uploadProfileImage(
            imageData: imageData,
            endpoint: "/api/v1/profile/me/avatar",
            fieldName: "avatar",
            fileName: "avatar.jpg"
        )
    }

    func uploadProfileBackground(imageData: Data) -> AnyPublisher<AvatarUploadResponse, NetworkError> {
        uploadProfileImage(
            imageData: imageData,
            endpoint: "/api/v1/profile/me/background",
            fieldName: "background",
            fileName: "background.jpg"
        )
    }

    private func uploadProfileImage(
        imageData: Data,
        endpoint: String,
        fieldName: String,
        fileName: String
    ) -> AnyPublisher<AvatarUploadResponse, NetworkError> {
        return Future<AvatarUploadResponse, NetworkError> { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknown))
                return
            }

            let url = "\(self.baseURL)\(endpoint)"
            let headers = self.authorizedHeaders()

            DispatchQueue.main.async {
                self.isLoading = true
            }

            self.session.upload(
                multipartFormData: { multipartFormData in
                    multipartFormData.append(
                        imageData,
                        withName: fieldName,
                        fileName: fileName,
                        mimeType: "image/jpeg"
                    )
                },
                to: url,
                method: .put,
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
    func updateCardVisibility(cardId: String, isPublic: Bool) -> AnyPublisher<ToggleCardVisibilityResponse, NetworkError> {
        let parameters: Parameters = [
            "visibility": isPublic ? "PUBLIC" : "PRIVATE"
        ]

        return request(
            endpoint: "/api/v1/assets/\(cardId)/visibility",
            method: .post,
            parameters: parameters,
            responseType: ToggleCardVisibilityResponse.self
        )
    }

    func getUserCredit(
        presentsError: Bool = false
    ) -> AnyPublisher<NetworkResponse<CreditBalanceData>, NetworkError> {
        return request(
            endpoint: "/api/v1/credits/balance",
            method: .get,
            responseType: NetworkResponse<CreditBalanceData>.self,
            presentsError: presentsError,
            suppressesPayloadLogging: true
        )
    }

    func getCreditLedger(
        cursor: String? = nil,
        limit: Int = 20,
        presentsError: Bool = false
    ) -> AnyPublisher<CreditLedgerResponse, NetworkError> {
        var parameters: Parameters = ["limit": limit]
        if let cursor, !cursor.isEmpty {
            parameters["cursor"] = cursor
        }
        return request(
            endpoint: "/api/v1/credits/ledger",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: CreditLedgerResponse.self,
            presentsError: presentsError,
            suppressesPayloadLogging: true
        )
    }

    func getUserStats() -> AnyPublisher<StatsResponse, NetworkError> {
        return request(
            endpoint: "/api/v1/profile/me/stats",
            method: .get,
            responseType: StatsResponse.self
        )
    }

    func getPrivacySettings(
        presentsError: Bool = false
    ) -> AnyPublisher<NetworkResponse<PrivacySettingsData>, NetworkError> {
        request(
            endpoint: "/api/v1/profile/me/privacy",
            method: .get,
            responseType: NetworkResponse<PrivacySettingsData>.self,
            presentsError: presentsError,
            suppressesPayloadLogging: true
        )
    }

    func updatePrivacySetting(
        _ setting: PrivacySetting,
        enabled: Bool,
        presentsError: Bool = false
    ) -> AnyPublisher<NetworkResponse<PrivacySettingsData>, NetworkError> {
        request(
            endpoint: "/api/v1/profile/me/privacy",
            method: .put,
            parameters: [setting.rawValue: enabled],
            responseType: NetworkResponse<PrivacySettingsData>.self,
            presentsError: presentsError,
            suppressesPayloadLogging: true
        )
    }

    func getTopUsers() -> AnyPublisher<TopUsersResponse, NetworkError> {
        return request(
            endpoint: "/api/v1/credits/leaderboard",
            method: .get,
            responseType: TopUsersResponse.self
        )
    }
    func checkFavoriteStatus(cardIds: String) -> AnyPublisher<NetworkResponse<[String: Bool]>, NetworkError> {
        let parameters: Parameters = [
            "asset_ids": cardIds.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        ]

        return request(
            endpoint: "/api/v1/actors/me/favorites/status",
            method: .post,
            parameters: parameters,
            responseType: NetworkResponse<[String: Bool]>.self
        )
    }

    func getFollowersList(
        actorId: String,
        cursor: String? = nil,
        limit: Int = 20,
        presentsError: Bool = true
    ) -> AnyPublisher<FollowListResponse, NetworkError> {
        var parameters: Parameters = [
            "limit": limit
        ]
        if let cursor = cursor, !cursor.isEmpty {
            parameters["cursor"] = cursor
        }

        return request(
            endpoint: "/api/v1/actors/\(actorId)/followers",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: FollowListResponse.self,
            presentsError: presentsError
        )
    }

    func getFollowingList(
        actorId: String,
        cursor: String? = nil,
        limit: Int = 20,
        presentsError: Bool = true
    ) -> AnyPublisher<FollowListResponse, NetworkError> {
        var parameters: Parameters = [
            "limit": limit
        ]
        if let cursor = cursor, !cursor.isEmpty {
            parameters["cursor"] = cursor
        }

        return request(
            endpoint: "/api/v1/actors/\(actorId)/following",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: FollowListResponse.self,
            presentsError: presentsError
        )
    }
    // MARK: - 文件上传API
    func uploadCardMedia(
        data: Data,
        filename: String,
        mimeType: String
    ) -> AnyPublisher<UploadResponse, NetworkError> {
        Future<UploadResponse, NetworkError> { [weak self] promise in
            guard let self else {
                promise(.failure(.unknown))
                return
            }

            var headers = HTTPHeaders()
            if let token = self.authToken {
                headers.add(.authorization(bearerToken: token))
            }

            DispatchQueue.main.async {
                self.isLoading = true
            }

            self.session.upload(
                multipartFormData: { form in
                    form.append(
                        data,
                        withName: "file",
                        fileName: filename,
                        mimeType: mimeType
                    )
                    form.append(Data("inline".utf8), withName: "kind")
                },
                to: "\(self.baseURL)/api/v1/media/upload",
                headers: headers
            )
            .validate()
            .responseData { response in
                DispatchQueue.main.async {
                    self.isLoading = false
                }

                switch response.result {
                case .success(let responseData):
                    do {
                        let upload = try JSONDecoder().decode(
                            UploadResponse.self,
                            from: responseData
                        )
                        guard upload.success else {
                            promise(.failure(.serverError(0, upload.message)))
                            return
                        }
                        promise(.success(upload))
                    } catch {
                        promise(.failure(.decodingError))
                    }
                case .failure(let error):
                    promise(.failure(
                        self.handleError(error, response: response.response)
                    ))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func uploadFile(data: Data, filename: String, mimeType: String, assetId: String, kind: String = "background") -> AnyPublisher<UploadResponse, NetworkError> {
        return Future<UploadResponse, NetworkError> { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknown))
                return
            }

            let url = "\(self.baseURL)/api/v1/media/upload"

            print("文件上传URL: \(url)")
            print("文件名: \(filename)")
            print("文件大小: \(data.count) bytes")
            print("MIME类型: \(mimeType)")
            print("关联资产ID: \(assetId)")
            print("上传类型: \(kind)")

            var headers = HTTPHeaders()
            if let token = self.authToken {
                headers.add(.authorization(bearerToken: token))
                print("认证Token: <redacted>")
            }

            DispatchQueue.main.async {
                self.isLoading = true
            }

            self.session.upload(
                multipartFormData: { multipartFormData in
                    multipartFormData.append(data, withName: "file", fileName: filename, mimeType: mimeType)
                    multipartFormData.append(Data(assetId.utf8), withName: "asset_id")
                    multipartFormData.append(Data(kind.utf8), withName: "kind")
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
    func getNotificationInbox(
        _ request: GetNotificationsRequest,
        presentsError: Bool = false
    ) -> AnyPublisher<NotificationInboxResponse, NetworkError> {
        let parameters: [String: Any] = [
            "page": request.page,
            "per_page": request.perPage
        ]

        return self.request(
            endpoint: "/api/notifications",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: NotificationInboxResponse.self,
            presentsError: presentsError
        )
    }

    func markNotificationRead(
        notificationId: String,
        presentsError: Bool = true
    ) -> AnyPublisher<SuccessResponse, NetworkError> {
        return self.request(
            endpoint: "/api/notifications/\(notificationId)/read",
            method: .patch,
            responseType: SuccessResponse.self,
            presentsError: presentsError
        )
    }

    // MARK: 邀请码相关API
    func useInvitationCode(
        _ request: UseInvitationRequest,
        presentsError: Bool = false
    ) -> AnyPublisher<InvitationRedeemResponse, NetworkError> {
        let parameters: Parameters = [
            "code": request.code
        ]

        return self.request(
            endpoint: "/api/invitations/redeem",
            method: .post,
            parameters: parameters,
            responseType: InvitationRedeemResponse.self,
            presentsError: presentsError,
            suppressesPayloadLogging: true
        )
    }

    func getUserGroup(
        presentsError: Bool = false
    ) -> AnyPublisher<InvitationReferralResponse, NetworkError> {
        return self.request(
            endpoint: "/api/invitations/referral",
            method: .get,
            responseType: InvitationReferralResponse.self,
            presentsError: presentsError,
            suppressesPayloadLogging: true
        )
    }

    func validateInvitationCode(
        _ request: ValidateInvitationRequest,
        presentsError: Bool = false
    ) -> AnyPublisher<InvitationValidateResponse, NetworkError> {
        let parameters: Parameters = [
            "code": request.code
        ]

        return self.request(
            endpoint: "/api/invitations/validate",
            method: .post,
            parameters: parameters,
            responseType: InvitationValidateResponse.self,
            presentsError: presentsError,
            suppressesPayloadLogging: true
        )
    }

    func trackInvitationClick(_ request: InvitationTrackRequest) -> AnyPublisher<InvitationTrackResponse, NetworkError> {
        var parameters: Parameters = [
            "code": request.code
        ]
        if let deviceFingerprint = request.deviceFingerprint {
            parameters["device_fingerprint"] = deviceFingerprint
        }

        return self.request(
            endpoint: "/api/invitations/track",
            method: .post,
            parameters: parameters,
            responseType: InvitationTrackResponse.self,
            suppressesPayloadLogging: true
        )
    }

    func getInvitationRecords(
        page: Int = 1,
        limit: Int = 20,
        status: String? = nil,
        presentsError: Bool = false
    ) -> AnyPublisher<InvitationRecordsResponse, NetworkError> {
        var parameters: Parameters = [
            "page": page,
            "limit": limit
        ]
        if let status = status {
            parameters["status"] = status
        }

        return self.request(
            endpoint: "/api/invitations/records",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: InvitationRecordsResponse.self,
            presentsError: presentsError,
            suppressesPayloadLogging: true
        )
    }

    func getInvitationRewards(
        page: Int = 1,
        limit: Int = 20,
        presentsError: Bool = false
    ) -> AnyPublisher<InvitationRewardsResponse, NetworkError> {
        let parameters: Parameters = [
            "page": page,
            "limit": limit
        ]

        return self.request(
            endpoint: "/api/invitations/rewards",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: InvitationRewardsResponse.self,
            presentsError: presentsError,
            suppressesPayloadLogging: true
        )
    }

    func healthCheck() -> AnyPublisher<HealthResponse, NetworkError> {
        return request(
            endpoint: "/health",
            method: .get,
            responseType: HealthResponse.self
        )
    }
    // MARK: 评论相关API
    func getComments(cardId: String, page: Int = 1, perPage: Int = 20, completion: @escaping (Result<CommentListResponse, NetworkError>) -> Void) {
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

    func createComment(cardId: String, request: CreateCommentRequest, completion: @escaping (Result<CreateCommentResponse, NetworkError>) -> Void) {
        var parameters: Parameters = [
            "body": request.content,
            "visibility": request.visibility.rawValue
        ]
        if let parentCommentId = request.parentCommentId {
            parameters["parent_comment_id"] = parentCommentId
        }

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
    func getUserProfile(actorId: String, completion: @escaping (Result<UserProfileResponse, NetworkError>) -> Void) {
        self.request(
            endpoint: "/api/v1/profile/\(actorId)",
            method: .get,
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

    func getCurrentUserProfile(completion: @escaping (Result<UserProfileResponse, NetworkError>) -> Void) {
        self.request(
            endpoint: "/api/v1/profile/me",
            method: .get,
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

    func getFavorites(page: Int = 1, perPage: Int = 20, completion: @escaping (Result<FavoritesListResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "per_page": perPage,
            "page": page
        ]

        self.request(
            endpoint: "/api/v1/actors/me/favorites",
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

    func deleteCard(cardId: String, completion: @escaping (Result<NetworkResponse<CardMessageData>, NetworkError>) -> Void) {
        self.request(
            endpoint: "/api/cards/\(cardId)",
            method: .delete,
            encoding: URLEncoding.default,
            responseType: NetworkResponse<CardMessageData>.self,
            presentsError: false
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
    func toggleCardVisibility(cardId: String, isPublic: Bool, completion: @escaping (Result<ToggleCardVisibilityResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "visibility": isPublic ? "PUBLIC" : "PRIVATE"
        ]

        self.request(
            endpoint: "/api/v1/assets/\(cardId)/visibility",
            method: .post,
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
    func toggleCardPin(cardId: String, completion: @escaping (Result<ToggleCardPinResponse, NetworkError>) -> Void) {
        self.request(
            endpoint: "/api/cards/\(cardId)/pin",
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
    func unpinCard(cardId: String, completion: @escaping (Result<ToggleCardPinResponse, NetworkError>) -> Void) {

        self.request(
            endpoint: "/api/cards/\(cardId)/pin",
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
    func getTrashCards(page: Int = 1, perPage: Int = 20, completion: @escaping (Result<TrashListResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "per_page": perPage,
            "page": page
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
    func restoreCard(cardId: String, completion: @escaping (Result<NetworkResponse<CreateCardData>, NetworkError>) -> Void) {
        self.request(
            endpoint: "/api/cards/trash/\(cardId)/restore",
            method: .post,
            responseType: NetworkResponse<CreateCardData>.self,
            presentsError: false
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
    func permanentlyDeleteCard(cardId: String, completion: @escaping (Result<NetworkResponse<CardMessageData>, NetworkError>) -> Void) {
        self.request(
            endpoint: "/api/cards/trash/\(cardId)/permanent",
            method: .delete,
            encoding: URLEncoding.default,
            responseType: NetworkResponse<CardMessageData>.self,
            presentsError: false
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
    func updateUserProfilePublisher(
        username: String,
        bio: String,
        location: String,
        birthday: String
    ) -> AnyPublisher<UserProfileResponse, NetworkError> {
        var parameters: Parameters = [
            "username": username,
            "bio": bio,
            "city": location
        ]

        let trimmedBirthday = birthday.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBirthday.isEmpty {
            parameters["birthday"] = trimmedBirthday
        }

        return request(
            endpoint: "/api/v1/profile/me",
            method: .put,
            parameters: parameters,
            responseType: UserProfileResponse.self
        )
    }

    func updateUserProfile(
        username: String,
        bio: String,
        location: String,
        birthday: String,
        completion: @escaping (Result<UserProfileResponse, NetworkError>) -> Void
    ) {
        updateUserProfilePublisher(
            username: username,
            bio: bio,
            location: location,
            birthday: birthday
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
    func searchCards(query: String, page: Int = 1, perPage: Int = 20, completion: @escaping (Result<SearchResponse, NetworkError>) -> Void) {
        let parameters: Parameters = [
            "per_page": perPage,
            "page": page,
            "sort_order": "desc",
            "sort_by": "relevance",
            "search_type": "all",
            "query": query
        ]

        self.request(
            endpoint: "/api/v1/explore/search",
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
    func getCardDetailPublisher(
        cardId: String,
        presentsError: Bool = true
    ) -> AnyPublisher<CardDetailResponse, NetworkError> {
        request(
            endpoint: "/api/cards/\(cardId)",
            method: .get,
            encoding: URLEncoding.default,
            responseType: CardDetailResponse.self,
            presentsError: presentsError
        )
    }

    func getCardDetail(cardId: String, completion: @escaping (Result<CardDetailResponse, NetworkError>) -> Void) {
        getCardDetailPublisher(cardId: cardId)
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
        createMergeJob(request)
            .flatMap { [weak self] job -> AnyPublisher<MergeArtifactResponse, NetworkError> in
                guard let self = self else {
                    return Fail(error: .unknown).eraseToAnyPublisher()
                }
                return self.waitForMergeArtifact(jobId: job.jobId)
            }
            .map { $0.toPreviewResponse() }
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        completion(.failure(error))
                    }
                },
                receiveValue: { response in
                    completion(.success(response))
                }
            )
            .store(in: &cancellables)
    }

    func createMergeJob(_ request: MergeCardsRequest) -> AnyPublisher<MergeJobResponse, NetworkError> {
        do {
            return self.request(
                endpoint: "/api/merge/jobs",
                method: .post,
                parameters: try encodedParameters(request),
                responseType: MergeJobResponse.self,
                presentsError: false
            )
        } catch {
            return Fail(error: NetworkError.encodingError).eraseToAnyPublisher()
        }
    }

    func getMergeJob(jobId: String) -> AnyPublisher<MergeJobResponse, NetworkError> {
        return self.request(
            endpoint: "/api/merge/jobs/\(jobId)",
            method: .get,
            encoding: URLEncoding.default,
            responseType: MergeJobResponse.self,
            presentsError: false
        )
    }

    func getMergeArtifact(jobId: String) -> AnyPublisher<MergeArtifactResponse, NetworkError> {
        return self.request(
            endpoint: "/api/merge/jobs/\(jobId)/artifact",
            method: .get,
            encoding: URLEncoding.default,
            responseType: MergeArtifactResponse.self,
            presentsError: false
        )
    }

    func cancelMergeJob(
        jobId: String,
        request: CancelMergeJobRequest
    ) -> AnyPublisher<MergeJobResponse, NetworkError> {
        do {
            return self.request(
                endpoint: "/api/merge/jobs/\(jobId)/cancel",
                method: .post,
                parameters: try encodedParameters(request),
                responseType: MergeJobResponse.self,
                presentsError: false
            )
        } catch {
            return Fail(error: NetworkError.encodingError)
                .eraseToAnyPublisher()
        }
    }

    func listMergeCapabilities() -> AnyPublisher<MergeCapabilitiesResponse, NetworkError> {
        self.request(
            endpoint: "/api/merge/capabilities",
            method: .get,
            encoding: URLEncoding.default,
            responseType: MergeCapabilitiesResponse.self,
            presentsError: false
        )
    }

    func getSharePreview(
        cardId: String
    ) -> AnyPublisher<SharePreviewWireResponse, NetworkError> {
        request(
            endpoint: "/api/cards/\(cardId)/share-preview",
            parameters: ["template": "auto"],
            encoding: URLEncoding.default,
            responseType: SharePreviewWireResponse.self,
            presentsError: false
        )
    }

    func getShareArtifactImage(
        cardId: String,
        artifactId: String
    ) -> AnyPublisher<Data, NetworkError> {
        requestData(
            endpoint: "/api/cards/\(cardId)/share-artifacts/\(artifactId)/image",
            accept: "image/png",
            presentsError: false
        )
    }

    func pinShareArtifact(
        cardId: String,
        artifactId: String
    ) -> AnyPublisher<SharePinWireResponse, NetworkError> {
        request(
            endpoint: "/api/cards/\(cardId)/share-artifacts/\(artifactId)/pin",
            method: .post,
            responseType: SharePinWireResponse.self,
            presentsError: false
        )
    }

    func createContentReport(
        _ input: ContentReportWireRequest
    ) -> AnyPublisher<ContentReportWireEnvelope, NetworkError> {
        do {
            return request(
                endpoint: "/api/content-reports",
                method: .post,
                parameters: try encodedParameters(input),
                responseType: ContentReportWireEnvelope.self,
                presentsError: false
            )
        } catch {
            return Fail(error: .encodingError).eraseToAnyPublisher()
        }
    }

    private func waitForMergeArtifact(jobId: String, attempt: Int = 0) -> AnyPublisher<MergeArtifactResponse, NetworkError> {
        return getMergeJob(jobId: jobId)
            .flatMap { [weak self] job -> AnyPublisher<MergeArtifactResponse, NetworkError> in
                guard let self = self else {
                    return Fail(error: .unknown).eraseToAnyPublisher()
                }

                switch job.status {
                case "ARTIFACT_READY", "COMMITTING", "COMMITTED":
                    return self.getMergeArtifact(jobId: jobId)
                case "FAILED", "CANCELLED":
                    return Fail(error: .serverError(409, job.status))
                        .eraseToAnyPublisher()
                default:
                    guard attempt < 30 else {
                        return Fail(error: .timeout).eraseToAnyPublisher()
                    }
                    return Just(())
                        .delay(for: .seconds(1), scheduler: DispatchQueue.global(qos: .userInitiated))
                        .setFailureType(to: NetworkError.self)
                        .flatMap { self.waitForMergeArtifact(jobId: jobId, attempt: attempt + 1) }
                        .eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }

    // MARK: 关注相关API

    /// 关注用户
    func followUser(
        targetActorId: String,
        presentsError: Bool = true
    ) -> AnyPublisher<FollowResponse, NetworkError> {
        return self.request(
            endpoint: "/api/follows/\(targetActorId)",
            method: .post,
            responseType: FollowResponse.self,
            presentsError: presentsError
        )
    }

    /// 取消关注用户
    func unfollowUser(
        targetActorId: String,
        presentsError: Bool = true
    ) -> AnyPublisher<UnfollowResponse, NetworkError> {
        return self.request(
            endpoint: "/api/follows/\(targetActorId)",
            method: .delete,
            responseType: UnfollowResponse.self,
            presentsError: presentsError
        )
    }

    /// 检查关注状态
    func checkFollowStatus(targetActorIds: [String]) -> AnyPublisher<FollowStatusResponse, NetworkError> {
        guard let targetActorId = targetActorIds.first, targetActorIds.count == 1 else {
            return Fail(error: NetworkError.serverError(400, "Go profile API supports one follow-status target per request")).eraseToAnyPublisher()
        }

        return self.request(
            endpoint: "/api/v1/profile/\(targetActorId)",
            method: .get,
            encoding: URLEncoding.default,
            responseType: UserProfileResponse.self
        )
        .map { response in
            FollowStatusResponse(
                success: response.success,
                message: response.message ?? "",
                data: [targetActorId: response.data.isFollowing ?? false]
            )
        }
        .eraseToAnyPublisher()
    }

    /// 拉黑用户
    func blockUser(
        blockedActorId: String,
        presentsError: Bool = true
    ) -> AnyPublisher<BlockUserResponse, NetworkError> {
        return self.request(
            endpoint: "/api/user-blocks/\(blockedActorId)",
            method: .post,
            responseType: BlockUserResponse.self,
            presentsError: presentsError
        )
    }

    /// 取消拉黑用户
    func unblockUser(
        blockedActorId: String,
        presentsError: Bool = true
    ) -> AnyPublisher<UnblockUserResponse, NetworkError> {
        return self.request(
            endpoint: "/api/user-blocks/\(blockedActorId)",
            method: .delete,
            responseType: UnblockUserResponse.self,
            presentsError: presentsError
        )
    }

    func getBlockedActors(
        cursor: String? = nil,
        limit: Int = 20,
        presentsError: Bool = true
    ) -> AnyPublisher<BlockedActorsResponse, NetworkError> {
        var parameters: Parameters = ["limit": limit]
        if let cursor, !cursor.isEmpty {
            parameters["cursor"] = cursor
        }
        return self.request(
            endpoint: "/api/user-blocks",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: BlockedActorsResponse.self,
            presentsError: presentsError
        )
    }

    // MARK: Apple登录API

    /// Apple登录
    func appleLogin(loginRequest: AppleLoginRequest) -> AnyPublisher<AuthResponse, NetworkError> {
        var parameters: Parameters = [
            "identity_token": loginRequest.identityToken
        ]
        let fullName = [loginRequest.userInfo.name.firstName, loginRequest.userInfo.name.lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !fullName.isEmpty {
            parameters["full_name"] = fullName
        }
        Self.appendAccessPair(
            code: loginRequest.accessCode,
            key: loginRequest.idempotencyKey,
            to: &parameters
        )

        return self.request(
            endpoint: "/api/auth/apple-login",
            method: .post,
            parameters: parameters,
            responseType: AuthResponse.self,
            suppressesPayloadLogging: true
        )
    }

    // MARK: - 卡片链接API

    /// 获取卡片链接
    func getCardLinks(cardId: String) -> AnyPublisher<CardLinksResponse, NetworkError> {
        let parameters: Parameters = [
            "include": "cards"
        ]

        return self.request(
            endpoint: "/api/cards/\(cardId)/links",
            method: .get,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: CardLinksResponse.self
        )
    }

    func commitMergeJob(
        jobId: String,
        request: CommitMergeJobRequest
    ) -> AnyPublisher<MergeCommitResponse, NetworkError> {
        do {
            return self.request(
                endpoint: "/api/merge/jobs/\(jobId)/commit",
                method: .post,
                parameters: try encodedParameters(request),
                responseType: MergeCommitResponse.self,
                presentsError: false
            )
        } catch {
            return Fail(error: NetworkError.encodingError).eraseToAnyPublisher()
        }
    }

    func commitMergeJob(
        jobId: String,
        titleOverride: String?
    ) -> AnyPublisher<MergeCommitResponse, NetworkError> {
        // The current commit contract seals the latest artifact revision.
        // titleOverride is retained only for source compatibility with the
        // legacy preview screen; the server no longer accepts it here.
        getMergeArtifact(jobId: jobId)
            .flatMap { [weak self] artifact
                -> AnyPublisher<MergeCommitResponse, NetworkError> in
                guard let self else {
                    return Fail(error: .unknown).eraseToAnyPublisher()
                }
                return self.commitMergeJob(
                    jobId: jobId,
                    request: CommitMergeJobRequest(
                        revision: artifact.latestRevision,
                        artifactHash: artifact.latestHash,
                        idemKey: "ios-legacy-merge-commit-\(jobId)"
                    )
                )
            }
            .eraseToAnyPublisher()
    }

    func getOnboardingStatus(
    ) -> AnyPublisher<NetworkResponse<OnboardingStatusSnapshot>, NetworkError> {
        request(
            endpoint: "/api/v1/onboarding/status",
            responseType: NetworkResponse<OnboardingStatusSnapshot>.self,
            presentsError: false
        )
    }

    func startOnboarding(
        flowVersion: Int
    ) -> AnyPublisher<NetworkResponse<OnboardingGuideSession>, NetworkError> {
        request(
            endpoint: "/api/v1/onboarding/sessions",
            method: .post,
            parameters: ["flow_version": flowVersion],
            responseType: NetworkResponse<OnboardingGuideSession>.self,
            presentsError: false
        )
    }

    func getCurrentOnboarding(
    ) -> AnyPublisher<NetworkResponse<OnboardingGuideSession>, NetworkError> {
        request(
            endpoint: "/api/v1/onboarding/sessions/current",
            responseType: NetworkResponse<OnboardingGuideSession>.self,
            presentsError: false
        )
    }

    func respondToOnboarding(
        sessionID: String,
        input: OnboardingGuideInput
    ) -> AnyPublisher<NetworkResponse<OnboardingGuideSession>, NetworkError> {
        do {
            return request(
                endpoint: "/api/v1/onboarding/sessions/\(sessionID)/respond",
                method: .post,
                parameters: try encodedParameters(input),
                responseType: NetworkResponse<OnboardingGuideSession>.self,
                presentsError: false
            )
        } catch {
            return Fail(error: NetworkError.encodingError).eraseToAnyPublisher()
        }
    }

    func completeOnboarding(
        sessionID: String
    ) -> AnyPublisher<NetworkResponse<OnboardingGuideSession>, NetworkError> {
        request(
            endpoint: "/api/v1/onboarding/sessions/\(sessionID)/complete",
            method: .post,
            responseType: NetworkResponse<OnboardingGuideSession>.self,
            presentsError: false
        )
    }

    func skipOnboarding(
        sessionID: String
    ) -> AnyPublisher<NetworkResponse<OnboardingGuideSession>, NetworkError> {
        request(
            endpoint: "/api/v1/onboarding/sessions/\(sessionID)/skip",
            method: .post,
            responseType: NetworkResponse<OnboardingGuideSession>.self,
            presentsError: false
        )
    }


    // MARK: 删除卡片关联
    func deleteCardLink(cardId: String, linkedCardId: String) -> AnyPublisher<NetworkResponse<DeleteLinkData>, NetworkError> {
        return removeCardLink(cardId: cardId, linkedCardId: linkedCardId)
    }
}

// MARK: - Chora profile, note import, and Notion source APIs
extension NetworkManager {
    func getChoraAgentProfile() -> AnyPublisher<ChoraDataEnvelope<ChoraAgentProfileResponse>, NetworkError> {
        let spec = ChoraSourceRequests.agentProfile
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            responseType: ChoraDataEnvelope<ChoraAgentProfileResponse>.self,
            presentsError: spec.presentsError
        )
    }

    func getChoraAgentUsers() -> AnyPublisher<ChoraDataEnvelope<ChoraAgentUsersResponse>, NetworkError> {
        let spec = ChoraSourceRequests.agentUsers
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            responseType: ChoraDataEnvelope<ChoraAgentUsersResponse>.self,
            presentsError: spec.presentsError
        )
    }

    func getChoraOwnProfile() -> AnyPublisher<ChoraDataEnvelope<ChoraOwnProfileResponse>, NetworkError> {
        let spec = ChoraSourceRequests.ownProfile
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            responseType: ChoraDataEnvelope<ChoraOwnProfileResponse>.self,
            presentsError: spec.presentsError
        )
    }

    func getChoraGrowth(
        agentActorID: String
    ) -> AnyPublisher<ChoraGrowthViewEnvelope, NetworkError> {
        let spec = ChoraSourceRequests.growth
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            parameters: [spec.queryFields[0]: agentActorID],
            encoding: URLEncoding.default,
            responseType: ChoraGrowthViewEnvelope.self,
            presentsError: spec.presentsError
        )
    }

    func updateChoraAgentDisplayName(
        agentActorID: String,
        displayName: String
    ) -> AnyPublisher<ChoraDataEnvelope<ChoraAgentUserResponse>, NetworkError> {
        let spec = ChoraSourceRequests.agentDisplayName(agentActorID)
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            parameters: [spec.bodyFields[0]: displayName],
            responseType: ChoraDataEnvelope<ChoraAgentUserResponse>.self,
            presentsError: spec.presentsError
        )
    }

    func updateChoraPreferredAddress(
        _ value: String
    ) -> AnyPublisher<ChoraDataEnvelope<ChoraOwnProfileResponse>, NetworkError> {
        let spec = ChoraSourceRequests.preferredAddress
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            parameters: [spec.bodyFields[0]: value],
            responseType: ChoraDataEnvelope<ChoraOwnProfileResponse>.self,
            presentsError: spec.presentsError
        )
    }

    func updateChoraAgentAvatar(
        agentActorID: String,
        data: Data,
        filename: String,
        mimeType: String
    ) -> AnyPublisher<ChoraDataEnvelope<ChoraOwnProfileResponse>, NetworkError> {
        let spec = ChoraSourceRequests.agentAvatar
        return multipartRequest(
            spec: spec,
            responseType: ChoraDataEnvelope<ChoraOwnProfileResponse>.self
        ) { form in
            form.append(
                Data(agentActorID.utf8),
                withName: spec.multipartFields[0]
            )
            form.append(
                data,
                withName: spec.multipartFields[1],
                fileName: filename,
                mimeType: mimeType
            )
        }
    }

    func enqueueNoteImport(
        parts: [NoteImportUploadPart],
        clientRequestID: String,
        termination: NoteImportUploadTermination
    ) -> AnyPublisher<NoteImportUploadTransportResult, NetworkError> {
        let spec = ChoraSourceRequests.noteImportEnqueue
        return multipartDataRequest(
            spec: spec,
            termination: termination
        ) { form in
            for part in parts {
                form.append(
                    part.url,
                    withName: spec.multipartFields[0],
                    fileName: part.filename,
                    mimeType: part.mimeType
                )
                form.append(
                    Data(part.sourceKey.utf8),
                    withName: spec.multipartFields[1]
                )
                form.append(
                    Data(part.label.utf8),
                    withName: spec.multipartFields[2]
                )
            }
            form.append(
                Data(clientRequestID.utf8),
                withName: spec.multipartFields[3]
            )
        }
        .map { payload in
            if let response = try? JSONDecoder().decode(
                NoteImportEnqueueResponse.self,
                from: payload.data
            ) {
                return .response(response)
            }
            return .undecodableSuccess(statusCode: payload.statusCode)
        }
        .eraseToAnyPublisher()
    }

    func getNoteImportJobs(
        limit: Int
    ) -> AnyPublisher<NoteImportJobListResponse, NetworkError> {
        let spec = ChoraSourceRequests.noteImportList
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            parameters: [spec.queryFields[0]: limit],
            encoding: URLEncoding.default,
            responseType: NoteImportJobListResponse.self,
            presentsError: spec.presentsError
        )
    }

    func getNoteImportJob(
        id: String
    ) -> AnyPublisher<NoteImportJobDetailResponse, NetworkError> {
        let spec = ChoraSourceRequests.noteImportDetail(id)
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            responseType: NoteImportJobDetailResponse.self,
            presentsError: spec.presentsError
        )
    }

    func cancelNoteImportJob(
        id: String
    ) -> AnyPublisher<NoteImportCancelResponse, NetworkError> {
        let spec = ChoraSourceRequests.noteImportCancel(id)
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            responseType: NoteImportCancelResponse.self,
            presentsError: spec.presentsError
        )
    }

    func getNotionStatus() -> AnyPublisher<NotionStatusResponse, NetworkError> {
        let spec = ChoraSourceRequests.notionStatus
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            responseType: NotionStatusResponse.self,
            presentsError: spec.presentsError
        )
    }

    func getNotionAuthorizationURL() -> AnyPublisher<NotionConnectResponse, NetworkError> {
        let spec = ChoraSourceRequests.notionConnect
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            parameters: spec.queryValues,
            encoding: URLEncoding.default,
            responseType: NotionConnectResponse.self,
            presentsError: spec.presentsError
        )
    }

    func getNotionPages(
        query: String?
    ) -> AnyPublisher<NotionPagesResponse, NetworkError> {
        let spec = ChoraSourceRequests.notionPages
        var parameters: Parameters?
        if let query {
            parameters = [spec.queryFields[0]: query]
        }
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            parameters: parameters,
            encoding: URLEncoding.default,
            responseType: NotionPagesResponse.self,
            presentsError: spec.presentsError
        )
    }

    func enqueueNotionImport(
        pageIDs: [String]
    ) -> AnyPublisher<NotionEnqueueResponse, NetworkError> {
        let spec = ChoraSourceRequests.notionEnqueue
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            parameters: [spec.bodyFields[0]: pageIDs],
            responseType: NotionEnqueueResponse.self,
            presentsError: spec.presentsError
        )
    }

    func getNotionImportJob(
        id: String
    ) -> AnyPublisher<NotionImportJobResponse, NetworkError> {
        let spec = ChoraSourceRequests.notionJob(id)
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            responseType: NotionImportJobResponse.self,
            presentsError: spec.presentsError
        )
    }

    func disconnectNotion() -> AnyPublisher<NotionDisconnectResponse, NetworkError> {
        let spec = ChoraSourceRequests.notionDisconnect
        return request(
            endpoint: spec.endpoint,
            method: spec.httpMethod,
            responseType: NotionDisconnectResponse.self,
            presentsError: spec.presentsError
        )
    }

    private struct MultipartPayload {
        let data: Data
        let statusCode: Int
    }

    private func multipartRequest<Response: Decodable>(
        spec: ChoraSourceRequestSpec,
        responseType: Response.Type,
        form: @escaping (MultipartFormData) -> Void
    ) -> AnyPublisher<Response, NetworkError> {
        let termination = NoteImportUploadTermination()
        return multipartDataRequest(
            spec: spec,
            termination: termination,
            form: form
        )
        .tryMap { payload in
            do {
                return try JSONDecoder().decode(responseType, from: payload.data)
            } catch {
                throw NetworkError.decodingError
            }
        }
        .mapError { ($0 as? NetworkError) ?? .unknown }
        .eraseToAnyPublisher()
    }

    private func multipartDataRequest(
        spec: ChoraSourceRequestSpec,
        termination: NoteImportUploadTermination,
        form: @escaping (MultipartFormData) -> Void
    ) -> AnyPublisher<MultipartPayload, NetworkError> {
        Deferred { [weak self] () -> AnyPublisher<MultipartPayload, NetworkError> in
            guard let self else {
                termination.signal()
                return Fail(error: .unknown).eraseToAnyPublisher()
            }
            var headers = self.authorizedHeaders()
            headers.remove(name: "Content-Type")
            let request = self.session.upload(
                multipartFormData: form,
                to: "\(self.baseURL)\(spec.endpoint)",
                usingThreshold: spec.multipartEncodingThreshold
                    ?? MultipartFormData.encodingMemoryThreshold,
                method: spec.httpMethod,
                headers: headers
            )
            .validate()
            let upstream = request.publishData()
                .tryMap { response -> MultipartPayload in
                    switch response.result {
                    case .success(let data):
                        return MultipartPayload(
                            data: data,
                            statusCode: response.response?.statusCode ?? 200
                        )
                    case .failure(let error):
                        if spec.presentsError,
                           let data = response.data,
                           let message = self.extractMessage(from: data),
                           !message.isEmpty {
                            self.presentErrorAlert(message: message)
                        }
                        throw self.handleError(
                            error,
                            response: response.response
                        )
                    }
                }
                .mapError { ($0 as? NetworkError) ?? .unknown }
                .eraseToAnyPublisher()
            return MultipartUploadPublisherBuilder.publisher(
                handle: AlamofireMultipartUploadHandle(request: request),
                upstream: upstream,
                termination: termination
            )
        }
        .eraseToAnyPublisher()
    }
}

private final class AlamofireMultipartUploadHandle:
    MultipartUploadHandling,
    @unchecked Sendable
{
    private let request: UploadRequest

    init(request: UploadRequest) {
        self.request = request
    }

    func cancel() {
        request.cancel()
    }

    func observeTermination(
        _ callback: @escaping @Sendable () -> Void
    ) {
        request.responseData { _ in callback() }
    }
}

private extension ChoraSourceRequestSpec {
    var httpMethod: HTTPMethod { HTTPMethod(rawValue: method.rawValue) }
}

struct CardLinksResponse: Codable {
    let success: Bool
    let message: String?
    let data: CardLinksData
}

struct DeleteLinkData: Codable {
    let removed: Bool
    let sourceAssetId: String
    let targetAssetId: String
    let activityId: String?
    let actionLogId: String?

    enum CodingKeys: String, CodingKey {
        case removed
        case sourceAssetId = "source_asset_id"
        case targetAssetId = "target_asset_id"
        case activityId = "activity_id"
        case actionLogId = "action_log_id"
    }
}
