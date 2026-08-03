import Combine
import CoreFlow
import Foundation
import Security

final class KeychainStore: CodeStoring, @unchecked Sendable {
    static let shared = KeychainStore()

    private static let service = "com.michen.arcnote.access"
    private static let account = "pending"

    private init() {}

    func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              let code = Self.normalized(value) else {
            return nil
        }
        return code
    }

    func save(_ value: String) {
        guard let code = Self.normalized(value) else {
            clear()
            return
        }

        let item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: "pending",
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: Data(code.utf8),
        ]
        let updates: [CFString: Any] = [
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: Data(code.utf8),
        ]

        let status = SecItemUpdate(
            Self.baseQuery as CFDictionary,
            updates as CFDictionary
        )
        if status == errSecItemNotFound {
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(Self.baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private var baseQuery: [String: Any] { Self.baseQuery }

    private static func normalized(_ value: String) -> String? {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.isEmpty == false, code.count <= 64 else { return nil }
        return code
    }
}

final class NetworkAccess: AccessServing, @unchecked Sendable {
    static let shared = NetworkAccess()

    private let network: NetworkManager

    private init(network: NetworkManager = .shared) {
        self.network = network
    }

    func get() async throws -> AccessState {
        let response = try await first(network.getAccess())
        guard response.success, response.data.isValid else {
            throw NetworkError.decodingError
        }
        return response.data
    }

    func claim(_ input: ClaimInput) async throws -> ClaimResult {
        let response = try await first(network.claimAccess(input))
        guard response.success, response.data.access.isValid else {
            throw NetworkError.decodingError
        }
        return response.data
    }

    func campaign() async -> CampaignBlock? {
        do {
            let response = try await first(network.resolveCampaign())
            guard response.success, response.data.isSupported else { return nil }
            return response.data
        } catch {
            return nil
        }
    }

    private func first<T>(
        _ publisher: AnyPublisher<T, NetworkError>
    ) async throws -> T {
        var values = publisher.values.makeAsyncIterator()
        guard let value = try await values.next() else {
            throw NetworkError.unknown
        }
        return value
    }
}
