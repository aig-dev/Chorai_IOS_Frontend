import Foundation
import XCTest

final class ProfileEditingSourceContractTests: XCTestCase {

    func testBothProfilePickerLaunchersAndCallbacksRespectSaveLock() throws {
        let source = try source("ArcNote/EditProfileView.swift")
        for (start, end) in [("private var profileMediaEditor", "private var backgroundContent"),
                             ("private var avatarButton", "private var avatarContent")] {
            let lower = try XCTUnwrap(source.range(of: start)).lowerBound
            let upper = try XCTUnwrap(source.range(of: end, range: lower..<source.endIndex)).lowerBound
            XCTAssertTrue(source[lower..<upper].contains(".disabled(isSaving)"))
        }
        XCTAssertTrue(source.contains("imageSelectionBinding($selectedAvatarImage, isSaving: { isSaving })"))
        XCTAssertTrue(source.contains("imageSelectionBinding($selectedBackgroundImage, isSaving: { isSaving })"))
    }
    func testProfileModelMapsCanonicalBackgroundURL() throws {
        let source = try source("ArcNote/Models/UserProfileModels.swift")

        XCTAssertTrue(source.contains("let background: String?"))
        XCTAssertTrue(source.contains("case backgroundUrl = \"background_url\""))
        XCTAssertTrue(source.contains("forKey: .backgroundUrl"))
    }

    func testNetworkManagerUsesCanonicalBackgroundMultipartContract() throws {
        let source = try source("ArcNote/NetworkManager.swift")

        XCTAssertTrue(
            source.contains(
                "func uploadProfileBackground(imageData: Data)"
            )
        )
        XCTAssertTrue(source.contains("/api/v1/profile/me/background"))
        XCTAssertTrue(source.contains("fieldName: \"background\""))
        XCTAssertTrue(source.contains("withName: fieldName"))
        XCTAssertTrue(source.contains("method: .put"))
    }

    func testEditProfileStagesBothMediaAndResolvesRemoteResources() throws {
        let source = try source("ArcNote/EditProfileView.swift")

        XCTAssertTrue(source.contains("selectedAvatarImage"))
        XCTAssertTrue(source.contains("selectedBackgroundImage"))
        XCTAssertTrue(source.contains("APIConfiguration.resourceURLString"))
        XCTAssertTrue(source.contains("edit-profile.background"))
        XCTAssertTrue(source.contains("uploadProfileBackground"))
    }

    func testEditProfileNormalizesGoBirthdayForEditing() throws {
        let source = try source("ArcNote/EditProfileView.swift")

        XCTAssertTrue(source.contains("private func editableBirthday"))
        XCTAssertTrue(source.contains("^\\d{4}-\\d{2}-\\d{2}$"))
        XCTAssertTrue(source.contains("birthday = editableBirthday(profile.birthday)"))
    }

    func testSettingsOwnsEditProfileDismissal() throws {
        let settings = try source("ArcNote/SettingsView.swift")
        let editor = try source("ArcNote/EditProfileView.swift")

        XCTAssertTrue(settings.contains("navigateToEditProfile = false"))
        XCTAssertTrue(settings.contains("EditProfileView("))
        XCTAssertTrue(editor.contains("edit-profile.back"))
        XCTAssertTrue(editor.contains("@Environment(\\.dismiss)"))
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
