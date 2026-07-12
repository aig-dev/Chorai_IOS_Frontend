import XCTest

final class ArcNoteUITests: XCTestCase {
    private var app: XCUIApplication!
    private var sparkSessionScope: String!
    private static var cachedSmokeSession: SmokeSession?

    private var sparkSeedCardID: String {
        ProcessInfo.processInfo.environment["CHORAI_UI_TEST_SPARK_CARD_ID"]
            ?? "ast_cs_art_88ba36bc8dea"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        sparkSessionScope = "\(name).\(UUID().uuidString)"
    }

    func testNotificationContractFixtureRoute() throws {
        app.launchArguments.append("--ui-test-notification-contract")
        app.launch()

        XCTAssertEqual(
            waitFor("notification.contract.actor").label,
            "act_source"
        )
        XCTAssertEqual(
            waitFor("notification.contract.asset").label,
            "ast_1"
        )
        XCTAssertEqual(
            waitFor("notification.contract.legacy").label,
            "legacy"
        )
        XCTAssertEqual(
            waitFor("notification.contract.unread-count").label,
            "2"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["notification.contract.error"]
                .exists
        )
    }

    func testChoraProfileContractFixtureRoute() throws {
        app.launchArguments.append("--ui-test-chora-contract")
        app.launch()

        let fixtureError = app.descendants(matching: .any)[
            "chora.contract.error"
        ]
        if fixtureError.waitForExistence(timeout: 2) {
            XCTFail("Chora contract fixture failed: \(fixtureError.label)")
        }

        let expectedValues = [
            "chora.contract.human-actor-id": "act_human_contract",
            "chora.contract.agent-actor-id": "act_agent_contract",
            "chora.contract.preferred-address": "Avery",
            "chora.contract.avatar-url": "https://cdn.chorai.test/agent.png",
            "chora.contract.growth-stage": "4",
            "chora.contract.growth.curiosity": "1.25",
            "chora.contract.growth.insight": "2.5",
            "chora.contract.growth.creativity": "3.75",
            "chora.contract.growth.empathy": "5.0",
            "chora.contract.growth.judgment": "6.25",
            "chora.contract.growth.resonance": "7.5",
            "chora.contract.import.client-request-id": "req_import_contract",
            "chora.contract.import.job-id": "job_import_contract",
            "chora.contract.import.total-files": "2",
            "chora.contract.import.imported-count": "1",
            "chora.contract.import.asset-id": "ast_import_contract",
            "chora.contract.import.nullable-fields": "nil,nil,nil,nil,nil,nil,nil",
            "chora.contract.import.unknown-status": "future_import_state",
            "chora.contract.import.unknown-soul-status": "future_soul_state",
            "chora.contract.notion.workspace-id": "workspace_contract",
            "chora.contract.notion.page-id": "page_contract",
            "chora.contract.notion.enqueue-job-id": "job_notion_contract",
            "chora.contract.notion.job-id": "job_notion_detail_contract",
            "chora.contract.notion.nullable-fields": "nil,nil",
            "chora.contract.notion.unknown-job-status": "future_notion_state",
            "chora.contract.notion.unknown-page-status": "future_page_state",
            "chora.contract.notion.page-sync-fields": "page_contract,nil,future_page_state,nil,nil,0",
            "chora.contract.notion.connect-auth-url": "https://api.notion.test/oauth?state=opaque_contract",
            "chora.contract.notion.connect-state": "state_contract",
            "chora.contract.notion.disconnect": "disconnected",
            "chora.contract.request.identity": "GET /api/agent/profile|GET /api/agent/users|GET /api/v1/profile/me|presentsError:false",
            "chora.contract.request.profile-writes": "PATCH /api/agent/users/:agent_actor_id display_name|PUT /api/v1/profile/me preferred_address|PUT /api/v1/profile/agent/avatar agent_actor_id,avatar|presentsError:false",
            "chora.contract.request.growth": "GET /api/v1/growth/view actor_id|presentsError:false",
            "chora.contract.request.note-import": "POST /api/v1/imports/notes files,source_keys,labels,client_request_id threshold=0|GET /api/v1/imports/notes limit|GET /api/v1/imports/notes/:job_id|POST /api/v1/imports/notes/:job_id/cancel|presentsError:false",
            "chora.contract.request.notion": "GET /api/v1/integrations/notion/connect client=ios|GET /api/v1/integrations/notion/status|GET /api/v1/integrations/notion/pages q|POST /api/v1/integrations/notion/import page_ids|GET /api/v1/integrations/notion/import/:job_id|DELETE /api/v1/integrations/notion/connect|presentsError:false",
            "chora.contract.scope.atomic-failure": "acquire:a,acquire:b,release:a,no-upload",
            "chora.contract.scope.cancel-order": "acquire:a,upload,cancel,terminated,release:a",
            "chora.contract.scope.cancel-result": "CancellationError",
            "chora.contract.scope.duplicate-count": "acquire:1,release:1",
            "chora.contract.transport.cancel-immediate": "true",
            "chora.contract.transport.pending-before-terminal": "true",
            "chora.contract.transport.terminal-order": "cancel,pending,terminal,release:a,completion"
        ]

        for (identifier, expectedValue) in expectedValues {
            XCTAssertEqual(waitFor(identifier).label, expectedValue)
        }
        XCTAssertFalse(app.descendants(matching: .any)["chora.contract.error"].exists)
    }

    func testNotificationInboxUIContract() throws {
        app.launchArguments.append("--ui-test-notification-inbox")
        app.launchEnvironment["CHORAI_NOTIFICATION_FIXTURE_MODE"] = "loaded"
        app.launch()

        waitFor("screen.notification-inbox")
        waitFor("notification.list.loaded")
        waitFor("notification.row.ntf_follow")
        waitFor("notification.row.ntf_like")
        waitFor("notification.row.ntf_system")
        waitFor("notification.unread-dot.ntf_follow")

        app.buttons["Notification filters"].tap()
        tap("notification.filter.unread")
        XCTAssertTrue(app.descendants(matching: .any)["notification.row.ntf_follow"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["notification.row.ntf_like"].exists)

        tap("notification.filter.activity")
        XCTAssertTrue(app.descendants(matching: .any)["notification.row.ntf_follow"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["notification.row.ntf_like"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["notification.row.ntf_system"].exists)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.16))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.22, dy: 0.16)
                )
            )
        tap("notification.filter.system")
        waitFor("notification.row.ntf_system")
        XCTAssertFalse(app.descendants(matching: .any)["notification.row.ntf_follow"].exists)

        app.terminate()
        app.launch()
        waitFor("notification.row.ntf_follow")
        app.buttons["Notification filters"].tap()
        app.buttons["Read All"].tap()
        XCTAssertFalse(
            app.descendants(matching: .any)["notification.unread-dot.ntf_follow"]
                .waitForExistence(timeout: 1)
        )

        tap("notification.row.ntf_follow")
        XCTAssertEqual(
            waitFor("notification.fixture.actor-destination").label,
            "act_source"
        )
        app.navigationBars.buttons.firstMatch.tap()

        tap("notification.row.ntf_like")
        XCTAssertEqual(
            waitFor("notification.fixture.asset-destination").label,
            "ast_card"
        )

        app.terminate()
        app.launchEnvironment["CHORAI_NOTIFICATION_FIXTURE_MODE"] = "empty"
        app.launch()
        XCTAssertTrue(app.staticTexts["No notifications"].waitForExistence(timeout: 10))

        app.terminate()
        app.launchEnvironment["CHORAI_NOTIFICATION_FIXTURE_MODE"] = "mark-read-failure"
        app.launch()
        waitFor("notification.row.ntf_follow")
        app.buttons["Notification filters"].tap()
        app.buttons["Read All"].tap()
        XCTAssertTrue(
            app.staticTexts["Couldn’t update notification. Try again."]
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testMainTabsRenderAgainstSeededGoSession() throws {
        launchAuthenticatedApp()

        waitFor("tab.flow")
        waitFor("tab.library")
        waitFor("tab.chat")

        tap("tab.library")
        waitFor("screen.home.content", timeout: 20)

        tap("tab.chat")
        waitFor("screen.chat.content", timeout: 20)

        tap("tab.flow")
        waitFor("screen.flow.content", timeout: 20)
    }

    func testExploreSearchSubmitsAgainstGoSearchRoute() throws {
        launchAuthenticatedApp()

        waitFor("tab.flow")
        waitFor("screen.flow.content", timeout: 20)

        tap("explore.search")
        waitFor("explore.search.invoked", timeout: 10)
        waitFor("explore.search.completed", timeout: 30)
    }

    func testExploreTypedSearchResultTapOpensGoDetailRoute() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)

        let searchToken = "typed-search-\(Int(Date().timeIntervalSince1970))"
        let cardId = try createPublicSmokeCard(token: session.token, searchToken: searchToken)
        defer {
            deleteSmokeCard(id: cardId, token: session.token)
        }

        launchAuthenticatedApp()

        waitFor("tab.flow")
        waitFor("screen.flow.content", timeout: 20)
        openExploreSearchMode()

        let input = waitFor("explore.search.input")
        input.tap()
        input.typeText(searchToken)
        input.typeText("\n")

        waitFor("explore.search.results", timeout: 30)
        let resultCardId = waitFor("explore.search.result.card-id", timeout: 10)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(resultCardId, cardId)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52)).tap()

        waitFor("screen.detail.loaded", timeout: 30)
        let detailCardId = waitFor("screen.detail.card-id", timeout: 10)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(detailCardId, cardId)
    }

    func testExploreSearchResultFavoriteLikeMutateGoState() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)

        let searchToken = "favorite-like-\(Int(Date().timeIntervalSince1970))"
        let cardId = try createPublicSmokeCard(token: session.token, searchToken: searchToken)
        defer {
            clearFavoriteLikeState(id: cardId, token: session.token)
            deleteSmokeCard(id: cardId, token: session.token)
        }

        XCTAssertFalse(try fetchAssetStatus(kind: "favorites", id: cardId, token: session.token))
        XCTAssertFalse(try fetchAssetStatus(kind: "likes", id: cardId, token: session.token))

        launchAuthenticatedApp()
        showExploreSearchResult(searchToken: searchToken, expectedCardId: cardId)

        tap("card.favorite.\(cardId)")
        waitForAssetStatus(kind: "favorites", id: cardId, token: session.token, expected: true)

        tap("card.like.\(cardId)")
        waitForAssetStatus(kind: "likes", id: cardId, token: session.token, expected: true)
    }

    func testChatConversationSendMessageAppearsInGoList() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)

        let targetActorId = ProcessInfo.processInfo.environment["CHORAI_UI_TEST_CHAT_TARGET"] ?? "act_ag_sci"
        let conversationId = try createSmokeConversation(targetActorId: targetActorId, token: session.token)
        let messageText = "iOS UI chat \(Int(Date().timeIntervalSince1970))"

        launchAuthenticatedApp()

        tap("tab.chat")
        waitFor("screen.chat.content", timeout: 20)
        tap("chat.conversation.\(conversationId)")

        waitFor("chat.detail.loaded", timeout: 30)
        let visibleConversationId = waitFor("chat.detail.conversation-id", timeout: 10)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(visibleConversationId, conversationId)

        let input = waitFor("chat.message.input", timeout: 10)
        input.tap()
        input.typeText(messageText)
        tap("chat.message.send")

        waitForStaticText(messageText, timeout: 30)
        waitForChatMessage(conversationId: conversationId, content: messageText, token: session.token)
    }

    func testDetailMergeMenuCreatesArtifactAndCancelsGoJob() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)

        let uniqueSuffix = Int(Date().timeIntervalSince1970)
        let sourceToken = "merge-source-\(uniqueSuffix)"
        let targetToken = "merge-target-\(uniqueSuffix)"
        let sourceCardId = try createPublicSmokeCard(token: session.token, searchToken: sourceToken)
        let targetCardId = try createPublicSmokeCard(token: session.token, searchToken: targetToken)
        defer {
            deleteSmokeCard(id: sourceCardId, token: session.token)
            deleteSmokeCard(id: targetCardId, token: session.token)
        }

        app.launchArguments.append("--ui-test-open-recommended-detail")
        app.launchEnvironment["CHORAI_UI_TEST_DETAIL_CARD_ID"] = sourceCardId
        app.launchEnvironment[
            "CHORAI_UI_TEST_MERGE_SESSION_SCOPE"
        ] = sparkSessionScope
        launchAuthenticatedApp()

        waitFor("screen.detail.loaded", timeout: 30)
        let visibleSourceId = waitFor("screen.detail.card-id", timeout: 10)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(visibleSourceId, sourceCardId)

        tap("detail.menu.open")
        tap("popup-menu.item.merge")

        waitFor("screen.merge.loaded", timeout: 30)
        let mergeSourceId = waitFor("merge.source.card-id", timeout: 20)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(mergeSourceId, sourceCardId)

        waitForMergeCardsLoaded()
        let searchInput = waitFor("merge.search.input", timeout: 20)
        searchInput.tap()
        searchInput.typeText(targetToken)

        waitFor("merge.card.\(targetCardId)", timeout: 30)
        tap("merge.card.\(targetCardId)")
        XCTAssertEqual(app.descendants(matching: .any)["merge.card.\(targetCardId)"].value as? String, "selected")
        dismissKeyboard()
        captureMergeVisual("selection")

        tap("merge.action")
        waitFor("merge.job.id", timeout: 30)
        captureMergeVisual("processing")

        waitForMergeArtifactReady(timeout: 90)

        let jobID = mergeAnchorValue("merge.job.id")
        XCTAssertFalse(jobID.isEmpty)
        XCTAssertEqual(mergeAnchorValue("merge.job.status"), "ARTIFACT_READY")
        XCTAssertEqual(
            try fetchSmokeMergeJob(jobID: jobID, token: session.token).status,
            "ARTIFACT_READY"
        )

        let title = waitFor("merge.artifact.title")
        XCTAssertEqual(title.elementType, .textField)
        XCTAssertFalse(
            (title.value as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )
        let body = waitFor("merge.artifact.body")
        XCTAssertNotEqual(body.elementType, .textField)
        XCTAssertNotEqual(body.elementType, .textView)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        captureMergeVisual("artifact-ready")

        tap("merge.cancel")
        let cancel = app.sheets.buttons["Cancel Merge"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        cancel.tap()
        waitFor("merge.phase.cancelled", timeout: 30)
        captureMergeVisual("cancelled")
        XCTAssertEqual(
            try fetchSmokeMergeJob(jobID: jobID, token: session.token).status,
            "CANCELLED"
        )
    }

    func testMergeRelaunchResumesCommitsAndOpensCanonicalCard() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)

        let uniqueSuffix = Int(Date().timeIntervalSince1970)
        let sourceToken = "merge-resume-source-\(uniqueSuffix)"
        let targetToken = "merge-resume-target-\(uniqueSuffix)"
        let committedTitle = "iOS resumed merge \(uniqueSuffix)"
        let sourceCardID = try createPublicSmokeCard(
            token: session.token,
            searchToken: sourceToken
        )
        let targetCardID = try createPublicSmokeCard(
            token: session.token,
            searchToken: targetToken
        )
        var committedCardID: String?
        defer {
            if let committedCardID {
                deleteSmokeCard(id: committedCardID, token: session.token)
            }
            deleteSmokeCard(id: sourceCardID, token: session.token)
            deleteSmokeCard(id: targetCardID, token: session.token)
        }

        app.launchArguments.append("--ui-test-open-recommended-detail")
        app.launchEnvironment["CHORAI_UI_TEST_DETAIL_CARD_ID"] = sourceCardID
        app.launchEnvironment[
            "CHORAI_UI_TEST_MERGE_SESSION_SCOPE"
        ] = sparkSessionScope
        launchAuthenticatedApp()

        waitFor("screen.detail.loaded", timeout: 30)
        tap("detail.menu.open")
        tap("popup-menu.item.merge")
        waitFor("screen.merge.loaded", timeout: 30)
        waitForMergeCardsLoaded()

        let searchInput = waitFor("merge.search.input", timeout: 20)
        searchInput.tap()
        searchInput.typeText(targetToken)
        waitFor("merge.card.\(targetCardID)", timeout: 30)
        tap("merge.card.\(targetCardID)")
        dismissKeyboard()
        tap("merge.action")
        waitForMergeArtifactReady(timeout: 90)
        let originalJobID = mergeAnchorValue("merge.job.id")
        XCTAssertEqual(mergeAnchorValue("merge.job.status"), "ARTIFACT_READY")

        app.terminate()
        app.launchArguments.removeAll {
            $0 == "--ui-test-open-recommended-detail"
        }
        launchAuthenticatedApp()

        waitFor("screen.flow.content", timeout: 30)
        waitFor("merge.resume", timeout: 20)
        captureMergeVisual("resume-affordance")
        tap("merge.resume")

        waitFor("screen.merge.loaded", timeout: 30)
        waitForMergeArtifactReady(timeout: 30)
        XCTAssertEqual(mergeAnchorValue("merge.job.id"), originalJobID)
        XCTAssertEqual(mergeAnchorValue("merge.job.status"), "ARTIFACT_READY")

        replaceText("merge.artifact.title", with: committedTitle)
        dismissKeyboard()
        tap("merge.commit")
        committedCardID = waitForCommittedMergeCard(
            excluding: sourceCardID,
            timeout: 90
        )

        guard let committedCardID else {
            XCTFail("Merge commit did not expose a canonical card ID")
            return
        }
        XCTAssertEqual(
            try fetchSmokeMergeJob(
                jobID: originalJobID,
                token: session.token
            ).status,
            "COMMITTED_CARD"
        )
        let committedCard = try fetchSmokeCard(
            id: committedCardID,
            token: session.token
        )
        XCTAssertEqual(committedCard.title, committedTitle)
        XCTAssertFalse(
            committedCard.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )
        waitForLoadedDetailCard(committedCardID, timeout: 30)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        captureMergeVisual("committed-detail")

        app.terminate()
        launchAuthenticatedApp()
        waitFor("screen.flow.content", timeout: 30)
        XCTAssertFalse(
            app.descendants(matching: .any)["merge.resume"]
                .waitForExistence(timeout: 3),
            "Completed Merge recovery should be cleared after opening detail"
        )
    }

    func testRevokedSessionRelaunchReturnsToWelcome() throws {
        let session = try requireFreshSmokeSession()
        seedAppSession(session)
        launchAuthenticatedApp()

        waitFor("screen.flow.content", timeout: 30)
        waitForSessionPhase("verified", timeout: 30)

        app.terminate()
        try revokeSmokeSession(token: session.token)
        app.launch()

        waitFor("welcome.login", timeout: 30)
        waitForSessionPhase("signed-out", timeout: 10)
        XCTAssertFalse(exists("screen.flow.content", timeout: 1))
    }

    func testOfflineSessionVerificationKeepsRestoredShell() throws {
        let session = try requireFreshSmokeSession()
        seedAppSession(session)
        app.launchEnvironment["CHORAI_UI_TEST"] = "1"
        app.launchEnvironment["CHORAI_API_BASE_URL"] = "http://127.0.0.1:1"
        app.launch()

        waitFor("tab.flow", timeout: 15)
        waitForSessionPhase("degraded", timeout: 30)
        XCTAssertTrue(exists("screen.flow.content", timeout: 2))
    }

    func testSessionActorMismatchClearsLocalProjection() throws {
        let session = try requireFreshSmokeSession()
        seedAppSession(session)
        app.launchEnvironment["CHORAI_UI_TEST"] = "1"
        app.launchEnvironment["CHORAI_UI_TEST_ACTOR_ID"] = "act_mismatch"
        if let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] {
            app.launchEnvironment["CHORAI_API_BASE_URL"] = baseURL
        }
        app.launch()

        waitFor("welcome.login", timeout: 30)
        waitForSessionPhase("signed-out", timeout: 10)
    }

    func testSettingsLogoutRevokesCanonicalGoSession() throws {
        let session = try requireFreshSmokeSession()
        seedAppSession(session)
        launchAuthenticatedApp()

        waitForSessionPhase("verified", timeout: 30)
        tap("side-menu.open")
        tap("side-menu.settings")
        waitFor("screen.settings.loaded", timeout: 20)
        captureVisual("session-settings-before-logout")

        tap("settings.logout")
        let confirmation = app.alerts.buttons["Log Out"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirmation.tap()

        waitFor("welcome.login", timeout: 30)
        waitForSessionPhase("signed-out", timeout: 10)
        XCTAssertFalse(
            app.alerts.firstMatch.waitForExistence(timeout: 2),
            "Logout should not leave an authenticated-screen error over welcome"
        )
        captureVisual("session-welcome-after-logout")
        try assertSmokeTokenUnauthorized(session.token)
    }

    func testSettingsLogoutTransportFailureKeepsRestoredSession() throws {
        let session = try requireFreshSmokeSession()
        seedAppSession(session)
        app.launchEnvironment["CHORAI_UI_TEST"] = "1"
        app.launchEnvironment["CHORAI_API_BASE_URL"] = "http://127.0.0.1:1"
        app.launch()

        waitFor("screen.flow.content", timeout: 15)
        waitForSessionPhase("degraded", timeout: 30)
        tap("side-menu.open")
        tap("side-menu.settings")
        waitFor("screen.settings.loaded", timeout: 20)
        tap("settings.logout")

        let confirmation = app.alerts.buttons["Log Out"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirmation.tap()

        waitFor("settings.logout.error", timeout: 15)
        XCTAssertTrue(exists("settings.logout", timeout: 2))
        XCTAssertFalse(exists("welcome.login", timeout: 2))
        XCTAssertEqual(
            try verifySmokeToken(token: session.token).user.id,
            session.actorId,
            "A transport failure must not revoke or discard the current session"
        )
    }

    func testCanonicalOnboardingRecordAndFlowResumeGoV1() throws {
        let smoke = try requireFreshSmokeSession()
        let started = try restartSmokeOnboarding(
            token: smoke.token,
            flowVersion: 1
        )
        XCTAssertEqual(started.state, "elicit_signal")

        seedAppSession(smoke)
        app.launchEnvironment["CHORAI_UI_TEST_ONBOARDING"] = "1"
        launchAuthenticatedApp()

        waitForSessionPhase("verified", timeout: 30)
        waitForOnboardingAnchor("onboarding.state", value: "elicit_signal")
        waitFor("record.sheet", timeout: 30)
        captureVisual("onboarding-record-handoff")

        let signal = "iOS onboarding signal \(Int(Date().timeIntervalSince1970))"
        replaceText("record.input", with: signal)
        tapButton("record.save")

        waitForOnboardingAnchor("onboarding.state", value: "deepen_signal")
        waitFor("onboarding.choice.accurate", timeout: 15)
        captureVisual("onboarding-deepen-choice")
        tap("onboarding.choice.accurate")

        waitForOnboardingAnchor(
            "onboarding.state",
            value: "product_explore_card",
            timeout: 30
        )
        waitFor("onboarding.guide", timeout: 15)
        let visibleCardID = waitFor("flow.visible-card.id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(visibleCardID.isEmpty)
        captureVisual("onboarding-flow-guide")

        tap("flow.skip.\(visibleCardID)")
        waitForOnboardingAnchor(
            "onboarding.state",
            value: "product_spark_intro",
            timeout: 30
        )

        let canonical = try fetchCurrentSmokeOnboarding(token: smoke.token)
        XCTAssertEqual(canonical.sessionID, started.sessionID)
        XCTAssertEqual(canonical.flowVersion, 1)
        XCTAssertEqual(canonical.state, "product_spark_intro")

        app.terminate()
        app.launch()
        waitForSessionPhase("verified", timeout: 30)
        waitForOnboardingAnchor(
            "onboarding.state",
            value: "product_spark_intro",
            timeout: 30
        )
        waitForOnboardingAnchor(
            "onboarding.session.id",
            value: started.sessionID,
            timeout: 10
        )
        captureVisual("onboarding-v1-resumed")
    }

    func testCanonicalOnboardingCompletesRealGoFirstLoop() throws {
        let smoke = try requireFreshSmokeSession()
        let started = try restartSmokeOnboarding(
            token: smoke.token,
            flowVersion: 1
        )
        XCTAssertEqual(started.state, "elicit_signal")

        seedAppSession(smoke)
        app.launchEnvironment["CHORAI_UI_TEST_ONBOARDING"] = "1"
        app.launchEnvironment[
            "CHORAI_UI_TEST_SPARK_SESSION_SCOPE"
        ] = sparkSessionScope
        app.launchEnvironment[
            "CHORAI_UI_TEST_MERGE_SESSION_SCOPE"
        ] = sparkSessionScope
        launchAuthenticatedApp()

        var recordedCardID: String?
        var savedSparkCardID: String?
        var committedCardID: String?
        defer {
            if let committedCardID {
                deleteSmokeCard(id: committedCardID, token: smoke.token)
            }
            if let savedSparkCardID {
                deleteFavorite(id: savedSparkCardID, token: smoke.token)
            }
            if let recordedCardID {
                deleteSmokeCard(id: recordedCardID, token: smoke.token)
            }
        }

        waitForSessionPhase("verified", timeout: 30)
        waitForOnboardingAnchor("onboarding.state", value: "elicit_signal")
        waitFor("record.sheet", timeout: 30)
        let signal = "iOS complete loop \(Int(Date().timeIntervalSince1970))"
        replaceText("record.input", with: signal)
        tapButton("record.save")
        recordedCardID = waitFor("record.created-card-id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(recordedCardID?.isEmpty ?? true)

        waitForOnboardingAnchor("onboarding.state", value: "deepen_signal")
        tap("onboarding.choice.accurate")
        waitForOnboardingAnchor(
            "onboarding.state",
            value: "product_explore_card",
            timeout: 30
        )
        let firstFlowCardID = waitFor("flow.visible-card.id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        tap("flow.skip.\(firstFlowCardID)")
        waitForOnboardingAnchor(
            "onboarding.state",
            value: "product_spark_intro",
            timeout: 30
        )

        let sparkSourceID = waitFor("flow.visible-card.id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        openFlowSparkWithResults(startingCardID: sparkSourceID)
        waitForSmokeOnboardingState(
            "product_save_material",
            token: smoke.token,
            timeout: 30
        )
        waitFor("onboarding.guide", timeout: 15)
        captureVisual("onboarding-spark-save")

        let sparkResultID = try waitForCompactUnfavoritedSparkResult(
            token: smoke.token
        )
        let mergeSearchQuery = mergeCandidateSearchQuery(
            for: try fetchSmokeCard(id: sparkResultID, token: smoke.token)
        )
        savedSparkCardID = sparkResultID
        waitFor("spark.card.\(sparkResultID)").swipeRight()
        waitForAssetStatus(
            kind: "favorites",
            id: sparkResultID,
            token: smoke.token,
            expected: true
        )

        waitForOnboardingAnchor(
            "onboarding.state",
            value: "product_merge_intro",
            timeout: 30
        )
        waitFor("screen.home.content", timeout: 30)
        captureVisual("onboarding-library-merge-intro")

        guard let recordedCardID else {
            XCTFail("Record did not expose its canonical card ID")
            return
        }
        waitFor("card.home.\(recordedCardID)", timeout: 30)
        tap("home.card.menu.\(recordedCardID)")
        tap("popup-menu.item.merge")
        waitFor("screen.merge.loaded", timeout: 30)
        waitForMergeCardsLoaded()
        let mergeSearchInput = waitFor("merge.search.input", timeout: 10)
        mergeSearchInput.tap()
        mergeSearchInput.typeText(mergeSearchQuery)
        waitFor("merge.card.\(sparkResultID)", timeout: 30)
        tap("merge.card.\(sparkResultID)")
        dismissKeyboard()
        tap("merge.action")

        waitForSmokeOnboardingState(
            "product_merge_preview",
            token: smoke.token,
            timeout: 30
        )
        waitFor("onboarding.guide", timeout: 15)
        waitForMergeArtifactReady(timeout: 90)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        captureVisual("onboarding-merge-preview")
        tap("merge.commit")

        waitForOnboardingAnchor(
            "onboarding.phase",
            value: "completed",
            timeout: 90
        )
        waitFor("onboarding.completed", timeout: 10)
        captureVisual("onboarding-first-loop-complete")
        waitFor("screen.home.content", timeout: 30)
        committedCardID = waitFor("record.created-card-id", timeout: 20)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotEqual(committedCardID, recordedCardID)

        let status = try fetchSmokeOnboardingStatus(token: smoke.token)
        XCTAssertTrue(status.completed)
        XCTAssertFalse(status.needsOnboarding)
        XCTAssertEqual(status.latestSessionID, started.sessionID)
        XCTAssertNil(status.activeSessionID)
    }

    func testActiveWebV2OnboardingIsNotMutatedByIOS() throws {
        let smoke = try requireFreshSmokeSession()
        let started = try restartSmokeOnboarding(
            token: smoke.token,
            flowVersion: 2
        )
        XCTAssertEqual(started.flowVersion, 2)

        seedAppSession(smoke)
        app.launchEnvironment["CHORAI_UI_TEST_ONBOARDING"] = "1"
        launchAuthenticatedApp()

        waitForSessionPhase("verified", timeout: 30)
        waitForOnboardingAnchor(
            "onboarding.phase",
            value: "deferred:2",
            timeout: 30
        )
        waitForOnboardingAnchor(
            "onboarding.session.id",
            value: started.sessionID,
            timeout: 10
        )
        XCTAssertFalse(exists("record.sheet", timeout: 2))
        XCTAssertFalse(exists("onboarding.guide", timeout: 2))

        let unchanged = try fetchCurrentSmokeOnboarding(token: smoke.token)
        XCTAssertEqual(unchanged.sessionID, started.sessionID)
        XCTAssertEqual(unchanged.flowVersion, 2)
        XCTAssertEqual(unchanged.state, started.state)
        XCTAssertEqual(unchanged.status, "active")
    }

    func testSettingsPersonalDataSaveUpdatesGoProfileMe() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)

        let originalProfile = try fetchCurrentSmokeProfile(token: session.token)
        let uniqueSuffix = Int(Date().timeIntervalSince1970)
        let updatedBio = "iOS profile UI smoke \(uniqueSuffix)"
        let updatedCity = "Shanghai UI \(uniqueSuffix)"

        defer {
            try? updateCurrentSmokeProfile(
                token: session.token,
                username: originalProfile.username,
                avatarURL: originalProfile.avatarURL,
                bio: originalProfile.bio,
                city: originalProfile.city,
                birthday: originalProfile.birthday
            )
        }

        try updateCurrentSmokeProfile(
            token: session.token,
            username: originalProfile.username,
            avatarURL: originalProfile.avatarURL,
            bio: "",
            city: "",
            birthday: originalProfile.birthday
        )
        waitForCurrentSmokeProfile(token: session.token, bio: "", city: "")

        launchAuthenticatedApp()

        waitFor("tab.flow")
        waitFor("screen.flow.content", timeout: 20)
        tap("side-menu.open")
        tap("side-menu.settings")

        waitFor("screen.settings.loaded", timeout: 20)
        tap("settings.personal-data")

        waitFor("screen.edit-profile.loaded", timeout: 20)
        let loadedProfileId = waitFor("edit-profile.profile-id", timeout: 20)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(loadedProfileId, session.actorId)
        replaceText("edit-profile.bio", with: updatedBio)
        replaceText("edit-profile.location", with: updatedCity)
        dismissKeyboard()
        tapEditProfileSave()

        waitForCurrentSmokeProfile(token: session.token, bio: updatedBio, city: updatedCity)
    }

    func testSettingsAvatarPickerUploadsGoProfileAvatar() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)

        let originalProfile = try fetchCurrentSmokeProfile(token: session.token)
        defer {
            try? updateCurrentSmokeProfile(
                token: session.token,
                username: originalProfile.username,
                avatarURL: originalProfile.avatarURL,
                bio: originalProfile.bio,
                city: originalProfile.city,
                birthday: originalProfile.birthday
            )
        }

        launchAuthenticatedApp()

        waitFor("tab.flow")
        waitFor("screen.flow.content", timeout: 20)
        tap("side-menu.open")
        tap("side-menu.settings")

        waitFor("screen.settings.loaded", timeout: 20)
        tap("settings.personal-data")

        waitFor("screen.edit-profile.loaded", timeout: 20)
        let loadedProfileId = waitFor("edit-profile.profile-id", timeout: 20)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(loadedProfileId, session.actorId)

        tap("edit-profile.avatar")
        try selectFirstPhotoFromImagePicker()
        waitForEditProfileAvatarUploadStatus("success", timeout: 45)

        let updatedProfile = waitForCurrentSmokeProfileAvatarChanged(
            token: session.token,
            previousAvatarURL: originalProfile.avatarURL
        )
        XCTAssertFalse(updatedProfile.avatarURL.isEmpty)
    }

    func testSettingsAvatarSmokeUploadUpdatesGoProfileAvatar() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)

        let originalProfile = try fetchCurrentSmokeProfile(token: session.token)
        defer {
            try? updateCurrentSmokeProfile(
                token: session.token,
                username: originalProfile.username,
                avatarURL: originalProfile.avatarURL,
                bio: originalProfile.bio,
                city: originalProfile.city,
                birthday: originalProfile.birthday
            )
        }

        launchAuthenticatedApp()

        waitFor("tab.flow")
        waitFor("screen.flow.content", timeout: 20)
        tap("side-menu.open")
        tap("side-menu.settings")

        waitFor("screen.settings.loaded", timeout: 20)
        tap("settings.personal-data")

        waitFor("screen.edit-profile.loaded", timeout: 20)
        let loadedProfileId = waitFor("edit-profile.profile-id", timeout: 20)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(loadedProfileId, session.actorId)

        tap("edit-profile.avatar-smoke-upload")
        waitForEditProfileAvatarUploadStatus("success", timeout: 45)

        let updatedProfile = waitForCurrentSmokeProfileAvatarChanged(
            token: session.token,
            previousAvatarURL: originalProfile.avatarURL
        )
        XCTAssertFalse(updatedProfile.avatarURL.isEmpty)
    }

    func testNotificationDetailMarksUnreadGoNotificationRead() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)

        let notificationId = try requireSmokeNotificationId()

        guard let initialReadState = try fetchNotificationReadState(notificationId: notificationId, token: session.token) else {
            throw XCTSkip("Smoke notification \(notificationId) is not present in local Go notification inbox")
        }
        guard initialReadState == false else {
            throw XCTSkip("Smoke notification \(notificationId) is already read; reset it before running the mark-read UI smoke")
        }

        launchAuthenticatedApp()

        waitFor("tab.flow")
        waitFor("screen.flow.content", timeout: 20)
        tap("side-menu.open")
        tap("side-menu.notification")

        waitFor("notification.list.loaded", timeout: 30)
        waitFor("notification.unread-dot.\(notificationId)", timeout: 10)
        tap("notification.row.\(notificationId)")

        waitFor("notification.detail.loaded", timeout: 20)
        waitForStaticText("iOS notification UI smoke \(notificationId)", timeout: 10)

        waitForNotificationReadState(notificationId: notificationId, token: session.token, expected: true)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.09)).tap()
        waitFor("notification.list.loaded", timeout: 20)
        waitForMissing("notification.unread-dot.\(notificationId)", timeout: 10)
    }

    func testFollowNotificationOpensSourceProfileAndPersistsRead() throws {
        let recipient = try requireSmokeSession()
        let source = try requireSecondarySmokeSession()
        try? setSmokeFollowing(actorID: recipient.actorId, token: source.token, following: false)
        defer {
            try? setSmokeFollowing(actorID: recipient.actorId, token: source.token, following: false)
        }
        let existing = try notificationIDs(
            sourceType: "FOLLOW",
            targetID: source.actorId,
            token: recipient.token
        )
        try setSmokeFollowing(actorID: recipient.actorId, token: source.token, following: true)
        let notification = try waitForSmokeNotification(
            sourceType: "FOLLOW",
            targetID: source.actorId,
            excluding: existing,
            token: recipient.token
        )

        seedAppSession(recipient)
        openNotificationInbox(notificationID: notification.notificationId)
        captureVisual("notification-follow-unread")
        tap("notification.row.\(notification.notificationId)")

        waitFor("screen.user-profile", timeout: 30)
        XCTAssertEqual(
            waitFor("user-profile.actor-id").label
                .trimmingCharacters(in: .whitespacesAndNewlines),
            source.actorId
        )
        captureVisual("notification-follow-source-profile")
        waitForNotificationReadState(
            notificationId: notification.notificationId,
            token: recipient.token,
            expected: true
        )
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testLikeNotificationOpensCanonicalCard() throws {
        let recipient = try requireSmokeSession()
        let source = try requireSecondarySmokeSession()
        let cardID = try createPublicSmokeCard(
            token: recipient.token,
            searchToken: "notification-like-\(Int(Date().timeIntervalSince1970))"
        )
        try? setSmokeLikeStatus(false, id: cardID, token: source.token)
        defer {
            try? setSmokeLikeStatus(false, id: cardID, token: source.token)
            deleteSmokeCard(id: cardID, token: recipient.token)
        }
        let existing = try notificationIDs(
            sourceType: "LIKE",
            targetID: cardID,
            token: recipient.token
        )
        try setSmokeLikeStatus(true, id: cardID, token: source.token)
        let notification = try waitForSmokeNotification(
            sourceType: "LIKE",
            targetID: cardID,
            excluding: existing,
            token: recipient.token
        )

        seedAppSession(recipient)
        openNotificationInbox(notificationID: notification.notificationId)
        tap("notification.row.\(notification.notificationId)")

        waitFor("screen.detail.loaded", timeout: 30)
        XCTAssertEqual(
            waitFor("screen.detail.card-id").label
                .trimmingCharacters(in: .whitespacesAndNewlines),
            cardID
        )
        captureVisual("notification-like-canonical-card")
        waitForNotificationReadState(
            notificationId: notification.notificationId,
            token: recipient.token,
            expected: true
        )
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testCommentNotificationOpensCanonicalCard() throws {
        let recipient = try requireSmokeSession()
        let source = try requireSecondarySmokeSession()
        let cardID = try createPublicSmokeCard(
            token: recipient.token,
            searchToken: "notification-comment-\(Int(Date().timeIntervalSince1970))"
        )
        defer { deleteSmokeCard(id: cardID, token: recipient.token) }
        let existing = try notificationIDs(
            sourceType: "COMMENT",
            targetID: cardID,
            token: recipient.token
        )
        try createSmokeComment(
            cardID: cardID,
            body: "Notification comment \(UUID().uuidString)",
            token: source.token
        )
        let notification = try waitForSmokeNotification(
            sourceType: "COMMENT",
            targetID: cardID,
            excluding: existing,
            token: recipient.token
        )

        seedAppSession(recipient)
        openNotificationInbox(notificationID: notification.notificationId)
        tap("notification.row.\(notification.notificationId)")

        waitFor("screen.detail.loaded", timeout: 30)
        XCTAssertEqual(
            waitFor("screen.detail.card-id").label
                .trimmingCharacters(in: .whitespacesAndNewlines),
            cardID
        )
        captureVisual("notification-comment-canonical-card")
        waitForNotificationReadState(
            notificationId: notification.notificationId,
            token: recipient.token,
            expected: true
        )
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testNotificationReadAllAndUnreadFilterStayCanonical() throws {
        let recipient = try requireSmokeSession()
        let source = try requireSecondarySmokeSession()
        try? setSmokeFollowing(actorID: recipient.actorId, token: source.token, following: false)
        let before = try notificationIDs(
            sourceType: "FOLLOW",
            targetID: source.actorId,
            token: recipient.token
        )
        try setSmokeFollowing(actorID: recipient.actorId, token: source.token, following: true)
        defer {
            try? setSmokeFollowing(actorID: recipient.actorId, token: source.token, following: false)
        }
        let notification = try waitForSmokeNotification(
            sourceType: "FOLLOW",
            targetID: source.actorId,
            excluding: before,
            token: recipient.token
        )

        seedAppSession(recipient)
        launchAuthenticatedApp()
        tap("side-menu.open")
        waitFor("side-menu.notification-unread", timeout: 30)
        captureVisual("notification-side-menu-unread-dot")
        tap("side-menu.notification")
        waitFor("notification.row.\(notification.notificationId)", timeout: 30)
        captureVisual("notification-read-all-before")
        app.buttons["Notification filters"].tap()
        app.buttons["Read All"].tap()
        waitForNotificationReadState(
            notificationId: notification.notificationId,
            token: recipient.token,
            expected: true
        )
        tap("notification.filter.unread")
        waitForMissing("notification.row.\(notification.notificationId)", timeout: 15)
        captureVisual("notification-read-all-filtered")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testNotificationMutationFailureRemainsInlineAndRestoresUnread() throws {
        let recipient = try requireFreshSmokeSession()
        let source = try requireSecondarySmokeSession()
        try? setSmokeFollowing(actorID: recipient.actorId, token: source.token, following: false)
        let before = try notificationIDs(
            sourceType: "FOLLOW",
            targetID: source.actorId,
            token: recipient.token
        )
        try setSmokeFollowing(actorID: recipient.actorId, token: source.token, following: true)
        defer {
            try? setSmokeFollowing(actorID: recipient.actorId, token: source.token, following: false)
        }
        let notification = try waitForSmokeNotification(
            sourceType: "FOLLOW",
            targetID: source.actorId,
            excluding: before,
            token: recipient.token
        )

        seedAppSession(recipient)
        openNotificationInbox(notificationID: notification.notificationId)
        try revokeSmokeSession(token: recipient.token)
        tap("notification.row.\(notification.notificationId)")
        XCTAssertTrue(
            app.staticTexts["Couldn’t update notification. Try again."]
                .waitForExistence(timeout: 20)
        )
        waitFor("screen.notification-inbox")
        captureVisual("notification-inline-mutation-failure")
        XCTAssertFalse(app.alerts.firstMatch.exists)

        let password = ProcessInfo.processInfo.environment[
            "CHORAI_UI_TEST_PASSWORD"
        ] ?? "Password123"
        let renewed = recipient.email.isEmpty
            ? fetchLocalPhoneSmokeSession(
                phone: ProcessInfo.processInfo.environment[
                    "CHORAI_UI_TEST_DISPOSABLE_PHONE"
                ]
            )
            : fetchSmokeSession(email: recipient.email, password: password)
        guard let renewed else {
            XCTFail("Unable to re-authenticate notification recipient")
            return
        }
        Self.cachedSmokeSession = renewed
        waitForNotificationReadState(
            notificationId: notification.notificationId,
            token: renewed.token,
            expected: false
        )
    }

    func testLegacyNotificationUsesDetailFallback() throws {
        let recipient = try requireSmokeSession()
        let notificationID = try requireSmokeNotificationId()
        guard try fetchNotificationReadState(
            notificationId: notificationID,
            token: recipient.token
        ) == false else {
            XCTFail("Legacy notification fixture must start unread")
            return
        }

        seedAppSession(recipient)
        openNotificationInbox(notificationID: notificationID)
        app.buttons["Notification filters"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.16))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.22, dy: 0.16)
                )
            )
        tap("notification.filter.system")
        tap("notification.row.\(notificationID)")
        waitFor("notification.detail.loaded", timeout: 20)
        waitForStaticText("Legacy notification fixture", timeout: 10)
        captureVisual("notification-legacy-detail")
        waitForNotificationReadState(
            notificationId: notificationID,
            token: recipient.token,
            expected: true
        )
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testExploreRecommendedCardOpensGoDetailRoute() throws {
        app.launchArguments.append("--ui-test-open-recommended-detail")
        launchAuthenticatedApp()

        waitFor("screen.detail.loaded", timeout: 30)
    }

    func testExploreVisibleRecommendedCardTapOpensGoDetailRoute() throws {
        launchAuthenticatedApp()

        waitFor("tab.flow")
        waitFor("screen.flow.content", timeout: 20)

        let visibleCardId = waitFor("explore.visible-card.id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(visibleCardId.isEmpty, "Visible recommended card id is empty")

        waitFor("flow.card.\(visibleCardId)").tap()

        waitFor("screen.detail.loaded", timeout: 30)
        let detailCardId = waitFor("screen.detail.card-id", timeout: 10)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(detailCardId, visibleCardId)
    }

    func testFlowLeftSwipeAdvancesWithoutFavoriteMutation() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        launchAuthenticatedApp()

        waitFor("tab.flow")
        waitFor("screen.flow.content", timeout: 20)

        let firstCardId = waitFor("flow.visible-card.id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(firstCardId.isEmpty, "Visible Flow card id is empty")

        let initialFavoriteState = try fetchAssetStatus(
            kind: "favorites",
            id: firstCardId,
            token: session.token
        )

        waitFor("flow.card.\(firstCardId)").swipeLeft()

        let nextCardId = waitForDifferentVisibleFlowCard(from: firstCardId)
        XCTAssertNotEqual(nextCardId, firstCardId)
        XCTAssertEqual(
            try fetchAssetStatus(kind: "favorites", id: firstCardId, token: session.token),
            initialFavoriteState,
            "Left swipe must not mutate favorite state"
        )
    }

    func testFlowRightSwipeFavoritesAndUndoRestoresCard() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        launchAuthenticatedApp()

        waitFor("tab.flow")
        waitFor("screen.flow.content", timeout: 20)

        let cardId = try waitForUnfavoritedFlowCard(token: session.token)
        defer {
            clearFavoriteLikeState(id: cardId, token: session.token)
        }

        waitFor("flow.card.\(cardId)").swipeRight()
        waitForAssetStatus(kind: "favorites", id: cardId, token: session.token, expected: true)

        tap("flow.undo")
        waitForAssetStatus(kind: "favorites", id: cardId, token: session.token, expected: false)

        let restoredCardId = waitFor("flow.visible-card.id", timeout: 10)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(restoredCardId, cardId, "Undo must restore the saved card")
    }

    func testFlowLikeAndUnlikeStayOnCardAndPersistToGo() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let fixtureID = try createPublicSmokeCard(
            token: session.token,
            searchToken: "flow-like-\(Int(Date().timeIntervalSince1970))"
        )
        defer {
            permanentlyCleanUpSmokeCard(id: fixtureID, token: session.token)
        }
        launchAuthenticatedApp()
        waitFor("screen.flow.content", timeout: 30)

        let cardID = flowVisibleCardID()
        XCTAssertEqual(cardID, fixtureID)
        let originalLiked = try fetchAssetStatus(
            kind: "likes",
            id: cardID,
            token: session.token
        )
        let originalFavorite = try fetchAssetStatus(
            kind: "favorites",
            id: cardID,
            token: session.token
        )
        defer {
            try? setSmokeLikeStatus(
                originalLiked,
                id: cardID,
                token: session.token
            )
        }

        if originalLiked {
            tap("flow.like.\(cardID)")
            waitForAssetStatus(
                kind: "likes",
                id: cardID,
                token: session.token,
                expected: false
            )
            waitForAccessibilityValue("flow.like.\(cardID)", expected: "false")
        }

        let baselineCount = anchorLabel("flow.like.count.\(cardID)")
        let favoriteValue = anchorLabel("flow.favorite.\(cardID)")
        let favoriteCount = anchorLabel("flow.favorite.count.\(cardID)")

        tap("flow.like.\(cardID)")
        waitForAssetStatus(
            kind: "likes",
            id: cardID,
            token: session.token,
            expected: true
        )
        waitForAccessibilityValue("flow.like.\(cardID)", expected: "true")
        XCTAssertEqual(flowVisibleCardID(), cardID)
        XCTAssertEqual(
            try fetchAssetStatus(
                kind: "favorites",
                id: cardID,
                token: session.token
            ),
            originalFavorite
        )
        XCTAssertEqual(anchorLabel("flow.favorite.\(cardID)"), favoriteValue)
        XCTAssertEqual(anchorLabel("flow.favorite.count.\(cardID)"), favoriteCount)
        captureVisual("flow-liked-stays-on-card")

        tap("flow.like.\(cardID)")
        waitForAssetStatus(
            kind: "likes",
            id: cardID,
            token: session.token,
            expected: false
        )
        waitForAccessibilityValue("flow.like.\(cardID)", expected: "false")
        XCTAssertEqual(flowVisibleCardID(), cardID)
        XCTAssertEqual(anchorLabel("flow.like.count.\(cardID)"), baselineCount)
        XCTAssertEqual(anchorLabel("flow.favorite.\(cardID)"), favoriteValue)
        XCTAssertEqual(anchorLabel("flow.favorite.count.\(cardID)"), favoriteCount)
        captureVisual("flow-unliked-stays-on-card")
    }

    func testFlowLikeSynchronizesWithDetail() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let fixtureID = try createPublicSmokeCard(
            token: session.token,
            searchToken: "flow-detail-like-\(Int(Date().timeIntervalSince1970))"
        )
        defer {
            permanentlyCleanUpSmokeCard(id: fixtureID, token: session.token)
        }
        launchAuthenticatedApp()
        waitFor("screen.flow.content", timeout: 30)

        let cardID = flowVisibleCardID()
        XCTAssertEqual(cardID, fixtureID)
        let originalLiked = try fetchAssetStatus(
            kind: "likes",
            id: cardID,
            token: session.token
        )
        defer {
            try? setSmokeLikeStatus(
                originalLiked,
                id: cardID,
                token: session.token
            )
        }
        if originalLiked {
            tap("flow.like.\(cardID)")
            waitForAssetStatus(
                kind: "likes",
                id: cardID,
                token: session.token,
                expected: false
            )
        }

        tap("flow.like.\(cardID)")
        waitForAssetStatus(
            kind: "likes",
            id: cardID,
            token: session.token,
            expected: true
        )
        tap("flow.card.\(cardID)")
        waitFor("screen.detail.loaded", timeout: 30)
        waitForAccessibilityValue("detail.like.\(cardID)", expected: "true")
        captureVisual("flow-like-synchronized-detail")

        tap("detail.like.\(cardID)")
        waitForAssetStatus(
            kind: "likes",
            id: cardID,
            token: session.token,
            expected: false
        )
        tap("detail.back")
        waitFor("screen.flow.content", timeout: 30)
        XCTAssertEqual(flowVisibleCardID(), cardID)
        waitForAccessibilityValue("flow.like.\(cardID)", expected: "false")
    }

    func testFlowLikeSynchronizesWithProfile() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let fixtureID = try createPublicSmokeCard(
            token: session.token,
            searchToken: "flow-profile-like-\(Int(Date().timeIntervalSince1970))"
        )
        defer {
            clearFavoriteLikeState(id: fixtureID, token: session.token)
            permanentlyCleanUpSmokeCard(id: fixtureID, token: session.token)
        }
        launchAuthenticatedApp()
        waitFor("screen.flow.content", timeout: 30)
        XCTAssertEqual(flowVisibleCardID(), fixtureID)

        tap("flow.like.\(fixtureID)")
        waitForAssetStatus(
            kind: "likes",
            id: fixtureID,
            token: session.token,
            expected: true
        )
        let authorButton = app.buttons["Open author"]
        XCTAssertTrue(
            authorButton.waitForExistence(timeout: 15),
            "Flow author button was not available"
        )
        authorButton.tap()

        waitFor("screen.user-profile", timeout: 30)
        waitForAccessibilityValue(
            "profile.like.\(fixtureID)",
            expected: "true",
            timeout: 30
        )
        captureVisual("flow-like-synchronized-profile")
    }

    func testFlowLikeFailureKeepsCardAndFavoriteState() throws {
        let cleanupSession = try requireSmokeSession()
        let session = try requireDisposableSmokeSession()
        let fixtureID = try createPublicSmokeCard(
            token: session.token,
            searchToken: "flow-like-failure-\(Int(Date().timeIntervalSince1970))"
        )
        defer {
            permanentlyCleanUpSmokeCard(
                id: fixtureID,
                token: cleanupSession.token
            )
        }
        seedAppSession(session)
        launchAuthenticatedApp()
        waitFor("screen.flow.content", timeout: 30)

        let cardID = flowVisibleCardID()
        XCTAssertEqual(cardID, fixtureID)
        let likeValue = accessibilityValue("flow.like.\(cardID)")
        let likeCount = anchorLabel("flow.like.count.\(cardID)")
        let favoriteValue = anchorLabel("flow.favorite.\(cardID)")
        let favoriteCount = anchorLabel("flow.favorite.count.\(cardID)")

        try revokeSmokeSession(token: session.token)
        tap("flow.like.\(cardID)")
        waitFor("flow.like.error.\(cardID)", timeout: 30)

        XCTAssertEqual(flowVisibleCardID(), cardID)
        XCTAssertEqual(accessibilityValue("flow.like.\(cardID)"), likeValue)
        XCTAssertEqual(anchorLabel("flow.like.count.\(cardID)"), likeCount)
        XCTAssertEqual(anchorLabel("flow.favorite.\(cardID)"), favoriteValue)
        XCTAssertEqual(anchorLabel("flow.favorite.count.\(cardID)"), favoriteCount)
        captureVisual("flow-like-failure-preserves-card")
    }

    func testFlowSparkOpensGoSparkScreen() throws {
        launchAuthenticatedApp()

        waitFor("screen.flow.content", timeout: 20)
        let cardId = waitFor("flow.visible-card.id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)

        tap("flow.spark.\(cardId)")

        waitFor("screen.spark.loaded", timeout: 60)
        let sourceCardId = waitFor("spark.source.card-id", timeout: 10)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(sourceCardId, cardId)
    }

    func testSparkUsesAnyNonEmptyGoBucketAndLeftSwipeAdvances() throws {
        let session = try requireSmokeSession()
        let sparkCardId = sparkSeedCardID
        openSparkFromDetail(cardID: sparkCardId, session: session)

        let activityID = sparkAnchorValue("spark.activity.id")
        let page = try fetchSparkActivity(activityID: activityID, token: session.token)
        let visibleID = sparkAnchorValue("spark.visible-card.id")
        let visibleBucket = sparkAnchorValue("spark.visible-card.bucket")

        XCTAssertTrue(page.orderedAssetIDs.contains(visibleID))
        XCTAssertEqual(page.bucketByAssetID[visibleID], visibleBucket)
        guard page.orderedAssetIDs.count > 1 else {
            throw XCTSkip("Go Spark returned only one visible result")
        }

        waitFor("spark.card.\(visibleID)").swipeLeft()
        let nextID = waitForDifferentSparkCard(from: visibleID)
        XCTAssertTrue(page.orderedAssetIDs.contains(nextID))
    }

    func testSparkRightSwipeSavesWithDiscoveryContextAndUndo() throws {
        let session = try requireSmokeSession()
        openSparkFromDetail(cardID: sparkSeedCardID, session: session)

        let resultID = try waitForUnfavoritedSparkResult(token: session.token)
        let activityID = sparkAnchorValue("spark.activity.id")
        let rootActivityID = sparkAnchorValue("spark.root.id")
        defer { deleteFavorite(id: resultID, token: session.token) }

        waitFor("spark.card.\(resultID)").swipeRight()
        waitForAssetStatus(
            kind: "favorites",
            id: resultID,
            token: session.token,
            expected: true
        )
        XCTAssertEqual(
            try waitForDiscoveryRoot(assetID: resultID, token: session.token),
            rootActivityID
        )
        XCTAssertFalse(activityID.isEmpty)

        tap("spark.save.undo")
        waitForAssetStatus(
            kind: "favorites",
            id: resultID,
            token: session.token,
            expected: false
        )
        XCTAssertEqual(sparkAnchorValue("spark.visible-card.id"), resultID)
    }

    func testSparkUpSwipeCreatesChildAndChainReplayRestoresParent() throws {
        let session = try requireSmokeSession()
        openSparkFromDetail(cardID: sparkSeedCardID, session: session)

        let rootActivityID = sparkAnchorValue("spark.activity.id")
        let rootID = sparkAnchorValue("spark.root.id")
        let parentVisibleID = sparkAnchorValue("spark.visible-card.id")

        waitFor("spark.card.\(parentVisibleID)").swipeUp()
        let childActivityID = waitForDifferentSparkActivity(from: rootActivityID, timeout: 90)
        XCTAssertEqual(sparkAnchorValue("spark.root.id"), rootID)
        XCTAssertEqual(sparkAnchorValue("spark.parent.id"), rootActivityID)
        XCTAssertEqual(sparkAnchorValue("spark.depth"), "1")
        XCTAssertEqual(sparkAnchorValue("spark.source.card-id"), parentVisibleID)
        XCTAssertNotEqual(childActivityID, rootActivityID)

        tap("spark.chain.\(rootActivityID)")
        waitForSparkActivity(rootActivityID, timeout: 60)
        XCTAssertEqual(sparkAnchorValue("spark.visible-card.id"), parentVisibleID)
        XCTAssertEqual(sparkAnchorValue("spark.depth"), "0")
    }

    func testSparkRelaunchRehydratesActivityWithoutNewTrigger() throws {
        let session = try requireSmokeSession()
        let cardID = sparkSeedCardID
        openSparkFromDetail(cardID: cardID, session: session)

        let activityID = sparkAnchorValue("spark.activity.id")
        let rootActivityID = sparkAnchorValue("spark.root.id")
        let depth = sparkAnchorValue("spark.depth")
        let visibleCardID = sparkAnchorValue("spark.visible-card.id")
        let historyBefore = try fetchSparkHistoryTotal(
            cardID: cardID,
            token: session.token
        )

        app.terminate()
        app.launch()
        navigateToSparkFromFlow(cardID: cardID)

        waitFor("spark.card.\(visibleCardID)", timeout: 30)

        XCTAssertEqual(sparkAnchorValue("spark.activity.id"), activityID)
        XCTAssertEqual(sparkAnchorValue("spark.root.id"), rootActivityID)
        XCTAssertEqual(sparkAnchorValue("spark.depth"), depth)
        XCTAssertEqual(sparkAnchorValue("spark.visible-card.id"), visibleCardID)
        XCTAssertEqual(
            try fetchSparkHistoryTotal(cardID: cardID, token: session.token),
            historyBefore,
            "Relaunch replay must not create another Spark activity"
        )
    }

    func testSparkTriggerFailureRestoresParentCard() throws {
        let session = try requireSmokeSession()
        app.launchEnvironment["CHORAI_UI_TEST_SPARK_FAIL_CHILD_TRIGGER"] = "1"
        openSparkFromDetail(cardID: sparkSeedCardID, session: session)

        let parentActivityID = sparkAnchorValue("spark.activity.id")
        let parentVisibleID = sparkAnchorValue("spark.visible-card.id")
        waitFor("spark.card.\(parentVisibleID)").swipeUp()

        waitFor("screen.spark.error", timeout: 20)
        XCTAssertEqual(sparkAnchorValue("spark.activity.id"), parentActivityID)
        XCTAssertEqual(sparkAnchorValue("spark.visible-card.id"), parentVisibleID)
        waitFor("spark.card.\(parentVisibleID)")
    }

    func testSparkResultDetailAndMenuRemainReachable() throws {
        let session = try requireSmokeSession()
        openSparkFromDetail(cardID: sparkSeedCardID, session: session)

        let visibleCardID = sparkAnchorValue("spark.visible-card.id")
        tap("spark.card.\(visibleCardID)")
        waitFor("screen.detail.loaded", timeout: 30)
        XCTAssertEqual(sparkAnchorValue("screen.detail.card-id"), visibleCardID)

        tap("detail.back")
        waitFor("screen.spark.loaded", timeout: 20)
        tap("spark.menu.\(visibleCardID)")
        waitFor("popup-menu.item.view", timeout: 10)
    }

    func testSparkVisualEvidenceMatrix() throws {
        guard ProcessInfo.processInfo.environment[
            "CHORAI_CAPTURE_SPARK_VISUALS"
        ] == "1" else {
            throw XCTSkip("Set CHORAI_CAPTURE_SPARK_VISUALS=1 to capture evidence")
        }

        let session = try requireSmokeSession()
        let cardID = sparkSeedCardID

        prepareSparkVisualApp(
            session: session,
            cardID: cardID,
            suffix: "root-child-save",
            environment: ["CHORAI_UI_TEST_SPARK_TRIGGER_DELAY_MS": "1200"]
        )
        openSparkRouteFromFlow(cardID: cardID)
        waitFor("screen.spark.loading", timeout: 10)
        captureSparkVisual("initial-loading")
        waitFor("screen.spark.loaded", timeout: 90)
        captureSparkVisual("root-loaded")

        let rootActivityID = sparkAnchorValue("spark.activity.id")
        let rootVisibleID = sparkAnchorValue("spark.visible-card.id")
        waitFor("spark.card.\(rootVisibleID)").swipeUp()
        waitFor("screen.spark.loading", timeout: 10)
        captureSparkVisual("child-loading")
        _ = waitForDifferentSparkActivity(from: rootActivityID, timeout: 90)
        captureSparkVisual("child-loaded")

        let savedID = try waitForUnfavoritedSparkResult(token: session.token)
        waitFor("spark.card.\(savedID)").swipeRight()
        waitFor("spark.save.undo", timeout: 20)
        captureSparkVisual("save-success")
        tap("spark.save.undo")
        waitForAssetStatus(
            kind: "favorites",
            id: savedID,
            token: session.token,
            expected: false
        )

        prepareSparkVisualApp(
            session: session,
            cardID: cardID,
            suffix: "error",
            environment: ["CHORAI_UI_TEST_SPARK_FAIL_CHILD_TRIGGER": "1"]
        )
        navigateToSparkFromFlow(cardID: cardID)
        let errorParentID = sparkAnchorValue("spark.visible-card.id")
        waitFor("spark.card.\(errorParentID)").swipeUp()
        waitFor("screen.spark.error", timeout: 20)
        captureSparkVisual("confirmed-trigger-error")

        prepareSparkVisualApp(
            session: session,
            cardID: cardID,
            suffix: "empty",
            environment: ["CHORAI_UI_TEST_SPARK_EMPTY_ROOT": "1"]
        )
        openSparkRouteFromFlow(cardID: cardID)
        waitFor("screen.spark.empty", timeout: 30)
        captureSparkVisual("all-groups-empty")

        prepareSparkVisualApp(
            session: session,
            cardID: cardID,
            suffix: "save-rollback",
            environment: ["CHORAI_UI_TEST_SPARK_FAIL_FAVORITE": "1"]
        )
        navigateToSparkFromFlow(cardID: cardID)
        let rollbackID = try waitForUnfavoritedSparkResult(token: session.token)
        waitFor("spark.card.\(rollbackID)").swipeRight()
        waitFor("spark.save.failed", timeout: 20)
        captureSparkVisual("save-rollback")

        prepareSparkVisualApp(
            session: session,
            cardID: cardID,
            suffix: "restored",
            environment: [:]
        )
        navigateToSparkFromFlow(cardID: cardID)
        let restoredActivityID = sparkAnchorValue("spark.activity.id")
        let restoredVisibleID = sparkAnchorValue("spark.visible-card.id")
        app.terminate()
        app.launch()
        navigateToSparkFromFlow(cardID: cardID)
        waitFor("spark.card.\(restoredVisibleID)", timeout: 30)
        XCTAssertEqual(sparkAnchorValue("spark.activity.id"), restoredActivityID)
        captureSparkVisual("restored-session")

        prepareSparkVisualApp(
            session: session,
            cardID: cardID,
            suffix: "accessibility",
            environment: ["CHORAI_UI_TEST_SPARK_ACCESSIBILITY_MODE": "1"]
        )
        navigateToSparkFromFlow(cardID: cardID)
        captureSparkVisual("accessibility-xxxl-contrast-reduced-motion")
    }

    func testRecordCreatesPrivateGoCardAndRefreshesLibrary() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        launchAuthenticatedApp()

        let content = "Flow record \(Int(Date().timeIntervalSince1970))"
        let input = openRecordWithEmptyDraft()
        input.tap()
        input.typeText(content)
        XCTAssertEqual(input.value as? String, content)
        XCTAssertTrue(waitForButton("record.save").isEnabled, "Record Save should enable for a non-empty draft")
        tapButton("record.save")

        let cardId = waitFor("record.created-card-id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        waitFor("record.acknowledgement", timeout: 5)
        defer {
            deleteSmokeCard(id: cardId, token: session.token)
        }

        let card = try fetchSmokeCard(id: cardId, token: session.token)
        XCTAssertEqual(card.content, content)
        XCTAssertFalse(card.isPublic)

        tap("tab.library")
        waitFor("card.home.\(cardId)", timeout: 30)
    }

    func testLibraryOwnedCardVisibilityAndPinMutateGoState() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let suffix = "stewardship-\(Int(Date().timeIntervalSince1970))"
        let cardID = try createSmokeCard(
            token: session.token,
            searchToken: suffix,
            isPublic: false
        )
        defer {
            permanentlyCleanUpSmokeCard(id: cardID, token: session.token)
        }

        launchAuthenticatedApp()
        tap("tab.library")
        waitFor("card.home.\(cardID)", timeout: 30)

        tap("home.card.menu.\(cardID)")
        tap("popup-menu.item.public")
        waitForSmokeCardState(id: cardID, token: session.token) {
            $0.isPublic
        }

        waitFor("home.card.menu.\(cardID)", timeout: 30).tap()
        tap("popup-menu.item.private")
        waitForSmokeCardState(id: cardID, token: session.token) {
            !$0.isPublic
        }

        waitFor("home.card.menu.\(cardID)", timeout: 30).tap()
        tap("popup-menu.item.pin")
        waitForSmokeCardState(id: cardID, token: session.token) {
            $0.isPinned
        }

        waitFor("home.card.menu.\(cardID)", timeout: 30).tap()
        waitFor("popup-menu.item.unpin", timeout: 20)
        captureVisual("library-owned-card-pinned")
        tap("popup-menu.item.unpin")
        waitForSmokeCardState(id: cardID, token: session.token) {
            !$0.isPinned
        }
    }

    func testLibrarySoftDeleteMovesCardToTrashAndRestoresIt() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let suffix = "trash-restore-\(Int(Date().timeIntervalSince1970))"
        let cardID = try createSmokeCard(
            token: session.token,
            searchToken: suffix,
            isPublic: false
        )
        defer {
            permanentlyCleanUpSmokeCard(id: cardID, token: session.token)
        }

        launchAuthenticatedApp()
        tap("tab.library")
        waitFor("card.home.\(cardID)", timeout: 30)
        tap("home.card.menu.\(cardID)")
        tap("popup-menu.item.remove")

        waitFor("home.delete.confirmation", timeout: 10)
        captureVisual("library-soft-delete-confirmation")
        tap("home.delete.confirm")
        waitForTrashCard(id: cardID, token: session.token, isPresent: true)
        waitForMissing("card.home.\(cardID)", timeout: 20)

        tap("side-menu.open")
        tap("side-menu.item.Trash")
        waitFor("screen.trash", timeout: 20)
        waitForTrashCardVisible(cardID)
        captureVisual("trash-card-ready-to-restore")

        tap("trash.card.restore.\(cardID)")
        waitForTrashCard(id: cardID, token: session.token, isPresent: false)
        waitForMissing("trash.card.\(cardID)", timeout: 20)
        XCTAssertEqual(try fetchSmokeCard(id: cardID, token: session.token).id, cardID)
    }

    func testCardEditorSavePersistsNormalizedTagsToGo() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let suffix = "editor-save-\(Int(Date().timeIntervalSince1970))"
        let cardID = try createSmokeCard(
            token: session.token,
            searchToken: suffix,
            isPublic: false
        )
        defer {
            permanentlyCleanUpSmokeCard(id: cardID, token: session.token)
        }

        launchAuthenticatedApp()
        tap("tab.library")
        waitFor("card.home.\(cardID)", timeout: 30).tap()
        waitFor("screen.card-editor", timeout: 20)

        let editor = waitFor("cardEditorContent", timeout: 20)
        editor.tap()
        app.typeText(" #editortag #editortag")
        tap("cardEditorBackButton")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        tap("cardEditorBackButton")

        waitForSmokeCardState(id: cardID, token: session.token) { card in
            card.content.contains("#editortag")
                && card.tags.filter { $0 == "editortag" }.count == 1
        }
        waitFor("screen.home.content", timeout: 20)
    }

    func testCardEditorLinkFailureKeepsCanonicalRelationshipList() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let suffix = Int(Date().timeIntervalSince1970)
        let sourceID = try createSmokeCard(
            token: session.token,
            searchToken: "editor-link-source-\(suffix)",
            isPublic: false
        )
        let targetToken = "editor-link-target-\(suffix)"
        let targetID = try createSmokeCard(
            token: session.token,
            searchToken: targetToken,
            isPublic: false
        )
        defer {
            permanentlyCleanUpSmokeCard(id: sourceID, token: session.token)
            permanentlyCleanUpSmokeCard(id: targetID, token: session.token)
        }

        launchAuthenticatedApp()
        tap("tab.library")
        waitFor("card.home.\(sourceID)", timeout: 30).tap()
        waitFor("screen.card-editor", timeout: 20)
        waitFor("cardEditorContent", timeout: 20).tap()
        tap("cardEditorLinkButton")
        waitFor("linkPopup", timeout: 20)
        let search = waitFor("linkPopupSearch")
        search.tap()
        search.typeText(targetToken)
        waitFor("linkPopupCard.\(targetID)", timeout: 30)

        permanentlyCleanUpSmokeCard(id: targetID, token: session.token)
        tap("linkPopupCard.\(targetID)")

        XCTAssertEqual(waitFor("linkPopupError", timeout: 20).label, "链接失败")
        XCTAssertTrue(exists("screen.card-editor", timeout: 2))
        XCTAssertFalse(exists("cardEditorLink.\(targetID)", timeout: 2))
        captureVisual("card-editor-link-failure-retained")
    }

    func testCardEditorBackgroundUploadAndRemovalPersistToGo() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let suffix = "editor-background-\(Int(Date().timeIntervalSince1970))"
        let cardID = try createSmokeCard(
            token: session.token,
            searchToken: suffix,
            isPublic: false
        )
        defer {
            permanentlyCleanUpSmokeCard(id: cardID, token: session.token)
        }

        launchAuthenticatedApp()
        tap("tab.library")
        waitFor("card.home.\(cardID)", timeout: 30).tap()
        waitFor("screen.card-editor", timeout: 20)
        waitFor("cardEditorContent", timeout: 20).tap()
        revealEditorBackgroundButton()
        tap("cardEditorBackgroundButton")
        try selectFirstPhotoFromImagePicker()

        waitForSmokeCardState(id: cardID, token: session.token) {
            !($0.backgroundMediaRef ?? "").isEmpty
        }
        waitFor("cardEditorBackgroundImage", timeout: 20)
        captureVisual("card-editor-background-uploaded")

        waitFor("cardEditorContent", timeout: 10).tap()
        revealEditorBackgroundButton()
        tap("cardEditorBackgroundButton")
        let remove = app.sheets.buttons["Remove Background"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.tap()

        waitForSmokeCardState(id: cardID, token: session.token) {
            $0.backgroundMediaRef == nil
        }
    }

    func testLibrarySoftDeleteFailureKeepsRetryableConfirmation() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let suffix = "trash-error-\(Int(Date().timeIntervalSince1970))"
        let cardID = try createSmokeCard(
            token: session.token,
            searchToken: suffix,
            isPublic: false
        )
        defer {
            permanentlyCleanUpSmokeCard(id: cardID, token: session.token)
        }

        launchAuthenticatedApp()
        tap("tab.library")
        waitFor("card.home.\(cardID)", timeout: 30)
        tap("home.card.menu.\(cardID)")
        tap("popup-menu.item.remove")
        waitFor("home.delete.confirmation", timeout: 10)

        deleteSmokeCard(id: cardID, token: session.token)
        tap("home.delete.confirm")

        waitFor("home.delete.error", timeout: 20)
        waitFor("home.delete.confirm")
        XCTAssertFalse(
            app.alerts["Error"].exists,
            "The retryable delete dialog must own its error presentation"
        )
        captureVisual("library-soft-delete-retryable-error")
    }

    func testTrashPermanentlyDeletesCardFromGo() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let suffix = "trash-permanent-\(Int(Date().timeIntervalSince1970))"
        let cardID = try createSmokeCard(
            token: session.token,
            searchToken: suffix,
            isPublic: false
        )
        defer {
            permanentlyCleanUpSmokeCard(id: cardID, token: session.token)
        }
        deleteSmokeCard(id: cardID, token: session.token)
        waitForTrashCard(id: cardID, token: session.token, isPresent: true)
        XCTAssertEqual(try fetchSmokeTrashCardIDsInOrder(token: session.token).first, cardID)

        launchAuthenticatedApp()
        tap("side-menu.open")
        tap("side-menu.item.Trash")
        waitFor("screen.trash", timeout: 20)
        waitForTrashCardVisible(cardID)
        tap("trash.card.delete.\(cardID)")
        waitFor("trash.delete.confirmation", timeout: 10)
        captureVisual("trash-permanent-delete-confirmation")
        tap("trash.delete.confirm")

        waitForTrashCard(id: cardID, token: session.token, isPresent: false)
        waitForMissing("trash.card.\(cardID)", timeout: 20)
    }

    func testTrashPermanentDeleteFailureKeepsRetryableConfirmation() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let suffix = "trash-permanent-error-\(Int(Date().timeIntervalSince1970))"
        let cardID = try createSmokeCard(
            token: session.token,
            searchToken: suffix,
            isPublic: false
        )
        defer {
            permanentlyCleanUpSmokeCard(id: cardID, token: session.token)
        }
        deleteSmokeCard(id: cardID, token: session.token)
        waitForTrashCard(id: cardID, token: session.token, isPresent: true)

        launchAuthenticatedApp()
        tap("side-menu.open")
        tap("side-menu.item.Trash")
        waitFor("screen.trash", timeout: 20)
        waitForTrashCardVisible(cardID)
        tap("trash.card.delete.\(cardID)")
        waitFor("trash.delete.confirmation", timeout: 10)

        permanentlyCleanUpSmokeCard(id: cardID, token: session.token)
        tap("trash.delete.confirm")

        waitFor("trash.delete.error", timeout: 20)
        waitFor("trash.delete.confirm")
        XCTAssertFalse(app.alerts["Error"].exists)
        captureVisual("trash-permanent-delete-retryable-error")

        tap("trash.delete.cancel")
        waitForMissing("trash.delete.confirmation", timeout: 10)
        XCTAssertFalse(app.descendants(matching: .any)["trash.card.error.\(cardID)"].exists)
    }

    func testTrashRestoreFailureStaysOnCardAndCanRetry() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let suffix = "trash-restore-error-\(Int(Date().timeIntervalSince1970))"
        let cardID = try createSmokeCard(
            token: session.token,
            searchToken: suffix,
            isPublic: false
        )
        defer {
            permanentlyCleanUpSmokeCard(id: cardID, token: session.token)
        }
        deleteSmokeCard(id: cardID, token: session.token)
        waitForTrashCard(id: cardID, token: session.token, isPresent: true)
        XCTAssertEqual(try fetchSmokeTrashCardIDsInOrder(token: session.token).first, cardID)

        launchAuthenticatedApp()
        tap("side-menu.open")
        tap("side-menu.item.Trash")
        waitFor("screen.trash", timeout: 20)
        waitForTrashCardVisible(cardID)

        permanentlyCleanUpSmokeCard(id: cardID, token: session.token)
        tap("trash.card.restore.\(cardID)")

        waitFor("trash.card.error.\(cardID)", timeout: 20)
        waitFor("trash.card.restore.\(cardID)")
        XCTAssertTrue(app.descendants(matching: .any)["trash.card.\(cardID)"].exists)
        XCTAssertFalse(app.alerts["Error"].exists)
        captureVisual("trash-restore-retryable-error")
    }

    func testLibraryCardShareLoadsGoArtifactAndOpensNativeShare() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let searchToken = "share-\(Int(Date().timeIntervalSince1970))"
        let cardID = try createPublicSmokeCard(
            token: session.token,
            searchToken: searchToken
        )
        defer {
            deleteSmokeCard(id: cardID, token: session.token)
        }
        let canonicalPreview = try fetchSmokeSharePreview(
            cardID: cardID,
            token: session.token
        )

        launchAuthenticatedApp()
        tap("tab.library")
        waitFor("card.home.\(cardID)", timeout: 30)
        tap("home.card.menu.\(cardID)")
        tap("popup-menu.item.share")

        waitFor("screen.share-card", timeout: 20)
        waitFor("share-card.preview", timeout: 30)
        XCTAssertEqual(
            waitFor("share-card.artifact-id")
                .label
                .trimmingCharacters(in: .whitespacesAndNewlines),
            canonicalPreview.artifact.id
        )
        captureShareVisual("library-card-share-preview")

        tap("share-card.action")
        XCTAssertTrue(
            app.otherElements["ActivityListView"].waitForExistence(timeout: 20),
            "Native share sheet did not open after Go artifact pin"
        )
    }

    func testLibraryCardShareShowsRetryableErrorWhenCardDisappears() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let searchToken = "share-error-\(Int(Date().timeIntervalSince1970))"
        let cardID = try createPublicSmokeCard(
            token: session.token,
            searchToken: searchToken
        )

        launchAuthenticatedApp()
        tap("tab.library")
        waitFor("card.home.\(cardID)", timeout: 30)
        deleteSmokeCard(id: cardID, token: session.token)

        tap("home.card.menu.\(cardID)")
        tap("popup-menu.item.share")

        waitFor("screen.share-card", timeout: 20)
        waitFor("share-card.error", timeout: 30)
        XCTAssertEqual(
            waitFor("share-card.error-code")
                .label
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "forbidden"
        )
        waitFor("share-card.retry")
        captureShareVisual("library-card-share-error")
    }

    func testPublicCardReportCreatesCanonicalGoCase() throws {
        let session = try requireSmokeSession()
        let targetSession = try requireSecondarySmokeSession()
        XCTAssertNotEqual(session.actorId, targetSession.actorId)
        seedAppSession(session)
        let searchToken = "report-\(Int(Date().timeIntervalSince1970))"
        let cardID = try createPublicSmokeCard(
            token: targetSession.token,
            searchToken: searchToken
        )
        defer {
            deleteSmokeCard(id: cardID, token: targetSession.token)
        }

        launchAuthenticatedApp()
        showExploreSearchResult(
            searchToken: searchToken,
            expectedCardId: cardID
        )
        tap("ellipsis")
        tap("popup-menu.item.report")

        waitFor("screen.content-report", timeout: 20)
        waitFor("content-report.reason")
        captureReportVisual("content-report-form")
        tap("content-report.submit")

        waitFor("content-report.submitted", timeout: 30)
        let reportID = waitFor("content-report.report-id")
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let report = try fetchSmokeReport(id: reportID, token: session.token)
        XCTAssertEqual(report.reportID, reportID)
        XCTAssertEqual(report.status, "OPEN")
        captureReportVisual("content-report-submitted")
    }

    func testPublicCardReportFailureKeepsRetryableDraft() throws {
        let session = try requireSmokeSession()
        let targetSession = try requireSecondarySmokeSession()
        seedAppSession(session)
        let searchToken = "report-error-\(Int(Date().timeIntervalSince1970))"
        let cardID = try createPublicSmokeCard(
            token: targetSession.token,
            searchToken: searchToken
        )

        launchAuthenticatedApp()
        showExploreSearchResult(
            searchToken: searchToken,
            expectedCardId: cardID
        )
        deleteSmokeCard(id: cardID, token: targetSession.token)
        tap("ellipsis")
        tap("popup-menu.item.report")
        waitFor("screen.content-report", timeout: 20)
        tap("content-report.submit")

        waitFor("content-report.error", timeout: 30)
        waitFor("content-report.retry")
        XCTAssertFalse(
            waitFor("content-report.error-code")
                .label
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )
        XCTAssertTrue(waitFor("content-report.reason").label.contains("Spam"))
        captureReportVisual("content-report-error")
    }

    func testPublicProfileReportCreatesCanonicalActorCase() throws {
        let session = try requireSmokeSession()
        let targetSession = try requireSecondarySmokeSession()
        seedAppSession(session)
        let searchToken = "actor-report-\(Int(Date().timeIntervalSince1970))"
        let cardID = try createPublicSmokeCard(
            token: targetSession.token,
            searchToken: searchToken
        )
        defer {
            deleteSmokeCard(id: cardID, token: targetSession.token)
        }

        launchAuthenticatedApp()
        showExploreSearchResult(
            searchToken: searchToken,
            expectedCardId: cardID
        )
        tapFirstHittableButton(label: "avatar")

        waitFor("screen.user-profile", timeout: 30)
        XCTAssertEqual(
            waitFor("user-profile.actor-id")
                .label
                .trimmingCharacters(in: .whitespacesAndNewlines),
            targetSession.actorId
        )
        tapFirstExistingButton(["user-profile.actions"], timeout: 20)
        let reportAction = app.buttons["Report this user"]
        XCTAssertTrue(reportAction.waitForExistence(timeout: 10))
        reportAction.tap()

        waitFor("screen.content-report", timeout: 20)
        tap("content-report.submit")
        waitFor("content-report.submitted", timeout: 30)
        let reportID = waitFor("content-report.report-id")
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let report = try fetchSmokeReport(id: reportID, token: session.token)
        XCTAssertEqual(report.reportID, reportID)
        XCTAssertEqual(report.status, "OPEN")
        captureReportVisual("actor-report-submitted")
    }

    func testOwnPublicProfileHidesSelfSocialActions() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        launchProfileTestRoute(actorID: session.actorId)

        waitFor("screen.user-profile", timeout: 30)
        XCTAssertEqual(
            waitFor("user-profile.actor-id")
                .label
                .trimmingCharacters(in: .whitespacesAndNewlines),
            session.actorId
        )
        waitFor("user-profile.followers-count", timeout: 30)
        XCTAssertFalse(exists("user-profile.actions", timeout: 2))
        XCTAssertFalse(exists("user-profile.follow", timeout: 2))
        XCTAssertFalse(exists("user-profile.chat", timeout: 2))
        captureVisual("profile-own-no-self-actions")
    }

    func testPublicProfileFollowAndUnfollowCommitCanonicalCount() throws {
        let session = try requireSmokeSession()
        let target = try requireSecondarySmokeSession()
        XCTAssertNotEqual(session.actorId, target.actorId)
        try? setSmokeBlocked(
            actorID: target.actorId,
            token: session.token,
            blocked: false
        )
        try? setSmokeFollowing(
            actorID: target.actorId,
            token: session.token,
            following: false
        )
        defer {
            try? setSmokeFollowing(
                actorID: target.actorId,
                token: session.token,
                following: false
            )
        }

        let initial = try fetchSmokePublicProfile(
            actorID: target.actorId,
            token: session.token
        )
        XCTAssertFalse(initial.isFollowing)
        seedAppSession(session)
        launchProfileTestRoute(actorID: target.actorId)

        waitFor("screen.user-profile", timeout: 30)
        waitForProfileFollowValue("not-following")
        tap("user-profile.follow")
        waitForProfileFollowValue("following", timeout: 30)
        let followed = waitForSmokePublicProfile(
            actorID: target.actorId,
            token: session.token,
            isFollowing: true
        )
        XCTAssertEqual(followed.followerCount, initial.followerCount + 1)
        waitForAccessibilityValue(
            "user-profile.followers-count",
            value: "\(followed.followerCount)"
        )

        tap("user-profile.follow")
        waitForProfileFollowValue("not-following", timeout: 30)
        let unfollowed = waitForSmokePublicProfile(
            actorID: target.actorId,
            token: session.token,
            isFollowing: false
        )
        XCTAssertEqual(unfollowed.followerCount, initial.followerCount)
        captureVisual("profile-follow-round-trip")
    }

    func testFollowersListHonorsCanonicalPrivacy() throws {
        let session = try requireSmokeSession()
        let target = try requireSecondarySmokeSession()
        let originalPrivacy = try fetchSmokePrivacy(token: target.token)
        try? setSmokeBlocked(
            actorID: target.actorId,
            token: session.token,
            blocked: false
        )
        try setSmokePrivacy(token: target.token, showFollowLists: true)
        try ensureSmokeFollowing(
            actorID: target.actorId,
            token: session.token,
            following: true
        )
        defer {
            try? ensureSmokeFollowing(
                actorID: target.actorId,
                token: session.token,
                following: false
            )
            try? setSmokePrivacy(
                token: target.token,
                showFollowLists: originalPrivacy.showFollowLists
            )
        }

        seedAppSession(session)
        launchProfileTestRoute(actorID: target.actorId)
        waitFor("user-profile.followers-count", timeout: 30).tap()
        waitFor("screen.follow-list", timeout: 20)
        waitFor("follow-list.row.\(session.actorId)", timeout: 30)
        captureVisual("profile-followers-visible")

        app.terminate()
        try setSmokePrivacy(token: target.token, showFollowLists: false)
        app.launch()
        waitFor("user-profile.followers-count", timeout: 30).tap()
        waitFor("follow-list.private", timeout: 30)
        captureVisual("profile-followers-private")
    }

    func testBlockedUserPersistsAcrossRelaunchAndCanBeUnblocked() throws {
        let session = try requireSmokeSession()
        let target = try requireSecondarySmokeSession()
        try? setSmokeBlocked(
            actorID: target.actorId,
            token: session.token,
            blocked: false
        )
        defer {
            try? setSmokeBlocked(
                actorID: target.actorId,
                token: session.token,
                blocked: false
            )
        }

        seedAppSession(session)
        launchProfileTestRoute(actorID: target.actorId)
        waitFor("screen.user-profile", timeout: 30)
        tap("user-profile.actions")
        let blockAction = app.buttons["Block this user"]
        XCTAssertTrue(blockAction.waitForExistence(timeout: 10))
        blockAction.tap()
        let confirmation = app.alerts.buttons["Block"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirmation.tap()
        waitForSmokeBlockedActor(
            actorID: target.actorId,
            token: session.token,
            blocked: true
        )

        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-test-open-profile" }
        app.launchEnvironment.removeValue(
            forKey: "CHORAI_UI_TEST_PROFILE_ACTOR_ID"
        )
        launchAuthenticatedApp()
        tap("side-menu.open")
        tap("side-menu.settings")
        waitFor("screen.settings.loaded", timeout: 20)
        tap("settings.account-privacy")
        tap("account-privacy.blocked-users")
        waitFor("screen.blocked-users", timeout: 20)
        waitFor("blocked-users.row.\(target.actorId)", timeout: 30)
        captureVisual("profile-blocked-users-restored")

        tap("blocked-users.unblock.\(target.actorId)")
        waitFor("blocked-users.empty", timeout: 30)
        waitForSmokeBlockedActor(
            actorID: target.actorId,
            token: session.token,
            blocked: false
        )
    }

    func testPublicProfileTransportFailureRemainsInline() throws {
        let session = try requireSmokeSession()
        let target = try requireSecondarySmokeSession()
        seedAppSession(session)
        app.launchEnvironment["CHORAI_API_BASE_URL"] = "http://127.0.0.1:1"
        launchProfileTestRoute(actorID: target.actorId)

        waitFor("screen.user-profile", timeout: 15)
        waitFor("user-profile.load-error", timeout: 20)
        XCTAssertFalse(
            app.alerts.firstMatch.waitForExistence(timeout: 2),
            "Profile transport errors should stay local to the profile screen"
        )
    }

    func testFailedRecordDraftRestoresAfterRelaunch() throws {
        let session = try requireSmokeSession()
        let healthyBaseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"]
            ?? "http://127.0.0.1:8080"
        seedAppSession(session)
        app.launchEnvironment["CHORAI_API_BASE_URL"] = "http://127.0.0.1:65535"
        app.launch()

        let draft = "Recovered draft \(Int(Date().timeIntervalSince1970))"
        let input = openRecordWithEmptyDraft()
        input.tap()
        input.typeText(draft)
        tapButton("record.save")
        waitFor("record.error", timeout: 20)

        app.terminate()
        app.launchEnvironment["CHORAI_API_BASE_URL"] = healthyBaseURL
        app.launch()

        if !exists("record.input", timeout: 3) {
            tap("record.open")
        }
        XCTAssertEqual(waitFor("record.input").value as? String, draft)
        tapButton("record.discard")
        confirmRecordDiscard()
    }

    func testRecordRemainsVisibleFromEveryPrimaryTab() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        launchAuthenticatedApp()

        for tabId in ["tab.flow", "tab.library", "tab.chat"] {
            tap(tabId)
            XCTAssertTrue(
                waitFor("record.open").isHittable,
                "Record must remain visible on \(tabId)"
            )
        }
    }

    func testRecommendedDetailCommentCreateAppearsInVisibleList() throws {
        app.launchArguments.append("--ui-test-open-recommended-detail")
        launchAuthenticatedApp()

        waitFor("screen.detail.loaded", timeout: 30)
        tap("detail.comment.open")
        waitFor("comment.popup", timeout: 15)

        let commentText = "iOS UI comment \(Int(Date().timeIntervalSince1970))"
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Missing comment text field")
        input.tap()
        input.typeText(commentText)

        tapFirstExistingButton(["comment.send", "send"])
        waitForStaticText(commentText, timeout: 30)
    }

    func testRecommendedDetailSparkMenuOpensGoSparkResults() throws {
        let session = try requireSmokeSession()
        let sparkCardId = sparkSeedCardID
        openSparkFromDetail(cardID: sparkCardId, session: session)

        let sourceCardId = waitFor("spark.source.card-id", timeout: 10)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(sourceCardId, sparkCardId)

        let activityID = sparkAnchorValue("spark.activity.id")
        let page = try fetchSparkActivity(activityID: activityID, token: session.token)
        let visibleID = sparkAnchorValue("spark.visible-card.id")
        XCTAssertTrue(
            page.orderedAssetIDs.contains(visibleID),
            "Visible Spark card \(visibleID) was not in Go activity \(activityID)"
        )
    }

    func testFirstRunInterestsLoadAndSaveCanonicalSelection() throws {
        let session = try requireSmokeSession()
        let original = try fetchSmokeInterests(token: session.token)
        let options = try fetchSmokeInterestOptions(token: session.token)
        guard options.count >= 2 else {
            throw XCTSkip("Local Go needs at least two canonical interest options")
        }

        defer {
            _ = try? saveSmokeInterests(original.domains, token: session.token)
        }

        _ = try saveSmokeInterests([options[0]], token: session.token)
        seedAppSession(session)
        launchInterestTestRoute()

        waitFor("screen.interests", timeout: 30)
        XCTAssertEqual(waitFor("interests.option.0").value as? String, "selected")
        tap("interests.option.1")
        tap("interests.next")
        waitFor("tab.flow", timeout: 30)

        let saved = try fetchSmokeInterests(token: session.token)
        XCTAssertEqual(Set(saved.domains), Set(options.prefix(2)))
        XCTAssertTrue(saved.interestSelectionCompleted)
    }

    func testFirstRunInterestsSkipDoesNotWrite() throws {
        let session = try requireSmokeSession()
        let original = try fetchSmokeInterests(token: session.token)
        seedAppSession(session)
        launchInterestTestRoute()

        waitFor("screen.interests", timeout: 30)
        tap("interests.skip")
        waitFor("tab.flow", timeout: 30)

        let after = try fetchSmokeInterests(token: session.token)
        XCTAssertEqual(after.domains, original.domains)
        XCTAssertEqual(
            after.interestSelectionCompleted,
            original.interestSelectionCompleted
        )
    }

    private func launchAuthenticatedApp() {
        let environment = ProcessInfo.processInfo.environment

        app.launchEnvironment["CHORAI_UI_TEST"] = "1"
        if let baseURL = environment["CHORAI_API_BASE_URL"], !baseURL.isEmpty {
            app.launchEnvironment["CHORAI_API_BASE_URL"] = baseURL
        }
        if app.launchEnvironment["CHORAI_UI_TEST_AUTH_TOKEN"] == nil,
           let token = environment["CHORAI_UI_TEST_AUTH_TOKEN"],
           !token.isEmpty {
            app.launchEnvironment["CHORAI_UI_TEST_AUTH_TOKEN"] = token
        }
        if app.launchEnvironment["CHORAI_UI_TEST_ACTOR_ID"] == nil,
           let actorId = environment["CHORAI_UI_TEST_ACTOR_ID"],
           !actorId.isEmpty {
            app.launchEnvironment["CHORAI_UI_TEST_ACTOR_ID"] = actorId
        }
        if app.launchEnvironment["CHORAI_UI_TEST_AUTH_TOKEN"] == nil,
           let session = fetchLocalSmokeSession() {
            app.launchEnvironment["CHORAI_UI_TEST_AUTH_TOKEN"] = session.token
            app.launchEnvironment["CHORAI_UI_TEST_ACTOR_ID"] = session.actorId
            app.launchEnvironment["CHORAI_UI_TEST_EMAIL"] = session.email
            app.launchEnvironment["CHORAI_UI_TEST_USERNAME"] = session.username
        }
        app.launch()

        if app.launchArguments.contains("--ui-test-open-recommended-detail") {
            return
        }

        if !exists("tab.flow", timeout: 10) {
            signInWithLocalSmokeUser()
        }
    }

    private func signInWithLocalSmokeUser() {
        let environment = ProcessInfo.processInfo.environment
        let email = environment["CHORAI_UI_TEST_EMAIL"] ?? "ios-smoke-a-20260619@example.com"
        let password = environment["CHORAI_UI_TEST_PASSWORD"] ?? "Password123"

        if exists("welcome.login", timeout: 5) {
            tap("welcome.login")
        }

        let emailField = waitFor("signin.email", timeout: 15)
        emailField.tap()
        emailField.typeText(email)

        let passwordField = waitFor("signin.password")
        passwordField.tap()
        passwordField.typeText(password)

        tap("signin.submit")
        waitFor("tab.flow", timeout: 30)
    }

    private func seedAppSession(_ session: SmokeSession) {
        app.launchEnvironment["CHORAI_UI_TEST_AUTH_TOKEN"] = session.token
        app.launchEnvironment["CHORAI_UI_TEST_ACTOR_ID"] = session.actorId
        app.launchEnvironment["CHORAI_UI_TEST_EMAIL"] = session.email
        app.launchEnvironment["CHORAI_UI_TEST_USERNAME"] = session.username
    }

    private func launchInterestTestRoute() {
        app.launchEnvironment["CHORAI_UI_TEST"] = "1"
        let environment = ProcessInfo.processInfo.environment
        if let baseURL = environment["CHORAI_API_BASE_URL"], !baseURL.isEmpty {
            app.launchEnvironment["CHORAI_API_BASE_URL"] = baseURL
        }
        app.launchArguments.append("--ui-test-open-interests")
        app.launch()
    }

    private func launchProfileTestRoute(actorID: String) {
        app.launchEnvironment["CHORAI_UI_TEST"] = "1"
        if let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ], app.launchEnvironment["CHORAI_API_BASE_URL"] == nil {
            app.launchEnvironment["CHORAI_API_BASE_URL"] = baseURL
        }
        app.launchEnvironment["CHORAI_UI_TEST_PROFILE_ACTOR_ID"] = actorID
        if !app.launchArguments.contains("--ui-test-open-profile") {
            app.launchArguments.append("--ui-test-open-profile")
        }
        app.launch()
    }

    private func waitForProfileFollowValue(
        _ expected: String,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        waitForAccessibilityValue(
            "user-profile.follow",
            value: expected,
            timeout: timeout,
            file: file,
            line: line
        )
    }

    private func waitForAccessibilityValue(
        _ identifier: String,
        value expected: String,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let element = waitFor(identifier, timeout: timeout, file: file, line: line)
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Timed out waiting for \(identifier) value \(expected)",
            file: file,
            line: line
        )
    }

    @discardableResult
    private func waitFor(_ identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing accessibility identifier: \(identifier)", file: file, line: line)
        return element
    }

    @discardableResult
    private func waitForButton(
        _ identifier: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let button = app.buttons[identifier]
        XCTAssertTrue(
            button.waitForExistence(timeout: timeout),
            "Missing button accessibility identifier: \(identifier)",
            file: file,
            line: line
        )
        return button
    }

    private func waitForDifferentVisibleFlowCard(
        from initialCardId: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        let anchor = app.staticTexts["flow.visible-card.id"]
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let cardId = anchor.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if anchor.exists, !cardId.isEmpty, cardId != initialCardId {
                return cardId
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTFail("Flow did not advance from card \(initialCardId)", file: file, line: line)
        return initialCardId
    }

    private func flowVisibleCardID() -> String {
        anchorLabel("flow.visible-card.id")
    }

    private func anchorLabel(_ identifier: String) -> String {
        waitFor(identifier, timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func accessibilityValue(_ identifier: String) -> String {
        (waitFor(identifier, timeout: 30).value as? String) ?? ""
    }

    private func waitForAccessibilityValue(
        _ identifier: String,
        expected: String,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let element = app.descendants(matching: .any)[identifier]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String) == expected {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail(
            "Accessibility value for \(identifier) did not become \(expected)",
            file: file,
            line: line
        )
    }

    private func openSparkFromDetail(
        cardID: String,
        session: SmokeSession
    ) {
        seedAppSession(session)
        app.launchEnvironment["CHORAI_UI_TEST_DETAIL_CARD_ID"] = cardID
        app.launchEnvironment["CHORAI_UI_TEST_SPARK_SESSION_SCOPE"] = sparkSessionScope
        launchAuthenticatedApp()

        navigateToSparkFromFlow(cardID: cardID)
    }

    private func openFlowSparkWithResults(
        startingCardID: String,
        maxAttempts: Int = 6,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var cardID = startingCardID

        for _ in 0..<maxAttempts {
            tap("flow.spark.\(cardID)", file: file, line: line)
            if waitForSparkLoadedOrTerminal(file: file, line: line) {
                return
            }

            tap("spark.back", file: file, line: line)
            waitFor("screen.flow.content", timeout: 30, file: file, line: line)
            tap("flow.skip.\(cardID)", file: file, line: line)
            cardID = waitForDifferentVisibleFlowCard(
                from: cardID,
                timeout: 30,
                file: file,
                line: line
            )
            waitFor(
                "flow.spark.\(cardID)",
                timeout: 20,
                file: file,
                line: line
            )
        }

        XCTFail(
            "Flow did not yield a Spark result after \(maxAttempts) cards",
            file: file,
            line: line
        )
    }

    private func waitForSparkLoadedOrTerminal(
        timeout: TimeInterval = 90,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let loaded = app.descendants(matching: .any)["screen.spark.loaded"]
        let empty = app.descendants(matching: .any)["screen.spark.empty"]
        let failed = app.descendants(matching: .any)["screen.spark.error"]

        while Date() < deadline {
            if loaded.exists { return true }
            if empty.exists || failed.exists { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        XCTFail(
            "Spark did not reach loaded, empty, or failed state",
            file: file,
            line: line
        )
        return false
    }

    private func mergeCandidateSearchQuery(
        for card: SmokeCardResponse.SmokeCardData
    ) -> String {
        let asciiTokens = card.content
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count >= 6
                    && token.unicodeScalars.allSatisfy { $0.isASCII }
            }
        let token = asciiTokens.max { $0.count < $1.count }
            ?? card.title
            ?? card.id
        return String(token.prefix(24))
    }

    private func navigateToSparkFromFlow(cardID: String) {
        openSparkRouteFromFlow(cardID: cardID)
        waitFor("screen.spark.loaded", timeout: 90)
    }

    private func openSparkRouteFromFlow(cardID: String) {
        waitFor("screen.flow.content", timeout: 30)
        tap("explore.card-detail")
        waitFor("screen.detail.loaded", timeout: 30)
        XCTAssertEqual(
            waitFor("screen.detail.card-id")
                .label
                .trimmingCharacters(in: .whitespacesAndNewlines),
            cardID
        )
        tap("detail.menu.open")
        tap("popup-menu.item.spark")
    }

    private func prepareSparkVisualApp(
        session: SmokeSession,
        cardID: String,
        suffix: String,
        environment: [String: String]
    ) {
        if app.state != .notRunning {
            app.terminate()
        }
        app = XCUIApplication()
        sparkSessionScope = "\(name).\(suffix).\(UUID().uuidString)"
        seedAppSession(session)
        app.launchEnvironment["CHORAI_UI_TEST_DETAIL_CARD_ID"] = cardID
        app.launchEnvironment[
            "CHORAI_UI_TEST_SPARK_SESSION_SCOPE"
        ] = sparkSessionScope
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        launchAuthenticatedApp()
    }

    private func captureSparkVisual(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func captureMergeVisual(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "merge-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func captureShareVisual(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func captureReportVisual(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func captureVisual(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForSessionPhase(
        _ expected: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        let phase = app.descendants(matching: .any)["auth.session.phase"]
        var lastPhase = "missing"
        while Date() < deadline {
            if phase.exists {
                lastPhase = phase.label.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if lastPhase == expected {
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail(
            "Session phase did not become \(expected); last phase: \(lastPhase)",
            file: file,
            line: line
        )
    }

    private func waitForOnboardingAnchor(
        _ identifier: String,
        value expected: String,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        let anchor = app.descendants(matching: .any)[identifier]
        var lastValue = "missing"
        while Date() < deadline {
            if anchor.exists {
                lastValue = anchor.label.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if lastValue == expected {
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail(
            "\(identifier) did not become \(expected); last value: \(lastValue)",
            file: file,
            line: line
        )
    }

    private func mergeAnchorValue(
        _ identifier: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        waitFor(identifier, timeout: timeout, file: file, line: line)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sparkAnchorValue(
        _ identifier: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        waitFor(identifier, timeout: timeout, file: file, line: line)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func waitForDifferentSparkCard(
        from initialCardID: String,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = app.staticTexts["spark.visible-card.id"]
                .label
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.isEmpty, current != initialCardID {
                return current
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Spark did not advance from \(initialCardID)", file: file, line: line)
        return initialCardID
    }

    private func waitForDifferentSparkActivity(
        from initialActivityID: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = app.staticTexts["spark.activity.id"]
                .label
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.isEmpty, current != initialActivityID,
               exists("screen.spark.loaded", timeout: 0.2) {
                return current
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Spark did not create a child activity", file: file, line: line)
        return initialActivityID
    }

    private func waitForSparkActivity(
        _ expectedActivityID: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = app.staticTexts["spark.activity.id"]
                .label
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if current == expectedActivityID,
               exists("screen.spark.loaded", timeout: 0.2) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail(
            "Spark did not restore activity \(expectedActivityID)",
            file: file,
            line: line
        )
    }

    private func waitForUnfavoritedSparkResult(
        token: String,
        maximumAttempts: Int = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        for _ in 0..<maximumAttempts {
            let resultID = sparkAnchorValue(
                "spark.visible-card.id",
                timeout: 30,
                file: file,
                line: line
            )
            if try !fetchAssetStatus(kind: "favorites", id: resultID, token: token) {
                return resultID
            }
            waitFor("spark.card.\(resultID)", file: file, line: line).swipeLeft()
            _ = waitForDifferentSparkCard(from: resultID, file: file, line: line)
        }
        throw XCTSkip("No unfavorited Spark result was available")
    }

    private func waitForCompactUnfavoritedSparkResult(
        token: String,
        maximumContentLength: Int = 900,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        for _ in 0..<12 {
            let resultID = waitFor(
                "spark.visible-card.id",
                timeout: 30,
                file: file,
                line: line
            ).label.trimmingCharacters(in: .whitespacesAndNewlines)
            let card = try fetchSmokeCard(id: resultID, token: token)
            let isFavorite = try fetchAssetStatus(
                kind: "favorites",
                id: resultID,
                token: token
            )
            if !isFavorite, card.content.count <= maximumContentLength {
                return resultID
            }

            waitFor(
                "spark.card.\(resultID)",
                file: file,
                line: line
            ).swipeLeft()
            _ = waitForDifferentSparkCard(
                from: resultID,
                file: file,
                line: line
            )
        }

        throw XCTSkip("No compact unfavorited Spark result was available")
    }

    private func waitForUnfavoritedFlowCard(
        token: String,
        maximumAttempts: Int = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        for _ in 0..<maximumAttempts {
            let cardId = waitFor("flow.visible-card.id", timeout: 30, file: file, line: line)
                .label
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if try !fetchAssetStatus(kind: "favorites", id: cardId, token: token) {
                return cardId
            }

            waitFor("flow.card.\(cardId)", file: file, line: line).swipeLeft()
            _ = waitForDifferentVisibleFlowCard(from: cardId, file: file, line: line)
        }

        throw XCTSkip("No unfavorited recommendation was available for the Flow save test")
    }

    private func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = waitFor(identifier, file: file, line: line)
        XCTAssertTrue(element.isHittable, "Identifier is not hittable: \(identifier)", file: file, line: line)
        element.tap()
    }

    private func tapButton(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = waitForButton(identifier, file: file, line: line)
        XCTAssertTrue(button.isHittable, "Button is not hittable: \(identifier)", file: file, line: line)
        button.tap()
    }

    private func exists(_ identifier: String, timeout: TimeInterval) -> Bool {
        app.descendants(matching: .any)[identifier].waitForExistence(timeout: timeout)
    }

    private func openExploreSearchMode(file: StaticString = #filePath, line: UInt = #line) {
        if exists("explore.search.open", timeout: 2) {
            tap("explore.search.open", file: file, line: line)
        } else if exists("explore.search.open.test-hook", timeout: 2) {
            tap("explore.search.open.test-hook", file: file, line: line)
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.09)).tap()
        }

        _ = waitFor("explore.search.input", timeout: 10, file: file, line: line)
    }

    private func openRecordWithEmptyDraft(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        tap("record.open", file: file, line: line)
        var input = waitFor("record.input", file: file, line: line)

        if let existingDraft = input.value as? String, !existingDraft.isEmpty {
            tapButton("record.discard", file: file, line: line)
            confirmRecordDiscard(file: file, line: line)
            waitForMissing("record.sheet", timeout: 10, file: file, line: line)

            tap("record.open", file: file, line: line)
            input = waitFor("record.input", file: file, line: line)
        }

        return input
    }

    private func confirmRecordDiscard(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let discardConfirmation = app.alerts.buttons["Discard"]
        XCTAssertTrue(
            discardConfirmation.waitForExistence(timeout: 10),
            "Missing Record discard confirmation",
            file: file,
            line: line
        )
        discardConfirmation
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()
    }

    private func showExploreSearchResult(searchToken: String, expectedCardId: String, file: StaticString = #filePath, line: UInt = #line) {
        waitFor("tab.flow", file: file, line: line)
        waitFor("screen.flow.content", timeout: 20, file: file, line: line)
        openExploreSearchMode(file: file, line: line)

        let input = waitFor("explore.search.input", file: file, line: line)
        input.tap()
        input.typeText(searchToken)
        input.typeText("\n")

        waitFor("explore.search.results", timeout: 30, file: file, line: line)
        let resultCardId = waitFor("explore.search.result.card-id", timeout: 10, file: file, line: line)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(resultCardId, expectedCardId, file: file, line: line)
    }

    private func tapFirstExistingButton(_ identifiers: [String], timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var candidate: XCUIElement?

        while Date() < deadline {
            for identifier in identifiers {
                let button = app.buttons[identifier]
                if button.exists {
                    candidate = button
                    if button.isHittable {
                        button.tap()
                        return
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        if let candidate {
            XCTAssertTrue(candidate.isHittable, "Button is not hittable: \(candidate)", file: file, line: line)
        } else {
            let identifierList = identifiers.joined(separator: ", ")
            XCTFail("Missing button identifiers: \(identifierList)", file: file, line: line)
        }
    }

    private func tapFirstHittableButton(
        label: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        let query = app.buttons.matching(
            NSPredicate(format: "label == %@", label)
        )

        while Date() < deadline {
            for index in 0..<query.count {
                let button = query.element(boundBy: index)
                if button.isHittable {
                    button.tap()
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTFail("Missing hittable button with label: \(label)", file: file, line: line)
    }

    private func replaceText(_ identifier: String, with text: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = waitFor(identifier, timeout: 10, file: file, line: line)
        XCTAssertTrue(element.isHittable, "Identifier is not hittable: \(identifier)", file: file, line: line)
        element.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        if let remaining = element.value as? String, !remaining.isEmpty {
            element.press(forDuration: 1)
            let selectAllMenuItem = app.menuItems["Select All"].firstMatch
            let selectAllButton = app.buttons["Select All"].firstMatch
            if selectAllMenuItem.waitForExistence(timeout: 3) {
                selectAllMenuItem.tap()
            } else if selectAllButton.waitForExistence(timeout: 1) {
                selectAllButton.tap()
            } else {
                XCTFail(
                    "Could not select all text for \(identifier)",
                    file: file,
                    line: line
                )
                return
            }
        }
        app.typeText(text)
        XCTAssertEqual(
            element.value as? String ?? "",
            text,
            "Could not replace text for \(identifier)",
            file: file,
            line: line
        )
    }

    private func dismissKeyboard() {
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
    }

    private func revealEditorBackgroundButton(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let button = app.descendants(matching: .any)[
            "cardEditorBackgroundButton"
        ]
        for _ in 0..<4 where !button.isHittable {
            let start = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.84, dy: 0.55)
            )
            let end = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.18, dy: 0.55)
            )
            start.press(forDuration: 0.05, thenDragTo: end)
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(
            button.isHittable,
            "Background control was not reachable in the editor toolbar",
            file: file,
            line: line
        )
    }

    private func tapEditProfileSave(file: StaticString = #filePath, line: UInt = #line) {
        _ = waitFor("edit-profile.save", timeout: 10, file: file, line: line)
        let visibleSaveButton = app.buttons["Save"].firstMatch
        if visibleSaveButton.waitForExistence(timeout: 3) {
            visibleSaveButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1)).tap()
    }

    private func waitForFinalEditProfileSaveStatus(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        let element = waitFor("edit-profile.save-status", timeout: 10, file: file, line: line)
        var lastStatus = element.label.trimmingCharacters(in: .whitespacesAndNewlines)

        while Date() < deadline {
            lastStatus = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if lastStatus != "idle" && lastStatus != "attempted" {
                return lastStatus
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        XCTFail("Timed out waiting for final edit profile save status; last status: \(lastStatus)", file: file, line: line)
        return lastStatus
    }

    @discardableResult
    private func waitForStaticText(_ text: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = app.staticTexts[text]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing static text: \(text)", file: file, line: line)
        return element
    }

    private func waitForMergeArtifactReady(
        timeout: TimeInterval = 90,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        let ready = app.descendants(matching: .any)["merge.artifact.ready"]
        let paused = app.descendants(matching: .any)["merge.phase.paused"]
        let failed = app.descendants(matching: .any)["merge.phase.failed"]
        var lastStatus = "missing"

        while Date() < deadline {
            if ready.exists {
                return
            }
            if paused.exists {
                XCTFail("Merge paused before artifact became ready", file: file, line: line)
                return
            }
            if failed.exists {
                XCTFail("Merge failed before artifact became ready", file: file, line: line)
                return
            }
            let status = app.descendants(matching: .any)["merge.job.status"]
            if status.exists {
                lastStatus = status.label.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        XCTFail(
            "Timed out waiting for Merge artifact; last job status: \(lastStatus)",
            file: file,
            line: line
        )
    }

    private func waitForCommittedMergeCard(
        excluding sourceCardID: String,
        timeout: TimeInterval = 90,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        let detailID = app.descendants(matching: .any)["screen.detail.card-id"]
        let paused = app.descendants(matching: .any)["merge.phase.paused"]
        let failed = app.descendants(matching: .any)["merge.phase.failed"]
        var lastStatus = "missing"

        while Date() < deadline {
            if detailID.exists {
                let value = detailID.label.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !value.isEmpty, value != sourceCardID {
                    return value
                }
            }
            if paused.exists {
                XCTFail("Merge commit paused before opening detail", file: file, line: line)
                return nil
            }
            if failed.exists {
                XCTFail("Merge commit failed before opening detail", file: file, line: line)
                return nil
            }
            let status = app.descendants(matching: .any)["merge.job.status"]
            if status.exists {
                lastStatus = status.label.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        XCTFail(
            "Timed out waiting for committed Merge detail; last status: \(lastStatus)",
            file: file,
            line: line
        )
        return nil
    }

    private func waitForLoadedDetailCard(
        _ expectedCardID: String,
        timeout: TimeInterval = 30,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        let loadedCardID = app.descendants(matching: .any)[
            "screen.detail.loaded-card-id"
        ]
        var lastCardID = "missing"

        while Date() < deadline {
            if loadedCardID.exists {
                lastCardID = loadedCardID.label.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if lastCardID == expectedCardID {
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTFail(
            "Detail did not load committed card \(expectedCardID); last loaded card: \(lastCardID)",
            file: file,
            line: line
        )
    }

    private func waitForMergeCardsLoaded(timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        let loaded = app.descendants(matching: .any)["merge.cards.loaded"]
        let error = app.descendants(matching: .any)["merge.cards.error"]

        while Date() < deadline {
            if loaded.exists {
                return
            }
            if error.exists {
                XCTFail("Merge candidate cards failed to load: \(error.label)", file: file, line: line)
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        XCTFail("Timed out waiting for merge candidate cards to load", file: file, line: line)
    }

    private func waitForEditProfileAvatarUploadStatus(_ expectedStatus: String, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        let status = app.descendants(matching: .any)["edit-profile.avatar-upload-status"]
        let error = app.descendants(matching: .any)["edit-profile.avatar-upload-error"]
        var lastStatus = "missing"

        while Date() < deadline {
            if status.exists {
                lastStatus = status.label.trimmingCharacters(in: .whitespacesAndNewlines)
                if lastStatus == expectedStatus {
                    return
                }
                if lastStatus == "failure" {
                    XCTFail("Avatar upload failed: \(error.label)", file: file, line: line)
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }

        XCTFail("Timed out waiting for avatar upload status \(expectedStatus); last status: \(lastStatus)", file: file, line: line)
    }

    private func selectFirstPhotoFromImagePicker(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(timeout)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButtons = [
            "Allow Full Access",
            "Allow Access to All Photos",
            "Full Access",
            "Allow"
        ]

        while Date() < deadline {
            for title in allowButtons {
                if springboard.buttons[title].exists {
                    springboard.buttons[title].tap()
                    break
                }
                if app.buttons[title].exists {
                    app.buttons[title].tap()
                    break
                }
            }

            let firstCell = app.collectionViews.cells.element(boundBy: 0)
            if firstCell.exists && firstCell.isHittable {
                firstCell.tap()
                tapImagePickerConfirmationIfNeeded()
                return
            }

            if isSystemImagePickerVisible() {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.42)).tap()
                tapImagePickerConfirmationIfNeeded()
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }

        throw XCTSkip("No selectable image was found in the simulator photo library; preload media before running avatar picker smoke")
    }

    private func isSystemImagePickerVisible() -> Bool {
        app.buttons["照片"].exists ||
        app.buttons["Photos"].exists ||
        app.buttons["精选集"].exists ||
        app.buttons["Collections"].exists ||
        app.staticTexts["私密访问照片"].exists ||
        app.staticTexts["Private Access to Photos"].exists
    }

    private func tapImagePickerConfirmationIfNeeded() {
        let confirmationTitles = [
            "Choose",
            "Use Photo",
            "Add",
            "Done",
            "选取",
            "使用照片",
            "添加",
            "完成"
        ]

        for title in confirmationTitles {
            let button = app.buttons[title]
            if button.waitForExistence(timeout: 1) && button.isHittable {
                button.tap()
                return
            }
        }
    }

    private struct SmokeSession {
        let token: String
        let actorId: String
        let email: String
        let username: String
    }

    private struct SmokeInterestResponse: Decodable {
        let data: SmokeInterestData
    }

    private struct SmokeInterestData: Decodable {
        let domains: [String]
        let interestSelectionCompleted: Bool

        enum CodingKeys: String, CodingKey {
            case domains
            case interestSelectionCompleted = "interest_selection_completed"
        }
    }

    private struct SmokeInterestOptionsResponse: Decodable {
        let data: SmokeInterestOptionsData
    }

    private struct SmokeInterestOptionsData: Decodable {
        let domains: [String]
    }

    private struct SmokeCardResponse: Decodable {
        let data: SmokeCardData

        struct SmokeCardData: Decodable {
            let id: String
            let title: String?
            let content: String
            let isPublic: Bool
            let isPinned: Bool
            let tags: [String]
            let backgroundMediaRef: String?

            enum CodingKeys: String, CodingKey {
                case id, title, content, tags
                case isPublic = "is_public"
                case isPinned = "is_pinned"
                case backgroundMediaRef = "background_media_ref"
            }
        }
    }

    private struct SmokeTrashListResponse: Decodable {
        let data: [SmokeTrashCard]

        struct SmokeTrashCard: Decodable {
            let id: String
        }
    }

    private struct SmokeSharePreview: Decodable {
        let artifact: Artifact

        struct Artifact: Decodable {
            let id: String
        }
    }

    private struct SmokeReportResponse: Decodable {
        let data: SmokeReport
    }

    private struct SmokeReport: Decodable {
        let reportID: String
        let status: String

        enum CodingKeys: String, CodingKey {
            case reportID = "report_id"
            case status
        }
    }

    private struct SmokeMergeJobResponse: Decodable {
        let status: String
    }

    private struct AssetStatusResponse: Decodable {
        let data: [String: Bool]
    }

    private struct SmokeCreateConversationResponse: Decodable {
        let data: SmokeCreateConversationData

        struct SmokeCreateConversationData: Decodable {
            let id: String

            enum CodingKeys: String, CodingKey {
                case id = "conversation_id"
            }
        }
    }

    private struct SmokeMessagesResponse: Decodable {
        let data: SmokeMessagesData

        struct SmokeMessagesData: Decodable {
            let items: [SmokeMessage]
        }

        struct SmokeMessage: Decodable {
            let content: String
        }
    }

    private struct SmokeNotificationsResponse: Decodable {
        let data: [SmokeNotification]

        struct SmokeNotification: Decodable {
            let notificationId: String
            let sourceType: String
            let isRead: Bool
            let target: SmokeNotificationTarget?

            enum CodingKeys: String, CodingKey {
                case notificationId = "notification_id"
                case sourceType = "source_type"
                case isRead = "is_read"
                case target
            }
        }

        struct SmokeNotificationTarget: Decodable {
            let type: String
            let id: String
        }
    }

    private struct SmokeProfileResponse: Decodable {
        let data: SmokeProfile
    }

    private struct SmokePublicProfileResponse: Decodable {
        let data: SmokePublicProfile
    }

    private struct SmokePublicProfile: Decodable {
        let actorID: String
        let followerCount: Int
        let followingCount: Int
        let isFollowing: Bool

        enum CodingKeys: String, CodingKey {
            case actorID = "actor_id"
            case followerCount = "follower_count"
            case followingCount = "following_count"
            case isFollowing = "is_following"
        }
    }

    private struct SmokePrivacyResponse: Decodable {
        let data: SmokePrivacy
    }

    private struct SmokePrivacy: Decodable {
        let showFollowLists: Bool

        enum CodingKeys: String, CodingKey {
            case showFollowLists = "show_follow_lists"
        }
    }

    private struct SmokeBlockedActorsResponse: Decodable {
        let data: SmokeBlockedActorsPage
    }

    private struct SmokeBlockedActorsPage: Decodable {
        let items: [SmokeBlockedActor]
    }

    private struct SmokeBlockedActor: Decodable {
        let actorID: String

        enum CodingKeys: String, CodingKey {
            case actorID = "actor_id"
        }
    }

    private struct SmokeProfile: Decodable {
        let username: String
        let avatarURL: String
        let bio: String
        let city: String
        let birthday: String

        enum CodingKeys: String, CodingKey {
            case username
            case avatar
            case avatarURL = "avatar_url"
            case bio
            case city
            case location
            case birthday
        }

        init(username: String, avatarURL: String, bio: String, city: String, birthday: String) {
            self.username = username
            self.avatarURL = avatarURL
            self.bio = bio
            self.city = city
            self.birthday = birthday
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            username = (try? container.decode(String.self, forKey: .username)) ?? ""
            avatarURL = (try? container.decode(String.self, forKey: .avatarURL))
                ?? (try? container.decode(String.self, forKey: .avatar))
                ?? ""
            bio = (try? container.decode(String.self, forKey: .bio)) ?? ""
            city = (try? container.decode(String.self, forKey: .city))
                ?? (try? container.decode(String.self, forKey: .location))
                ?? ""
            birthday = (try? container.decode(String.self, forKey: .birthday)) ?? ""
        }
    }

    private struct SmokeSparkActivityResponse: Decodable {
        let data: SmokeSparkActivity

        struct SmokeSparkActivity: Decodable {
            let activityID: String
            let parentActivityID: String?
            let rootActivityID: String
            let chainDepth: Int
            let sourceAssetID: String
            let groups: SmokeSparkGroups

            var orderedItems: [SmokeSparkItem] {
                [groups.related, groups.angles, groups.keywords]
                    .compactMap { $0 }
                    .flatMap(\.items)
            }

            var orderedAssetIDs: [String] {
                var seen = Set<String>()
                return orderedItems
                    .map(\.assetID)
                    .filter { seen.insert($0).inserted }
            }

            var bucketByAssetID: [String: String] {
                var result: [String: String] = [:]
                for item in orderedItems where result[item.assetID] == nil {
                    result[item.assetID] = item.bucket
                }
                return result
            }

            enum CodingKeys: String, CodingKey {
                case activityID = "activity_id"
                case parentActivityID = "parent_activity_id"
                case rootActivityID = "root_activity_id"
                case chainDepth = "chain_depth"
                case sourceAssetID = "source_asset_id"
                case groups
            }
        }

        struct SmokeSparkGroups: Decodable {
            let related: SmokeSparkBucket?
            let angles: SmokeSparkBucket?
            let keywords: SmokeSparkBucket?
        }

        struct SmokeSparkBucket: Decodable {
            let items: [SmokeSparkItem]
        }

        struct SmokeSparkItem: Decodable {
            let assetID: String
            let bucket: String

            enum CodingKeys: String, CodingKey {
                case assetID = "asset_id"
                case bucket
            }
        }
    }

    private struct SmokeDiscoveryPathResponse: Decodable {
        let data: SmokeDiscoveryPath

        struct SmokeDiscoveryPath: Decodable {
            let rootActivityID: String

            enum CodingKeys: String, CodingKey {
                case rootActivityID = "root_activity_id"
            }
        }
    }

    private struct SmokeSparkHistoryResponse: Decodable {
        let data: SmokeSparkHistory

        struct SmokeSparkHistory: Decodable {
            let total: Int
        }
    }

    private func requireSmokeNotificationId(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let notificationId = ProcessInfo.processInfo.environment["CHORAI_UI_TEST_NOTIFICATION_ID"] ?? "ntf_ios_ui_active"
        guard !notificationId.isEmpty else {
            throw XCTSkip("CHORAI_UI_TEST_NOTIFICATION_ID is required for notification UI smoke")
        }
        return notificationId
    }

    private struct LoginResponse: Decodable {
        let data: LoginData

        struct LoginData: Decodable {
            let token: String
            let user: LoginUser
        }

        struct LoginUser: Decodable {
            let id: String
            let email: String
            let username: String
        }
    }

    private struct SmokeOnboardingResponse: Decodable {
        let data: SmokeOnboardingSession
    }

    private struct SmokeOnboardingStatusResponse: Decodable {
        let data: SmokeOnboardingStatus
    }

    private struct SmokeOnboardingStatus: Decodable {
        let completed: Bool
        let needsOnboarding: Bool
        let latestSessionID: String?
        let activeSessionID: String?

        enum CodingKeys: String, CodingKey {
            case completed
            case needsOnboarding = "needs_onboarding"
            case latestSessionID = "latest_session_id"
            case activeSessionID = "active_session_id"
        }
    }

    private struct SmokeOnboardingSession: Decodable {
        let sessionID: String
        let flowVersion: Int
        let status: String
        let state: String

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case flowVersion = "flow_version"
            case status, state
        }
    }

    private struct SmokeVerifyTokenResponse: Decodable {
        let data: VerifyData

        struct VerifyData: Decodable {
            let user: VerifyUser
        }

        struct VerifyUser: Decodable {
            let id: String
        }
    }

    private func requireSmokeSession(file: StaticString = #filePath, line: UInt = #line) throws -> SmokeSession {
        if let cached = Self.cachedSmokeSession {
            return cached
        }
        let environment = ProcessInfo.processInfo.environment
        if let token = environment["CHORAI_UI_TEST_AUTH_TOKEN"], !token.isEmpty {
            return SmokeSession(
                token: token,
                actorId: environment["CHORAI_UI_TEST_ACTOR_ID"] ?? "",
                email: environment["CHORAI_UI_TEST_EMAIL"] ?? "ios-smoke-a-20260619@example.com",
                username: environment["CHORAI_UI_TEST_USERNAME"] ?? "iossmokea20260619"
            )
        }

        if let session = fetchLocalSmokeSession() {
            return session
        }

        XCTFail("Unable to authenticate against local Go backend", file: file, line: line)
        throw NSError(domain: "ArcNoteUITests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to authenticate against local Go backend"])
    }

    private func requireFreshSmokeSession(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SmokeSession {
        if let session = fetchFreshSmokeSession() {
            return session
        }
        XCTFail(
            "Unable to create a fresh local Go session",
            file: file,
            line: line
        )
        throw NSError(
            domain: "ArcNoteUITests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to create a fresh local Go session"]
        )
    }

    private func requireDisposableSmokeSession(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SmokeSession {
        let environment = ProcessInfo.processInfo.environment
        if let token = environment["CHORAI_UI_TEST_DISPOSABLE_AUTH_TOKEN"],
           let actorID = environment["CHORAI_UI_TEST_DISPOSABLE_ACTOR_ID"],
           !token.isEmpty,
           !actorID.isEmpty {
            return SmokeSession(
                token: token,
                actorId: actorID,
                email: environment["CHORAI_UI_TEST_DISPOSABLE_EMAIL"] ?? "",
                username: environment["CHORAI_UI_TEST_DISPOSABLE_USERNAME"]
                    ?? "notification-disposable"
            )
        }
        if let session = fetchLocalPhoneSmokeSession(
            phone: environment["CHORAI_UI_TEST_DISPOSABLE_PHONE"]
        ) {
            return session
        }
        XCTFail(
            "Unable to authenticate disposable local Go session",
            file: file,
            line: line
        )
        throw NSError(
            domain: "ArcNoteUITests",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Unable to authenticate disposable local Go session"
            ]
        )
    }

    private func requireSecondarySmokeSession(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SmokeSession {
        let environment = ProcessInfo.processInfo.environment
        if let token = environment["CHORAI_UI_TEST_TARGET_AUTH_TOKEN"],
           let actorID = environment["CHORAI_UI_TEST_TARGET_ACTOR_ID"],
           !token.isEmpty,
           !actorID.isEmpty {
            return SmokeSession(
                token: token,
                actorId: actorID,
                email: environment["CHORAI_UI_TEST_TARGET_EMAIL"] ?? "",
                username: environment["CHORAI_UI_TEST_TARGET_USERNAME"]
                    ?? "notification-source"
            )
        }
        let email = environment["CHORAI_UI_TEST_TARGET_EMAIL"]
            ?? "ios-smoke-b-20260619@example.com"
        let password = environment["CHORAI_UI_TEST_TARGET_PASSWORD"]
            ?? "Password123"
        if let session = fetchSmokeSession(email: email, password: password) {
            return session
        }
        let phone = environment["CHORAI_UI_TEST_TARGET_PHONE"]
            ?? "+8613907111235"
        if let session = fetchLocalPhoneSmokeSession(phone: phone) {
            return session
        }
        XCTFail(
            "Unable to authenticate secondary local Go user",
            file: file,
            line: line
        )
        throw NSError(
            domain: "ArcNoteUITests",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Unable to authenticate secondary local Go user"
            ]
        )
    }

    private func revokeSmokeSession(token: String) throws {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/auth/logout") else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Go logout URL"]
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try sendRawRequest(request)
    }

    private func fetchSmokeInterestOptions(token: String) throws -> [String] {
        let response: SmokeInterestOptionsResponse = try sendAuthenticatedSmokeRequest(
            path: "/api/v1/profile/interests/options",
            token: token
        )
        return response.data.domains
    }

    private func fetchSmokeInterests(token: String) throws -> SmokeInterestData {
        let response: SmokeInterestResponse = try sendAuthenticatedSmokeRequest(
            path: "/api/v1/profile/interests",
            token: token
        )
        return response.data
    }

    @discardableResult
    private func saveSmokeInterests(
        _ domains: [String],
        token: String
    ) throws -> SmokeInterestData {
        let response: SmokeInterestResponse = try sendAuthenticatedSmokeRequest(
            path: "/api/v1/profile/interests",
            token: token,
            method: "PUT",
            body: ["domains": domains]
        )
        return response.data
    }

    private func sendAuthenticatedSmokeRequest<T: Decodable>(
        path: String,
        token: String,
        method: String = "GET",
        body: [String: Any]? = nil
    ) throws -> T {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Go API URL"]
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try sendRequest(request, responseType: T.self)
    }

    private func restartSmokeOnboarding(
        token: String,
        flowVersion: Int
    ) throws -> SmokeOnboardingSession {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/v1/onboarding/sessions") else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 16,
                userInfo: [NSLocalizedDescriptionKey: "Invalid onboarding start URL"]
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "flow_version": flowVersion,
            "restart": true
        ])
        return try sendRequest(
            request,
            responseType: SmokeOnboardingResponse.self
        ).data
    }

    private func fetchCurrentSmokeOnboarding(
        token: String
    ) throws -> SmokeOnboardingSession {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(
            string: "\(baseURL)/api/v1/onboarding/sessions/current"
        ) else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 16,
                userInfo: [NSLocalizedDescriptionKey: "Invalid onboarding current URL"]
            )
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokeOnboardingResponse.self
        ).data
    }

    private func waitForSmokeOnboardingState(
        _ expected: String,
        token: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        var lastState = "missing"
        var lastError: Error?

        while Date() < deadline {
            do {
                let session = try fetchCurrentSmokeOnboarding(token: token)
                lastState = session.state
                if lastState == expected { return }
            } catch {
                lastError = error
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        XCTFail(
            "Go onboarding did not become \(expected); last state: "
                + "\(lastState), last error: \(String(describing: lastError))",
            file: file,
            line: line
        )
    }

    private func fetchSmokeOnboardingStatus(
        token: String
    ) throws -> SmokeOnboardingStatus {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/v1/onboarding/status") else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 16,
                userInfo: [
                    NSLocalizedDescriptionKey: "Invalid onboarding status URL"
                ]
            )
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokeOnboardingStatusResponse.self
        ).data
    }

    private func verifySmokeToken(
        token: String
    ) throws -> SmokeVerifyTokenResponse.VerifyData {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/auth/verify-token") else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Go verify-token URL"]
            )
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokeVerifyTokenResponse.self
        ).data
    }

    private func assertSmokeTokenUnauthorized(
        _ token: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/auth/verify-token") else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Go verify-token URL"]
            )
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            _ = try sendRawRequest(request)
            XCTFail("Go token remained valid after logout", file: file, line: line)
        } catch let error as NSError {
            XCTAssertEqual(error.code, 401, file: file, line: line)
        }
    }

    private func createPublicSmokeCard(token: String, searchToken: String) throws -> String {
        try createSmokeCard(token: token, searchToken: searchToken, isPublic: true)
    }

    private func createSmokeCard(
        token: String,
        searchToken: String,
        isPublic: Bool
    ) throws -> String {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/cards") else {
            throw NSError(domain: "ArcNoteUITests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid Go API base URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": "iOS typed search UI \(searchToken)",
            "content": "iOS typed search result navigation smoke \(searchToken)",
            "tags": ["ios-ui-smoke", searchToken],
            "is_public": isPublic
        ])

        let response = try sendRequest(request, responseType: SmokeCardResponse.self)
        return response.data.id
    }

    private func deleteSmokeCard(id: String, token: String) {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/cards/\(id)") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? sendRawRequest(request)
    }

    private func permanentlyCleanUpSmokeCard(id: String, token: String) {
        deleteSmokeCard(id: id, token: token)
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/cards/trash/\(id)/permanent") else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? sendRawRequest(request)
    }

    private func waitForSmokeCardState(
        id: String,
        token: String,
        timeout: TimeInterval = 20,
        predicate: (SmokeCardResponse.SmokeCardData) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let card = try? fetchSmokeCard(id: id, token: token), predicate(card) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("Go card state did not converge for \(id)", file: file, line: line)
    }

    private func waitForTrashCard(
        id: String,
        token: String,
        isPresent: Bool,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let ids = try? fetchSmokeTrashCardIDs(token: token),
               ids.contains(id) == isPresent {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail(
            "Go trash state did not converge for \(id), expected present=\(isPresent)",
            file: file,
            line: line
        )
    }

    private func waitForTrashCardVisible(
        _ id: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if app.descendants(matching: .any)["trash.card.\(id)"].waitForExistence(timeout: 20) {
            return
        }
        captureVisual("trash-card-not-visible")
        XCTFail("Newest Trash card \(id) was not visible on the first page", file: file, line: line)
    }

    private func fetchSmokeTrashCardIDs(token: String) throws -> Set<String> {
        Set(try fetchSmokeTrashCardIDsInOrder(token: token))
    }

    private func fetchSmokeTrashCardIDsInOrder(token: String) throws -> [String] {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/cards/trash?page=1&per_page=100") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response = try sendRequest(request, responseType: SmokeTrashListResponse.self)
        return response.data.map(\.id)
    }

    private func fetchSmokeCard(
        id: String,
        token: String
    ) throws -> SmokeCardResponse.SmokeCardData {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/cards/\(id)") else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Go card URL"]
            )
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(request, responseType: SmokeCardResponse.self).data
    }

    private func fetchSmokeSharePreview(
        cardID: String,
        token: String
    ) throws -> SmokeSharePreview {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard var components = URLComponents(
            string: "\(baseURL)/api/cards/\(cardID)/share-preview"
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "template", value: "auto")]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokeSharePreview.self
        )
    }

    private func fetchSmokeReport(
        id: String,
        token: String
    ) throws -> SmokeReport {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(
            string: "\(baseURL)/api/content-reports/\(id)"
        ) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokeReportResponse.self
        ).data
    }

    private func fetchSmokeMergeJob(
        jobID: String,
        token: String
    ) throws -> SmokeMergeJobResponse {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"]
            ?? "http://127.0.0.1:8080"
        guard let url = URL(
            string: "\(baseURL)/api/merge/jobs/\(jobID)"
        ) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokeMergeJobResponse.self
        )
    }

    private func clearFavoriteLikeState(id: String, token: String) {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        for kind in ["favorites", "likes"] {
            guard let url = URL(string: "\(baseURL)/api/v1/actors/me/\(kind)/\(id)") else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? sendRawRequest(request)
        }
    }

    private func setSmokeLikeStatus(
        _ liked: Bool,
        id: String,
        token: String
    ) throws {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        let path = liked
            ? "/api/v1/actors/me/likes"
            : "/api/v1/actors/me/likes/\(id)"
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = liked ? "POST" : "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if liked {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["asset_id": id]
            )
        }
        _ = try sendRawRequest(request)
    }

    private func fetchAssetStatus(kind: String, id: String, token: String) throws -> Bool {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/v1/actors/me/\(kind)/status") else {
            throw NSError(domain: "ArcNoteUITests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid Go asset status URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "asset_ids": [id]
        ])

        let response = try sendRequest(request, responseType: AssetStatusResponse.self)
        return response.data[id] ?? false
    }

    private func waitForAssetStatus(kind: String, id: String, token: String, expected: Bool, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var lastValue: Bool?
        var lastError: Error?

        while Date() < deadline {
            do {
                let value = try fetchAssetStatus(kind: kind, id: id, token: token)
                lastValue = value
                if value == expected {
                    return
                }
            } catch {
                lastError = error
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }

        if let lastError {
            XCTFail("Timed out waiting for \(kind) status \(expected) for \(id); last error: \(lastError)", file: file, line: line)
        } else {
            XCTFail("Timed out waiting for \(kind) status \(expected) for \(id); last value: \(String(describing: lastValue))", file: file, line: line)
        }
    }

    private func createSmokeConversation(targetActorId: String, token: String) throws -> String {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/chats/conversations") else {
            throw NSError(domain: "ArcNoteUITests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid Go chat conversation URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "participant_actor_id": targetActorId
        ])

        let response = try sendRequest(request, responseType: SmokeCreateConversationResponse.self)
        return response.data.id
    }

    private func fetchChatMessages(conversationId: String, token: String) throws -> [String] {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard var components = URLComponents(string: "\(baseURL)/api/chats/conversations/\(conversationId)/messages") else {
            throw NSError(domain: "ArcNoteUITests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid Go chat messages URL"])
        }
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: "50")
        ]
        guard let url = components.url else {
            throw NSError(domain: "ArcNoteUITests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Invalid encoded Go chat messages URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let response = try sendRequest(request, responseType: SmokeMessagesResponse.self)
        return response.data.items.map(\.content)
    }

    private func fetchCurrentSmokeProfile(token: String) throws -> SmokeProfile {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/v1/profile/me") else {
            throw NSError(domain: "ArcNoteUITests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Invalid Go profile/me URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try sendRequest(request, responseType: SmokeProfileResponse.self).data
    }

    private func fetchSmokePublicProfile(
        actorID: String,
        token: String
    ) throws -> SmokePublicProfile {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(
            string: "\(baseURL)/api/v1/profile/\(actorID)"
        ) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokePublicProfileResponse.self
        ).data
    }

    private func waitForSmokePublicProfile(
        actorID: String,
        token: String,
        isFollowing: Bool,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> SmokePublicProfile {
        let deadline = Date().addingTimeInterval(timeout)
        var last: SmokePublicProfile?
        var lastError: Error?
        while Date() < deadline {
            do {
                let profile = try fetchSmokePublicProfile(
                    actorID: actorID,
                    token: token
                )
                last = profile
                if profile.isFollowing == isFollowing {
                    return profile
                }
            } catch {
                lastError = error
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        XCTFail(
            "Timed out waiting for follow=\(isFollowing); last=\(String(describing: last)), error=\(String(describing: lastError))",
            file: file,
            line: line
        )
        return last ?? SmokePublicProfile(
            actorID: actorID,
            followerCount: -1,
            followingCount: -1,
            isFollowing: !isFollowing
        )
    }

    private func setSmokeFollowing(
        actorID: String,
        token: String,
        following: Bool
    ) throws {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(
            string: "\(baseURL)/api/follows/\(actorID)"
        ) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = following ? "POST" : "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try sendRawRequest(request)
    }

    private func ensureSmokeFollowing(
        actorID: String,
        token: String,
        following: Bool
    ) throws {
        let current = try fetchSmokePublicProfile(
            actorID: actorID,
            token: token
        )
        guard current.isFollowing != following else { return }
        try setSmokeFollowing(
            actorID: actorID,
            token: token,
            following: following
        )
    }

    private func fetchSmokePrivacy(token: String) throws -> SmokePrivacy {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(
            string: "\(baseURL)/api/v1/profile/me/privacy"
        ) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokePrivacyResponse.self
        ).data
    }

    private func setSmokePrivacy(
        token: String,
        showFollowLists: Bool
    ) throws {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(
            string: "\(baseURL)/api/v1/profile/me/privacy"
        ) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "show_follow_lists": showFollowLists
        ])
        _ = try sendRawRequest(request)
    }

    private func setSmokeBlocked(
        actorID: String,
        token: String,
        blocked: Bool
    ) throws {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(
            string: "\(baseURL)/api/user-blocks/\(actorID)"
        ) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = blocked ? "POST" : "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try sendRawRequest(request)
    }

    private func fetchSmokeBlockedActors(
        token: String
    ) throws -> [SmokeBlockedActor] {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(
            string: "\(baseURL)/api/user-blocks?limit=50"
        ) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokeBlockedActorsResponse.self
        ).data.items
    }

    private func waitForSmokeBlockedActor(
        actorID: String,
        token: String,
        blocked: Bool,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        var lastIDs: [String] = []
        var lastError: Error?
        while Date() < deadline {
            do {
                lastIDs = try fetchSmokeBlockedActors(token: token).map(\.actorID)
                if lastIDs.contains(actorID) == blocked {
                    return
                }
            } catch {
                lastError = error
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        XCTFail(
            "Timed out waiting for blocked=\(blocked); ids=\(lastIDs), error=\(String(describing: lastError))",
            file: file,
            line: line
        )
    }

    private func updateCurrentSmokeProfile(token: String, username: String, avatarURL: String, bio: String, city: String, birthday: String) throws {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/v1/profile/me") else {
            throw NSError(domain: "ArcNoteUITests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Invalid Go profile/me URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "username": username,
            "avatar_url": avatarURL,
            "bio": bio,
            "city": city
        ]
        if !birthday.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["birthday"] = birthday
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        _ = try sendRawRequest(request)
    }

    private func waitForCurrentSmokeProfile(token: String, bio: String, city: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var lastProfile: SmokeProfile?
        var lastError: Error?

        while Date() < deadline {
            do {
                let profile = try fetchCurrentSmokeProfile(token: token)
                lastProfile = profile
                if profile.bio == bio && profile.city == city {
                    return
                }
            } catch {
                lastError = error
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }

        if let lastError {
            XCTFail("Timed out waiting for Go profile/me update; last error: \(lastError)", file: file, line: line)
        } else {
            XCTFail("Timed out waiting for Go profile/me update; last profile: \(String(describing: lastProfile))", file: file, line: line)
        }
    }

    private func waitForCurrentSmokeProfileAvatarChanged(token: String, previousAvatarURL: String, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) -> SmokeProfile {
        let deadline = Date().addingTimeInterval(timeout)
        var lastProfile: SmokeProfile?
        var lastError: Error?

        while Date() < deadline {
            do {
                let profile = try fetchCurrentSmokeProfile(token: token)
                lastProfile = profile
                if !profile.avatarURL.isEmpty && profile.avatarURL != previousAvatarURL {
                    return profile
                }
            } catch {
                lastError = error
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }

        if let lastError {
            XCTFail("Timed out waiting for profile avatar URL change; last error: \(lastError)", file: file, line: line)
        } else {
            XCTFail("Timed out waiting for profile avatar URL change; previous: \(previousAvatarURL), last profile: \(String(describing: lastProfile))", file: file, line: line)
        }
        return lastProfile ?? SmokeProfile(username: "", avatarURL: "", bio: "", city: "", birthday: "")
    }

    private func waitForChatMessage(conversationId: String, content: String, token: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var lastMessages: [String] = []
        var lastError: Error?

        while Date() < deadline {
            do {
                lastMessages = try fetchChatMessages(conversationId: conversationId, token: token)
                if lastMessages.contains(content) {
                    return
                }
            } catch {
                lastError = error
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }

        if let lastError {
            XCTFail("Timed out waiting for chat message in Go list; last error: \(lastError)", file: file, line: line)
        } else {
            XCTFail("Timed out waiting for chat message in Go list; last messages: \(lastMessages)", file: file, line: line)
        }
    }

    private func fetchNotificationReadState(notificationId: String, token: String) throws -> Bool? {
        try fetchSmokeNotifications(token: token).first(where: {
            $0.notificationId == notificationId
        })?.isRead
    }

    private func fetchSmokeNotifications(
        token: String
    ) throws -> [SmokeNotificationsResponse.SmokeNotification] {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard var components = URLComponents(string: "\(baseURL)/api/notifications") else {
            throw NSError(domain: "ArcNoteUITests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid Go notifications URL"])
        }
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: "100")
        ]
        guard let url = components.url else {
            throw NSError(domain: "ArcNoteUITests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid encoded Go notifications URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let response = try sendRequest(request, responseType: SmokeNotificationsResponse.self)
        return response.data
    }

    private func notificationIDs(
        sourceType: String,
        targetID: String,
        token: String
    ) throws -> Set<String> {
        Set(try fetchSmokeNotifications(token: token).filter {
            $0.sourceType.uppercased() == sourceType &&
                $0.target?.id == targetID
        }.map(\.notificationId))
    }

    private func waitForSmokeNotification(
        sourceType: String,
        targetID: String,
        excluding: Set<String>,
        token: String,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SmokeNotificationsResponse.SmokeNotification {
        let deadline = Date().addingTimeInterval(timeout)
        var last: [SmokeNotificationsResponse.SmokeNotification] = []
        var lastError: Error?
        while Date() < deadline {
            do {
                last = try fetchSmokeNotifications(token: token)
                if let match = last.first(where: {
                    !excluding.contains($0.notificationId) &&
                        $0.sourceType.uppercased() == sourceType &&
                        $0.target?.id == targetID &&
                        $0.target?.type.uppercased() == (
                            sourceType == "FOLLOW" ? "ACTOR" : "ASSET"
                        ) && !$0.isRead
                }) {
                    return match
                }
            } catch {
                lastError = error
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        XCTFail(
            "Timed out waiting for \(sourceType) notification target \(targetID); last=\(last.map(\.notificationId)), error=\(String(describing: lastError))",
            file: file,
            line: line
        )
        throw lastError ?? NSError(
            domain: "ArcNoteUITests",
            code: 31,
            userInfo: [NSLocalizedDescriptionKey: "Missing projected notification"]
        )
    }

    private func createSmokeComment(
        cardID: String,
        body: String,
        token: String
    ) throws {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(
            string: "\(baseURL)/api/cards/\(cardID)/comments"
        ) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["body": body]
        )
        _ = try sendRawRequest(request)
    }

    private func openNotificationInbox(notificationID: String) {
        launchAuthenticatedApp()
        waitFor("tab.flow", timeout: 20)
        tap("side-menu.open")
        tap("side-menu.notification")
        waitFor("notification.row.\(notificationID)", timeout: 30)
    }


    private func fetchSparkActivity(
        activityID: String,
        token: String
    ) throws -> SmokeSparkActivityResponse.SmokeSparkActivity {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard let url = URL(
            string: "\(baseURL)/api/v1/spark/activities/\(activityID)/results"
        ) else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Go Spark activity URL"]
            )
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokeSparkActivityResponse.self
        ).data
    }

    private func fetchSparkHistoryTotal(
        cardID: String,
        token: String
    ) throws -> Int {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"]
            ?? "http://127.0.0.1:8080"
        guard var components = URLComponents(
            string: "\(baseURL)/api/v1/assets/\(cardID)/spark/history"
        ) else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 14,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Spark history URL"]
            )
        }
        components.queryItems = [
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "100")
        ]
        guard let url = components.url else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 15,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Spark history query"]
            )
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokeSparkHistoryResponse.self
        ).data.total
    }

    private func deleteFavorite(id: String, token: String) {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"]
            ?? "http://127.0.0.1:8080"
        guard let url = URL(
            string: "\(baseURL)/api/v1/actors/me/favorites/\(id)"
        ) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? sendRawRequest(request)
    }

    private func fetchDiscoveryRoot(
        assetID: String,
        token: String
    ) throws -> String {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"]
            ?? "http://127.0.0.1:8080"
        guard let url = URL(
            string: "\(baseURL)/api/v1/actors/me/favorites/\(assetID)/discovery-path"
        ) else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 13,
                userInfo: [NSLocalizedDescriptionKey: "Invalid discovery path URL"]
            )
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokeDiscoveryPathResponse.self
        ).data.rootActivityID
    }

    private func waitForDiscoveryRoot(
        assetID: String,
        token: String,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var lastRoot = ""
        var lastError: Error?
        while Date() < deadline {
            do {
                lastRoot = try fetchDiscoveryRoot(assetID: assetID, token: token)
                if !lastRoot.isEmpty { return lastRoot }
            } catch {
                lastError = error
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        if let lastError {
            XCTFail(
                "Timed out waiting for discovery path; last error: \(lastError)",
                file: file,
                line: line
            )
        } else {
            XCTFail("Timed out waiting for discovery path", file: file, line: line)
        }
        return lastRoot
    }

    private func waitForNotificationReadState(notificationId: String, token: String, expected: Bool, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var lastValue: Bool?
        var lastError: Error?

        while Date() < deadline {
            do {
                lastValue = try fetchNotificationReadState(notificationId: notificationId, token: token)
                if lastValue == expected {
                    return
                }
            } catch {
                lastError = error
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }

        if let lastError {
            XCTFail("Timed out waiting for notification read state \(expected); last error: \(lastError)", file: file, line: line)
        } else {
            XCTFail("Timed out waiting for notification read state \(expected); last value: \(String(describing: lastValue))", file: file, line: line)
        }
    }

    private func waitForMissing(_ identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.descendants(matching: .any)[identifier]
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Identifier still exists: \(identifier)", file: file, line: line)
    }

    private func fetchLocalSmokeSession() -> SmokeSession? {
        if let cachedSession = Self.cachedSmokeSession {
            return cachedSession
        }

        let result = fetchFreshSmokeSession() ?? fetchLocalPhoneSmokeSession()
        Self.cachedSmokeSession = result
        return result
    }

    private func fetchFreshSmokeSession() -> SmokeSession? {
        let environment = ProcessInfo.processInfo.environment
        let email = environment["CHORAI_UI_TEST_EMAIL"] ?? "ios-smoke-a-20260619@example.com"
        let password = environment["CHORAI_UI_TEST_PASSWORD"] ?? "Password123"
        return fetchSmokeSession(email: email, password: password)
    }

    private func fetchSmokeSession(
        email: String,
        password: String
    ) -> SmokeSession? {
        let environment = ProcessInfo.processInfo.environment
        let baseURL = environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/auth/login") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])

        let semaphore = DispatchSemaphore(value: 0)
        var result: SmokeSession?

        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let response = try? JSONDecoder().decode(LoginResponse.self, from: data) else {
                return
            }

            result = SmokeSession(
                token: response.data.token,
                actorId: response.data.user.id,
                email: response.data.user.email,
                username: response.data.user.username
            )
        }.resume()

        _ = semaphore.wait(timeout: .now() + 10)
        return result
    }

    private func fetchLocalPhoneSmokeSession(
        phone phoneOverride: String? = nil
    ) -> SmokeSession? {
        let environment = ProcessInfo.processInfo.environment
        let baseURL = environment["CHORAI_API_BASE_URL"]
            ?? "http://127.0.0.1:8080"
        let phone = phoneOverride
            ?? environment["CHORAI_UI_TEST_PHONE"]
            ?? "+8613907111234"
        let password = environment["CHORAI_UI_TEST_PASSWORD"]
            ?? "Password123"

        func request(path: String, body: [String: String]) -> SmokeSession? {
            guard let url = URL(string: "\(baseURL)\(path)") else {
                return nil
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            let semaphore = DispatchSemaphore(value: 0)
            var result: SmokeSession?
            URLSession.shared.dataTask(with: request) { data, _, _ in
                defer { semaphore.signal() }
                guard let data,
                      let response = try? JSONDecoder().decode(
                          LoginResponse.self,
                          from: data
                      ) else {
                    return
                }
                result = SmokeSession(
                    token: response.data.token,
                    actorId: response.data.user.id,
                    email: response.data.user.email,
                    username: response.data.user.username
                )
            }.resume()
            _ = semaphore.wait(timeout: .now() + 10)
            return result
        }

        if let session = request(
            path: "/api/auth/login",
            body: [
                "credential_type": "phone",
                "phone": phone,
                "password": password
            ]
        ) {
            return session
        }

        return request(
            path: "/api/auth/phone/register",
            body: [
                "phone": phone,
                "password": password,
                "invite_code": environment["CHORAI_UI_TEST_INVITE_CODE"]
                    ?? "LOCAL-OK"
            ]
        )
    }

    private func sendRequest<T: Decodable>(_ request: URLRequest, responseType: T.Type) throws -> T {
        let data = try sendRawRequest(request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sendRawRequest(_ request: URLRequest, timeout: TimeInterval = 15) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var urlResponse: URLResponse?
        var responseError: Error?

        URLSession.shared.dataTask(with: request) { data, response, error in
            responseData = data
            urlResponse = response
            responseError = error
            semaphore.signal()
        }.resume()

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw NSError(domain: "ArcNoteUITests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for Go API response"])
        }

        if let responseError {
            throw responseError
        }

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw NSError(domain: "ArcNoteUITests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing HTTP response"])
        }

        let data = responseData ?? Data()
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ArcNoteUITests",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Go API returned \(httpResponse.statusCode): \(body)"]
            )
        }

        return data
    }

}
