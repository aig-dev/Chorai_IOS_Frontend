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
        XCTAssertTrue(network.contains("AuthAccessPair"))
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

    func testGoogleLoginForwardsThePendingAccessPairAtEveryEntryPoint() throws {
        let entries: [(path: String, pairSource: String)] = [
            ("ArcNote/ContentView.swift", "pendingAccessPair"),
            ("ArcNote/SignInView.swift", "pendingAccessPair"),
            ("ArcNote/SignUpView.swift", "currentAccessPair"),
        ]

        for entry in entries {
            let source = try source(entry.path)

            XCTAssertTrue(source.contains("private func handleGoogleLoginResponse"), entry.path)
            XCTAssertTrue(source.contains("let pair = \(entry.pairSource)()"), entry.path)
            XCTAssertTrue(source.contains("authManager.googleLogin("), entry.path)
            XCTAssertTrue(source.contains("accessCode: pair.code"), entry.path)
            XCTAssertTrue(source.contains("idempotencyKey: pair.key"), entry.path)
        }
    }

    func testPrivateBetaEntryUsesShortCodeFormat() throws {
        let signup = try source("ArcNote/SignUpView.swift")
        let gate = try source("ArcNote/AccessGateView.swift")
        let content = try source("ArcNote/ContentView.swift")

        XCTAssertTrue(gate.contains("struct PrivateBetaEntryView"))
        XCTAssertTrue(gate.contains("private-beta.code"))
        XCTAssertTrue(gate.contains("private-beta.continue"))
        XCTAssertTrue(gate.contains("(9...64).contains(trimmedCode.count)"))
        XCTAssertTrue(gate.contains("TextField(\"CRAI-XXXX\", text: $code)"))
        XCTAssertTrue(content.contains("PrivateBetaEntryView"))
        XCTAssertFalse(signup.contains("signup.access-code"))
        XCTAssertFalse(signup.contains("placeholder: \"CRAI-XXXX\""))
        XCTAssertTrue(signup.contains("signup.get-code"))
        XCTAssertTrue(signup.contains("signup.confirm-password"))
        XCTAssertTrue(signup.contains("password == confirmPassword"))
        XCTAssertTrue(signup.contains("authManager.register("))
        XCTAssertTrue(signup.contains("authManager.googleLogin("))
        XCTAssertTrue(signup.contains("let appleLoginRequest = AppleLoginRequest("))
        XCTAssertTrue(signup.contains("accessCode: pair.code"))
        XCTAssertTrue(signup.contains("idempotencyKey: pair.key"))
        XCTAssertTrue(signup.contains("KeychainStore.shared.load()"))
    }

    func testNativeContextualTipsHaveNoAcknowledgementControls() throws {
        let guide = try source("ArcNote/CoreFlow/OnboardingGuideLine.swift")

        XCTAssertTrue(guide.contains("struct ContextualGuideCallout"))
        XCTAssertTrue(guide.contains("struct ContextualGuideTargetHalo"))
        XCTAssertTrue(guide.contains("Dismiss tip"))
        XCTAssertTrue(guide.contains("accessibilityAction"))
        XCTAssertTrue(guide.contains("accessibilityReduceMotion"))
        XCTAssertTrue(guide.contains("allowsHitTesting(false)"))
        XCTAssertTrue(guide.contains("onboarding.retry"))
        XCTAssertTrue(guide.contains("store.retryPendingEvidence"))
        XCTAssertFalse(guide.contains("Got it"))
        XCTAssertFalse(guide.contains("store.skip"))
        XCTAssertFalse(guide.contains("onboarding.skip"))
    }

    func testEveryNativeOnboardingTipIsWiredToItsRealTarget() throws {
        let tabBar = try source("ArcNote/TabBarView.swift")
        let home = try source("ArcNote/HomeView.swift")
        let flow = try source("ArcNote/CoreFlow/FlowViews.swift")
        let spark = try source("ArcNote/CoreFlow/SparkContinuationViews.swift")
        let merge = try source("ArcNote/CoreFlow/MergeLifecycleViews.swift")

        XCTAssertTrue(tabBar.contains("ContextualGuideTipStore"))
        XCTAssertTrue(tabBar.contains("contextualTipStore.load(actorID: actorID)"))
        XCTAssertTrue(tabBar.contains("contextualTipStore: contextualTipStore"))
        XCTAssertFalse(tabBar.contains("First loop complete"))
        XCTAssertFalse(tabBar.contains("showOnboardingCompletionAcknowledgement"))

        assertSource(home, matches: #"complete\(\s*\.libraryCreate,"#)
        assertSource(home, matches: #"dismiss\(\s*\.libraryCreate,"#)
        XCTAssertTrue(home.contains("ContextualGuideCallout"))
        XCTAssertTrue(home.contains("ContextualGuideTargetHalo"))

        XCTAssertTrue(flow.contains("flow.spark.\\(card.id)"))
        assertSource(flow, matches: #"complete\(\s*\.flowSpark,"#)
        assertSource(flow, matches: #"dismiss\(\s*\.flowSpark,"#)
        assertSource(spark, matches: #"complete\(\s*\.sparkFavorite,"#)
        assertSource(spark, matches: #"dismiss\(\s*\.sparkFavorite,"#)
        assertSource(merge, matches: #"complete\(\s*\.mergeAction,"#)
        assertSource(merge, matches: #"dismiss\(\s*\.mergeAction,"#)
    }

    func testProductionNonTargetInteractionsDismissVisibleTips() throws {
        let home = try source("ArcNote/HomeView.swift")
        let spark = try source("ArcNote/CoreFlow/SparkContinuationViews.swift")
        let merge = try source("ArcNote/CoreFlow/MergeLifecycleViews.swift")

        XCTAssertTrue(home.contains("private func dismissLibraryTipIfVisible()"))
        assertSource(
            home,
            matches: #"dismissLibraryTipIfVisible\(\)\s+showFilterTags\.toggle\(\)"#
        )
        assertSource(
            home,
            matches: #"dismissLibraryTipIfVisible\(\)\s+selectedSegment = 1"#
        )
        assertSource(
            home,
            matches: #"dismissLibraryTipIfVisible\(\)\s+let scope: LibrarySearchScope"#
        )

        assertSource(
            spark,
            matches: #"dismissSparkFavoriteTipIfVisible\(\)\s+store\.selectNode\(activityID: nodeID\)"#
        )
        assertSource(
            spark,
            matches: #"dismissSparkFavoriteTipIfVisible\(\)\s+openAuthor\(author\.id\)"#
        )

        assertSource(
            merge,
            matches: #"abs\(value\.translation\.height\) < 50[\s\S]*dismissMergeTipIfVisible\(\)\s+onBack\(\)"#
        )
        XCTAssertTrue(merge.contains("onChange(of: isTextInputFocused)"))
        XCTAssertTrue(merge.contains("dismissMergeTipIfVisible()"))
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

    private func assertSource(
        _ source: String,
        matches pattern: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotNil(
            source.range(of: pattern, options: .regularExpression),
            "Expected source to match regex: \(pattern)",
            file: file,
            line: line
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
