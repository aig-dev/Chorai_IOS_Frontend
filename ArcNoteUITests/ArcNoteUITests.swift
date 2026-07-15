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

    func testCardEditorShellEmptyHierarchyIsHeaderlessAndAccessible() {
        launchCardEditorFixture(mode: "empty")

        let content = waitFor("cardEditorContent")
        let tags = waitFor("cardEditorTagsRow")
        let links = waitFor("cardEditorLinksRow")
        XCTAssertLessThan(content.frame.maxY, tags.frame.minY)
        XCTAssertLessThan(tags.frame.maxY, links.frame.minY)
        XCTAssertFalse(app.descendants(matching: .any)["cardEditorHeader"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["cardEditorTitleField"].exists)

        for identifier in [
            "cardEditorFloatingBack",
            "cardEditorMoreButton",
            "cardEditorAddTag",
            "cardEditorAddLink",
        ] {
            assertPrimaryControl(waitFor(identifier), identifier: identifier)
        }
        captureVisual("card-editor-empty")
    }

    func testCardEditorShellPopulatedRowsKeepActionsTrailing() {
        launchCardEditorFixture(mode: "populated")

        let lastTag = waitFor("cardEditorTag.research")
        let addTag = waitFor("cardEditorAddTag")
        assertReadingOrder(lastTag, before: addTag)

        let firstLink = waitFor("cardEditorLink.ast_fixture_a")
        let secondLink = waitFor("cardEditorLink.ast_fixture_b")
        let overflow = waitFor("cardEditorLinkOverflow")
        let addLink = waitFor("cardEditorAddLink")
        assertReadingOrder(firstLink, before: secondLink)
        assertReadingOrder(secondLink, before: overflow)
        assertReadingOrder(overflow, before: addLink)
        XCTAssertEqual(overflow.label, "+3")
        XCTAssertFalse(
            app.descendants(matching: .any)["cardEditorLink.ast_fixture_c"]
                .exists
        )
        assertPrimaryControl(addTag, identifier: "cardEditorAddTag")
        assertPrimaryControl(addLink, identifier: "cardEditorAddLink")
        captureVisual("card-editor-populated")
    }

    func testCardEditorShellBackgroundStopsBeforeMetadata() {
        launchCardEditorFixture(mode: "background")

        let content = waitFor("cardEditorContent")
        let tags = waitFor("cardEditorTagsRow")
        XCTAssertLessThan(content.frame.maxY, tags.frame.minY)
        for decorativeIdentifier in [
            "cardEditorBodyBackground",
            "cardEditorPendingBackgroundImage",
            "cardEditorBackgroundImage",
        ] {
            XCTAssertFalse(
                app.descendants(matching: .any)[decorativeIdentifier].exists,
                "Decorative background layers must stay out of accessibility"
            )
        }
        captureVisual("card-editor-background")
    }

    func testCardEditorBridgeFailureFallbackRetriesIntoFreshWebView() {
        app.launchArguments.append("--ui-test-card-editor-shell")
        app.launchEnvironment["CHORAI_CARD_EDITOR_FIXTURE_MODE"] =
            "bridge-failure"
        app.launch()

        waitFor("screen.card-editor-shell")
        XCTAssertTrue(waitFor("cardEditorBridgeFailureFallback").isHittable)
        XCTAssertTrue(waitFor("cardEditorBridgeFailureNotice").isHittable)
        XCTAssertFalse(
            app.descendants(matching: .any)["cardEditorBodyWebView"].exists
        )
        let save = waitForButton("cardEditorSave")
        XCTAssertFalse(save.isEnabled)
        let retry = waitForButton("cardEditorBridgeRetry")
        assertPrimaryControl(retry, identifier: "cardEditorBridgeRetry")
        captureVisual("card-editor-bridge-failure")

        retry.tap()
        XCTAssertTrue(
            waitFor("cardEditorBodyWebView", timeout: 20).isHittable,
            "Retry must mount a fresh body WebView"
        )
        waitForEnabled(save, timeout: 20)
        XCTAssertFalse(
            app.descendants(matching: .any)["cardEditorBridgeFailureNotice"]
                .exists
        )
        captureVisual("card-editor-bridge-recovered")
    }

    func testCardEditorShellCompatibilityBlockIsReadOnlyAndCannotSave() {
        launchCardEditorFixture(mode: "blocked")

        XCTAssertTrue(waitFor("cardEditorCompatibilityNotice").isHittable)
        XCTAssertEqual(
            waitFor("cardEditorReadOnlyFallback").label,
            "A note from a newer editor"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["cardEditorBodyWebView"].exists
        )
        let save = waitForButton("cardEditorSave")
        XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(waitForButton("cardEditorAddTag").isEnabled)
        XCTAssertFalse(waitForButton("cardEditorTag.archive").isEnabled)
        XCTAssertFalse(waitForButton("cardEditorAddLink").isEnabled)
        XCTAssertFalse(app.buttons["cardEditorFormatBold"].exists)
        XCTAssertTrue(waitForButton("cardEditorFloatingBack").isEnabled)

        let preservedLink = waitForButton("cardEditorLink.ast_blocked")
        XCTAssertTrue(preservedLink.isEnabled)
        preservedLink.tap()
        waitFor("cardEditorLinksSheet")
        XCTAssertTrue(waitFor("cardEditorReadOnlyLink.ast_blocked").exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["cardEditorRemoveLink.ast_blocked"]
                .exists
        )
        app.buttons["Done"].tap()

        waitForButton("cardEditorMoreButton").tap()
        XCTAssertFalse(waitForButton("cardEditorPrivacyButton").isEnabled)
        XCTAssertFalse(waitForButton("cardEditorBackgroundButton").isEnabled)
        captureVisual("card-editor-compatibility-blocked")
    }

    func testCardEditorFormattingBarKeepsDismissFixedAndReflectsSelection() {
        launchCardEditorFixture(mode: "keyboard")

        let body = waitFor("cardEditorBodyWebView")
        body.coordinate(
            withNormalizedOffset: CGVector(dx: 0.25, dy: 0.04)
        ).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        waitFor("cardEditorFormattingBar")
        let dismiss = waitForButton("cardEditorKeyboardDismiss")
        let paragraph = waitForButton("cardEditorFormatParagraph")
        let heading2 = waitForButton("cardEditorFormatHeading2")
        let bold = waitForButton("cardEditorFormatBold")
        XCTAssertLessThan(dismiss.frame.maxX, paragraph.frame.minX)
        XCTAssertEqual(heading2.value as? String, "selected")
        XCTAssertEqual(bold.value as? String, "selected")
        for (identifier, element) in [
            ("cardEditorKeyboardDismiss", dismiss),
            ("cardEditorFormatParagraph", paragraph),
            ("cardEditorFormatHeading2", heading2),
            ("cardEditorFormatBold", bold),
        ] {
            assertPrimaryControl(element, identifier: identifier)
        }
        captureVisual("card-editor-formatting")

        dismiss.tap()
        waitForMissing("cardEditorFormattingBar")
        waitForElementToDisappear(app.keyboards.firstMatch)
    }

    func testCardEditorFormattingBarFollowsInteractiveScrollDismissal() {
        launchCardEditorFixture(mode: "keyboard")

        waitFor("cardEditorBodyWebView")
        let visibleParagraph = app.staticTexts["Scroll fixture paragraph 0"]
        XCTAssertTrue(visibleParagraph.waitForExistence(timeout: 10))
        XCTAssertTrue(visibleParagraph.isHittable)
        visibleParagraph.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        waitFor("cardEditorFormattingBar")

        let scroll = app.scrollViews.firstMatch
        let start = scroll.coordinate(
            withNormalizedOffset: CGVector(dx: 0.55, dy: 0.72)
        )
        let end = scroll.coordinate(
            withNormalizedOffset: CGVector(dx: 0.55, dy: 0.28)
        )
        start.press(forDuration: 0.05, thenDragTo: end)
        waitForMissing("cardEditorFormattingBar")
        waitForElementToDisappear(app.keyboards.firstMatch)

        XCTAssertTrue(visibleParagraph.isHittable)
        visibleParagraph.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        waitFor("cardEditorFormattingBar")
    }

    func testNativeMetadataInputsDoNotShowBodyFormattingBar() {
        launchCardEditorFixture(mode: "empty")

        waitForButton("cardEditorAddTag").tap()
        let tagInput = waitFor("cardEditorNativeTagInput")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.descendants(matching: .any)["cardEditorFormattingBar"].exists
        )
        tagInput.typeText("native tag")
        app.buttons["Done"].tap()
        waitForMissing("cardEditorNativeTagInput")

        waitForButton("cardEditorAddLink").tap()
        let linkInput = waitFor("cardEditorNativeLinkInput")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.descendants(matching: .any)["cardEditorFormattingBar"].exists
        )
        linkInput.typeText("linked note")
        app.buttons["Done"].tap()
        waitForMissing("cardEditorNativeLinkInput")
    }

    func testCardEditorLinkSheetOnlyDeletesRemovableRelations() {
        launchCardEditorFixture(mode: "populated")

        waitFor("cardEditorLinkOverflow").tap()
        waitFor("cardEditorLinksSheet")
        XCTAssertTrue(
            waitFor("cardEditorRemoveLink.ast_fixture_a").isEnabled
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "cardEditorRemoveLink.ast_fixture_c"
            ].exists
        )
        XCTAssertTrue(
            waitFor("cardEditorNonRemovableLink.ast_fixture_c").exists
        )
    }

    func testCardEditorMoreMenuKeepsBackgroundEntryPointStable() {
        launchCardEditorFixture(mode: "empty")

        waitForButton("cardEditorMoreButton").tap()
        XCTAssertTrue(waitForButton("cardEditorBackgroundButton").isEnabled)
        let cardActions = waitForButton("cardEditorCardActionsButton")
        XCTAssertTrue(cardActions.isEnabled)
        cardActions.tap()
        waitFor("cardEditorCardActionsRequested")
    }

    func testCardEditorLongTagStaysInsideReadableWidth() {
        app.launchArguments += [
            "--ui-test-card-editor-shell",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launchEnvironment["CHORAI_CARD_EDITOR_FIXTURE_MODE"] = "long-tag"
        app.launch()

        waitFor("screen.card-editor-shell")
        let tag = waitFor("cardEditorTag.this-is-an-intentionally-long-tag-that-must-compress")
        let row = waitFor("cardEditorTagsRow")
        XCTAssertGreaterThanOrEqual(tag.frame.minX, row.frame.minX - 1)
        XCTAssertLessThanOrEqual(tag.frame.maxX, row.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(tag.frame.height, 44)
        assertReadingOrder(tag, before: waitFor("cardEditorAddTag"))
    }

    func testCardEditorBootstrapReachesReadyForMinimalDocument() {
        launchCardEditorFixture(mode: "empty")

        let body = waitFor("cardEditorBodyWebView")
        XCTAssertTrue(waitForButton("cardEditorSave").isEnabled)
        body.coordinate(
            withNormalizedOffset: CGVector(dx: 0.25, dy: 0.04)
        ).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        app.typeText("x")
    }

    func testCardEditorShellSupportsAccessibilityTextSize() {
        let bodyText =
            "A lightweight note begins with its body, without a title row."
        launchCardEditorFixture(mode: "populated")
        let normalBody = app.staticTexts[bodyText]
        XCTAssertTrue(normalBody.waitForExistence(timeout: 10))
        let normalBodyHeight = normalBody.frame.height

        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "--ui-test-card-editor-shell",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launchEnvironment["CHORAI_CARD_EDITOR_FIXTURE_MODE"] = "populated"
        app.launch()

        waitFor("screen.card-editor-shell")
        let accessibilityBody = app.staticTexts[bodyText]
        XCTAssertTrue(accessibilityBody.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(
            accessibilityBody.frame.height,
            normalBodyHeight * 1.2,
            "The Web-backed body must visibly scale with Dynamic Type"
        )

        for identifier in ["cardEditorFloatingBack", "cardEditorMoreButton"] {
            let control = waitFor(identifier)
            XCTAssertEqual(control.frame.width, 44, accuracy: 1.5)
            XCTAssertEqual(control.frame.height, 44, accuracy: 1.5)
        }
        let addTag = waitFor("cardEditorAddTag")
        let addLink = waitFor("cardEditorAddLink")
        for (identifier, control) in [
            ("cardEditorAddTag", addTag),
            ("cardEditorAddLink", addLink),
        ] {
            XCTAssertGreaterThanOrEqual(
                control.frame.width,
                44,
                "\(identifier) must remain at least 44 points wide"
            )
            XCTAssertGreaterThanOrEqual(
                control.frame.height,
                44,
                "\(identifier) must remain at least 44 points tall"
            )
        }
        XCTAssertFalse(app.descendants(matching: .any)["cardEditorHeader"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["cardEditorTitleField"].exists
        )
        captureVisual("card-editor-accessibility-text")
    }

    func testSignInOnlyShowsSupportedAuthenticationActions() {
        app.launchArguments.append("--ui-test-sign-in")
        app.launch()

        waitFor("screen.sign-in")
        waitFor("signin.email")
        waitFor("signin.password")
        waitFor("signin.submit")
        XCTAssertFalse(
            app.descendants(matching: .any)["signin.forgot-password"].exists
        )
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
            "chora.contract.scope.empty-preflight": "acquire:a,coordinate:a,release:a,no-upload|empty:a.md",
            "chora.contract.scope.metadata-failure": "acquire:a,coordinate:a,release:a,no-upload|metadata-unavailable",
            "chora.contract.transport.cancel-immediate": "true",
            "chora.contract.transport.pending-before-terminal": "true",
            "chora.contract.transport.terminal-order": "cancel,pending,terminal,release:a,completion",
            "chora.contract.picker.content-types": "net.daringfireball.markdown,public.html",
            "chora.contract.picker.multiple-selection": "true",
            "chora.contract.picker.descriptors": "notes.md:markdown:4,page.htm:html:5,empty.md:markdown:0,unsupported.txt:unsupported:3",
            "chora.contract.picker.source-key": "same:true,different:true,opaque:true",
            "chora.contract.oauth.success": "success",
            "chora.contract.oauth.cancelled": "cancelled",
            "chora.contract.oauth.failed": "failed",
            "chora.contract.oauth.duplicate-result": "failed",
            "chora.contract.oauth.lifecycle-owner": "retained",
            "chora.contract.oauth.request-id-replay": "ignored"
        ]

        for (identifier, expectedValue) in expectedValues {
            XCTAssertEqual(waitFor(identifier).label, expectedValue)
        }
        XCTAssertFalse(app.descendants(matching: .any)["chora.contract.error"].exists)
    }

    func testInvitationCreditContractFixtureRoute() throws {
        app.launchArguments.append("--ui-test-invitation-credit-contract")
        app.launch()

        let fixtureError = app.descendants(matching: .any)[
            "invitation.contract.error"
        ]
        if fixtureError.waitForExistence(timeout: 2) {
            XCTFail("Invitation contract fixture failed: \(fixtureError.label)")
        }

        let expectedValues = [
            "invitation.contract.referral":
                "MixedCase09,https://chorai.test/r/MixedCase09,3,nil",
            "invitation.contract.balance": "credit:12,premium_credit:4",
            "invitation.contract.record": "inv_1,registered,1710000000",
            "invitation.contract.reward": "rew_1,credit,5,issued,true,1710000000",
            "invitation.contract.ledger":
                "log_1,future_direction,5,credit,FUTURE_ACTION,7,future_status,nil,false",
            "invitation.contract.logging": "request-and-response-redacted",
            "invitation.contract.empty-pages": "invitations:0,rewards:0",
            "invitation.contract.auth":
                "validate:public|referral,redeem,records,rewards,balance,ledger:authenticated",
            "invitation.contract.routes":
                "GET /api/invitations/referral|POST /api/invitations/validate|POST /api/invitations/redeem|GET /api/invitations/records page,limit|GET /api/invitations/rewards page,limit|GET /api/v1/credits/balance|GET /api/v1/credits/ledger cursor,limit|presentsError:false"
        ]

        for (identifier, expectedValue) in expectedValues {
            XCTAssertEqual(waitFor(identifier).label, expectedValue)
        }
        XCTAssertFalse(fixtureError.exists)
    }

    func testDiscoveryPathContractFixtureRoute() throws {
        app.launchArguments.append("--ui-test-discovery-path-contract")
        app.launch()

        XCTAssertEqual(
            waitFor("discovery.contract.summary").label,
            "ast_collected,actv_root,3"
        )
        XCTAssertEqual(
            waitFor("discovery.contract.nodes").label,
            "ast_origin:ver_origin:actv_root:0,ast_direct:ver_direct:actv_child:1,ast_collected:ver_collected:actv_child:2"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["discovery.contract.error"]
                .exists
        )
    }

    func testDiscoveryPathFixtureShowsCollectedToOriginOrder() throws {
        launchDiscoveryPathFixture(mode: "loaded")

        waitFor("screen.discovery-path")
        waitFor("discovery-path.collected")
        waitFor("discovery-path.ancestor.ast_direct")
        waitFor("discovery-path.ancestor.ast_origin")
        XCTAssertEqual(
            waitFor("discovery-path.order").label,
            "ast_direct,ast_origin"
        )
        XCTAssertFalse(app.staticTexts["Credits"].exists)
        XCTAssertFalse(app.staticTexts["Results"].exists)
    }

    func testDiscoveryPathFixtureShowsNoProvenanceState() throws {
        launchDiscoveryPathFixture(mode: "empty")

        waitFor("screen.discovery-path")
        waitFor("discovery-path.collected")
        waitFor("discovery-path.empty")
        XCTAssertFalse(
            app.descendants(matching: .any)["discovery-path.retry"].exists
        )
    }

    func testDiscoveryPathFixtureRetriesTransportFailure() throws {
        launchDiscoveryPathFixture(mode: "failure")

        waitFor("screen.discovery-path")
        waitFor("discovery-path.error")
        tap("discovery-path.retry")
        waitFor("discovery-path.ancestor.ast_direct")
        XCTAssertFalse(
            app.descendants(matching: .any)["discovery-path.error"].exists
        )
    }

    func testInvitationCreditsLoadedFixture() throws {
        launchInvitationCreditFixture(mode: "success")

        waitFor("screen.invitation-credits")
        XCTAssertEqual(
            waitFor("invitation-credits.balance.credit").value as? String,
            "12"
        )
        XCTAssertEqual(
            waitFor("invitation-credits.balance.premium-credit").value as? String,
            "4"
        )
        waitFor("invitation-credits.referral.share")
        tap("invitation-credits.referral.copy")
        XCTAssertEqual(
            waitFor("invitation-credits.referral.copy-status").label,
            "Copied"
        )
        waitFor("invitation-credits.redeem.disclosure")
        waitFor("invitation-credits.history.link")
        waitFor("invitation-credits.rewards.link")
        waitFor("invitation-credits.ledger.link")
    }

    func testInvitationCreditsPartialFailureFixture() throws {
        launchInvitationCreditFixture(mode: "referral-error")
        XCTAssertEqual(
            waitFor("invitation-credits.balance.credit").value as? String,
            "12"
        )
        XCTAssertEqual(
            waitFor("invitation-credits.balance.premium-credit").value as? String,
            "4"
        )
        waitFor("invitation-credits.referral.error")
        waitFor("invitation-credits.referral.retry")

        launchInvitationCreditFixture(mode: "balance-error")
        waitFor("invitation-credits.referral.code")
        waitFor("invitation-credits.referral.share")
        waitFor("invitation-credits.balance.error")
        waitFor("invitation-credits.balance.retry")
    }

    func testInvitationCreditDetailPaginationFixtures() throws {
        launchInvitationCreditFixture(mode: "history-pagination")
        waitFor("screen.invitation-history")
        waitFor("invitation-history.row.inv_1")
        tap("invitation-history.load-more")
        waitFor("invitation-history.row.inv_2")

        launchInvitationCreditFixture(mode: "reward-pagination")
        waitFor("screen.invitation-rewards")
        XCTAssertTrue(
            waitFor("invitation-rewards.row.rew_1").label
                .contains("Milestone bonus")
        )
        tap("invitation-rewards.load-more")
        waitFor("invitation-rewards.row.rew_2")

        launchInvitationCreditFixture(mode: "ledger-pagination")
        waitFor("screen.credit-ledger")
        XCTAssertTrue(
            waitFor("credit-ledger.row.log_1").label.contains("Future action")
        )
        tap("credit-ledger.load-more")
        waitFor("credit-ledger.row.log_2")
    }

    func testInvitationCreditsRecoveryFixtures() throws {
        launchInvitationCreditFixture(mode: "pending-redemption")
        waitFor("invitation-credits.redeem.pending")
        if !app.descendants(matching: .any)[
            "invitation-credits.redeem.code"
        ].exists {
            tap("invitation-credits.redeem.disclosure")
        }
        XCTAssertEqual(
            waitFor("invitation-credits.redeem.code").value as? String,
            "MixedCase09"
        )

        launchInvitationCreditFixture(mode: "redeem-failure")
        submitInvitationFixtureCode("MixedCase09")
        waitFor("invitation-credits.redeem.error")
        waitFor("invitation-credits.redeem.pending")
        waitFor("invitation-credits.redeem.retry")
        waitFor("invitation-credits.redeem.discard")

        launchInvitationCreditFixture(mode: "redeem-success")
        submitInvitationFixtureCode("MixedCase09")
        waitFor("invitation-credits.redeem.success")
    }

    func testInvitationCreditsLoadingAndEmptyFixtures() throws {
        launchInvitationCreditFixture(mode: "loading")
        waitFor("invitation-credits.balance.loading")
        waitFor("invitation-credits.referral.loading")

        launchInvitationCreditFixture(mode: "history-empty")
        waitFor("invitation-history.empty")
        launchInvitationCreditFixture(mode: "reward-empty")
        waitFor("invitation-rewards.empty")
        launchInvitationCreditFixture(mode: "ledger-empty")
        waitFor("credit-ledger.empty")
    }

    func testSignupInvitationBlankCode() throws {
        launchSignupInvitationFixture(mode: "blank")
        tapSignupFixtureAction("signup.create-account")
        waitForLabel(
            "signup.fixture.trace",
            expected: "register,complete"
        )
        XCTAssertEqual(waitFor("signup.fixture.registrar-count").label, "1")
    }

    func testSignupInvitationInvalidCode() throws {
        launchSignupInvitationFixture(mode: "invalid")
        tapSignupFixtureAction("signup.create-account")
        waitForLabel(
            "signup.fixture.trace",
            expected: "validate,invalid"
        )
        waitFor("signup.invitation.error")
        XCTAssertEqual(waitFor("signup.fixture.registrar-count").label, "0")
    }

    func testSignupInvitationPartialSuccessAndRetry() throws {
        launchSignupInvitationFixture(mode: "redeem-failure")
        tapSignupFixtureAction("signup.create-account")
        waitForLabel(
            "signup.fixture.trace",
            expected:
                "validate,register,session-established,redeem,persist-pending"
        )
        XCTAssertEqual(waitFor("signup.fixture.normalized-code").label, "MixedCase09")
        XCTAssertEqual(waitFor("signup.fixture.registrar-count").label, "1")
        waitFor("signup.invitation.partial")

        tapSignupFixtureAction("signup.invitation.retry")
        waitForLabel(
            "signup.fixture.recovery-trace",
            expected: "redeem,complete"
        )
        XCTAssertEqual(waitFor("signup.fixture.registrar-count").label, "1")
    }

    func testSignupInvitationValidAndTransportFixtures() throws {
        launchSignupInvitationFixture(mode: "valid")
        tapSignupFixtureAction("signup.create-account")
        waitForLabel(
            "signup.fixture.trace",
            expected:
                "validate,register,session-established,redeem,complete"
        )
        XCTAssertEqual(waitFor("signup.fixture.normalized-code").label, "MixedCase09")

        launchSignupInvitationFixture(mode: "validation-transport")
        tapSignupFixtureAction("signup.create-account")
        waitForLabel(
            "signup.fixture.trace",
            expected: "validate,retry-or-remove"
        )
        waitFor("signup.invitation.retry-validation")
        waitFor("signup.invitation.remove-code")
        XCTAssertEqual(waitFor("signup.fixture.registrar-count").label, "0")
    }

    func testSignupInvitationContinuePartialFixture() throws {
        launchSignupInvitationFixture(mode: "redeem-failure")
        tapSignupFixtureAction("signup.create-account")
        waitFor("signup.invitation.partial")
        tapSignupFixtureAction("signup.invitation.continue")
        waitForLabel(
            "signup.fixture.recovery-trace",
            expected: "complete-with-pending"
        )
        XCTAssertEqual(waitFor("signup.fixture.registrar-count").label, "1")
    }

    func testSettingsShowsChoraProfileEntry() throws {
        app.launchArguments.append("--ui-test-settings")
        app.launch()

        waitFor("screen.settings.loaded")
        waitFor("settings.choraProfile")
    }

    func testSettingsOnlyShowsConnectedModules() throws {
        app.launchArguments.append("--ui-test-settings")
        app.launch()

        waitFor("screen.settings.loaded")
        XCTAssertTrue(app.staticTexts["Settings"].exists)
        XCTAssertTrue(app.buttons["settings.personal-data"].exists)
        XCTAssertTrue(app.buttons["settings.choraProfile"].exists)
        XCTAssertTrue(app.buttons["settings.invitation-credits"].exists)
        XCTAssertTrue(app.buttons["settings.account-privacy"].exists)

        XCTAssertFalse(app.buttons["search"].exists)
        XCTAssertFalse(app.buttons["settings.row.About Us"].exists)
        XCTAssertFalse(app.buttons["settings.row.Check for Updates"].exists)

        XCTAssertEqual(
            waitFor("settings.footer").label,
            "Your notes stay yours. We never sell your data or run ads."
        )
    }

    func testSettingsShowsSingleInvitationCreditsEntry() throws {
        app.launchArguments.append("--ui-test-settings")
        app.launch()

        waitFor("screen.settings.loaded")
        let rows = app.buttons.matching(
            identifier: "settings.invitation-credits"
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.firstMatch.value as? String, "12 Credits")
        XCTAssertFalse(app.staticTexts["Upgrade"].exists)

        for _ in 0..<3 where !rows.firstMatch.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(rows.firstMatch.isHittable)
        rows.firstMatch.tap()
        waitFor("screen.invitation-credits")
    }

    func testInvitationCreditsDecodeLiveGoResponses() throws {
        let liveGoBaseURL = "http://127.0.0.1:8081"
        guard let session = fetchSmokeSession(
            email: "ios-smoke-a-20260619@example.com",
            password: "Password123",
            baseURL: liveGoBaseURL
        ) else {
            XCTFail("Unable to authenticate against Go on port 8081")
            return
        }
        seedAppSession(session)
        app.launchEnvironment["CHORAI_API_BASE_URL"] = liveGoBaseURL
        launchAuthenticatedApp()

        waitFor("tab.flow", timeout: 30)
        tap("side-menu.open")
        tap("side-menu.settings")
        waitFor("screen.settings.loaded", timeout: 20)

        let settingsRow = waitFor("settings.invitation-credits")
        for _ in 0..<4 where !settingsRow.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(settingsRow.isHittable)
        settingsRow.tap()

        waitFor("screen.invitation-credits", timeout: 20)
        waitFor("invitation-credits.balance.credit", timeout: 20)
        waitFor("invitation-credits.balance.premium-credit", timeout: 20)
        waitFor("invitation-credits.referral.code", timeout: 20)
        XCTAssertFalse(app.descendants(matching: .any)[
            "invitation-credits.balance.error"
        ].exists)
        XCTAssertFalse(app.descendants(matching: .any)[
            "invitation-credits.referral.error"
        ].exists)

        openInvitationCreditDetail(
            link: "invitation-credits.history.link",
            screen: "screen.invitation-history",
            empty: "invitation-history.empty",
            rowPrefix: "invitation-history.row.",
            error: "invitation-history.error"
        )
        openInvitationCreditDetail(
            link: "invitation-credits.rewards.link",
            screen: "screen.invitation-rewards",
            empty: "invitation-rewards.empty",
            rowPrefix: "invitation-rewards.row.",
            error: "invitation-rewards.error"
        )
        openInvitationCreditDetail(
            link: "invitation-credits.ledger.link",
            screen: "screen.credit-ledger",
            empty: "credit-ledger.empty",
            rowPrefix: "credit-ledger.row.",
            error: "credit-ledger.error"
        )
    }

    func testChoraProfileFixtureStates() throws {
        app.launchArguments.append("--ui-test-settings")
        app.launch()

        waitFor("screen.settings.loaded")
        XCTAssertEqual(
            waitFor("settings.profile.autoload").label,
            "disabled"
        )
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2))
        let choraRows = app.buttons.matching(
            identifier: "settings.choraProfile"
        )
        XCTAssertEqual(choraRows.count, 1)
        XCTAssertEqual(choraRows.firstMatch.label, "Chora Profile")
        for _ in 0..<3 where !choraRows.firstMatch.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(choraRows.firstMatch.isHittable)
        choraRows.firstMatch.tap()
        waitFor("screen.choraProfile")

        launchChoraProfileFixture(mode: "loaded")
        waitFor("chora.identity.section")
        waitFor("chora.growth.section")
        XCTAssertEqual(waitFor("chora.growth.stage").label, "Co-Think")
        XCTAssertEqual(
            waitFor("chora.growth.curiosity").value as? String,
            "2 out of 12"
        )
        app.swipeUp(); app.swipeUp()
        waitFor("chora.sources.section")
        let localNotes = waitFor("chora.sources.localNotes")
        XCTAssertTrue(
            (localNotes.value as? String)?.contains("Collapsed") == true
        )
        waitFor("chora.chat.section")
        XCTAssertEqual(
            waitFor("chora.profile.section-order").value as? String,
            "Identity, Growth, Soul Sources, Chat History"
        )
        let clearChat = waitFor("chora.chat.clear")
        for _ in 0..<4 where !clearChat.isHittable { app.swipeUp() }
        XCTAssertTrue(clearChat.isHittable)
        clearChat.tap()
        let clearChatAlert = app.alerts["Clear Chat History?"]
        XCTAssertTrue(clearChatAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(clearChatAlert.buttons["Hide Previous Messages"].exists)
        clearChatAlert.buttons["Cancel"].tap()

        launchChoraProfileFixture(mode: "partial-save")
        replaceShortFixtureText("chora.identity.displayName", with: "Nova")
        replaceShortFixtureText(
            "chora.identity.preferredAddress",
            with: "Captain"
        )
        tap("chora.identity.save")
        waitFor("chora.identity.error.preferredAddress")
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "chora.identity.error.displayName"
            ].exists
        )
        XCTAssertEqual(
            waitFor("chora.identity.displayName").value as? String,
            "Nova"
        )
        XCTAssertEqual(
            waitFor("chora.identity.preferredAddress").value as? String,
            "Captain"
        )
        replaceShortFixtureText(
            "chora.identity.preferredAddress",
            with: "Avery"
        )
        XCTAssertFalse(waitFor("chora.identity.save").isEnabled)

        launchChoraProfileFixture(mode: "saving")
        replaceShortFixtureText("chora.identity.displayName", with: "Nova")
        tap("chora.identity.save")
        let saving = waitFor("chora.identity.save")
        XCTAssertEqual(saving.label, "Saving…")
        XCTAssertFalse(saving.isEnabled)

        launchChoraProfileFixture(mode: "local-import-active")
        app.swipeUp(); app.swipeUp()
        tap("chora.sources.localNotes")
        waitFor("chora.sources.localNotes.active")
        XCTAssertEqual(
            app.buttons.matching(
                identifier: "chora.sources.localNotes.cancel"
            ).count,
            1
        )
        XCTAssertFalse(
            app.buttons["chora.sources.localNotes.start"].exists
        )
        tap("chora.sources.localNotes.cancel")
        XCTAssertTrue(app.alerts["Cancel Import?"].waitForExistence(timeout: 5))
        app.alerts["Cancel Import?"].buttons["Keep Importing"].tap()

        launchChoraProfileFixture(mode: "local-import-done")
        app.swipeUp(); app.swipeUp()
        tap("chora.sources.localNotes")
        waitFor("chora.sources.localNotes.done")
        XCTAssertFalse(app.buttons["chora.sources.localNotes.cancel"].exists)
        let importedFile = waitFor(
            "chora.sources.localNotes.file.source_fixture"
        )
        XCTAssertEqual(importedFile.value as? String, "Imported")
        importedFile.tap()
        XCTAssertEqual(
            waitFor("screen.detail.card-id", timeout: 10).label,
            "ast_fixture"
        )

        launchChoraProfileFixture(mode: "local-import-cancelled")
        app.swipeUp(); app.swipeUp()
        let cancelledSummary = waitFor("chora.sources.localNotes")
        waitFor("chora.sources.localNotes.cancelled")
        XCTAssertTrue(
            (cancelledSummary.value as? String)?.contains("Cancelled") == true
        )
        tap("chora.sources.localNotes")
        XCTAssertFalse(app.buttons["chora.sources.localNotes.cancel"].exists)

        launchChoraProfileFixture(mode: "inline-errors")
        app.swipeUp(); app.swipeUp()
        tap("chora.sources.localNotes")
        waitFor("chora.sources.localNotes.error")
        waitFor("chora.sources.localNotes.inlineError")
        tap("chora.sources.notion")
        waitFor("chora.sources.notion.unavailable")
        waitFor("chora.sources.notion.error")

        launchChoraProfileFixture(mode: "notion-disconnected")
        app.swipeUp(); app.swipeUp()
        tap("chora.sources.notion")
        waitFor("chora.sources.notion.disconnected")
        waitFor("chora.sources.notion.connect")

        launchChoraProfileFixture(mode: "notion-connected")
        app.swipeUp(); app.swipeUp()
        tap("chora.sources.notion")
        waitFor("chora.sources.notion.connected")
        let page = waitFor("chora.sources.notion.page.page_fixture")
        page.tap()
        XCTAssertTrue(page.isSelected)
        waitFor("chora.sources.notion.import")
        tap("chora.sources.notion.disconnect")
        XCTAssertTrue(
            app.alerts["Disconnect Notion?"].waitForExistence(timeout: 5)
        )
        app.alerts["Disconnect Notion?"].buttons["Keep Connected"].tap()

        launchChoraProfileFixture(mode: "notion-import-active")
        app.swipeUp(); app.swipeUp()
        tap("chora.sources.notion")
        tap("chora.sources.notion.page.page_fixture")
        tap("chora.sources.notion.import")
        waitFor("chora.sources.notion.import.running")
        XCTAssertFalse(waitFor("chora.sources.notion.import").isEnabled)

        app.terminate()
        app = XCUIApplication()
        app.launchArguments.append("--ui-test-library")
        app.launch()
        XCTAssertEqual(waitFor("library.fixture.session").label, "isolated")
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2))
        let libraryPlus = waitFor("note.create")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(
                identifier: "note.create"
            ).count,
            1
        )
        XCTAssertTrue(libraryPlus.isHittable)
        libraryPlus.tap()
        waitFor("cardEditorContent")
    }

    func testChoraProfileLoadedFixtureRendersOrderedProductionSections() throws {
        app.launchArguments.append("--ui-test-chora-profile")
        app.launchEnvironment["CHORAI_CHORA_PROFILE_FIXTURE_MODE"] = "loaded"
        app.launch()

        waitFor("screen.choraProfile")
        XCTAssertTrue(app.staticTexts["Chora Profile"].exists)
        XCTAssertTrue(app.buttons["Back"].isHittable)
        let identity = waitFor("chora.identity.section")
        waitFor("chora.identity.avatar")
        waitFor("chora.identity.displayName")
        waitFor("chora.identity.preferredAddress")
        let save = waitFor("chora.identity.save")
        XCTAssertGreaterThanOrEqual(save.frame.height, 44)
        XCTAssertLessThanOrEqual(save.frame.height, 60)

        let growth = waitFor("chora.growth.section")
        XCTAssertEqual(waitFor("chora.growth.stage").label, "Co-Think")
        for dimension in [
            "curiosity", "insight", "creativity", "empathy", "judgment",
            "resonance"
        ] {
            waitFor("chora.growth.\(dimension)")
        }

        app.swipeUp()
        let sources = waitFor("chora.sources.section")
        waitFor("chora.sources.localNotes")
        waitFor("chora.sources.notion")

        app.swipeUp()
        let chat = waitFor("chora.chat.section")
        waitFor("chora.chat.clear")
        XCTAssertTrue(
            app.staticTexts["Previous messages are hidden on this device."]
                .exists
        )
        XCTAssertLessThan(identity.frame.minY, growth.frame.minY)
        XCTAssertLessThan(growth.frame.minY, sources.frame.minY)
        XCTAssertLessThan(sources.frame.minY, chat.frame.minY)

        let notion = waitFor("chora.sources.notion")
        XCTAssertTrue((notion.value as? String)?.contains("Collapsed") == true)
        notion.tap()
        XCTAssertTrue((notion.value as? String)?.contains("Expanded") == true)
    }

    func testChoraLocalNotesPickerAndExactAssetDestination() throws {
        launchChoraProfileFixture(mode: "local-import-done")
        app.swipeUp(); app.swipeUp()
        tap("chora.sources.localNotes")

        waitFor("chora.sources.localNotes.chooseFiles")
        tap("chora.sources.localNotes.file.source_fixture")

        XCTAssertEqual(
            waitFor("screen.detail.card-id", timeout: 10).label,
            "ast_fixture"
        )
    }

    func testChoraDestructiveActionsAndOAuthUseProductionConfirmations() throws {
        launchChoraProfileFixture(mode: "local-import-active")
        app.swipeUp(); app.swipeUp()
        tap("chora.sources.localNotes")
        tap("chora.sources.localNotes.cancel")
        XCTAssertTrue(app.alerts["Cancel Import?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts["Cancel Import?"].buttons["Keep Importing"].exists)
        app.alerts["Cancel Import?"].buttons["Keep Importing"].tap()

        launchChoraProfileFixture(mode: "notion-connected")
        app.swipeUp(); app.swipeUp()
        tap("chora.sources.notion")
        tap("chora.sources.notion.disconnect")
        XCTAssertTrue(app.alerts["Disconnect Notion?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts["Disconnect Notion?"].buttons["Keep Connected"].exists)
        app.alerts["Disconnect Notion?"].buttons["Keep Connected"].tap()

        launchChoraProfileFixture(mode: "notion-disconnected")
        app.swipeUp(); app.swipeUp()
        tap("chora.sources.notion")
        tap("chora.sources.notion.connect")
        waitFor("chora.sources.notion.oauth.cancelled")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testActorScopedChatClearFiltersListAndDetailThenPostCutoffReappears() throws {
        app.launchArguments.append("--ui-test-chat-visibility")
        app.launch()

        tap("chat.fixture.open-list")
        waitFor("chat.conversation.conversation_before")
        tap("chat.conversation.conversation_before")
        waitFor("chat.message.message_before")
        app.buttons["Back"].tap()
        app.buttons["Back"].tap()

        tap("chat.fixture.open-clear")
        tap("chora.chat.clear")
        let alert = app.alerts["Clear Chat History?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Hide Previous Messages"].tap()
        app.buttons["Back"].tap()

        tap("chat.fixture.open-list")
        XCTAssertEqual(
            waitFor("chat.visibility.contract").label,
            "human_a|1|false|0"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "chat.conversation.conversation_before"
            ].exists
        )
        app.buttons["Back"].tap()

        tap("chat.fixture.open-other-list")
        waitFor("chat.conversation.conversation_other_actor")
        app.buttons["Back"].tap()

        tap("chat.fixture.publish-post-cutoff")
        tap("chat.fixture.open-list")
        tap("chat.conversation.conversation_before")
        waitFor("chat.message.message_after")
        XCTAssertFalse(app.descendants(matching: .any)["chat.message.message_before"].exists)
    }

    func testChoraProfileFixtureStatesStaySectionLocal() throws {
        launchChoraProfileFixture(mode: "loading")
        waitFor("chora.identity.loading")

        launchChoraProfileFixture(mode: "growth-error")
        waitFor("chora.growth.unavailable")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        tap("chora.growth.unavailable.retry")
        XCTAssertEqual(waitFor("chora.growth.stage").label, "Co-Think")

        for (mode, identifier) in [
            ("local-import-active", "chora.sources.localNotes.active"),
            ("local-import-done", "chora.sources.localNotes.done"),
            ("local-import-failure", "chora.sources.localNotes.failure"),
            ("notion-disconnected", "chora.sources.notion.disconnected"),
            ("notion-connected", "chora.sources.notion.connected"),
            ("inline-errors", "chora.sources.localNotes.error")
        ] {
            launchChoraProfileFixture(mode: mode)
            app.swipeUp()
            app.swipeUp()
            waitFor(identifier)
            XCTAssertFalse(app.alerts.firstMatch.exists)
        }
    }

    func testChoraProfileLoadedFixtureSupportsAccessibilityText() throws {
        app.launchArguments += [
            "--ui-test-chora-profile",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launchEnvironment["CHORAI_CHORA_PROFILE_FIXTURE_MODE"] = "loaded"
        app.launch()

        waitFor("chora.identity.section")
        let displayName = waitFor("chora.identity.displayName")
        XCTAssertEqual(displayName.label, "Display name")
        XCTAssertTrue(displayName.frame.intersects(app.frame))
        app.swipeUp()
        waitFor("chora.growth.section")
        XCTAssertFalse(waitFor("chora.growth.curiosity").value as? String == "")
        app.swipeUp()
        let local = waitFor("chora.sources.localNotes")
        XCTAssertTrue((local.value as? String)?.contains("Collapsed") == true)
        XCTAssertTrue(local.frame.intersects(app.frame))
        let notion = waitFor("chora.sources.notion")
        XCTAssertTrue((notion.value as? String)?.contains("Collapsed") == true)
        app.swipeUp()
        let clear = waitFor("chora.chat.clear")
        for _ in 0..<4 where !clear.isHittable { app.swipeUp() }
        XCTAssertTrue(clear.isHittable)
        clear.tap()
        let alert = app.alerts["Clear Chat History?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Previous messages will be hidden on this device. They are not deleted from Chorai."].exists)
        XCTAssertTrue(alert.buttons["Hide Previous Messages"].exists)
        XCTAssertTrue(alert.buttons["Cancel"].exists)
    }

    func testChoraProfilePartialSaveKeepsOnlyFailedDraft() throws {
        launchChoraProfileFixture(mode: "partial-save")
        replaceShortFixtureText("chora.identity.displayName", with: "Nova")
        replaceShortFixtureText(
            "chora.identity.preferredAddress",
            with: "Captain"
        )

        tap("chora.identity.save")

        waitFor("chora.identity.error.preferredAddress")
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "chora.identity.error.displayName"
            ].exists
        )
        XCTAssertEqual(
            waitFor("chora.identity.displayName").value as? String,
            "Nova"
        )
        XCTAssertEqual(
            waitFor("chora.identity.preferredAddress").value as? String,
            "Captain"
        )
    }

    func testChoraProfileRecoveryAndCanonicalNotionImportFixtures() throws {
        for (mode, identifiers) in [
            ("notion-connected", ["chora.sources.notion.page.page_fixture"]),
            ("notion-connected-error", ["chora.sources.notion.connected", "chora.sources.notion.error"]),
            ("notion-status-failed", ["chora.sources.notion.unavailable", "chora.sources.notion.retryStatus"]),
            ("local-initial-load-failure", ["chora.sources.localNotes.reload"]),
            ("local-relaunch-ambiguity", ["chora.sources.localNotes.reselect"]),
            ("local-pre-receipt", ["chora.sources.localNotes.submitting"]),
            ("notion-import-active", ["chora.sources.notion.import.receipt", "chora.sources.notion.import.running"]),
            ("notion-import-done", ["chora.sources.notion.import.done", "chora.sources.notion.import.imported", "chora.sources.notion.sync.page_fixture"]),
            ("notion-import-failure", ["chora.sources.notion.import.failed", "chora.sources.notion.import.failure.page_fixture", "chora.sources.notion.sync.page_fixture"])
        ] {
            launchChoraProfileFixture(mode: mode)
            app.swipeUp()
            app.swipeUp()
            let notionOrLocal = mode.hasPrefix("local-")
                ? "chora.sources.localNotes"
                : "chora.sources.notion"
            tap(notionOrLocal)
            if mode.hasPrefix("notion-import-") {
                let page = waitFor("chora.sources.notion.page.page_fixture")
                page.tap()
                XCTAssertTrue(page.isSelected)
                tap("chora.sources.notion.import")
            }
            for identifier in identifiers { waitFor(identifier) }
            if mode == "local-pre-receipt" {
                XCTAssertFalse(app.buttons["chora.sources.localNotes.cancel"].exists)
            }
        }
    }

    func testChoraProfileCanonicalUnknownAndCancellingStates() throws {
        launchChoraProfileFixture(mode: "local-cancelling")
        app.swipeUp(); app.swipeUp()
        tap("chora.sources.localNotes")
        tap("chora.sources.localNotes.cancel")
        app.alerts["Cancel Import?"].buttons["Cancel Import"].tap()
        waitFor("chora.sources.localNotes.cancelling")
        XCTAssertFalse(app.buttons["chora.sources.localNotes.cancel"].exists)

        launchChoraProfileFixture(mode: "notion-connecting")
        app.swipeUp(); app.swipeUp()
        tap("chora.sources.notion")
        waitFor("chora.sources.notion.connecting")
        XCTAssertFalse(app.buttons["chora.sources.notion.connect"].exists)

        launchChoraProfileFixture(mode: "notion-unknown")
        app.swipeUp(); app.swipeUp()
        let notion = waitFor("chora.sources.notion")
        XCTAssertTrue((notion.value as? String)?.contains("Unavailable") == true)
        XCTAssertFalse((notion.value as? String)?.contains("future_connection") == true)
        notion.tap()
        waitFor("chora.sources.notion.retryStatus")
        XCTAssertFalse(app.buttons["chora.sources.notion.connect"].exists)

        launchChoraProfileFixture(mode: "notion-unknown-import")
        app.swipeUp(); app.swipeUp()
        tap("chora.sources.notion")
        let page = waitFor("chora.sources.notion.page.page_fixture")
        page.tap()
        tap("chora.sources.notion.import")
        XCTAssertEqual(waitFor("chora.sources.notion.import.unknown").label, "Unknown")
        XCTAssertEqual(waitFor("chora.sources.notion.sync.page_fixture").value as? String, "Unknown")
    }

    func testLocalNotesUnknownStatesRenderNormalizedLabels() throws {
        launchChoraProfileFixture(mode: "local-unknown")
        app.swipeUp(); app.swipeUp()
        let local = waitFor("chora.sources.localNotes")
        XCTAssertTrue((local.value as? String)?.contains("Unavailable") == true)
        XCTAssertFalse((local.value as? String)?.contains("Importing") == true)
        XCTAssertFalse((local.value as? String)?.contains("future_import_state") == true)
        local.tap()
        waitFor("chora.sources.localNotes.unknown")
        let file = waitFor("chora.sources.localNotes.file.source_fixture")
        XCTAssertEqual(file.value as? String, "Unknown")
        XCTAssertFalse(file.label.contains("future_item_state"))
        XCTAssertFalse(file.value as? String == "future_item_state")
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

    func testCanonicalOnboardingLibraryNoteAndFlowResumeGoV1() throws {
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
        waitFor("screen.home.content", timeout: 30)
        waitFor("onboarding.guide", timeout: 15)
        waitFor("note.create.guide-halo", timeout: 15)
        XCTAssertFalse(exists("record.open", timeout: 1))
        captureVisual("onboarding-library-plus-handoff")

        let signal = "iOS onboarding signal \(Int(Date().timeIntervalSince1970))"
        tap("note.create")
        typeInCardEditorBody(signal)
        closeNewNoteEditor()

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

        waitFor("flow.card.\(visibleCardID)").swipeLeft()
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

    func testCancellingOnboardingNoteKeepsLibraryStep() throws {
        let smoke = try requireFreshSmokeSession()
        _ = try restartSmokeOnboarding(token: smoke.token, flowVersion: 1)

        seedAppSession(smoke)
        app.launchEnvironment["CHORAI_UI_TEST_ONBOARDING"] = "1"
        launchAuthenticatedApp()

        waitForSessionPhase("verified", timeout: 30)
        waitForOnboardingAnchor("onboarding.state", value: "elicit_signal")
        waitFor("screen.home.content", timeout: 30)
        tap("note.create")
        waitFor("cardEditorContent", timeout: 15)
        closeNewNoteEditor()

        waitForOnboardingAnchor("onboarding.state", value: "elicit_signal")
        waitFor("screen.home.content", timeout: 15)
        waitFor("note.create.guide-halo", timeout: 15)
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

        var noteCardID: String?
        var savedSparkCardID: String?
        var committedCardID: String?
        defer {
            if let committedCardID {
                deleteSmokeCard(id: committedCardID, token: smoke.token)
            }
            if let savedSparkCardID {
                deleteFavorite(id: savedSparkCardID, token: smoke.token)
            }
            if let noteCardID {
                deleteSmokeCard(id: noteCardID, token: smoke.token)
            }
        }

        waitForSessionPhase("verified", timeout: 30)
        waitForOnboardingAnchor("onboarding.state", value: "elicit_signal")
        waitFor("screen.home.content", timeout: 30)
        waitFor("note.create.guide-halo", timeout: 15)
        let signal = "iOS complete loop \(Int(Date().timeIntervalSince1970))"
        tap("note.create")
        typeInCardEditorBody(signal)
        closeNewNoteEditor()
        noteCardID = waitFor("note.created-card-id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(noteCardID?.isEmpty ?? true)

        waitForOnboardingAnchor(
            "onboarding.state",
            value: "product_explore_card",
            timeout: 30
        )
        let firstFlowCardID = waitFor("flow.visible-card.id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        waitFor("flow.card.\(firstFlowCardID)").swipeLeft()
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

        guard let noteCardID else {
            XCTFail("Library note creation did not expose its canonical card ID")
            return
        }
        waitFor("card.home.\(noteCardID)", timeout: 30)
        tap("home.card.menu.\(noteCardID)")
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
        committedCardID = waitFor("merge.committed-card-id", timeout: 20)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotEqual(committedCardID, noteCardID)

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
        XCTAssertFalse(exists("record.open", timeout: 2))
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

    func testFlowFavoriteIconActivatesWithoutAdvancingCard() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        launchAuthenticatedApp()

        waitFor("tab.flow")
        waitFor("screen.flow.content", timeout: 20)

        let cardID = try waitForUnfavoritedFlowCard(token: session.token)
        defer {
            clearFavoriteLikeState(id: cardID, token: session.token)
        }

        let favorite = waitForButton("flow.favorite.\(cardID)", timeout: 30)
        let like = waitForButton("flow.like.\(cardID)", timeout: 30)
        let comment = waitForButton("flow.comment.\(cardID)", timeout: 30)
        let spark = waitForButton("flow.spark.\(cardID)", timeout: 30)

        XCTAssertFalse(
            app.buttons["flow.skip.\(cardID)"].exists,
            "Flow dismissal should be swipe-only"
        )
        XCTAssertLessThan(favorite.frame.midX, like.frame.midX)
        XCTAssertLessThan(like.frame.midX, comment.frame.midX)
        XCTAssertLessThan(
            spark.frame.midY,
            favorite.frame.midY,
            "Spark should live in the card header above the engagement footer"
        )

        favorite.tap()
        waitForAssetStatus(
            kind: "favorites",
            id: cardID,
            token: session.token,
            expected: true
        )
        waitForAccessibilityValue("flow.favorite.\(cardID)", expected: "true")
        XCTAssertEqual(flowVisibleCardID(), cardID, "Favorite tap must keep the current card visible")
        captureVisual("flow-compact-icon-chrome")

        waitFor("flow.card.\(cardID)").swipeLeft()
        XCTAssertNotEqual(waitForDifferentVisibleFlowCard(from: cardID), cardID)
    }

    func testFlowRightSwipeAdvancesWithoutFavoriteMutationOrUndo() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        launchAuthenticatedApp()

        waitFor("tab.flow")
        waitFor("screen.flow.content", timeout: 20)

        let cardId = flowVisibleCardID()
        let initialFavoriteState = try fetchAssetStatus(
            kind: "favorites",
            id: cardId,
            token: session.token
        )

        waitFor("flow.card.\(cardId)").swipeRight()
        XCTAssertNotEqual(waitForDifferentVisibleFlowCard(from: cardId), cardId)
        XCTAssertEqual(
            try fetchAssetStatus(kind: "favorites", id: cardId, token: session.token),
            initialFavoriteState,
            "Right swipe must not mutate favorite state"
        )
        XCTAssertFalse(app.buttons["flow.undo"].exists, "Flow must not expose Undo")
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
        let favoriteValue = accessibilityValue("flow.favorite.\(cardID)")
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
        XCTAssertEqual(accessibilityValue("flow.favorite.\(cardID)"), favoriteValue)
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
        XCTAssertEqual(accessibilityValue("flow.favorite.\(cardID)"), favoriteValue)
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
        let favoriteValue = accessibilityValue("flow.favorite.\(cardID)")
        let favoriteCount = anchorLabel("flow.favorite.count.\(cardID)")

        try revokeSmokeSession(token: session.token)
        tap("flow.like.\(cardID)")
        waitFor("flow.like.error.\(cardID)", timeout: 30)

        XCTAssertEqual(flowVisibleCardID(), cardID)
        XCTAssertEqual(accessibilityValue("flow.like.\(cardID)"), likeValue)
        XCTAssertEqual(anchorLabel("flow.like.count.\(cardID)"), likeCount)
        XCTAssertEqual(accessibilityValue("flow.favorite.\(cardID)"), favoriteValue)
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

    func testDiscoveryPathRendersLiveGoSparkProvenance() throws {
        let session = try requireSmokeSession()
        openSparkFromDetail(cardID: sparkSeedCardID, session: session)

        let resultID = try waitForUnfavoritedSparkResult(token: session.token)
        defer { deleteFavorite(id: resultID, token: session.token) }

        waitFor("spark.card.\(resultID)").swipeRight()
        waitForAssetStatus(
            kind: "favorites",
            id: resultID,
            token: session.token,
            expected: true
        )
        let discovery = try waitForDiscoveryPath(
            assetID: resultID,
            token: session.token
        )
        var seen = Set<String>()
        let expectedAncestors = discovery.path
            .filter { $0.assetID != resultID }
            .sorted { $0.depth > $1.depth }
            .map(\.assetID)
            .filter { seen.insert($0).inserted }
        XCTAssertFalse(expectedAncestors.isEmpty)

        app.terminate()
        seedAppSession(session)
        app.launchEnvironment["CHORAI_UI_TEST"] = "1"
        app.launchEnvironment["CHORAI_UI_TEST_DISCOVERY_PATH_CARD_ID"] = resultID
        app.launchEnvironment["CHORAI_API_BASE_URL"] =
            ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"]
                ?? "http://127.0.0.1:8080"
        app.launchArguments.append("--ui-test-open-discovery-path")
        app.launch()

        waitFor("screen.discovery-path", timeout: 20)
        waitFor("discovery-path.collected", timeout: 30)
        XCTAssertEqual(
            waitFor("discovery-path.order", timeout: 30).label,
            expectedAncestors.joined(separator: ",")
        )
        for assetID in expectedAncestors {
            waitFor("discovery-path.ancestor.\(assetID)", timeout: 30)
        }
        XCTAssertFalse(
            app.descendants(matching: .any)["discovery-path.error"].exists
        )
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

    func testLibraryPlusCreatesPrivateGoCardAndRefreshesLibrary() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        launchAuthenticatedApp()

        tap("tab.library")
        waitFor("note.create", timeout: 15)
        let content = "Library note \(Int(Date().timeIntervalSince1970))"
        tap("note.create")
        typeInCardEditorBody(content)
        closeNewNoteEditor()

        let cardId = waitFor("note.created-card-id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            deleteSmokeCard(id: cardId, token: session.token)
        }

        let card = try fetchSmokeCard(id: cardId, token: session.token)
        XCTAssertTrue(card.content.contains(content))
        XCTAssertFalse(card.isPublic)

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
        waitFor("popup-menu.item.root")
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
        waitFor("cardEditorContent", timeout: 20)

        waitForEnabledButton("cardEditorAddTag", timeout: 20).tap()
        let addTagAlert = app.alerts["Add Tag"]
        XCTAssertTrue(addTagAlert.waitForExistence(timeout: 10))
        let tagInput = addTagAlert.textFields.firstMatch
        XCTAssertTrue(tagInput.waitForExistence(timeout: 10))
        tagInput.tap()
        tagInput.typeText("## editortag ")
        let add = addTagAlert.buttons["Add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        waitForEnabledButton("cardEditorAddTag", timeout: 20).tap()
        XCTAssertTrue(addTagAlert.waitForExistence(timeout: 10))
        let duplicateInput = addTagAlert.textFields.firstMatch
        XCTAssertTrue(duplicateInput.waitForExistence(timeout: 10))
        duplicateInput.tap()
        duplicateInput.typeText("#editortag")
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        closeNewNoteEditor()

        waitForSmokeCardState(id: cardID, token: session.token) { card in
            !card.content.contains("#editortag")
                && card.tags.filter { $0 == "editortag" }.count == 1
                && card.contentJSON != nil
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
        waitFor("cardEditorContent", timeout: 20)
        waitForEnabledButton("cardEditorAddLink", timeout: 20).tap()
        waitFor("linkPopup", timeout: 20)
        let search = waitFor("linkPopupSearch")
        search.tap()
        search.typeText(targetToken)
        waitFor("linkPopupCard.\(targetID)", timeout: 30)

        permanentlyCleanUpSmokeCard(id: targetID, token: session.token)
        tap("linkPopupCard.\(targetID)")

        XCTAssertEqual(
            waitFor("cardEditorSaveMessage", timeout: 20).label,
            "Couldn't add that link. Retry."
        )
        XCTAssertEqual(waitForButton("cardEditorSave").label, "Retry")
        XCTAssertTrue(exists("cardEditorContent", timeout: 2))
        XCTAssertFalse(exists("cardEditorLink.\(targetID)", timeout: 2))
        captureVisual("card-editor-link-failure-retained")
    }

    func testNewDirtyCardAddLinkCreatesOnceAndPersistsCanonicalRelation() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let suffix = Int(Date().timeIntervalSince1970)
        let targetToken = "new-editor-link-target-\(suffix)"
        let bodyText = "New editor link source \(suffix)"
        let targetID = try createSmokeCard(
            token: session.token,
            searchToken: targetToken,
            isPublic: false
        )
        var createdID: String?
        defer {
            permanentlyCleanUpSmokeCard(id: targetID, token: session.token)
            if let createdID {
                permanentlyCleanUpSmokeCard(id: createdID, token: session.token)
            }
            if let duplicateSources = try? fetchSmokeCards(
                search: bodyText,
                token: session.token
            ) {
                for card in duplicateSources where card.content.contains(bodyText) {
                    permanentlyCleanUpSmokeCard(id: card.id, token: session.token)
                }
            }
        }

        launchAuthenticatedApp()
        tap("tab.library")
        waitForButton("note.create", timeout: 20).tap()
        waitFor("cardEditorContent", timeout: 20)
        typeInCardEditorBody(bodyText)

        waitForEnabledButton("cardEditorAddLink", timeout: 20).tap()
        waitFor("linkPopup", timeout: 30)
        let search = waitFor("linkPopupSearch")
        search.tap()
        search.typeText(targetToken)
        waitFor("linkPopupCard.\(targetID)", timeout: 30).tap()

        waitForMissing("linkPopup", timeout: 20)
        waitFor("cardEditorLink.\(targetID)", timeout: 30)
        closeNewNoteEditor()

        let canonicalID = waitFor("note.created-card-id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(canonicalID.isEmpty)
        XCTAssertNotEqual(canonicalID, targetID)
        createdID = canonicalID

        let card = try fetchSmokeCard(id: canonicalID, token: session.token)
        XCTAssertTrue(card.content.contains(bodyText))
        XCTAssertNotNil(card.contentJSON)
        let matchingSources = try fetchSmokeCards(
            search: bodyText,
            token: session.token
        ).filter { $0.content.contains(bodyText) }
        XCTAssertEqual(
            matchingSources.map(\.id),
            [canonicalID],
            "Add Link and Back must reuse one canonical new card"
        )
        let matchingEdges = try fetchSmokeCardLinks(
            id: canonicalID,
            token: session.token
        ).filter {
            $0.sourceAssetID == canonicalID && $0.targetAssetID == targetID
        }
        XCTAssertEqual(
            matchingEdges.count,
            1,
            "The create-before-picker path must keep one canonical card and one relation"
        )
    }

    func testNewCardStagesBackgroundAndPrivacyBeforeFirstSave() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let bodyText = "New staged editor \(UUID().uuidString.lowercased())"
        var canonicalID: String?
        defer {
            if let canonicalID {
                permanentlyCleanUpSmokeCard(
                    id: canonicalID,
                    token: session.token
                )
            }
            if let matching = try? fetchSmokeCards(
                search: bodyText,
                token: session.token
            ) {
                for card in matching
                where card.content.contains(bodyText) && card.id != canonicalID {
                    permanentlyCleanUpSmokeCard(
                        id: card.id,
                        token: session.token
                    )
                }
            }
        }

        launchAuthenticatedApp()
        tap("tab.library")
        waitForButton("note.create", timeout: 20).tap()
        waitFor("cardEditorContent", timeout: 20)
        typeInCardEditorBody(bodyText)
        tapButton("cardEditorKeyboardDismiss")
        waitForElementToDisappear(app.keyboards.firstMatch)

        waitForButton("cardEditorMoreButton").tap()
        let makePublic = app.buttons["Make Public"].firstMatch
        XCTAssertTrue(makePublic.waitForExistence(timeout: 10))
        makePublic.tap()

        revealEditorBackgroundButton().tap()
        try selectFirstPhotoFromImagePicker()

        waitForButton("cardEditorMoreButton", timeout: 20).tap()
        XCTAssertTrue(
            app.buttons["Make Private"].firstMatch.waitForExistence(timeout: 10),
            "Privacy must remain staged in the unsaved draft"
        )
        XCTAssertTrue(
            app.buttons["Replace Background"].firstMatch
                .waitForExistence(timeout: 10),
            "The selected photo must remain staged before first save"
        )
        let cardsBeforeSave = try fetchSmokeCards(
            search: bodyText,
            token: session.token
        ).filter { $0.content.contains(bodyText) }
        XCTAssertTrue(
            cardsBeforeSave.isEmpty,
            "Staging privacy and a background must not create a server card"
        )
        captureVisual("card-editor-new-background-privacy-staged")

        app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)
        ).tap()
        closeNewNoteEditor()

        let callbackID = waitFor("note.created-card-id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(callbackID.isEmpty)
        canonicalID = callbackID

        let matchingCards = waitForSmokeCards(
            search: bodyText,
            token: session.token
        ) { cards in
            cards.filter { $0.content.contains(bodyText) }.count == 1
        }.filter { $0.content.contains(bodyText) }
        XCTAssertEqual(matchingCards.map(\.id), [callbackID])
        waitForSmokeCardState(id: callbackID, token: session.token) { card in
            card.isPublic && !(card.backgroundMediaRef ?? "").isEmpty
        }
        let persisted = try fetchSmokeCard(id: callbackID, token: session.token)
        XCTAssertTrue(persisted.isPublic)
        XCTAssertFalse((persisted.backgroundMediaRef ?? "").isEmpty)
    }

    func testNewCardCreateResponseLossRetryReusesCanonicalCard() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let suffix = Int(Date().timeIntervalSince1970)
        let bodyText = "New editor response loss \(suffix)"
        var canonicalID: String?
        defer {
            if let matching = try? fetchSmokeCards(
                search: bodyText,
                token: session.token
            ) {
                for card in matching where card.content.contains(bodyText) {
                    permanentlyCleanUpSmokeCard(
                        id: card.id,
                        token: session.token
                    )
                }
            }
        }

        app.launchEnvironment[
            "CHORAI_UI_TEST_CARD_CREATE_RESPONSE_LOSS_TOKEN"
        ] = bodyText
        launchAuthenticatedApp()
        tap("tab.library")
        waitForButton("note.create", timeout: 20).tap()
        waitFor("cardEditorContent", timeout: 20)
        typeInCardEditorBody(bodyText)

        tapButton("cardEditorFloatingBack")
        XCTAssertEqual(
            waitFor("cardEditorSaveMessage", timeout: 30).label,
            "Couldn't save this note. Retry when ready."
        )
        XCTAssertEqual(waitForButton("cardEditorSave").label, "Retry")
        XCTAssertTrue(
            exists("cardEditorContent", timeout: 2),
            "A lost create response must keep the editor on screen"
        )

        let cardsAfterLostResponse = waitForSmokeCards(
            search: bodyText,
            token: session.token
        ) { cards in
            cards.filter { $0.content.contains(bodyText) }.count == 1
        }.filter { $0.content.contains(bodyText) }
        XCTAssertEqual(cardsAfterLostResponse.count, 1)
        canonicalID = cardsAfterLostResponse.first?.id

        let latestSuffix = " recovered latest \(suffix)"
        typeInCardEditorBody(latestSuffix)
        waitForButton("cardEditorSave").tap()
        waitForMissing("cardEditorContent", timeout: 30)
        let callbackID = waitFor("note.created-card-id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(callbackID, canonicalID)

        let cardsAfterRetry = waitForSmokeCards(
            search: bodyText,
            token: session.token
        ) { cards in
            cards.filter { $0.content.contains(bodyText) }.count == 1
        }.filter { $0.content.contains(bodyText) }
        XCTAssertEqual(cardsAfterRetry.map(\.id), [callbackID])
        let latestCard = try fetchSmokeCard(id: callbackID, token: session.token)
        XCTAssertTrue(latestCard.content.contains(bodyText))
        XCTAssertTrue(
            latestCard.content.contains(latestSuffix),
            "Retry must recover the frozen create before updating the latest draft"
        )
    }

    func testCardEditorCardActionsExposeIDScopedNativeActions() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        let cardID = try createSmokeCard(
            token: session.token,
            searchToken: "editor-actions-\(Int(Date().timeIntervalSince1970))",
            isPublic: false
        )
        defer {
            permanentlyCleanUpSmokeCard(id: cardID, token: session.token)
        }

        launchAuthenticatedApp()
        tap("tab.library")
        waitFor("card.home.\(cardID)", timeout: 30).tap()
        waitFor("cardEditorContent", timeout: 20)
        _ = waitForEnabledButton("cardEditorAddTag", timeout: 20)
        waitForButton("cardEditorMoreButton").tap()
        let cardActions = app.buttons["Card Actions"].firstMatch
        XCTAssertTrue(cardActions.waitForExistence(timeout: 10))
        cardActions.tap()

        for label in ["Share", "Spark", "Merge", "Root", "Pin", "Remove"] {
            XCTAssertTrue(
                app.buttons[label].firstMatch.waitForExistence(timeout: 20),
                "Missing native card action: \(label)"
            )
        }
        captureVisual("card-editor-native-card-actions")
        app.buttons["Cancel"].firstMatch.tap()
        closeNewNoteEditor()
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
        waitFor("cardEditorContent", timeout: 20)
        revealEditorBackgroundButton().tap()
        try selectFirstPhotoFromImagePicker()

        waitForButton("cardEditorMoreButton", timeout: 20).tap()
        XCTAssertTrue(
            app.buttons["Replace Background"].firstMatch
                .waitForExistence(timeout: 10),
            "A selected photo must become the staged background action state"
        )
        XCTAssertNil(
            try fetchSmokeCard(id: cardID, token: session.token)
                .backgroundMediaRef,
            "Selecting a photo must stage locally until the exact body snapshot saves"
        )
        captureVisual("card-editor-background-staged")
        app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)
        ).tap()
        closeNewNoteEditor()

        waitForSmokeCardState(id: cardID, token: session.token) {
            !($0.backgroundMediaRef ?? "").isEmpty
        }
        waitFor("card.home.\(cardID)", timeout: 30).tap()
        waitFor("cardEditorContent", timeout: 20)
        _ = waitForEnabledButton("cardEditorAddTag", timeout: 20)
        waitForButton("cardEditorMoreButton").tap()
        XCTAssertTrue(
            app.buttons["Replace Background"].firstMatch
                .waitForExistence(timeout: 10)
        )
        captureVisual("card-editor-background-uploaded")

        let remove = app.buttons["Remove Background"].firstMatch
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

    func testAccountPrivacyLoadsAndPersistsCanonicalGoSetting() throws {
        let session = try requireSmokeSession()
        let original = try fetchSmokePrivacy(token: session.token)
        defer {
            try? setSmokePrivacy(
                token: session.token,
                showFollowLists: original.showFollowLists
            )
        }

        seedAppSession(session)
        launchAuthenticatedApp()
        tap("side-menu.open")
        tap("side-menu.settings")
        waitFor("screen.settings.loaded", timeout: 20)
        tap("settings.account-privacy")
        waitFor("screen.account-privacy", timeout: 20)

        let identifiers = [
            "show_follow_lists",
            "allow_follow",
            "show_email",
            "show_phone",
            "show_location",
            "show_birthday"
        ].map { "account-privacy.toggle.\($0)" }
        for identifier in identifiers {
            waitFor(identifier, timeout: 30)
        }

        let toggle = waitFor(
            "account-privacy.toggle.show_follow_lists",
            timeout: 30
        )
        let originalValue = original.showFollowLists ? "enabled" : "disabled"
        let changedValue = original.showFollowLists ? "disabled" : "enabled"
        XCTAssertEqual(toggle.value as? String, originalValue)

        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        waitForAccessibilityValue(
            "account-privacy.toggle.show_follow_lists",
            expected: changedValue,
            timeout: 20
        )
        waitForSmokePrivacy(
            token: session.token,
            showFollowLists: !original.showFollowLists
        )
        captureVisual("account-privacy-canonical-toggle")

        waitFor("account-privacy.toggle.show_follow_lists").tap()
        waitForAccessibilityValue(
            "account-privacy.toggle.show_follow_lists",
            expected: originalValue,
            timeout: 20
        )
        waitForSmokePrivacy(
            token: session.token,
            showFollowLists: original.showFollowLists
        )
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
        let blockedUsers = waitFor("account-privacy.blocked-users")
        for _ in 0..<6 where !blockedUsers.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(blockedUsers.isHittable)
        blockedUsers.tap()
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

    func testRecordIsAbsentAndLibraryPlusIsTheOnlyCreateEntry() throws {
        let session = try requireSmokeSession()
        seedAppSession(session)
        launchAuthenticatedApp()

        for tabId in ["tab.flow", "tab.library", "tab.chat"] {
            tap(tabId)
            XCTAssertFalse(
                exists("record.open", timeout: 1),
                "Record must be absent on \(tabId)"
            )
        }

        tap("tab.library")
        let create = waitFor("note.create", timeout: 15)
        XCTAssertTrue(create.isHittable)
        create.tap()
        waitFor("cardEditorContent", timeout: 15)
        closeNewNoteEditor()
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

    private func launchChoraProfileFixture(mode: String) {
        if app.state != .notRunning {
            app.terminate()
        }
        app = XCUIApplication()
        app.launchArguments.append("--ui-test-chora-profile")
        app.launchEnvironment["CHORAI_CHORA_PROFILE_FIXTURE_MODE"] = mode
        app.launch()
        waitFor("screen.choraProfile")
    }

    private func launchInvitationCreditFixture(mode: String) {
        if app.state != .notRunning {
            app.terminate()
        }
        app = XCUIApplication()
        app.launchArguments.append("--ui-test-invitation-credits")
        app.launchEnvironment["CHORAI_INVITATION_CREDIT_FIXTURE_MODE"] = mode
        app.launch()
    }

    private func launchSignupInvitationFixture(mode: String) {
        if app.state != .notRunning {
            app.terminate()
        }
        app = XCUIApplication()
        app.launchArguments.append("--ui-test-signup-invitation")
        app.launchEnvironment["CHORAI_SIGNUP_INVITATION_FIXTURE_MODE"] = mode
        app.launch()
        waitFor("screen.signup")
    }

    private func tapSignupFixtureAction(_ identifier: String) {
        let action = waitFor(identifier)
        for _ in 0..<6 where !action.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(action.isHittable)
        action.tap()
    }

    private func openInvitationCreditDetail(
        link: String,
        screen: String,
        empty: String,
        rowPrefix: String,
        error: String
    ) {
        let destination = waitFor(link)
        for _ in 0..<5 where !destination.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(destination.isHittable)
        destination.tap()

        waitFor(screen, timeout: 20)
        let terminalContent = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ OR identifier BEGINSWITH %@",
                empty,
                rowPrefix
            )
        ).firstMatch
        XCTAssertTrue(
            terminalContent.waitForExistence(timeout: 20),
            "Missing decoded content for \(screen)"
        )
        XCTAssertFalse(app.descendants(matching: .any)[error].exists)

        tap("settings.destination.back")
        waitFor("screen.invitation-credits", timeout: 10)
    }

    private func waitForLabel(
        _ identifier: String,
        expected: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let element = app.descendants(matching: .any)[identifier]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expected),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Timed out waiting for \(identifier) label \(expected)",
            file: file,
            line: line
        )
    }

    private func submitInvitationFixtureCode(_ code: String) {
        waitFor("screen.invitation-credits")
        tap("invitation-credits.redeem.disclosure")
        let field = waitFor("invitation-credits.redeem.code")
        field.tap()
        field.typeText(code)
        app.swipeUp()
        let submit = waitFor("invitation-credits.redeem.submit")
        for _ in 0..<4 where !submit.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(submit.isHittable)
        submit.tap()
    }

    private func launchDiscoveryPathFixture(mode: String) {
        app.launchArguments.append("--ui-test-discovery-path")
        app.launchEnvironment["CHORAI_DISCOVERY_PATH_FIXTURE_MODE"] = mode
        app.launch()
    }

    private func launchCardEditorFixture(mode: String) {
        app.launchArguments.append("--ui-test-card-editor-shell")
        app.launchEnvironment["CHORAI_CARD_EDITOR_FIXTURE_MODE"] = mode
        app.launch()
        waitFor("screen.card-editor-shell")
        if mode != "blocked" {
            waitForEnabled(waitForButton("cardEditorSave"))
        }
    }

    @discardableResult
    private func waitForEnabled(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Timed out waiting for \(element) to become enabled",
            file: file,
            line: line
        )
        return element
    }

    private func assertPrimaryControl(
        _ element: XCUIElement,
        identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.isHittable, "\(identifier) must be hittable", file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            element.frame.width,
            44,
            "\(identifier) must be at least 44 points wide",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.height,
            44,
            "\(identifier) must be at least 44 points tall",
            file: file,
            line: line
        )
    }

    private func assertReadingOrder(
        _ first: XCUIElement,
        before second: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sameLine = abs(first.frame.midY - second.frame.midY) < 4
        let ordered = sameLine
            ? first.frame.maxX <= second.frame.minX
            : first.frame.minY < second.frame.minY
        XCTAssertTrue(
            ordered,
            "Expected \(first.identifier) before \(second.identifier)",
            file: file,
            line: line
        )
    }

    private func waitForElementToDisappear(
        _ element: XCUIElement,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Element still exists: \(element)",
            file: file,
            line: line
        )
    }

    private func replaceShortFixtureText(_ identifier: String, with text: String) {
        let field = waitFor(identifier)
        field.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let currentLength = (field.value as? String)?.count ?? 0
        field.typeText(
            String(
                repeating: XCUIKeyboardKey.delete.rawValue,
                count: currentLength
            )
        )
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
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

    private func waitForEnabledButton(
        _ identifier: String,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let button = waitForButton(
            identifier,
            timeout: timeout,
            file: file,
            line: line
        )
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"),
            object: button
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            "Button never became enabled: \(identifier)",
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
            waitFor("flow.card.\(cardID)", file: file, line: line).swipeLeft()
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

    private func typeInCardEditorBody(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let body = waitFor(
            "cardEditorBodyWebView",
            timeout: 20,
            file: file,
            line: line
        )
        body.coordinate(
            withNormalizedOffset: CGVector(dx: 0.22, dy: 0.10)
        ).tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 10),
            "The body editor never accepted focus",
            file: file,
            line: line
        )
        app.typeText(text)
    }

    private func closeNewNoteEditor(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tapButton("cardEditorFloatingBack", file: file, line: line)
        waitForMissing("cardEditorContent", timeout: 30, file: file, line: line)
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
    ) -> XCUIElement {
        _ = waitForEnabledButton(
            "cardEditorAddTag",
            timeout: 20,
            file: file,
            line: line
        )
        waitForButton("cardEditorMoreButton", file: file, line: line).tap()
        let identifiedButton = app.descendants(matching: .any)[
            "cardEditorBackgroundButton"
        ]
        if identifiedButton.waitForExistence(timeout: 2),
           identifiedButton.isHittable {
            return identifiedButton
        }
        let labelButton = ["Add Background", "Replace Background"]
            .lazy
            .map { self.app.buttons[$0].firstMatch }
            .first { $0.waitForExistence(timeout: 3) && $0.isHittable }
        XCTAssertTrue(
            labelButton != nil,
            "Background control was not reachable in the editor More menu",
            file: file,
            line: line
        )
        return labelButton ?? identifiedButton
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
                if waitForImagePickerToDismiss(timeout: 3) {
                    return
                }
            }

            if isSystemImagePickerVisible() {
                for offset in [
                    CGVector(dx: 0.18, dy: 0.32),
                    CGVector(dx: 0.50, dy: 0.32),
                    CGVector(dx: 0.18, dy: 0.48),
                ] {
                    app.coordinate(withNormalizedOffset: offset).tap()
                    tapImagePickerConfirmationIfNeeded()
                    if waitForImagePickerToDismiss(timeout: 2) {
                        return
                    }
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }

        throw XCTSkip("No selectable image was found in the simulator photo library; preload media before running photo-picker smoke")
    }

    private func waitForImagePickerToDismiss(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isSystemImagePickerVisible() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return !isSystemImagePickerVisible()
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

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            for title in confirmationTitles {
                let button = app.buttons[title]
                if button.exists && button.isHittable {
                    button.tap()
                    return
                }
            }
            if !isSystemImagePickerVisible() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
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
            let contentJSON: String?
            let isPublic: Bool
            let isPinned: Bool
            let tags: [String]
            let backgroundMediaRef: String?

            enum CodingKeys: String, CodingKey {
                case id, title, content, tags
                case contentJSON = "content_json"
                case isPublic = "is_public"
                case isPinned = "is_pinned"
                case backgroundMediaRef = "background_media_ref"
            }
        }
    }

    private struct SmokeCardLinksResponse: Decodable {
        let data: SmokeCardLinksData

        struct SmokeCardLinksData: Decodable {
            let outgoingLinks: [SmokeCardLinkEdge]

            enum CodingKeys: String, CodingKey {
                case outgoingLinks = "outgoing_links"
            }
        }

        struct SmokeCardLinkEdge: Decodable {
            let sourceAssetID: String
            let targetAssetID: String

            enum CodingKeys: String, CodingKey {
                case sourceAssetID = "source_asset_id"
                case targetAssetID = "target_asset_id"
            }
        }
    }

    private struct SmokeCardListResponse: Decodable {
        let data: [SmokeCardListItem]

        struct SmokeCardListItem: Decodable {
            let id: String
            let content: String
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
        let showEmail: Bool
        let showPhone: Bool
        let showLocation: Bool
        let showBirthday: Bool
        let allowFollow: Bool
        let showFollowLists: Bool

        enum CodingKeys: String, CodingKey {
            case showEmail = "show_email"
            case showPhone = "show_phone"
            case showLocation = "show_location"
            case showBirthday = "show_birthday"
            case allowFollow = "allow_follow"
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
            let path: [SmokeDiscoveryPathNode]

            enum CodingKeys: String, CodingKey {
                case rootActivityID = "root_activity_id"
                case path
            }
        }

        struct SmokeDiscoveryPathNode: Decodable {
            let assetID: String
            let depth: Int

            enum CodingKeys: String, CodingKey {
                case assetID = "asset_id"
                case depth
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

    private func fetchSmokeCards(
        search: String,
        token: String
    ) throws -> [SmokeCardListResponse.SmokeCardListItem] {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard var components = URLComponents(string: "\(baseURL)/api/cards") else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 16,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Go card list URL"]
            )
        }
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "search", value: search),
        ]
        guard let url = components.url else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 17,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Go card list query"]
            )
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokeCardListResponse.self
        ).data
    }

    private func waitForSmokeCards(
        search: String,
        token: String,
        timeout: TimeInterval = 20,
        predicate: ([SmokeCardListResponse.SmokeCardListItem]) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [SmokeCardListResponse.SmokeCardListItem] {
        let deadline = Date().addingTimeInterval(timeout)
        var last: [SmokeCardListResponse.SmokeCardListItem] = []
        while Date() < deadline {
            if let cards = try? fetchSmokeCards(search: search, token: token) {
                last = cards
                if predicate(cards) {
                    return cards
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail(
            "Go card list did not converge for search \(search)",
            file: file,
            line: line
        )
        return last
    }

    private func fetchSmokeCardLinks(
        id: String,
        token: String
    ) throws -> [SmokeCardLinksResponse.SmokeCardLinkEdge] {
        let baseURL = ProcessInfo.processInfo.environment[
            "CHORAI_API_BASE_URL"
        ] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/cards/\(id)/links") else {
            throw NSError(
                domain: "ArcNoteUITests",
                code: 15,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Go card links URL"]
            )
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try sendRequest(
            request,
            responseType: SmokeCardLinksResponse.self
        ).data.outgoingLinks
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

    private func waitForSmokePrivacy(
        token: String,
        showFollowLists: Bool,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        var last: SmokePrivacy?
        var lastError: Error?
        while Date() < deadline {
            do {
                let settings = try fetchSmokePrivacy(token: token)
                last = settings
                if settings.showFollowLists == showFollowLists {
                    return
                }
            } catch {
                lastError = error
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        XCTFail(
            "Timed out waiting for show_follow_lists=\(showFollowLists); last=\(String(describing: last)), error=\(String(describing: lastError))",
            file: file,
            line: line
        )
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
        try fetchDiscoveryPath(assetID: assetID, token: token).rootActivityID
    }

    private func fetchDiscoveryPath(
        assetID: String,
        token: String
    ) throws -> SmokeDiscoveryPathResponse.SmokeDiscoveryPath {
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
        ).data
    }

    private func waitForDiscoveryPath(
        assetID: String,
        token: String,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SmokeDiscoveryPathResponse.SmokeDiscoveryPath {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        while Date() < deadline {
            do {
                return try fetchDiscoveryPath(assetID: assetID, token: token)
            } catch {
                lastError = error
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            }
        }
        XCTFail(
            "Timed out waiting for discovery path: \(lastError?.localizedDescription ?? "unknown")",
            file: file,
            line: line
        )
        throw lastError ?? NSError(
            domain: "ArcNoteUITests",
            code: 14,
            userInfo: [NSLocalizedDescriptionKey: "Discovery path timed out"]
        )
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
        password: String,
        baseURL: String? = nil
    ) -> SmokeSession? {
        let environment = ProcessInfo.processInfo.environment
        let resolvedBaseURL = baseURL
            ?? environment["CHORAI_API_BASE_URL"]
            ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(resolvedBaseURL)/api/auth/login") else {
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
