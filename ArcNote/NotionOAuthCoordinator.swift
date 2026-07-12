import AuthenticationServices
import Combine
import CoreFlow
import Foundation
import UIKit

@MainActor
protocol NotionOAuthCoordinating: AnyObject {
    func authorize(
        request: NotionAuthorizationRequest,
        completion: @escaping (UUID, NotionAuthorizationResult) -> Void
    )
    func cancel()
}

@MainActor
final class NotionOAuthCoordinatorHolder: ObservableObject {
    let coordinator: any NotionOAuthCoordinating

    init(_ coordinator: any NotionOAuthCoordinating) {
        self.coordinator = coordinator
    }
}

protocol NotionWebAuthenticationSession: AnyObject {
    var presentationContextProvider: ASWebAuthenticationPresentationContextProviding? { get set }
    var prefersEphemeralWebBrowserSession: Bool { get set }
    @discardableResult func start() -> Bool
    func cancel()
}

extension ASWebAuthenticationSession: NotionWebAuthenticationSession {}

protocol NotionWebAuthenticationSessionCreating {
    func makeSession(
        url: URL,
        callbackURLScheme: String,
        completion: @escaping (URL?, Error?) -> Void
    ) -> any NotionWebAuthenticationSession
}

struct SystemNotionWebAuthenticationSessionFactory:
    NotionWebAuthenticationSessionCreating
{
    func makeSession(
        url: URL,
        callbackURLScheme: String,
        completion: @escaping (URL?, Error?) -> Void
    ) -> any NotionWebAuthenticationSession {
        ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackURLScheme,
            completionHandler: completion
        )
    }
}

struct NotionOAuthRequestFence {
    private(set) var activeRequestID: UUID?

    mutating func begin(_ id: UUID) -> Bool {
        guard activeRequestID == nil else { return false }
        activeRequestID = id
        return true
    }

    mutating func consume(_ id: UUID) -> Bool {
        guard activeRequestID == id else { return false }
        activeRequestID = nil
        return true
    }

    mutating func cancel() {
        activeRequestID = nil
    }
}

@MainActor
final class NotionOAuthCoordinator: NSObject, NotionOAuthCoordinating {
    static let callbackScheme = "arcnote"
    static let callbackHost = "notion-connected"

    private let factory: any NotionWebAuthenticationSessionCreating
    private weak var presentationAnchor: UIWindow?
    private var session: (any NotionWebAuthenticationSession)?
    private var requestFence = NotionOAuthRequestFence()

    init(
        factory: any NotionWebAuthenticationSessionCreating =
            SystemNotionWebAuthenticationSessionFactory(),
        presentationAnchor: UIWindow? = nil
    ) {
        self.factory = factory
        self.presentationAnchor = presentationAnchor
    }

    func authorize(
        request: NotionAuthorizationRequest,
        completion: @escaping (UUID, NotionAuthorizationResult) -> Void
    ) {
        guard session == nil, requestFence.begin(request.id) else { return }
        let session = factory.makeSession(
            url: request.url,
            callbackURLScheme: Self.callbackScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self, self.requestFence.consume(request.id) else {
                    return
                }
                self.session = nil
                completion(
                    request.id,
                    Self.authorizationResult(
                        callbackURL: callbackURL,
                        error: error
                    )
                )
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        self.session = session
        guard session.start() else {
            self.session = nil
            requestFence.cancel()
            completion(request.id, .failed)
            return
        }
    }

    func cancel() {
        session?.cancel()
        session = nil
        requestFence.cancel()
    }

    static func authorizationResult(
        callbackURL: URL?,
        error: Error?
    ) -> NotionAuthorizationResult {
        if let error = error as NSError?,
           error.domain == ASWebAuthenticationSessionError.errorDomain,
           error.code == ASWebAuthenticationSessionError.Code.canceledLogin
            .rawValue {
            return .cancelled
        }
        guard error == nil,
              let callbackURL,
              callbackURL.scheme?.lowercased() == callbackScheme,
              callbackURL.host?.lowercased() == callbackHost,
              callbackURL.path.isEmpty,
              let queryItems = URLComponents(
                url: callbackURL,
                resolvingAgainstBaseURL: false
              )?.queryItems else {
            return .failed
        }
        let resultMarkers = queryItems.filter { $0.name == "result" }
        guard resultMarkers.count == 1,
              let marker = resultMarkers[0].value,
              marker.count <= 32 else {
            return .failed
        }
        switch marker.lowercased() {
        case "success": return .success
        case "cancelled": return .cancelled
        default: return .failed
        }
    }
}

extension NotionOAuthCoordinator:
    ASWebAuthenticationPresentationContextProviding
{
    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        if let presentationAnchor { return presentationAnchor }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
