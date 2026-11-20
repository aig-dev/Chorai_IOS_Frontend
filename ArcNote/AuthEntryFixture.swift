import Combine
import CoreFlow
import SwiftUI

enum AuthEntryDestination {
    case signIn
    case signUp
}

/// Account entry uses its live dependencies when this value is absent.
@MainActor
struct AuthEntryOverrides {
    let preflighter: any AccessCodePreflighting
    let codeStore: any CodeStoring
    let login: (String, String) -> AnyPublisher<AuthResponse, NetworkError>
    let sendVerificationCode: (String) -> AnyPublisher<SendVerificationCodeResponse, NetworkError>
    let register: (
        _ username: String,
        _ email: String,
        _ password: String,
        _ verificationCode: String,
        _ accessCode: String?,
        _ idempotencyKey: String?
    ) -> AnyPublisher<AuthResponse, NetworkError>
    let onAuthenticated: (AuthEntryDestination) -> Void
}

private struct AuthEntryOverridesKey: EnvironmentKey {
    static let defaultValue: AuthEntryOverrides? = nil
}

extension EnvironmentValues {
    var authEntryOverrides: AuthEntryOverrides? {
        get { self[AuthEntryOverridesKey.self] }
        set { self[AuthEntryOverridesKey.self] = newValue }
    }
}

#if DEBUG
@MainActor
struct AuthEntryFixtureScreen: View {
    @StateObject private var service = AuthEntryFixtureService()
    @StateObject private var codeStore = PrivateBetaCodeStoreFixture(storedCode: nil)
    @State private var path = NavigationPath()
    @State private var phase: Phase = .entry

    private enum EntryPage: Hashable {
        case signIn
        case privateBeta
    }

    private enum Phase {
        case entry
        case interests
        case complete
    }

    var body: some View {
        Group {
            switch phase {
            case .entry:
                NavigationStack(path: $path) {
                    ChoraiWelcomeView(
                        onLogin: { path.append(EntryPage.signIn) },
                        onStart: { path.append(EntryPage.privateBeta) },
                        remembersIntroduction: false,
                        startsWithSignIn: ProcessInfo.processInfo.environment[
                            "CHORAI_AUTH_ENTRY_STARTS_WITH_SIGN_IN"
                        ] == "1"
                    )
                    .navigationDestination(for: EntryPage.self) { page in
                        switch page {
                        case .signIn:
                            SignInView()
                        case .privateBeta:
                            PrivateBetaEntryView(
                                preflighter: AuthEntryFixturePreflight(),
                                codeStore: codeStore
                            )
                        }
                    }
                }
            case .interests:
                ChooseInterestsView(
                    service: AuthEntryFixtureInterests(),
                    actorID: AuthEntryFixtureService.actorID,
                    onComplete: { phase = .complete }
                )
            case .complete:
                Text("Offline fixture complete")
                    .accessibilityIdentifier("auth-entry.fixture.complete")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .choraiPageBackground()
            }
        }
        .environment(\.authEntryOverrides, overrides)
        .tint(ChoraiTheme.accent)
        .preferredColorScheme(fixtureColorScheme)
    }

    private var fixtureColorScheme: ColorScheme? {
        switch ProcessInfo.processInfo.environment["CHORAI_AUTH_ENTRY_APPEARANCE"] {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var overrides: AuthEntryOverrides {
        AuthEntryOverrides(
            preflighter: AuthEntryFixturePreflight(),
            codeStore: codeStore,
            login: service.login,
            sendVerificationCode: service.sendVerificationCode,
            register: service.register,
            onAuthenticated: { destination in
                switch destination {
                case .signIn: phase = .complete
                case .signUp: phase = .interests
                }
            }
        )
    }
}

@MainActor
private final class AuthEntryFixtureService: ObservableObject {
    static let actorID = "offline-auth-fixture"
    private var sentTo: String?
    private var failNextSend =
        ProcessInfo.processInfo.environment["CHORAI_AUTH_ENTRY_FAIL_FIRST_SEND"] == "1"

    func login(email: String, password: String) -> AnyPublisher<AuthResponse, NetworkError> {
        guard email == "reader@example.invalid", password == "SamplePass42" else {
            return response(.failure(.unauthorized))
        }
        return success(email: email, username: "TrailReader", isNewUser: false)
    }

    func sendVerificationCode(
        email: String
    ) -> AnyPublisher<SendVerificationCodeResponse, NetworkError> {
        if failNextSend {
            failNextSend = false
            return response(.failure(.timeout))
        }
        sentTo = email
        return response(.success(SendVerificationCodeResponse(
            success: true,
            message: nil,
            code: nil,
            errorCode: nil
        )))
    }

    func register(
        username: String,
        email: String,
        password: String,
        verificationCode: String,
        accessCode: String?,
        idempotencyKey: String?
    ) -> AnyPublisher<AuthResponse, NetworkError> {
        guard accessCode == AuthEntryFixturePreflight.acceptedCode,
              idempotencyKey?.isEmpty == false else {
            return response(.failure(.forbidden))
        }
        guard email == sentTo, verificationCode == "123456" else {
            return response(.failure(.api(
                statusCode: 422,
                code: nil,
                message: nil
            )))
        }
        return success(email: email, username: username, isNewUser: true)
    }

    private func success(
        email: String,
        username: String,
        isNewUser: Bool
    ) -> AnyPublisher<AuthResponse, NetworkError> {
        response(.success(AuthResponse(
            success: true,
            message: nil,
            data: AuthResponseData(
                token: "",
                user: User(
                    id: Self.actorID,
                    username: username,
                    email: email,
                    avatar: nil,
                    bio: nil,
                    credit: 0,
                    createdAt: "2026-01-01T09:00:00Z"
                ),
                isNewUser: isNewUser,
                productAccess: AccessState(
                    mode: "private_beta",
                    status: "allowed",
                    scope: "product_full",
                    reasonCode: nil
                )
            )
        )))
    }

    private func response<Value>(
        _ result: Result<Value, NetworkError>
    ) -> AnyPublisher<Value, NetworkError> {
        Just(result)
            .delay(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .setFailureType(to: NetworkError.self)
            .flatMap(\.publisher)
            .eraseToAnyPublisher()
    }
}

private struct AuthEntryFixturePreflight: AccessCodePreflighting {
    static let acceptedCode = "UI-TEST-BETA"

    func preflight(accessCode: String) async throws -> AccessCodePreflightResult {
        AccessCodePreflightResult(available: accessCode == Self.acceptedCode)
    }
}

private struct AuthEntryFixtureInterests: CoreInterestSelectionServing {
    func fetchOptions() async throws -> [String] {
        [
            "Art", "Writing", "Technology", "Design", "Philosophy",
            "Music", "Travel", "Science", "Film", "Photography"
        ]
    }

    func fetchSelection() async throws -> [String] { [] }

    func save(domains: [String]) async throws -> [String] { domains }
}
#endif
