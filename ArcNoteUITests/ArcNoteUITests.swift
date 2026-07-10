import XCTest

final class ArcNoteUITests: XCTestCase {
    private var app: XCUIApplication!
    private static var cachedSmokeSession: SmokeSession?

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
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

    func testDetailMergeMenuAttemptsGoMergeJob() throws {
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

        tap("merge.action")

        let terminalState = waitForMergeTerminalState(timeout: 75)
        XCTAssertTrue(
            terminalState == "new-insight" || terminalState == "error",
            "Unexpected merge terminal state: \(terminalState)"
        )
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

    func testFlowSparkOpensGoSparkScreen() throws {
        launchAuthenticatedApp()

        waitFor("screen.flow.content", timeout: 20)
        let cardId = waitFor("flow.visible-card.id", timeout: 30)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)

        tap("flow.spark.\(cardId)")

        waitFor("spark.screen.loaded", timeout: 20)
        let sourceCardId = waitFor("spark.source.card-id", timeout: 10)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(sourceCardId, cardId)
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
        defer {
            deleteSmokeCard(id: cardId, token: session.token)
        }

        let card = try fetchSmokeCard(id: cardId, token: session.token)
        XCTAssertEqual(card.content, content)
        XCTAssertFalse(card.isPublic)

        tap("tab.library")
        waitFor("card.home.\(cardId)", timeout: 30)
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
        seedAppSession(session)

        let sparkCardId = ProcessInfo.processInfo.environment["CHORAI_UI_TEST_SPARK_CARD_ID"] ?? "ast_cs_art_88ba36bc8dea"
        let expectedRelatedIds = try fetchSparkRelatedCardIds(cardId: sparkCardId, token: session.token)
        guard !expectedRelatedIds.isEmpty else {
            throw XCTSkip("Go Spark returned no related cards for \(sparkCardId); choose a seeded asset with related cards")
        }

        app.launchArguments.append("--ui-test-open-recommended-detail")
        app.launchEnvironment["CHORAI_UI_TEST_DETAIL_CARD_ID"] = sparkCardId
        launchAuthenticatedApp()

        waitFor("screen.detail.loaded", timeout: 30)
        let detailCardId = waitFor("screen.detail.card-id", timeout: 10)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(detailCardId, sparkCardId)

        tap("detail.menu.open")
        tap("popup-menu.item.spark")

        waitFor("spark.screen.loaded", timeout: 20)
        let sourceCardId = waitFor("spark.source.card-id", timeout: 10)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(sourceCardId, sparkCardId)

        waitFor("spark.related.loaded", timeout: 60)
        let visibleRelatedId = waitFor("spark.related.card-id", timeout: 10)
            .label
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(expectedRelatedIds.contains(visibleRelatedId), "Visible Spark related card \(visibleRelatedId) was not in Go preflight result \(expectedRelatedIds)")
    }

    private func launchAuthenticatedApp() {
        let environment = ProcessInfo.processInfo.environment

        app.launchEnvironment["CHORAI_UI_TEST"] = "1"
        if let baseURL = environment["CHORAI_API_BASE_URL"], !baseURL.isEmpty {
            app.launchEnvironment["CHORAI_API_BASE_URL"] = baseURL
        }
        if let token = environment["CHORAI_UI_TEST_AUTH_TOKEN"], !token.isEmpty {
            app.launchEnvironment["CHORAI_UI_TEST_AUTH_TOKEN"] = token
        }
        if let actorId = environment["CHORAI_UI_TEST_ACTOR_ID"], !actorId.isEmpty {
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

    private func replaceText(_ identifier: String, with text: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = waitFor(identifier, timeout: 10, file: file, line: line)
        XCTAssertTrue(element.isHittable, "Identifier is not hittable: \(identifier)", file: file, line: line)
        element.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        app.typeText(text)
    }

    private func dismissKeyboard() {
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
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

    private func waitForMergeTerminalState(timeout: TimeInterval = 75, file: StaticString = #filePath, line: UInt = #line) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        let newInsight = app.descendants(matching: .any)["screen.new-insight.loaded"]
        let error = app.descendants(matching: .any)["merge.error"]
        var sawLoading = false

        while Date() < deadline {
            if app.descendants(matching: .any)["merge.loading"].exists {
                sawLoading = true
            }
            if newInsight.exists {
                return "new-insight"
            }
            if error.exists {
                return "error"
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        XCTFail("Timed out waiting for merge UI terminal state; saw loading: \(sawLoading)", file: file, line: line)
        return "timeout"
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

    private struct SmokeCardResponse: Decodable {
        let data: SmokeCardData

        struct SmokeCardData: Decodable {
            let id: String
            let content: String
            let isPublic: Bool

            enum CodingKeys: String, CodingKey {
                case id, content
                case isPublic = "is_public"
            }
        }
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
            let isRead: Bool

            enum CodingKeys: String, CodingKey {
                case notificationId = "notification_id"
                case isRead = "is_read"
            }
        }
    }

    private struct SmokeProfileResponse: Decodable {
        let data: SmokeProfile
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

    private struct SmokeSparkResponse: Decodable {
        let data: SmokeSparkData

        struct SmokeSparkData: Decodable {
            let groups: SmokeSparkGroups
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
            let card: SmokeSparkCard?
        }

        struct SmokeSparkCard: Decodable {
            let id: String

            enum CodingKeys: String, CodingKey {
                case id
                case cardId = "card_id"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = (try? container.decode(String.self, forKey: .id))
                    ?? (try? container.decode(String.self, forKey: .cardId))
                    ?? ""
            }
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

    private func requireSmokeSession(file: StaticString = #filePath, line: UInt = #line) throws -> SmokeSession {
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

    private func createPublicSmokeCard(token: String, searchToken: String) throws -> String {
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
            "is_public": true
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
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard var components = URLComponents(string: "\(baseURL)/api/notifications") else {
            throw NSError(domain: "ArcNoteUITests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid Go notifications URL"])
        }
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: "50")
        ]
        guard let url = components.url else {
            throw NSError(domain: "ArcNoteUITests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid encoded Go notifications URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let response = try sendRequest(request, responseType: SmokeNotificationsResponse.self)
        return response.data.first(where: { $0.notificationId == notificationId })?.isRead
    }

    private func fetchSparkRelatedCardIds(cardId: String, token: String) throws -> [String] {
        let baseURL = ProcessInfo.processInfo.environment["CHORAI_API_BASE_URL"] ?? "http://127.0.0.1:8080"
        guard let url = URL(string: "\(baseURL)/api/v1/assets/\(cardId)/spark") else {
            throw NSError(domain: "ArcNoteUITests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Invalid Go Spark URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [:])

        let response = try sendRequest(request, responseType: SmokeSparkResponse.self)
        let buckets = [
            response.data.groups.related,
            response.data.groups.angles,
            response.data.groups.keywords
        ]

        return buckets
            .compactMap { $0 }
            .flatMap(\.items)
            .compactMap(\.card?.id)
            .filter { !$0.isEmpty }
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

        let environment = ProcessInfo.processInfo.environment
        let email = environment["CHORAI_UI_TEST_EMAIL"] ?? "ios-smoke-a-20260619@example.com"
        let password = environment["CHORAI_UI_TEST_PASSWORD"] ?? "Password123"
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
        Self.cachedSmokeSession = result
        return result
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
