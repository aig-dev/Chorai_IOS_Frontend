import XCTest

final class AuthEntryFlowUITests: XCTestCase {
    private let password = "SamplePass42"
    private let wrongPassword = "Mismatch42"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEmailSignupRecoversFromSendFailureAndSkipsInterests() {
        let app = launch(failFirstSend: true)
        openSignup(app)

        type("reader@example.invalid", into: app.textFields["signup.email"])
        capture("auth-polish-signup-email", in: app)
        let next = app.buttons["signup.continue"]
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isHittable, "Continue must be reachable with the email keyboard open")
        next.tap()
        XCTAssertTrue(app.staticTexts["signup.error"].waitForExistence(timeout: 5))
        next.tap()

        enterCodeAndUsername(app, captureSteps: true)

        typeSignupPassword(password, fieldID: "signup.password", in: app)
        capture("auth-polish-signup-password", in: app)
        next.tap()
        typeSignupPassword(wrongPassword, fieldID: "signup.confirm-password", in: app)
        capture("auth-polish-signup-confirmation", in: app)
        let create = app.buttons["signup.create-account"]
        create.tap()
        XCTAssertTrue(app.staticTexts["signup.error"].waitForExistence(timeout: 5))
        capture("auth-signup-password-mismatch", in: app)
        typeSignupPassword(password, replacing: wrongPassword, fieldID: "signup.confirm-password", in: app)
        create.tap()

        let skip = app.buttons["interests.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        capture("auth-interests-before-skip", in: app)
        skip.tap()
        XCTAssertTrue(app.staticTexts["auth-entry.fixture.complete"].waitForExistence(timeout: 5))
    }

    func testChangingSignupEmailClearsPreviousVerificationCode() {
        let app = launch()
        openSignup(app)

        let email = app.textFields["signup.email"]
        type("reader@example.invalid", into: email)
        app.buttons["signup.continue"].tap()
        let code = app.textFields["signup.code"]
        type("123456", into: code)

        let changeEmail = app.buttons["signup.change-email"]
        XCTAssertTrue(changeEmail.waitForExistence(timeout: 5))
        if !changeEmail.isHittable { app.swipeUp() }
        changeEmail.tap()
        replace("reader@example.invalid", with: "writer@example.invalid", in: email)
        app.buttons["signup.continue"].tap()

        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertNotEqual(code.value as? String, "123456")
        XCTAssertFalse(app.staticTexts["signup.step.username"].exists)
    }

    func testRejectedVerificationCodeReturnsToCodeStep() {
        let app = launch()
        openSignup(app)

        type("reader@example.invalid", into: app.textFields["signup.email"])
        app.buttons["signup.continue"].tap()
        enterCodeAndUsername(app, code: "000000")
        typeSignupPassword(password, fieldID: "signup.password", in: app)
        app.buttons["signup.continue"].tap()
        typeSignupPassword(password, fieldID: "signup.confirm-password", in: app)
        app.buttons["signup.create-account"].tap()

        let recover = app.buttons["signup.recover-code"]
        XCTAssertTrue(recover.waitForExistence(timeout: 5))
        if !recover.isHittable { app.swipeUp() }
        recover.tap()

        let code = app.textFields["signup.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertNotEqual(code.value as? String, "000000")
        XCTAssertFalse(app.buttons["signup.continue"].isEnabled)
        capture("auth-signup-verification-recovery", in: app)
    }

    func testSignInValidationAndOfflineCompletion() {
        let app = launch()
        tapWelcomeLogin(app)

        let email = app.textFields["signin.email"]
        type("invalid", into: email)
        typeSignInPassword(password, into: app.secureTextFields["signin.password"], in: app)
        let submit = app.buttons["signin.submit"]
        XCTAssertFalse(submit.isEnabled)
        replace("invalid", with: "reader@example.invalid", in: email)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(submit.isHittable, "Log in must be reachable with the keyboard open")
        XCTAssertTrue(submit.isEnabled)
        capture("auth-signin-keyboard", in: app)
        submit.tap()

        XCTAssertTrue(app.staticTexts["auth-entry.fixture.complete"].waitForExistence(timeout: 5))
    }

    func testReturningLaunchOpensSignInAndBackReturnsToWelcome() {
        let app = launch(startsWithSignIn: true)
        let email = app.textFields["signin.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))

        let back = app.navigationBars.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()

        XCTAssertTrue(app.buttons["welcome.login"].waitForExistence(timeout: 5))
        let next = app.buttons["welcome.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.buttons["welcome.previous"].waitForExistence(timeout: 5))
        XCTAssertFalse(email.exists)
        capture("auth-returning-welcome-back", in: app)
    }

    func testSignInSignUpLinkUsesOfflinePrivateBetaPreflight() {
        let app = launch()
        tapWelcomeLogin(app)
        let signup = app.buttons["signin.sign-up"]
        XCTAssertTrue(signup.waitForExistence(timeout: 5))
        signup.tap()
        enterPrivateBetaCode(app)
    }

    func testSwitchingFromSignUpBackToSignInPreservesDraftAndBackDestination() {
        let app = launch(startsWithSignIn: true)
        let email = app.textFields["signin.email"]
        type("reader@example.invalid", into: email)
        app.buttons["signin.sign-up"].tap()

        let login = app.buttons["private-beta.sign-in"]
        XCTAssertTrue(login.waitForExistence(timeout: 5))
        login.tap()

        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertEqual(email.value as? String, "reader@example.invalid",
                       "Switching auth intent must return to the existing sign-in draft")
        app.navigationBars.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["welcome.login"].waitForExistence(timeout: 5),
                      "Back must return to welcome, not another auth form")
    }

    func testPrivateBetaErrorClearsOnlyWhenCodeChanges() {
        let app = launch(startsWithSignIn: true)
        let signup = app.buttons["signin.sign-up"]
        XCTAssertTrue(signup.waitForExistence(timeout: 10))
        signup.tap()
        let code = app.textFields["private-beta.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        app.buttons["private-beta.continue"].tap()

        let error = app.staticTexts["private-beta.message"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.isHittable, "A validation error must stay in the visible reading area")
        code.tap()
        XCTAssertTrue(error.exists, "Changing focus is not a code edit")
        code.typeText("U")
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: error)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 3), .completed,
                       "Editing the code must clear stale validation feedback")
    }

    func testReturningFromSignInPreservesUnsubmittedPrivateBetaCode() {
        let app = launch()
        let next = app.buttons["welcome.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        let join = app.buttons["welcome.join-private-beta"]
        XCTAssertTrue(join.waitForExistence(timeout: 5))
        join.tap()

        let code = app.textFields["private-beta.code"]
        type("DRAFT-CODE", into: code)
        capture("auth-polish-private-beta-draft", in: app)
        app.buttons["private-beta.sign-in"].tap()
        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Back"].tap()

        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertEqual(code.value as? String, "DRAFT-CODE",
                       "Returning from Log In must preserve the code before it has been submitted")
        capture("auth-polish-private-beta-returned-draft", in: app)
    }

    func testUsernameExplainsMinimumBeforeContinueEnables() {
        let app = launch()
        openSignup(app)
        type("reader@example.invalid", into: app.textFields["signup.email"])
        app.buttons["signup.continue"].tap()
        type("123456", into: app.textFields["signup.code"])
        app.buttons["signup.continue"].tap()

        let username = app.textFields["signup.username"]
        type("T", into: username)
        XCTAssertTrue(app.staticTexts["Choose a username with at least 2 characters."].exists)
        XCTAssertFalse(app.buttons["signup.continue"].isEnabled)
        username.typeText("r")
        XCTAssertTrue(app.buttons["signup.continue"].isEnabled)
    }

    func testSignupInterestSelectionStopsAtNineAndContinues() {
        let app = launch()
        openSignup(app)

        type("reader@example.invalid", into: app.textFields["signup.email"])
        app.buttons["signup.continue"].tap()
        enterCodeAndUsername(app)
        typeSignupPassword(password, fieldID: "signup.password", in: app)
        app.buttons["signup.continue"].tap()
        typeSignupPassword(password, fieldID: "signup.confirm-password", in: app)
        app.buttons["signup.create-account"].tap()

        for index in 0..<10 {
            let interest = app.buttons["interests.option.\(index)"]
            XCTAssertTrue(interest.waitForExistence(timeout: 5))
            if !interest.isHittable { app.swipeUp() }
            if index < 9 {
                interest.tap()
            }
        }
        XCTAssertTrue(app.staticTexts["9 selected"].exists)
        let tenth = app.buttons["interests.option.9"]
        XCTAssertFalse(tenth.isEnabled)
        XCTAssertEqual(tenth.value as? String, "not selected")
        capture("auth-interests-nine-selected", in: app)
        app.buttons["interests.next"].tap()
        XCTAssertTrue(app.staticTexts["auth-entry.fixture.complete"].waitForExistence(timeout: 5))
    }

    func testLargeTextDarkSignupKeepsActionsReachable() {
        let app = launch(largeText: true, dark: true)
        openSignup(app)
        let email = app.textFields["signup.email"]
        type("reader@example.invalid", into: email)
        XCTAssertGreaterThan(email.frame.height, 60, "This check must really use accessibility-size text")
        assertSubmitAboveKeyboard(app.buttons["signup.continue"], in: app)
        capture("auth-polish-large-dark-email", in: app)
        app.buttons["signup.continue"].tap()
        enterCodeAndUsername(app)
        typeSignupPassword(password, fieldID: "signup.password", in: app)
        assertSubmitAboveKeyboard(app.buttons["signup.continue"], in: app)
        app.buttons["signup.continue"].tap()
        typeSignupPassword(password, fieldID: "signup.confirm-password", in: app)
        assertSubmitAboveKeyboard(app.buttons["signup.create-account"], in: app)
        capture("auth-polish-large-dark-confirm", in: app)
        app.buttons["signup.create-account"].tap()
        let first = app.buttons["interests.option.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let reset = app.buttons["interests.reset"]
        let skip = app.buttons["interests.skip"]
        XCTAssertTrue(reset.isHittable)
        XCTAssertTrue(skip.isHittable)
        XCTAssertFalse(reset.frame.intersects(skip.frame))
        capture("auth-polish-large-dark-interests", in: app)
        skip.tap()
        XCTAssertTrue(app.staticTexts["auth-entry.fixture.complete"].waitForExistence(timeout: 5))
    }

    private func assertSubmitAboveKeyboard(_ button: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable)
        XCTAssertLessThanOrEqual(button.frame.maxY, app.keyboards.firstMatch.frame.minY + 1,
                                 "The primary action must stay above the software keyboard")
    }

    private func launch(failFirstSend: Bool = false, startsWithSignIn: Bool = false,
                        largeText: Bool = false, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-auth-entry"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if dark { app.launchEnvironment["CHORAI_AUTH_ENTRY_APPEARANCE"] = "dark" }
        if failFirstSend {
            app.launchEnvironment["CHORAI_AUTH_ENTRY_FAIL_FIRST_SEND"] = "1"
        }
        if startsWithSignIn {
            app.launchEnvironment["CHORAI_AUTH_ENTRY_STARTS_WITH_SIGN_IN"] = "1"
        }
        app.launch()
        return app
    }

    private func tapWelcomeLogin(_ app: XCUIApplication) {
        let login = app.buttons["welcome.login"]
        XCTAssertTrue(login.waitForExistence(timeout: 10))
        login.tap()
    }

    private func openSignup(_ app: XCUIApplication) {
        let next = app.buttons["welcome.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()

        let join = app.buttons["welcome.join-private-beta"]
        XCTAssertTrue(join.waitForExistence(timeout: 5))
        join.tap()
        enterPrivateBetaCode(app)
    }

    private func enterPrivateBetaCode(_ app: XCUIApplication) {
        type("UI-TEST-BETA", into: app.textFields["private-beta.code"])
        app.buttons["private-beta.continue"].tap()
        XCTAssertTrue(app.textFields["signup.email"].waitForExistence(timeout: 5))
    }

    private func enterCodeAndUsername(_ app: XCUIApplication, code: String = "123456", captureSteps: Bool = false) {
        type(code, into: app.textFields["signup.code"])
        if captureSteps { capture("auth-polish-signup-code", in: app) }
        app.buttons["signup.continue"].tap()
        type("TrailReader", into: app.textFields["signup.username"])
        if captureSteps { capture("auth-polish-signup-username", in: app) }
        app.buttons["signup.continue"].tap()
    }

    private func type(_ value: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(value)
    }

    private func typeSignupPassword(
        _ value: String,
        replacing previous: String = "",
        fieldID: String,
        in app: XCUIApplication
    ) {
        let secureField = app.secureTextFields[fieldID]
        XCTAssertTrue(secureField.waitForExistence(timeout: 5))
        app.buttons["Show password"].tap()

        // Use the real visibility control to bypass Simulator Password AutoFill
        // interception while checking the exact input in the same form state.
        let revealedField = app.textFields[fieldID]
        XCTAssertTrue(revealedField.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let deletePrevious = String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count)
        revealedField.typeText(deletePrevious + value)
        XCTAssertEqual(revealedField.value as? String, value)
        app.buttons["Hide password"].tap()
        XCTAssertTrue(secureField.waitForExistence(timeout: 5))
    }

    private func typeSignInPassword(
        _ value: String,
        into field: XCUIElement,
        in app: XCUIApplication
    ) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText(value)
        let expectedMask = String(repeating: "•", count: value.count)
        let inputComplete = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", expectedMask),
            object: field
        )
        XCTAssertEqual(XCTWaiter.wait(for: [inputComplete], timeout: 5), .completed,
                       "The secure field must contain every typed character before submitting")
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func replace(_ previous: String, with value: String, in field: XCUIElement) {
        type(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value, into: field)
    }
}
