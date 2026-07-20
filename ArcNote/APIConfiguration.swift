import Foundation

// MARK: API配置管理
struct APIConfiguration {
    static var configuredEnvironment: APIEnvironment {
        guard let rawValue = Bundle.main.object(
            forInfoDictionaryKey: APIEnvironment.infoDictionaryKey
        ) as? String,
        let environment = APIEnvironment(rawValue: rawValue)
        else {
            preconditionFailure(
                "Missing or invalid \(APIEnvironment.infoDictionaryKey) build setting"
            )
        }
        return environment
    }

    static var baseURL: String {
        if let rawOverride = ProcessInfo.processInfo.environment[
            APIEnvironment.overrideEnvironmentKey
        ],
        !rawOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let override = APIEnvironment.normalizedBaseURL(
                from: rawOverride
            ) else {
                preconditionFailure(
                    "Invalid \(APIEnvironment.overrideEnvironmentKey) value"
                )
            }
            return override.absoluteString
        }

        return configuredEnvironment.baseURL.absoluteString
    }

    static var environmentLabel: String {
        if let rawOverride = ProcessInfo.processInfo.environment[
            APIEnvironment.overrideEnvironmentKey
        ],
        !rawOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "override"
        }
        return configuredEnvironment.rawValue
    }

    static func resourceURLString(_ pathOrURL: String) -> String {
        if pathOrURL.hasPrefix("http://") || pathOrURL.hasPrefix("https://") {
            return pathOrURL
        }

        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = pathOrURL.hasPrefix("/") ? String(pathOrURL.dropFirst()) : pathOrURL

        #if DEBUG
        if trimmedPath.hasPrefix("chorai-assets/"),
           let apiURL = URL(string: baseURL),
           let host = apiURL.host,
           host == "127.0.0.1" || host == "localhost" {
            let scheme = apiURL.scheme ?? "http"
            return "\(scheme)://\(host):9000/\(trimmedPath)"
        }
        #endif

        return "\(trimmedBase)/\(trimmedPath)"
    }
    
    // MARK: 环境配置
    enum Environment {
        case development
        case staging
        case production
        
        var timeout: TimeInterval {
            switch self {
            case .development:
                return 30
            case .staging:
                return 25
            case .production:
                return 20
            }
        }
    }
    
    // MARK: 当前环境
    static var current: Environment {
        configuredEnvironment == .production ? .production : .development
    }
    
    // MARK: HTTP状态码
    struct StatusCodes {
        static let success = 200
        static let created = 201
        static let noContent = 204
        static let badRequest = 400
        static let unauthorized = 401
        static let forbidden = 403
        static let notFound = 404
        static let conflict = 409
        static let unprocessableEntity = 422
        static let tooManyRequests = 429
        static let internalServerError = 500
        static let badGateway = 502
        static let serviceUnavailable = 503
    }
    
    // MARK: 请求头配置
    struct Headers {
        static let contentType = "Content-Type"
        static let authorization = "Authorization"
        static let accept = "Accept"
        static let userAgent = "User-Agent"
        static let apiVersion = "X-API-Version"
        
        static let applicationJSON = "application/json"
        static let multipartFormData = "multipart/form-data"
        
        static func bearer(token: String) -> String {
            return "Bearer \(token)"
        }
        
        static func apiVersion(_ version: String) -> String {
            return version
        }
    }
    
    // MARK: 分页配置
    struct Pagination {
        static let defaultPageSize = 20
        static let maxPageSize = 100
        static let defaultPage = 1
    }
    
    // MARK: 缓存配置
    struct Cache {
        static let defaultTTL: TimeInterval = 300 // 5分钟
        static let longTTL: TimeInterval = 3600 // 1小时
        static let shortTTL: TimeInterval = 60 // 1分钟
    }
    
    // MARK: 重试配置
    struct Retry {
        static let maxRetryCount = 3
        static let retryDelay: TimeInterval = 1.0
        static let exponentialBackoff = true
    }
}

// MARK: - API版本管理
struct APIVersion {
    static let current = "v1"
    static let supportedVersions = ["v1"]
    
    static func isVersionSupported(_ version: String) -> Bool {
        return supportedVersions.contains(version)
    }
}

// MARK: - 请求参数构建器
struct RequestParameters {
    
    // MARK: - 分页参数
    static func pagination(page: Int = 1, pageSize: Int = APIConfiguration.Pagination.defaultPageSize) -> [String: Any] {
        return [
            "page": page,
            "per_page": min(pageSize, APIConfiguration.Pagination.maxPageSize)
        ]
    }
    
    // MARK: - 搜索参数
    static func search(query: String, tags: [String]? = nil, page: Int = 1, pageSize: Int = APIConfiguration.Pagination.defaultPageSize) -> [String: Any] {
        var parameters: [String: Any] = [
            "query": query,
            "page": page,
            "per_page": min(pageSize, APIConfiguration.Pagination.maxPageSize)
        ]
        
        if let tags = tags, !tags.isEmpty {
            parameters["tags"] = tags.joined(separator: ",")
        }
        
        return parameters
    }
    
    // MARK: 排序参数
    static func sorting(sortBy: String, sortOrder: String = "desc") -> [String: Any] {
        return [
            "sort_by": sortBy,
            "sort_order": sortOrder
        ]
    }
    
    // MARK: 过滤参数
    static func filtering(filters: [String: Any]) -> [String: Any] {
        return filters
    }
}

// MARK: 响应缓存键生成器
struct CacheKeyGenerator {
    
    static func generate(for endpoint: String, parameters: [String: Any]? = nil) -> String {
        var key = endpoint
        
        if let parameters = parameters {
            let sortedParams = parameters.sorted { $0.key < $1.key }
            let paramString = sortedParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            key += "?\(paramString)"
        }
        
        return key
    }
    
}
