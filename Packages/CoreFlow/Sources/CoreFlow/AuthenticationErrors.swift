import Foundation

public struct APIErrorPayload: Equatable, Sendable {
    public let code: String?
    public let message: String?

    public init(code: String?, message: String?) {
        self.code = code
        self.message = message
    }

    public static func decode(
        from data: Data,
        statusCode: Int?
    ) -> APIErrorPayload? {
        guard let envelope = try? JSONDecoder().decode(
            APIErrorEnvelope.self,
            from: data
        ) else {
            return nil
        }

        let code = firstNonEmpty(
            envelope.error?.code,
            envelope.error?.errorCode,
            envelope.code,
            envelope.errorCode
        )
        let message = firstNonEmpty(
            envelope.error?.message,
            envelope.message
        )
        let isHTTPFailure = statusCode.map { !(200..<300).contains($0) } ?? false
        let isErrorEnvelope = envelope.success == false || envelope.error != nil

        guard isHTTPFailure || isErrorEnvelope else {
            return nil
        }
        return APIErrorPayload(code: code, message: message)
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

private struct APIErrorEnvelope: Decodable {
    let success: Bool?
    let error: APIErrorBody?
    let code: String?
    let errorCode: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success
        case error
        case code
        case errorCode = "error_code"
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try? container.decode(Bool.self, forKey: .success)
        error = try? container.decode(APIErrorBody.self, forKey: .error)
        code = try? container.decode(String.self, forKey: .code)
        errorCode = try? container.decode(String.self, forKey: .errorCode)
        message = try? container.decode(String.self, forKey: .message)
    }
}

private struct APIErrorBody: Decodable {
    let code: String?
    let errorCode: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case code
        case errorCode = "error_code"
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try? container.decode(String.self, forKey: .code)
        errorCode = try? container.decode(String.self, forKey: .errorCode)
        message = try? container.decode(String.self, forKey: .message)
    }
}

public enum AuthenticationErrorPresentation {
    public static func signInMessage(
        statusCode: Int?,
        errorCode: String?
    ) -> String {
        switch errorCode?.uppercased() {
        case "PRODUCT_ACCESS_REQUIRED":
            return privateBetaRequired
        case "FORBIDDEN", "ACCOUNT_DISABLED":
            return "This account is disabled. Please contact support."
        case "RATE_LIMIT_EXCEEDED":
            return "Too many sign-in attempts. Please wait a moment and try again."
        case "SERVICE_UNAVAILABLE", "DATABASE_ERROR", "INTERNAL_ERROR":
            return signInUnavailable
        case "UNAUTHORIZED", "INVALID_CREDENTIALS":
            return invalidCredentials
        default:
            switch statusCode {
            case 400, 401, 404:
                return invalidCredentials
            case 429:
                return "Too many sign-in attempts. Please wait a moment and try again."
            case let status? where (500...599).contains(status):
                return signInUnavailable
            default:
                return "Sign-in failed. Please try again."
            }
        }
    }

    public static func registrationMessage(
        statusCode: Int?,
        errorCode: String?
    ) -> String {
        switch errorCode?.uppercased() {
        case "PRODUCT_ACCESS_REQUIRED":
            return privateBetaRequired
        case "RATE_LIMIT_EXCEEDED":
            return "Too many attempts. Please wait a moment and try again."
        case "SERVICE_UNAVAILABLE", "DATABASE_ERROR", "INTERNAL_ERROR":
            return "Registration is temporarily unavailable. Please try again later."
        case "CONFLICT":
            return "Username or email is already in use. Please try another one."
        default:
            switch statusCode {
            case 400:
                return "Invalid request parameters. Please check your input."
            case 409:
                return "Username or email is already in use. Please try another one."
            case 422:
                return "Verification code is incorrect or expired. Please get a new one."
            case 429:
                return "Too many attempts. Please wait a moment and try again."
            case let status? where (500...599).contains(status):
                return "Registration is temporarily unavailable. Please try again later."
            default:
                return "Registration failed. Please try again."
            }
        }
    }

    public static func verificationCodeMessage(
        statusCode: Int?,
        errorCode: String?
    ) -> String {
        switch errorCode?.uppercased() {
        case "VALIDATION_ERROR", "INVALID_INPUT", "BAD_REQUEST":
            return "Please enter a valid email address."
        case "RATE_LIMIT_EXCEEDED":
            return "Too many verification code requests. Please wait a moment and try again."
        case "SERVICE_UNAVAILABLE", "DATABASE_ERROR", "INTERNAL_ERROR":
            return verificationServiceUnavailable
        default:
            switch statusCode {
            case 400, 422:
                return "Please enter a valid email address."
            case 429:
                return "Too many verification code requests. Please wait a moment and try again."
            case let status? where (500...599).contains(status):
                return verificationServiceUnavailable
            default:
                return "Verification code could not be sent. Please try again."
            }
        }
    }

    private static let invalidCredentials = "Email or password is incorrect."
    private static let privateBetaRequired =
        "Private Beta access is required. Enter a Product Access Code to continue."
    private static let signInUnavailable =
        "Sign-in is temporarily unavailable. Please try again later."
    private static let verificationServiceUnavailable =
        "Verification code service is temporarily unavailable. Please try again later."
}
