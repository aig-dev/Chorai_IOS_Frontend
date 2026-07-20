import Foundation

enum APIEnvironment: String, CaseIterable {
    case local
    case production

    static let infoDictionaryKey = "ChoraiAPIEnvironment"
    static let overrideEnvironmentKey = "CHORAI_API_BASE_URL"

    var baseURL: URL {
        let rawValue: String
        switch self {
        case .local:
            rawValue = "http://127.0.0.1:8180"
        case .production:
            rawValue = "https://api.chorai.top"
        }
        guard let url = URL(string: rawValue) else {
            preconditionFailure("Invalid canonical API endpoint for \(self.rawValue)")
        }
        return url
    }

    static func normalizedBaseURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else {
            return nil
        }

        components.scheme = scheme
        components.path = ""
        return components.url
    }
}

enum APIBaseURLResolutionError: Error, Equatable, CustomStringConvertible {
    case invalidOverride
    case invalidCompiledEnvironment

    var description: String {
        switch self {
        case .invalidOverride:
            return "Invalid \(APIEnvironment.overrideEnvironmentKey) value"
        case .invalidCompiledEnvironment:
            return "Missing or invalid \(APIEnvironment.infoDictionaryKey) build setting"
        }
    }
}

struct APIBaseURLResolution: Equatable {
    let baseURL: URL
    let environmentLabel: String
}

enum APIBaseURLResolver {
    static func resolve(
        processEnvironment: [String: String],
        compiledEnvironment rawCompiledEnvironment: String?
    ) throws -> APIBaseURLResolution {
        if let rawOverride = processEnvironment[
            APIEnvironment.overrideEnvironmentKey
        ],
        !rawOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let override = APIEnvironment.normalizedBaseURL(
                from: rawOverride
            ) else {
                throw APIBaseURLResolutionError.invalidOverride
            }
            return APIBaseURLResolution(
                baseURL: override,
                environmentLabel: "override"
            )
        }

        guard let rawCompiledEnvironment,
              let environment = APIEnvironment(
                rawValue: rawCompiledEnvironment
              )
        else {
            throw APIBaseURLResolutionError.invalidCompiledEnvironment
        }
        return APIBaseURLResolution(
            baseURL: environment.baseURL,
            environmentLabel: environment.rawValue
        )
    }
}
