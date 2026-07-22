# iOS Sidebar Profile and Credit Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Synchronize the native iOS sidebar with Personal Profile media, keep all drawer content inside one animated layer, and make every native `SYN` value equal only the ordinary `credit` balance.

**Architecture:** Keep `UserProfileManager.shared` as the single profile and balance source. Add a semantic `synBalance`, render the sidebar cover/avatar from `userProfile`, and clip the complete fixed-width drawer before applying its horizontal offset. Lock the decisions with a focused CoreFlow source-contract test, then validate both app schemes and the live simulator presentation.

**Tech Stack:** Swift 5.9+, SwiftUI, Combine, XCTest source-contract tests, Swift Package Manager, Xcode 26.3, iOS 16.0+

## Global Constraints

- Work only in `Chorai_IOS_Frontend`; do not modify Web or Go.
- Preserve and do not stage the unrelated in-progress edits in `ArcNote/CommentPopupView.swift`, `ArcNote/CoreFlow/CoreShellViews.swift`, `ArcNoteUITests/ArcNoteUITests.swift`, and `Packages/CoreFlow/Tests/CoreFlowTests/CoreTabBarSourceContractTests.swift`.
- The sidebar avatar and background must come from `UserProfileManager.userProfile`; bundled `avatar` and `side_bg` assets remain fallbacks.
- `SYN` means only `credit_tier == "credit"`; never add `premium_credit` or unknown tiers.
- The complete drawer must be framed and clipped before its open/closed offset is applied.
- Preserve existing navigation destinations, unread indication, adaptive width, loading placeholders, and network endpoints.
- Use red-green-refactor before production changes.
- The user selected inline autonomous execution; do not pause for additional design approval.

---

## File Map

- `ArcNote/Models/UserProfileModels.swift`
  - Owns `synBalance` and continues to expose `regularCreditTotal` for the Settings row.
- `ArcNote/SideMenuView.swift`
  - Renders the current profile cover/avatar, displays `synBalance`, and owns the clipped moving drawer composition.
- `ArcNote/MyProfileView.swift`
  - Uses the same `synBalance` for its existing `SYN` label.
- `Packages/CoreFlow/Tests/CoreFlowTests/SidebarProfileCreditSourceContractTests.swift`
  - Guards ordinary-credit semantics, shared profile media, fallbacks, and clip-before-offset ordering.

### Task 1: Lock and implement ordinary-credit SYN semantics

**Files:**
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/SidebarProfileCreditSourceContractTests.swift`
- Modify: `ArcNote/Models/UserProfileModels.swift:106-114`
- Modify: `ArcNote/SideMenuView.swift:68-78`
- Modify: `ArcNote/MyProfileView.swift:130-143`

**Interfaces:**
- Consumes: `UserProfileManager.creditBalance: [CreditBalanceData]` and `CreditBalanceData.creditTier`.
- Produces: `UserProfileManager.synBalance: Int`, used only where the UI label is `SYN`.

- [ ] **Step 1: Write the failing source contract**

Create the test file with this initial content:

```swift
import Foundation
import XCTest

final class SidebarProfileCreditSourceContractTests: XCTestCase {
    func testSynUsesOnlyOrdinaryCreditsAcrossProfileSurfaces() throws {
        let model = try source(at: "ArcNote/Models/UserProfileModels.swift")
        let sidebar = try source(at: "ArcNote/SideMenuView.swift")
        let profile = try source(at: "ArcNote/MyProfileView.swift")

        let synImplementation = """
    var synBalance: Int {
        creditBalance
            .filter { $0.creditTier == "credit" }
            .reduce(0) { $0 + $1.balance }
    }
"""
        XCTAssertTrue(model.contains(synImplementation))
        XCTAssertTrue(sidebar.contains("userProfileManager.synBalance"))
        XCTAssertTrue(profile.contains("userProfileManager.synBalance"))
        XCTAssertFalse(sidebar.contains("userProfileManager.creditTotal"))
        XCTAssertFalse(profile.contains("userProfileManager.creditTotal"))
    }

    private func source(at path: String) throws -> String {
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
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --package-path Packages/CoreFlow \
  --filter SidebarProfileCreditSourceContractTests.testSynUsesOnlyOrdinaryCreditsAcrossProfileSurfaces
```

Expected: FAIL because `synBalance` does not exist and both native `SYN`
surfaces still use `creditTotal`, which includes premium credits.

- [ ] **Step 3: Add the semantic balance property**

Replace `creditTotal` in `UserProfileManager` with:

```swift
var synBalance: Int {
    creditBalance
        .filter { $0.creditTier == "credit" }
        .reduce(0) { $0 + $1.balance }
}
```

Keep the existing `regularCreditTotal` property because `SettingsView` uses
it for a row explicitly labelled `Credits`.

- [ ] **Step 4: Point both SYN labels at the semantic property**

In `SideMenuView` use:

```swift
Text(
    userProfileManager.isCreditLoading
        ? "--"
        : "\(userProfileManager.synBalance)"
)
```

In `MyProfileView` use:

```swift
Text("\(userProfileManager.synBalance)")
```

- [ ] **Step 5: Run the focused test and verify GREEN**

Run the Step 2 command again. Expected: PASS.

Also run:

```bash
rg -n 'creditTotal|synBalance|regularCreditTotal' ArcNote --glob '*.swift'
```

Expected: `synBalance` appears in the model and both `SYN` surfaces;
`regularCreditTotal` remains in the model and Settings; `creditTotal` has no
matches.

- [ ] **Step 6: Commit the ordinary-credit slice**

```bash
git add ArcNote/Models/UserProfileModels.swift \
  ArcNote/SideMenuView.swift \
  ArcNote/MyProfileView.swift \
  Packages/CoreFlow/Tests/CoreFlowTests/SidebarProfileCreditSourceContractTests.swift
git commit -m "fix: align iOS SYN with credits"
```

### Task 2: Synchronize sidebar media and enforce the drawer layer boundary

**Files:**
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/SidebarProfileCreditSourceContractTests.swift`
- Modify: `ArcNote/SideMenuView.swift:34-43,175-214,254-260`

**Interfaces:**
- Consumes: `UserProfile.background`, `UserProfile.avatar`, `APIConfiguration.resourceURLString(_:)`, and `adaptiveLayout.drawerWidth`.
- Produces: `profileBackground`, `fallbackProfileBackground`, `profileResourceURL(_:)`, and a clip-before-offset drawer modifier sequence.

- [ ] **Step 1: Add the failing media and composition contract**

Add this method above the helper methods in
`SidebarProfileCreditSourceContractTests`:

```swift
func testSidebarUsesProfileMediaAndClipsWholeDrawerBeforeOffset() throws {
    let sidebar = try source(at: "ArcNote/SideMenuView.swift")

    XCTAssertTrue(sidebar.contains("private var profileBackground: some View"))
    XCTAssertTrue(sidebar.contains("profileResourceURL("))
    XCTAssertTrue(
        sidebar.contains("userProfileManager.userProfile?.background")
    )
    XCTAssertTrue(sidebar.contains("userProfileManager.userProfile?.avatar"))
    XCTAssertTrue(sidebar.contains("APIConfiguration.resourceURLString"))
    XCTAssertTrue(sidebar.contains("Image(\"side_bg\")"))
    XCTAssertTrue(sidebar.contains("Image(\"avatar\")"))

    let clipBeforeOffset = """
                .frame(width: adaptiveLayout.drawerWidth)
                .ignoresSafeArea()
                .clipped()
                .offset(x: isPresented ? 0 : -adaptiveLayout.drawerWidth)
"""
    XCTAssertTrue(sidebar.contains(clipBeforeOffset))
}
```

- [ ] **Step 2: Run the new contract and verify RED**

Run:

```bash
swift test --package-path Packages/CoreFlow \
  --filter SidebarProfileCreditSourceContractTests.testSidebarUsesProfileMediaAndClipsWholeDrawerBeforeOffset
```

Expected: FAIL because the cover is still the static asset, the avatar does not
use the shared URL helper, and the moving drawer is not clipped.

- [ ] **Step 3: Replace the static cover with the shared profile background**

Replace the top-level static `Image("side_bg")` inside the drawer ZStack with:

```swift
profileBackground
```

Add these private members inside `SideMenuView` before
`refreshNotificationIndicator()`:

```swift
private var profileBackgroundHeight: CGFloat {
    adaptiveLayout.drawerWidth * (495.0 / 762.0)
}

private var profileBackground: some View {
    Group {
        if let backgroundURL = profileResourceURL(
            userProfileManager.userProfile?.background
        ) {
            AsyncImage(url: backgroundURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .empty, .failure:
                    fallbackProfileBackground
                @unknown default:
                    fallbackProfileBackground
                }
            }
        } else {
            fallbackProfileBackground
        }
    }
    .frame(
        width: adaptiveLayout.drawerWidth,
        height: profileBackgroundHeight
    )
    .clipped()
    .overlay {
        LinearGradient(
            colors: [.clear, .black.opacity(0.28)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private var fallbackProfileBackground: some View {
    Image("side_bg")
        .resizable()
        .aspectRatio(contentMode: .fill)
}

private func profileResourceURL(_ rawValue: String?) -> URL? {
    guard let rawValue else { return nil }
    let trimmedValue = rawValue.trimmingCharacters(
        in: .whitespacesAndNewlines
    )
    guard !trimmedValue.isEmpty else { return nil }
    return URL(string: APIConfiguration.resourceURLString(trimmedValue))
}
```

The ratio `495 / 762` preserves the current bundled cover geometry and avoids
layout movement when a remote image replaces the fallback.

- [ ] **Step 4: Resolve the avatar through the same helper**

Replace the avatar URL branch with:

```swift
if let avatarURL = profileResourceURL(
    userProfileManager.userProfile?.avatar
) {
    AsyncImage(url: avatarURL) { image in
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
    } placeholder: {
        Image("avatar")
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
} else {
    Image("avatar")
        .resizable()
        .aspectRatio(contentMode: .fill)
}
```

- [ ] **Step 5: Clip the complete drawer before offsetting it**

Make the moving drawer modifier sequence exactly:

```swift
.frame(width: adaptiveLayout.drawerWidth)
.ignoresSafeArea()
.clipped()
.offset(x: isPresented ? 0 : -adaptiveLayout.drawerWidth)
.accessibilityIdentifier("adaptive-layout.drawer")
```

This clips any intrinsic HStack/text overflow at the drawer boundary while
preserving the existing animation and navigation state.

- [ ] **Step 6: Run the focused contracts and verify GREEN**

Run:

```bash
swift test --package-path Packages/CoreFlow \
  --filter SidebarProfileCreditSourceContractTests
```

Expected: both tests PASS.

- [ ] **Step 7: Build the Local scheme**

Run:

```bash
xcodebuild -project ArcNote.xcodeproj \
  -scheme ArcNote \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit the media and composition slice**

```bash
git add ArcNote/SideMenuView.swift \
  Packages/CoreFlow/Tests/CoreFlowTests/SidebarProfileCreditSourceContractTests.swift
git commit -m "fix: synchronize iOS sidebar profile media"
```

### Task 3: Complete regression and simulator verification

**Files:**
- Verify only; no planned production edits.

**Interfaces:**
- Consumes: the Task 1 and Task 2 behavior.
- Produces: test, build, and visual evidence for every acceptance criterion.

- [ ] **Step 1: Run the complete focused source-contract suite**

```bash
swift test --package-path Packages/CoreFlow \
  --filter SidebarProfileCreditSourceContractTests
```

Expected: PASS with two tests and zero failures.

- [ ] **Step 2: Run the complete CoreFlow test suite**

```bash
swift test --package-path Packages/CoreFlow
```

Expected: all tests PASS. If an unrelated dirty-worktree test fails, record the
exact failing test and separately prove that the focused sidebar suite passes;
do not modify unrelated user work.

- [ ] **Step 3: Build both app configurations**

```bash
xcodebuild -project ArcNote.xcodeproj \
  -scheme ArcNote \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -project ArcNote.xcodeproj \
  -scheme 'ArcNote Production' \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Expected: both commands end with `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Inspect the live drawer on the booted iPhone 17 Pro**

Use the already booted simulator `43E6164C-1F4B-47E4-9B65-D154C7281A56`.
Launch the Local app in its existing authenticated state, open the sidebar, and
capture the fully open state:

```bash
xcrun simctl io 43E6164C-1F4B-47E4-9B65-D154C7281A56 screenshot \
  /tmp/chorai-ios-sidebar-open.png
```

Visually confirm:

- the cover and avatar match Personal Profile;
- no statistics are visible outside the drawer while opening or closing;
- the displayed SYN equals the ordinary Credits value and excludes Premium;
- username, statistics, and navigation remain readable over the selected
  background.

- [ ] **Step 5: Audit the final diff and worktree ownership**

```bash
git diff HEAD~2 -- \
  ArcNote/Models/UserProfileModels.swift \
  ArcNote/SideMenuView.swift \
  ArcNote/MyProfileView.swift \
  Packages/CoreFlow/Tests/CoreFlowTests/SidebarProfileCreditSourceContractTests.swift
git status --short
```

Expected: only the four planned files appear in the sidebar implementation
commits; the pre-existing unrelated modified/untracked files remain untouched.
