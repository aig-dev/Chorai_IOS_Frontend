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

    func testPrivateBetaPreflightWireContractIsPublicBoundedAndRedacted() throws {
        let environment = try source("ArcNote/APIEnvironment.swift")
        let models = try source("ArcNote/NetworkModels.swift")
        let network = try source("ArcNote/NetworkManager.swift")
        let access = try source("ArcNote/KeychainStore.swift")

        XCTAssertTrue(environment.contains("/api/auth/access-code/preflight"))
        XCTAssertTrue(models.contains("enum AccessCodePreflightWireResult"))
        XCTAssertTrue(network.contains("func preflightAccessCode"))
        XCTAssertTrue(network.contains("请求参数: <redacted>"))
        XCTAssertTrue(access.contains("AccessCodePreflighting"))

        let methodStart = try XCTUnwrap(
            network.range(of: "func preflightAccessCode")
        ).lowerBound
        let methodEnd = network.range(
            of: "func resolveCampaign",
            range: methodStart..<network.endIndex
        )?.lowerBound ?? network.endIndex
        let method = String(network[methodStart..<methodEnd])

        XCTAssertTrue(method.contains("\"access_code\": input.accessCode"))
        XCTAssertFalse(method.contains("idempotency_key"))
        XCTAssertFalse(method.contains("print(input"))
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
            assertSource(source, matches: #"(?:authManager|AuthManager\.shared)\.googleLogin\("#)
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
    }

    func testSignupSubmitsEmailCodeOnlyWithValidatedRegistrationAndPendingAccessPair() throws {
        let signup = try source("ArcNote/SignUpView.swift")

        XCTAssertTrue(signup.contains("signup.get-code"))
        XCTAssertTrue(signup.contains("signup.confirm-password"))
        XCTAssertTrue(signup.contains("AuthManager.shared.sendVerificationCode(email: email)"))
        XCTAssertTrue(signup.contains("case .code: showUsername = true"))
        XCTAssertTrue(signup.contains("case .confirm: createAccount()"))
        XCTAssertTrue(signup.contains("guard draft.canRegister"))
        XCTAssertTrue(signup.contains("guard pair.code != nil, pair.key != nil"))
        XCTAssertTrue(signup.contains("AuthManager.shared.register("))
        XCTAssertTrue(signup.contains("verificationCode: draft.code"))
        XCTAssertTrue(signup.contains("let appleLoginRequest = AppleLoginRequest("))
        XCTAssertTrue(signup.contains("accessCode: pair.code"))
        XCTAssertTrue(signup.contains("idempotencyKey: pair.key"))
        XCTAssertTrue(signup.contains("authEntryOverrides?.codeStore ?? KeychainStore.shared"))
        XCTAssertTrue(signup.contains("codeStore.load()?.trimmingCharacters"))
        XCTAssertTrue(signup.contains(#"guard response.data.productAccess.status == "allowed""#))
    }

    func testPrivateBetaEntryPersistsOnlyAfterCurrentSuccessfulPreflight() throws {
        let gate = try source("ArcNote/AccessGateView.swift")
        let app = try source("ArcNote/ArcNoteApp.swift")

        XCTAssertTrue(gate.contains("preflighter: any AccessCodePreflighting"))
        XCTAssertTrue(gate.contains("codeStore: any CodeStoring"))
        XCTAssertTrue(gate.contains("guard isChecking == false else { return }"))
        XCTAssertTrue(gate.contains("let result = try await preflighter.preflight"))
        XCTAssertTrue(gate.contains("guard !Task.isCancelled, requestID == id else { return }"))
        XCTAssertTrue(gate.contains("codeStore.save(candidate)"))
        XCTAssertTrue(gate.contains("codeStore.load()?.trimmingCharacters"))
        XCTAssertTrue(gate.contains("storedCode == candidate"))
        XCTAssertTrue(gate.contains("codeStore.clear()"))
        XCTAssertTrue(gate.contains(".disabled(isChecking)"))
        XCTAssertTrue(gate.contains("checkTask?.cancel()"))
        XCTAssertTrue(app.contains("CHORAI_PRIVATE_BETA_PREFLIGHT_FIXTURE"))
        XCTAssertTrue(app.contains("PrivateBetaPreflightFixture"))
        XCTAssertTrue(app.contains("PrivateBetaCodeStoreFixture"))
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
        XCTAssertTrue(tabBar.contains("contextualTipStore.load("))
        XCTAssertTrue(tabBar.contains("actorID: actorID"))
        XCTAssertTrue(tabBar.contains("sessionID: session.sessionID"))
        XCTAssertTrue(tabBar.contains("contextualTipStore: contextualTipStore"))
        XCTAssertFalse(tabBar.contains("First loop complete"))
        XCTAssertFalse(tabBar.contains("showOnboardingCompletionAcknowledgement"))

        assertSource(home, matches: #"complete\(\s*\.libraryCreate,"#)
        assertSource(home, matches: #"dismiss\(\s*\.libraryCreate,"#)
        XCTAssertTrue(home.contains("ContextualGuideCallout"))
        XCTAssertTrue(home.contains("ContextualGuideTargetHalo"))

        XCTAssertTrue(flow.contains("flow.spark.\\(card.id)"))
        XCTAssertTrue(flow.contains("if isFlowSparkTipVisible { return .flowSpark }"))
        assertSource(flow, matches: #"complete\(\s*activeSparkTip,"#)
        assertSource(flow, matches: #"dismiss\(\s*tip,"#)
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
        XCTAssertTrue(home.contains("Picker(\"Sort by\", selection: librarySortSelection)"))
        for bounds in [("private var libraryHeader:", "@ToolbarContentBuilder private var libraryToolbar:"),
                       ("private var librarySearchHeader:", "private var librarySearchInputBackground:")] {
            let start = try XCTUnwrap(home.range(of: bounds.0))
            let end = try XCTUnwrap(home.range(of: bounds.1, range: start.upperBound..<home.endIndex))
            let header = String(home[start.lowerBound..<end.lowerBound])
            XCTAssertTrue(header.contains("Menu { librarySortOptions }"))
            assertSource(header, matches: #"simultaneousGesture\(TapGesture\(\)\.onEnded\s*\{\s*dismissLibraryTipIfVisible\(\)"#)
        }
        assertSource(
            home,
            matches: #"dismissLibraryTipIfVisible\(\)\s+selectedSegment = value"#
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
