import XCTest
@testable import CoreFlow

final class AuthenticationErrorsTests: XCTestCase {
    func testAPIErrorPayloadDecodesFlatGoErrorCode() throws {
        let data = Data(
            #"{"success":false,"error_code":"UNAUTHORIZED","message":"invalid credentials"}"#.utf8
        )

        let payload = try XCTUnwrap(
            APIErrorPayload.decode(from: data, statusCode: 401)
        )

        XCTAssertEqual(payload.code, "UNAUTHORIZED")
        XCTAssertEqual(payload.message, "invalid credentials")
    }

    func testAPIErrorPayloadKeepsFlatFieldsWhenLegacyErrorHasAnotherShape() throws {
        let data = Data(
            #"{"success":false,"error":"unauthorized","error_code":"UNAUTHORIZED","message":"invalid credentials"}"#.utf8
        )

        let payload = try XCTUnwrap(
            APIErrorPayload.decode(from: data, statusCode: 401)
        )

        XCTAssertEqual(payload.code, "UNAUTHORIZED")
        XCTAssertEqual(payload.message, "invalid credentials")
    }

    func testAPIErrorPayloadRecognizesLegacySuccessfulHTTPErrorEnvelope() throws {
        let data = Data(
            #"{"success":false,"error_code":"PRODUCT_ACCESS_REQUIRED","message":"product access code is required or invalid"}"#.utf8
        )

        let payload = try XCTUnwrap(
            APIErrorPayload.decode(from: data, statusCode: 200)
        )

        XCTAssertEqual(payload.code, "PRODUCT_ACCESS_REQUIRED")
    }

    func testAPIErrorPayloadDecodesNestedErrorEnvelope() throws {
        let data = Data(
            #"{"error":{"code":"FORBIDDEN","message":"account is disabled"}}"#.utf8
        )

        let payload = try XCTUnwrap(
            APIErrorPayload.decode(from: data, statusCode: 403)
        )

        XCTAssertEqual(payload.code, "FORBIDDEN")
        XCTAssertEqual(payload.message, "account is disabled")
    }

    func testAPIErrorPayloadDoesNotMisclassifySuccessfulAuthentication() {
        let data = Data(
            #"{"success":true,"message":"Login successful","data":{"token":"token-1"}}"#.utf8
        )

        XCTAssertNil(APIErrorPayload.decode(from: data, statusCode: 200))
    }

    func testAPIErrorPayloadDoesNotTreatSuccessfulVerificationCodeAsError() {
        let data = Data(
            #"{"success":true,"message":"Verification code sent","code":"123456"}"#.utf8
        )

        XCTAssertNil(APIErrorPayload.decode(from: data, statusCode: 200))
    }

    func testSignInPresentationMapsKnownFailureReasons() {
        XCTAssertEqual(
            AuthenticationErrorPresentation.signInMessage(
                statusCode: 401,
                errorCode: "UNAUTHORIZED"
            ),
            "Email or password is incorrect."
        )
        XCTAssertEqual(
            AuthenticationErrorPresentation.signInMessage(
                statusCode: 403,
                errorCode: "PRODUCT_ACCESS_REQUIRED"
            ),
            "Private Beta access is required. Enter a Product Access Code to continue."
        )
        XCTAssertEqual(
            AuthenticationErrorPresentation.signInMessage(
                statusCode: 403,
                errorCode: "FORBIDDEN"
            ),
            "This account is disabled. Please contact support."
        )
        XCTAssertEqual(
            AuthenticationErrorPresentation.signInMessage(
                statusCode: 404,
                errorCode: nil
            ),
            "Email or password is incorrect."
        )
        XCTAssertEqual(
            AuthenticationErrorPresentation.signInMessage(
                statusCode: 429,
                errorCode: "RATE_LIMIT_EXCEEDED"
            ),
            "Too many sign-in attempts. Please wait a moment and try again."
        )
        XCTAssertEqual(
            AuthenticationErrorPresentation.signInMessage(
                statusCode: 503,
                errorCode: "SERVICE_UNAVAILABLE"
            ),
            "Sign-in is temporarily unavailable. Please try again later."
        )
    }

    func testRegistrationPresentationExplainsPrivateBetaRequirement() {
        XCTAssertEqual(
            AuthenticationErrorPresentation.registrationMessage(
                statusCode: 403,
                errorCode: "PRODUCT_ACCESS_REQUIRED"
            ),
            "Private Beta access is required. Enter a Product Access Code to continue."
        )
    }

    func testVerificationCodePresentationDoesNotExposeServerText() {
        XCTAssertEqual(
            AuthenticationErrorPresentation.verificationCodeMessage(
                statusCode: 400,
                errorCode: "VALIDATION_ERROR"
            ),
            "Please enter a valid email address."
        )
        XCTAssertEqual(
            AuthenticationErrorPresentation.verificationCodeMessage(
                statusCode: 429,
                errorCode: "RATE_LIMIT_EXCEEDED"
            ),
            "Too many verification code requests. Please wait a moment and try again."
        )
        XCTAssertEqual(
            AuthenticationErrorPresentation.verificationCodeMessage(
                statusCode: 503,
                errorCode: "SERVICE_UNAVAILABLE"
            ),
            "Verification code service is temporarily unavailable. Please try again later."
        )
    }
}
