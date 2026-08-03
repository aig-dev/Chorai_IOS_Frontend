import Combine
import Foundation

public enum AccessPhase: Equatable, Sendable {
    case loading
    case allowed
    case required
    case claiming
    case failed
}

@MainActor
public final class AccessStore: ObservableObject {
    @Published public private(set) var phase: AccessPhase = .loading
    @Published public private(set) var state: AccessState?
    @Published public private(set) var pendingCode: String?
    @Published public private(set) var message: String?

    private let service: any AccessServing
    private let codes: any CodeStoring
    private let hosts: Set<String>
    private var attemptCode: String?
    private var attemptKey: String?
    private var generation = UUID()

    public init(
        service: any AccessServing,
        codes: any CodeStoring,
        hosts: Set<String>
    ) {
        self.service = service
        self.codes = codes
        self.hosts = Set(hosts.map { $0.lowercased() })
        let saved = Self.normalized(codes.load())
        pendingCode = saved
        if saved == nil { codes.clear() }
    }

    public convenience init(
        service: any AccessServing,
        codes: any CodeStoring,
        hosts: [String]
    ) {
        self.init(service: service, codes: codes, hosts: Set(hosts))
    }

    @discardableResult
    public func capture(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              hosts.contains(host),
              url.path == "/join",
              url.query == nil,
              let fragment = url.fragment,
              let components = URLComponents(string: "https://join.invalid/?\(fragment)"),
              let items = components.queryItems,
              items.count == 1,
              items[0].name == "code",
              let code = Self.normalized(items[0].value) else {
            return false
        }
        save(code)
        return true
    }

    public func save(_ rawCode: String) {
        guard let code = Self.normalized(rawCode) else {
            clear()
            phase = .required
            return
        }
        if pendingCode != code {
            attemptCode = nil
            attemptKey = nil
        }
        codes.save(code)
        pendingCode = code
        message = nil
        if phase == .failed { phase = .required }
    }

    public func clear() {
        codes.clear()
        pendingCode = nil
        attemptCode = nil
        attemptKey = nil
        message = nil
    }

    public func load() async {
        generation = UUID()
        let requestedGeneration = generation
        phase = .loading
        message = nil
        do {
            let next = try await service.get()
            guard requestedGeneration == generation else { return }
            apply(next)
        } catch is CancellationError {
            return
        } catch {
            guard requestedGeneration == generation else { return }
            state = nil
            phase = .failed
            message = "Access is temporarily unavailable. Please try again."
        }
    }

    public func claim() async {
        guard let code = Self.normalized(pendingCode ?? codes.load()) else {
            phase = .required
            message = "Enter your access code to continue."
            return
        }
        pendingCode = code
        let key = key(for: code)
        phase = .claiming
        message = nil

        do {
            let result = try await service.claim(
                ClaimInput(accessCode: code, idempotencyKey: key)
            )
            guard result.access.isValid else {
                state = nil
                phase = .failed
                message = "Access is temporarily unavailable. Please try again."
                return
            }
            apply(result.access)
            if result.access.status == "required" {
                message = "We could not use that code. Check it and try again."
            }
        } catch is CancellationError {
            phase = .required
        } catch {
            phase = .required
            message = "We could not use that code. Check it and try again."
        }
    }

    private func apply(_ next: AccessState) {
        guard next.isValid else {
            state = nil
            phase = .failed
            message = "Access is temporarily unavailable. Please try again."
            return
        }
        state = next
        if next.status == "allowed" {
            clear()
            phase = .allowed
        } else {
            phase = next.mode == "unavailable" ? .failed : .required
        }
    }

    private func key(for code: String) -> String {
        if attemptCode == code, let attemptKey { return attemptKey }
        let key = "ios-\(UUID().uuidString.lowercased())"
        attemptCode = code
        attemptKey = key
        return key
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.isEmpty == false, code.count <= 64 else { return nil }
        return code
    }
}
