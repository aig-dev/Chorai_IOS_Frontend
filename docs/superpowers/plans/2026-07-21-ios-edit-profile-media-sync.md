# iOS Edit Profile Media Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make iOS Edit Profile load, preview, and save the same avatar/background profile media as Web, while restoring reliable native back navigation.

**Architecture:** Keep `UserProfileManager` as the shared profile source and `NetworkManager` as the only HTTP boundary. Extend the existing profile DTO and multipart client, stage selected images inside `EditProfileView`, then execute avatar → background → text writes sequentially; `SettingsView` remains the owner of destination presentation and supplies the close action.

**Tech Stack:** Swift 5.9+, SwiftUI, UIKit image picker, Combine, Alamofire, XCTest/XCUITest, Swift Package Manager, Xcode 26.3, iOS 16.0+

## Global Constraints

- Work only in `Chorai_IOS_Frontend`; Web and Go are read-only references.
- Preserve unrelated in-progress Spark changes in the current checkout.
- Do not create or switch branches without explicit user instruction.
- Use `GET/PUT /api/v1/profile/me`, `PUT /api/v1/profile/me/avatar`, and `PUT /api/v1/profile/me/background` exactly.
- Multipart field names are `avatar` and `background`; encoded bytes and filename must both be JPEG.
- Media selections remain local until Save; Back performs no write.
- Keep all interactive targets at least `44 x 44` points and add stable accessibility identifiers.
- Do not log actor IDs, tokens, full profile payloads, or media URLs.
- Use red-green-refactor before production edits; build both Local and Production schemes afterward.

---

## File map

- `ArcNote/Models/UserProfileModels.swift`
  - Adds the canonical optional `background` field mapped from `background_url`.
- `ArcNote/NetworkManager.swift`
  - Owns the background multipart request and the publisher form of text update.
- `ArcNote/EditProfileView.swift`
  - Owns staged media, URL resolution, birthday display normalization, save sequencing, cover/avatar presentation, error state, and the reusable image picker.
- `ArcNote/SettingsView.swift`
  - Owns the edit destination binding and passes its explicit close action.
- `Packages/CoreFlow/Tests/CoreFlowTests/ProfileEditingSourceContractTests.swift`
  - Provides fast red-green contracts for model keys, canonical endpoints, staged media, and explicit navigation ownership.
- `ArcNoteUITests/ArcNoteUITests.swift`
  - Verifies the real Settings → Edit Profile → Back path, empty-background control, and Go-backed background persistence.

### Task 1: Lock the missing model, endpoint, and navigation contracts

**Files:**
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/ProfileEditingSourceContractTests.swift`

**Interfaces:**
- Consumes: repository Swift sources only.
- Produces: `ProfileEditingSourceContractTests`, a fast guard for exact API and UI ownership decisions.

- [ ] **Step 1: Write the failing source contracts**

Create the test file with repository-root discovery matching other CoreFlow source-contract tests, then add:

```swift
func testProfileModelMapsCanonicalBackgroundURL() throws {
    let source = try source("ArcNote/Models/UserProfileModels.swift")
    XCTAssertTrue(source.contains("let background: String?"))
    XCTAssertTrue(source.contains("case backgroundUrl = \"background_url\""))
    XCTAssertTrue(source.contains("forKey: .backgroundUrl"))
}

func testNetworkManagerUsesCanonicalBackgroundMultipartContract() throws {
    let source = try source("ArcNote/NetworkManager.swift")
    XCTAssertTrue(source.contains("func uploadProfileBackground(imageData: Data)"))
    XCTAssertTrue(source.contains("/api/v1/profile/me/background"))
    XCTAssertTrue(source.contains("withName: \"background\""))
    XCTAssertTrue(source.contains("method: .put"))
}

func testEditProfileStagesBothMediaAndResolvesRemoteResources() throws {
    let source = try source("ArcNote/EditProfileView.swift")
    XCTAssertTrue(source.contains("selectedAvatarImage"))
    XCTAssertTrue(source.contains("selectedBackgroundImage"))
    XCTAssertTrue(source.contains("APIConfiguration.resourceURLString"))
    XCTAssertTrue(source.contains("edit-profile.background"))
}

func testSettingsOwnsEditProfileDismissal() throws {
    let settings = try source("ArcNote/SettingsView.swift")
    let editor = try source("ArcNote/EditProfileView.swift")
    XCTAssertTrue(settings.contains("navigateToEditProfile = false"))
    XCTAssertTrue(settings.contains("EditProfileView("))
    XCTAssertTrue(editor.contains("edit-profile.back"))
    XCTAssertTrue(editor.contains("@Environment(\\.dismiss)"))
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter ProfileEditingSourceContractTests
```

Expected: all four tests fail because background DTO/networking, staged media,
and explicit destination closure are absent.

- [ ] **Step 3: Commit the red tests**

```bash
git add Packages/CoreFlow/Tests/CoreFlowTests/ProfileEditingSourceContractTests.swift
git commit -m "test: cover iOS profile media contracts"
```

### Task 2: Map canonical profile media and multipart writes

**Files:**
- Modify: `ArcNote/Models/UserProfileModels.swift:5-60`
- Modify: `ArcNote/NetworkManager.swift:1117-1180, 1888-1930`
- Test: `Packages/CoreFlow/Tests/CoreFlowTests/ProfileEditingSourceContractTests.swift`

**Interfaces:**
- Produces: `UserProfile.background: String?`, `NetworkManager.uploadProfileBackground(imageData:) -> AnyPublisher<AvatarUploadResponse, NetworkError>`, and `NetworkManager.updateUserProfilePublisher(username:bio:location:birthday:) -> AnyPublisher<UserProfileResponse, NetworkError>`.
- Consumes: existing `NetworkManager.request`, authorized headers, Alamofire multipart upload, and `AvatarUploadResponse`.

- [ ] **Step 1: Extend `UserProfile` with the canonical background field**

Add the property and coding key, decode it with `decodeIfPresent`, and encode it
with `encodeIfPresent`:

```swift
let background: String?

case backgroundUrl = "background_url"

background = try container.decodeIfPresent(String.self, forKey: .backgroundUrl)

try container.encodeIfPresent(background, forKey: .backgroundUrl)
```

- [ ] **Step 2: Extract the shared profile-image upload helper**

Keep the public avatar signature, add the background signature, and route both
through one private helper:

```swift
func uploadAvatar(imageData: Data) -> AnyPublisher<AvatarUploadResponse, NetworkError> {
    uploadProfileImage(
        imageData: imageData,
        endpoint: "/api/v1/profile/me/avatar",
        fieldName: "avatar",
        fileName: "avatar.jpg"
    )
}

func uploadProfileBackground(imageData: Data) -> AnyPublisher<AvatarUploadResponse, NetworkError> {
    uploadProfileImage(
        imageData: imageData,
        endpoint: "/api/v1/profile/me/background",
        fieldName: "background",
        fileName: "background.jpg"
    )
}
```

The private helper must use `method: .put`, `mimeType: "image/jpeg"`, the
authorized header, `.validate()`, and existing error conversion.

- [ ] **Step 3: Add a publisher text-update API and keep the callback adapter**

```swift
func updateUserProfilePublisher(
    username: String,
    bio: String,
    location: String,
    birthday: String
) -> AnyPublisher<UserProfileResponse, NetworkError> {
    var parameters: Parameters = [
        "username": username,
        "bio": bio,
        "city": location,
    ]
    let value = birthday.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.isEmpty { parameters["birthday"] = value }
    return request(
        endpoint: "/api/v1/profile/me",
        method: .put,
        parameters: parameters,
        responseType: UserProfileResponse.self
    )
}
```

Make the existing completion overload subscribe to this publisher so there is
only one payload implementation.

- [ ] **Step 4: Run the focused contracts and verify the model/network tests GREEN**

Run the same filtered `swift test`. Expected: model and network tests pass;
editor/navigation tests remain red.

- [ ] **Step 5: Build the Local scheme**

```bash
xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit the API slice**

```bash
git add ArcNote/Models/UserProfileModels.swift ArcNote/NetworkManager.swift
git commit -m "feat: sync iOS profile background media"
```

### Task 3: Make Back deterministic and add the cover-photo editor

**Files:**
- Modify: `ArcNote/EditProfileView.swift`
- Modify: `ArcNote/SettingsView.swift:246-254`
- Test: `Packages/CoreFlow/Tests/CoreFlowTests/ProfileEditingSourceContractTests.swift`
- Test: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: Task 2 publishers and `UserProfile.background`.
- Produces: `EditProfileView.init(loadsProfileOnAppear:onClose:)`, `edit-profile.back`, `edit-profile.background`, staged avatar/background state, and sequential `saveUserProfile()`.

- [ ] **Step 1: Add failing fixture UI tests**

Add two tests near the existing Settings fixture tests:

```swift
func testSettingsEditProfileBackReturnsToSettings() {
    app.launchArguments.append("--ui-test-settings")
    app.launch()
    tap("settings.personal-data")
    waitFor("screen.edit-profile.loaded")

    let back = waitForButton("edit-profile.back")
    XCTAssertGreaterThanOrEqual(back.frame.width, 44)
    XCTAssertGreaterThanOrEqual(back.frame.height, 44)
    back.tap()

    waitForMissing("screen.edit-profile.loaded")
    waitFor("screen.settings.loaded")
}

func testSettingsEditProfileOffersAccessibleBackgroundUpload() {
    app.launchArguments.append("--ui-test-settings")
    app.launch()
    tap("settings.personal-data")

    let background = waitForButton("edit-profile.background")
    XCTAssertEqual(background.label, "Add background photo")
    XCTAssertGreaterThanOrEqual(background.frame.height, 44)
}
```

- [ ] **Step 2: Run both tests and verify RED**

Run:

```bash
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testSettingsEditProfileBackReturnsToSettings \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testSettingsEditProfileOffersAccessibleBackgroundUpload
```

Expected: both fail because the identifiers/control and explicit closure do not
exist.

- [ ] **Step 3: Give Settings explicit destination ownership**

Use:

```swift
.navigationDestination(isPresented: $navigateToEditProfile) {
    EditProfileView(loadsProfileOnAppear: loadsProfileOnAppear) {
        navigateToEditProfile = false
    }
}
```

In `EditProfileView`, add `@Environment(\.dismiss) private var dismiss`, store
the optional closure, and use one `close()` helper:

```swift
private func close() {
    if let onClose { onClose() } else { dismiss() }
}
```

The real Back button must use `close`, a `44 x 44` frame,
`.contentShape(Rectangle())`, `.accessibilityLabel("Back")`, and
`.accessibilityIdentifier("edit-profile.back")`.

- [ ] **Step 4: Add staged media selection and canonical previews**

Replace the single selected image flag with:

```swift
private enum ProfileImageTarget: String, Identifiable {
    case avatar, background
    var id: String { rawValue }
}

@State private var selectedAvatarImage: UIImage?
@State private var selectedBackgroundImage: UIImage?
@State private var imagePickerTarget: ProfileImageTarget?
```

Use `APIConfiguration.resourceURLString(_:)` for both remote values. A selected
local image takes precedence. The background button identifier is
`edit-profile.background`; its VoiceOver label is “Add background photo” when
there is no remote/local image and “Change background photo” otherwise.

- [ ] **Step 5: Build the cover/avatar composition and scrollable form**

Create private view builders inside `EditProfileView` for the 18-point cover,
72-point overlapping avatar, and existing glass form. Use `photo.badge.plus`
for the empty state and `camera.fill` for replacement controls. Keep the full
cover surface tappable and avoid a second hidden hit target.

- [ ] **Step 6: Implement deterministic Save sequencing**

Convert selected images to JPEG only when Save starts. Build publishers from a
`Just` seed, then sequentially flat-map avatar upload, background upload, and
`updateUserProfilePublisher`. On every response update
`UserProfileManager.userProfile`; on final success clear staged state and call
`close()`. On failure keep the screen open, set `isSaving = false`, and show the
localized error.

Normalize birthday when loading:

```swift
private func editableBirthday(_ rawValue: String?) -> String {
    guard let rawValue else { return "" }
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 10 else { return trimmed }
    let end = trimmed.index(trimmed.startIndex, offsetBy: 10)
    let prefix = String(trimmed[..<end])
    return prefix.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil
        ? trimmed
        : prefix
}
```

- [ ] **Step 7: Run focused contracts and UI tests GREEN**

Run the Task 1 filtered Swift test and the two Task 3 XCUITests. Expected: all
pass with 0 failures.

- [ ] **Step 8: Commit the interaction slice**

```bash
git add ArcNote/EditProfileView.swift ArcNote/SettingsView.swift ArcNoteUITests/ArcNoteUITests.swift
git commit -m "fix: restore iOS profile editing flow"
```

### Task 4: Prove Go background persistence and finish visual QA

**Files:**
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`
- Create: `docs/qa/ios-edit-profile-media-sync.md`

**Interfaces:**
- Consumes: a configured local smoke session, canonical profile/background routes, system photo fixture utilities, and Task 3 UI.
- Produces: a reversible Go-backed background upload test and final QA record.

- [ ] **Step 1: Add a failing live background-picker test**

Mirror the existing avatar picker test: snapshot the current profile and skip
before mutation unless it has a non-empty restorable `background_url`. Launch
an authenticated app, open Settings → Personal Data, tap
`edit-profile.background`, select the imported JPEG, tap Save, and poll
`GET /api/v1/profile/me` until `background_url` changes. Restore a non-empty
prior URL with JSON `PUT /api/v1/profile/me/background` in `defer`.

- [ ] **Step 2: Run the live test and verify RED before the Task 3 implementation, then GREEN afterward**

```bash
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testSettingsBackgroundPickerUploadsGoProfileBackground
```

Expected final result: 1 test, 0 failures; if smoke credentials or the backend
are unavailable, record the exact prerequisite instead of claiming the route is
verified.

- [ ] **Step 3: Re-run existing profile regressions**

Run the text save, avatar picker, new background picker, Back, and empty-state
tests together. Expected: 5 tests, 0 failures.

- [ ] **Step 4: Build both schemes freshly**

```bash
xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ArcNote.xcodeproj -scheme 'ArcNote Production' -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: both end with `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Inspect the Simulator and record evidence**

Capture empty and populated background states at the reference phone viewport.
Verify image crop, cover/avatar overlap, form spacing, back hit area, Save/error
states, Reduce Transparency, and accessibility labels. Record commands,
screenshots, and any unverified prerequisite in
`docs/qa/ios-edit-profile-media-sync.md`.

- [ ] **Step 6: Run whitespace and scope checks**

```bash
git diff --check
git status --short
git diff -- ArcNote/Models/UserProfileModels.swift ArcNote/NetworkManager.swift ArcNote/EditProfileView.swift ArcNote/SettingsView.swift ArcNoteUITests/ArcNoteUITests.swift
```

Confirm no unrelated Spark diff is staged or modified by this work.

- [ ] **Step 7: Commit verification artifacts**

```bash
git add ArcNoteUITests/ArcNoteUITests.swift docs/qa/ios-edit-profile-media-sync.md
git commit -m "test: verify iOS profile media editing"
```
