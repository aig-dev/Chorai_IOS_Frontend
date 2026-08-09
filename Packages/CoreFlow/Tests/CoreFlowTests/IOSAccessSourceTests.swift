import Foundation
import XCTest

final class IOSAccessSourceTests: XCTestCase {
    func testContentViewGatesEveryAuthenticatedSessionBeforeProduct() throws {
        let source = try source("ArcNote/ContentView.swift")

        XCTAssertTrue(source.contains("AccessGateView"))
        XCTAssertTrue(source.contains("authManager.accessState"))
        XCTAssertTrue(source.contains("authManager.canEnterProduct"))
        XCTAssertTrue(source.contains(".onOpenURL"))
        XCTAssertFalse(
            source.contains(
                "if authManager.isAuthenticated {\n                if showChooseInterests"
            )
        )
    }

    func testAuthModelsCarryFailClosedProductAccess() throws {
        let source = try source("ArcNote/NetworkModels.swift")

        XCTAssertTrue(source.contains("import CoreFlow"))
        XCTAssertTrue(source.contains("let productAccess: AccessState"))
        XCTAssertTrue(source.contains("productAccess = \"product_access\""))
        XCTAssertTrue(source.contains("struct AccessResponse"))
        XCTAssertTrue(source.contains("struct ClaimResponse"))
        XCTAssertTrue(source.contains("struct CampaignResponse"))
    }

    func testPendingCodeUsesDeviceOnlyKeychainStorage() throws {
        let source = try source("ArcNote/KeychainStore.swift")

        XCTAssertTrue(source.contains("kSecClassGenericPassword"))
        XCTAssertTrue(source.contains("com.michen.arcnote.access"))
        XCTAssertTrue(source.contains("kSecAttrAccount: \"pending\""))
        XCTAssertTrue(
            source.contains("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly")
        )
        XCTAssertFalse(source.contains("print("))
    }

    func testAuthRequestsUseOneAtomicAccessPair() throws {
        let network = try source("ArcNote/NetworkManager.swift")
        let auth = try source("ArcNote/AuthManager.swift")
        let signup = try source("ArcNote/SignUpView.swift")

        XCTAssertTrue(network.contains("APIEnvironment.AccessRoute.state"))
        XCTAssertTrue(network.contains("APIEnvironment.AccessRoute.claim"))
        XCTAssertTrue(network.contains("APIEnvironment.AccessRoute.campaign"))
        XCTAssertTrue(network.contains("\"access_code\""))
        XCTAssertTrue(network.contains("\"idempotency_key\""))
        XCTAssertTrue(auth.contains("@Published private(set) var accessState"))
        XCTAssertTrue(auth.contains("var canEnterProduct: Bool"))
        XCTAssertTrue(signup.contains("accessCode:"))
        XCTAssertTrue(signup.contains("idempotencyKey:"))
        XCTAssertFalse(signup.contains("InvitationRegistrationStore"))
        XCTAssertFalse(signup.contains("registrationStore"))
    }

    func testAuthAttemptKeyRotatesWhenThePendingCodeChanges() throws {
        for path in [
            "ArcNote/ContentView.swift",
            "ArcNote/SignInView.swift",
            "ArcNote/SignUpView.swift",
        ] {
            let source = try source(path)
            XCTAssertTrue(source.contains("accessKeyCode"), path)
            XCTAssertTrue(source.contains("accessKeyCode != code"), path)
        }
    }

    func testPrivateBetaEntryUsesShortCodeFormat() throws {
        let signup = try source("ArcNote/SignUpView.swift")
        let gate = try source("ArcNote/AccessGateView.swift")

        XCTAssertTrue(signup.contains("placeholder: \"CRAI-XXXX\""))
        XCTAssertTrue(signup.contains("(9...64).contains(code.count)"))
        XCTAssertTrue(gate.contains("TextField(\"CRAI-XXXX\", text: $code)"))
    }

    func testUniversalLinkAndNewSourcesAreRegistered() throws {
        let entitlements = try source("ArcNote/ArcNote.entitlements")
        let project = try source("ArcNote.xcodeproj/project.pbxproj")

        XCTAssertTrue(
            entitlements.contains("com.apple.developer.associated-domains")
        )
        XCTAssertTrue(entitlements.contains("applinks:chorai.com"))
        XCTAssertTrue(project.contains("AccessGateView.swift in Sources"))
        XCTAssertTrue(project.contains("KeychainStore.swift in Sources"))
    }

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
