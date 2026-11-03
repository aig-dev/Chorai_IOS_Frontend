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
        let next = app.buttons["signup.continue"]
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isHittable, "Continue must be reachable with the email keyboard open")
        next.tap()
        XCTAssertTrue(app.staticTexts["signup.error"].waitForExistence(timeout: 5))
        next.tap()

        enterCodeAndUsername(app)

        typeSignupPassword(password, fieldID: "signup.password", in: app)
        next.tap()
        typeSignupPassword(wrongPassword, fieldID: "signup.confirm-password", in: app)
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

    private func launch(failFirstSend: Bool = false, startsWithSignIn: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-auth-entry"]
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

    private func enterCodeAndUsername(_ app: XCUIApplication, code: String = "123456") {
        type(code, into: app.textFields["signup.code"])
        app.buttons["signup.continue"].tap()
        type("TrailReader", into: app.textFields["signup.username"])
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
