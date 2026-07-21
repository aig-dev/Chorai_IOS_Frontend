# iOS Flow Glass Card Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render valid Flow author avatars and replace the flat one-layer Flow deck with the approved dark-violet native-glass foreground card plus two truthful rear surfaces.

**Architecture:** Keep `FlowDeckStore`, `FlowCard`, gestures, and actions unchanged. Resolve avatar resources at the existing app-view boundary, then introduce private SwiftUI glass-surface and backplate primitives in `FlowViews.swift`; `FlowDeckView` derives at most two decorative depths from its existing card array.

**Tech Stack:** Swift 5.9+, SwiftUI, Combine, XCTest, Swift Package Manager, Xcode 26.3, iOS 16.0+

## Global Constraints

- Work only in `Chorai_IOS_Frontend`; do not modify web or backend code.
- Preserve the current Flow content, Spark action, tags, engagement controls, navigation, and swipe decisions.
- Keep `FlowDeckStore` and `FlowCard` as the only deck/card data sources.
- Keep effective tap targets at least `44 x 44` points.
- Render at most two rear surfaces, and only when corresponding future cards exist.
- Rear surfaces must contain no card content, accept no hit testing, and remain hidden from VoiceOver.
- Preserve Reduce Motion; provide opaque Reduce Transparency and stronger Increased Contrast treatments.
- Do not add dependencies, endpoint literals, sensitive URL logging, or a second avatar source of truth.
- Use focused red-green cycles before production edits, then verify the full CoreFlow suite and both app schemes.

---

## File map

- `ArcNote/CoreFlow/FlowViews.swift`
  - Owns Flow avatar resolution and presentation.
  - Owns the private glass-surface/backplate primitives and deck composition.
- `Packages/CoreFlow/Tests/CoreFlowTests/FlowCardPresentationSourceContractTests.swift`
  - Locks avatar canonicalization, Material/fallback behavior, truthful two-layer composition, and existing Flow presentation invariants.
- `ArcNoteUITests/ArcNoteUITests.swift`
  - Creates a reversible Go-backed relative-avatar fixture with three fresh public cards and keeps the final Simulator capture.
- `docs/qa/ios-flow-glass-card-stack-design-qa.md`
  - Records the final reference/capture comparison and verification evidence.

### Task 1: Resolve relative Flow avatar resources

**Files:**
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/FlowCardPresentationSourceContractTests.swift:4-63`
- Modify: `ArcNote/CoreFlow/FlowViews.swift:227-243`

**Interfaces:**
- Consumes: `FlowAuthor.avatarURL: String?` and `APIConfiguration.resourceURLString(_:) -> String`.
- Produces: `FlowCardView.resolvedAvatarURL: URL?`, a 32-point circular `authorAvatar`, and `avatarPlaceholder`.

- [ ] **Step 1: Add the failing avatar source contract**

Add this test beside the existing body and engagement tests:

```swift
func testFlowAvatarCanonicalizesRelativeResourceURLBeforeLoading() throws {
    let source = try flowCardSource()

    XCTAssertTrue(
        source.contains("APIConfiguration.resourceURLString(rawURL)"),
        "Flow must resolve backend-relative avatar paths against the active API environment"
    )
    XCTAssertTrue(
        source.contains("AsyncImage(url: resolvedAvatarURL)"),
        "AsyncImage must receive the canonical URL"
    )
    XCTAssertTrue(
        source.contains(".frame(width: 32, height: 32)"),
        "The approved Flow avatar is a stable 32-point circle"
    )
    XCTAssertTrue(
        source.contains("case .failure:"),
        "A failed request must retain the quiet avatar fallback"
    )
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter FlowCardPresentationSourceContractTests
```

Expected: `testFlowAvatarCanonicalizesRelativeResourceURLBeforeLoading` fails because `FlowCardView` still passes the raw value to `URL(string:)`; the two pre-existing tests pass.

- [ ] **Step 3: Replace the raw avatar block with canonical resolution**

Replace the existing `authorAvatar` property with these three complete members:

```swift
private var resolvedAvatarURL: URL? {
    guard let candidate = card.author?.avatarURL else { return nil }
    let rawURL = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawURL.isEmpty else { return nil }

    return URL(string: APIConfiguration.resourceURLString(rawURL))
}

@ViewBuilder
private var authorAvatar: some View {
    Group {
        if let resolvedAvatarURL {
            AsyncImage(url: resolvedAvatarURL) { phase in
                switch phase {
                case .empty:
                    avatarPlaceholder
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    avatarPlaceholder
                @unknown default:
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }
    .frame(width: 32, height: 32)
    .clipShape(Circle())
}

private var avatarPlaceholder: some View {
    Circle()
        .fill(Color.white.opacity(0.1))
        .overlay(
            Image(systemName: "person.fill")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.72))
        )
}
```

Do not change the surrounding author button, label, disabled state, or action.

- [ ] **Step 4: Run the focused contract and verify GREEN**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter FlowCardPresentationSourceContractTests
```

Expected: 3 tests pass with 0 failures.

- [ ] **Step 5: Compile the app target**

Run:

```bash
xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit the avatar fix**

```bash
git add ArcNote/CoreFlow/FlowViews.swift Packages/CoreFlow/Tests/CoreFlowTests/FlowCardPresentationSourceContractTests.swift
git commit -m "fix: resolve Flow avatar resource URLs"
```

### Task 2: Build the native glass surface and truthful rear stack

**Files:**
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/FlowCardPresentationSourceContractTests.swift`
- Modify: `ArcNote/CoreFlow/FlowViews.swift:5-14, 76-78, 209-225, 404-438`

**Interfaces:**
- Consumes: `ZenVisualTokens.cardRadius`, SwiftUI `Material`, accessibility environment values, and `FlowDeckStore.cards`.
- Produces: private `FlowGlassLayer`, `FlowGlassSurface`, `FlowDeckBackplate`, `FlowDeckView.backplateDepths: [Int]`, and a foreground `FlowGlassSurface(layer: .foreground)`.

- [ ] **Step 1: Add failing glass and deck contracts**

Add these tests:

```swift
func testFlowUsesTintedNativeGlassWithAccessibilityFallbacks() throws {
    let source = try flowViewSource()

    XCTAssertTrue(source.contains("private struct FlowGlassSurface: View"))
    XCTAssertTrue(source.contains("shape.fill(.ultraThinMaterial)"))
    XCTAssertTrue(source.contains("if !reduceTransparency"))
    XCTAssertTrue(source.contains("ZenVisualTokens.opaqueCardFill"))
    XCTAssertTrue(source.contains("FlowGlassSurface(layer: .foreground)"))
    XCTAssertTrue(source.contains("contrast == .increased"))
}

func testFlowDeckUsesAtMostTwoTruthfulNoninteractiveBackplates() throws {
    let source = try flowViewSource()

    XCTAssertTrue(source.contains("min(2, max(0, store.cards.count - 1))"))
    XCTAssertTrue(source.contains("ForEach(backplateDepths.reversed(), id: \\.self)"))
    XCTAssertTrue(source.contains("FlowDeckBackplate(depth: depth)"))
    XCTAssertTrue(source.contains(".scaleEffect(depth == 1 ? 0.972 : 0.944)"))
    XCTAssertTrue(source.contains(".offset(x: depth == 1 ? 7 : 14, y: depth == 1 ? 14 : 28)"))
    XCTAssertTrue(source.contains(".allowsHitTesting(false)"))
    XCTAssertTrue(source.contains(".accessibilityHidden(true)"))
}
```

Refactor the existing source reader so both the whole-file and isolated-card checks use one implementation:

```swift
private func flowCardSource() throws -> String {
    let source = try flowViewSource()
    guard let start = source.range(of: "struct FlowCardView: View"),
          let end = source.range(of: "struct FlowDeckView: View") else {
        XCTFail("Unable to isolate FlowCardView source")
        return ""
    }
    return String(source[start.lowerBound..<end.lowerBound])
}

private func flowViewSource() throws -> String {
    try String(
        contentsOf: Self.repositoryRoot
            .appendingPathComponent("ArcNote/CoreFlow/FlowViews.swift"),
        encoding: .utf8
    )
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter FlowCardPresentationSourceContractTests
```

Expected: the two new tests fail because the current card uses a translucent color fill and the deck renders only one flat rear rectangle.

- [ ] **Step 3: Extend the shared Flow visual tokens**

Add the two tokens to `ZenVisualTokens`:

```swift
static let opaqueCardFill = Color(red: 0.09, green: 0.075, blue: 0.15)
static let glassTint = Color(red: 0.105, green: 0.065, blue: 0.18)
```

Keep `cardFill` because `FlowSkeletonView` still consumes it.

- [ ] **Step 4: Add the glass layer and surface primitives**

Insert these private declarations after `ZenVisualTokens`:

```swift
private enum FlowGlassLayer {
    case foreground
    case rear(depth: Int)

    var tintOpacity: Double {
        switch self {
        case .foreground:
            return 0.64
        case .rear(let depth):
            return depth == 1 ? 0.72 : 0.78
        }
    }

    var edgeOpacity: Double {
        switch self {
        case .foreground:
            return 0.46
        case .rear(let depth):
            return depth == 1 ? 0.28 : 0.2
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .foreground:
            return 0.3
        case .rear(let depth):
            return depth == 1 ? 0.2 : 0.14
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .foreground:
            return 18
        case .rear(let depth):
            return depth == 1 ? 14 : 10
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .foreground:
            return 10
        case .rear(let depth):
            return depth == 1 ? 8 : 6
        }
    }
}

private struct FlowGlassSurface: View {
    let layer: FlowGlassLayer

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: ZenVisualTokens.cardRadius,
            style: .continuous
        )
    }

    var body: some View {
        ZStack {
            shape.fill(
                reduceTransparency
                    ? ZenVisualTokens.opaqueCardFill
                    : Color.clear
            )

            if !reduceTransparency {
                shape.fill(.ultraThinMaterial)
            }

            shape.fill(
                ZenVisualTokens.glassTint.opacity(layer.tintOpacity)
            )
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                edgeGradient,
                lineWidth: contrast == .increased ? 1.5 : 1
            )
        )
        .shadow(
            color: Color.black.opacity(layer.shadowOpacity),
            radius: layer.shadowRadius,
            x: 0,
            y: layer.shadowY
        )
    }

    private var edgeGradient: LinearGradient {
        let contrastBoost = contrast == .increased ? 1.35 : 1
        let opacity = min(0.78, layer.edgeOpacity * contrastBoost)

        return LinearGradient(
            colors: [
                Color.white.opacity(opacity),
                ZenVisualTokens.accent.opacity(opacity * 0.48),
                Color.white.opacity(opacity * 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct FlowDeckBackplate: View {
    let depth: Int

    var body: some View {
        FlowGlassSurface(layer: .rear(depth: depth))
            .scaleEffect(depth == 1 ? 0.972 : 0.944)
            .offset(x: depth == 1 ? 7 : 14, y: depth == 1 ? 14 : 28)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
```

- [ ] **Step 5: Give the foreground card the shared glass surface**

Remove the now-unused `accessibilityReduceTransparency` and `colorSchemeContrast` environment properties from `FlowCardView`; keep `accessibilityReduceMotion`.

Replace `cardBackground` with:

```swift
private var cardBackground: some View {
    FlowGlassSurface(layer: .foreground)
}
```

- [ ] **Step 6: Replace the flat rear rectangle with two truthful depths**

Add this computed property inside `FlowDeckView`:

```swift
private var backplateDepths: [Int] {
    let count = min(2, max(0, store.cards.count - 1))
    guard count > 0 else { return [] }
    return Array(1...count)
}
```

Replace the current `if store.nextCard != nil` block inside `loadedDeck` with:

```swift
ForEach(backplateDepths.reversed(), id: \.self) { depth in
    FlowDeckBackplate(depth: depth)
}
```

Keep `FlowCardView`, its callbacks, `.id(card.id)`, and the empty state unchanged.

- [ ] **Step 7: Run focused tests and verify GREEN**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter FlowCardPresentationSourceContractTests
```

Expected: 5 tests pass with 0 failures.

- [ ] **Step 8: Compile the Local scheme**

Run:

```bash
xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit the glass stack**

```bash
git add ArcNote/CoreFlow/FlowViews.swift Packages/CoreFlow/Tests/CoreFlowTests/FlowCardPresentationSourceContractTests.swift
git commit -m "feat: add Flow glass card stack"
```

### Task 3: Run regression, scheme, and live Flow verification

**Files:**
- Verify: `Packages/CoreFlow`
- Verify: `ArcNote.xcodeproj`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: the Task 1 avatar resolver, Task 2 glass primitives, the Local Go stack, existing profile/card smoke helpers, and `edit-profile.avatar-smoke-upload`.
- Produces: `testFlowGlassDeckRendersUploadedRelativeAvatarAndThreeCardStack()`, fresh unit/build/UI result bundles, and a kept `flow-glass-avatar-stack` attachment for design QA.

- [ ] **Step 1: Add a reversible live relative-avatar and three-card UI fixture**

Add this test beside the existing Flow UI tests:

```swift
func testFlowGlassDeckRendersUploadedRelativeAvatarAndThreeCardStack() throws {
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
    waitFor("screen.flow.content", timeout: 30)
    tap("side-menu.open")
    tap("side-menu.settings")
    waitFor("screen.settings.loaded", timeout: 20)
    tap("settings.personal-data")
    waitFor("screen.edit-profile.loaded", timeout: 20)
    tap("edit-profile.avatar-smoke-upload")
    waitForEditProfileAvatarUploadStatus("success", timeout: 45)

    let uploadedProfile = waitForCurrentSmokeProfileAvatarChanged(
        token: session.token,
        previousAvatarURL: originalProfile.avatarURL
    )
    XCTAssertTrue(
        uploadedProfile.avatarURL.hasPrefix("/"),
        "The live fixture must exercise a backend-relative avatar URL"
    )

    let runID = Int(Date().timeIntervalSince1970)
    var cardIDs: [String] = []
    for index in 0..<3 {
        cardIDs.append(
            try createPublicSmokeCard(
                token: session.token,
                searchToken: "flow-glass-\(runID)-\(index)"
            )
        )
    }
    defer {
        for cardID in cardIDs {
            permanentlyCleanUpSmokeCard(id: cardID, token: session.token)
        }
    }

    app.terminate()
    launchAuthenticatedApp()
    waitFor("screen.flow.content", timeout: 30)

    let visibleCardID = flowVisibleCardID()
    XCTAssertTrue(
        cardIDs.contains(visibleCardID),
        "A fresh authored card must be foreground so its uploaded avatar is visible"
    )
    captureVisual("flow-glass-avatar-stack")

    waitFor("flow.card.\(visibleCardID)").swipeLeft()
    XCTAssertNotEqual(
        waitForDifferentVisibleFlowCard(from: visibleCardID),
        visibleCardID
    )
}
```

This fixture restores the original profile and permanently removes all three cards even when an assertion fails.

- [ ] **Step 2: Compile the new UI test before running live dependencies**

```bash
xcodebuild build-for-testing \
  -project ArcNote.xcodeproj \
  -scheme ArcNote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/chorai-flow-glass-derived \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the focused source contract once more**

```bash
swift test --package-path Packages/CoreFlow --filter FlowCardPresentationSourceContractTests
```

Expected: 5 tests pass with 0 failures.

- [ ] **Step 4: Run the complete CoreFlow suite**

```bash
swift test --package-path Packages/CoreFlow
```

Expected: every CoreFlow test passes with 0 failures.

- [ ] **Step 5: Build both supported app schemes**

```bash
xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ArcNote.xcodeproj -scheme 'ArcNote Production' -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Expected: both commands end with `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Confirm the Local backend profile and health**

From `../Chorai_Go/chorai-go`, run:

```bash
make config-check
make env-show
curl --fail --silent --show-error http://127.0.0.1:8180/health
```

Expected: config validation succeeds, the Local profile resolves to port 8180, and health returns a successful response. If the stack is not already running, start `make run-stack` in a separate terminal session and wait for health before continuing.

- [ ] **Step 7: Run the relative-avatar visual fixture and existing interaction journey**

```bash
xcodebuild test \
  -project ArcNote.xcodeproj \
  -scheme ArcNote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/chorai-flow-glass-derived \
  -resultBundlePath /tmp/ChoraiFlowGlass-20260721.xcresult \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testFlowGlassDeckRendersUploadedRelativeAvatarAndThreeCardStack \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testFlowFavoriteIconActivatesWithoutAdvancingCard \
  CODE_SIGNING_ALLOWED=NO
```

Expected: 2 tests pass with 0 failures. The new fixture proves the backend returned a relative avatar path, creates enough fresh authored cards for two truthful rear layers, preserves swipe, and keeps `flow-glass-avatar-stack`; the existing test proves engagement ordering and Spark placement remain unchanged.

- [ ] **Step 8: Export and inspect the screenshot**

```bash
xcrun xcresulttool export attachments \
  --path /tmp/ChoraiFlowGlass-20260721.xcresult \
  --output-path /tmp/ChoraiFlowGlassAttachments-20260721
```

Expected: the export manifest lists the kept `flow-glass-avatar-stack` and `flow-compact-icon-chrome` attachments. Open `flow-glass-avatar-stack` and the approved reference at `/Users/luffylu/.codex/attachments/1e4c906b-cb0d-4690-9368-879a9de7239c/image-2.png` with the local image viewer.

Confirm all of the following in the same dark-mode state:

- The author photo is visible rather than the generic person glyph.
- One foreground card and two rear rims are visible when the deck has at least three cards.
- Rear layers read at the bottom and right without exposing card content.
- The foreground has a dark-violet translucent body, a fine top-left highlight, and clear text/control contrast.
- No card edge, tag, or engagement control clips at the reference iPhone viewport.

- [ ] **Step 9: Inspect accessibility presentation variants**

Run the focused UI journey once with Increase Contrast enabled:

```bash
xcrun simctl ui booted increase_contrast enabled
xcodebuild test \
  -project ArcNote.xcodeproj \
  -scheme ArcNote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/chorai-flow-glass-contrast-derived \
  -resultBundlePath /tmp/ChoraiFlowGlassContrast-20260721.xcresult \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testFlowGlassDeckRendersUploadedRelativeAvatarAndThreeCardStack \
  CODE_SIGNING_ALLOWED=NO
xcrun simctl ui booted increase_contrast disabled
```

Expected: 1 test passes with 0 failures and the stronger rim remains readable without washing out content. In Simulator Settings, enable Reduce Transparency, relaunch the built app, and visually confirm opaque violet foreground/rear separation; return the setting to its original value afterward.

Run the existing interaction journey at Accessibility XXXL and restore the normal category:

```bash
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large
xcodebuild test \
  -project ArcNote.xcodeproj \
  -scheme ArcNote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/chorai-flow-glass-xxxl-derived \
  -resultBundlePath /tmp/ChoraiFlowGlassXXXL-20260721.xcresult \
  -only-testing:ArcNoteUITests/ArcNoteUITests/testFlowFavoriteIconActivatesWithoutAdvancingCard \
  CODE_SIGNING_ALLOWED=NO
xcrun simctl ui booted content_size large
```

Expected: 1 test passes with 0 failures, all existing controls stay reachable, and no foreground content escapes the card.

- [ ] **Step 10: Commit the live Flow UI fixture**

```bash
git add ArcNoteUITests/ArcNoteUITests.swift
git commit -m "test: cover Flow glass avatar stack"
```

### Task 4: Record visual QA and complete the requirement audit

**Files:**
- Create: `docs/qa/ios-flow-glass-card-stack-design-qa.md`
- Verify: `ArcNote/CoreFlow/FlowViews.swift`
- Verify: `Packages/CoreFlow/Tests/CoreFlowTests/FlowCardPresentationSourceContractTests.swift`

**Interfaces:**
- Consumes: the approved reference, exported Flow attachment, focused/full test output, two scheme builds, and accessibility variant inspection.
- Produces: a durable requirement-by-requirement QA report with `final result: passed` only after all gates have direct evidence.

- [ ] **Step 1: Compare the implementation against every acceptance criterion**

Use the design spec at `docs/superpowers/specs/2026-07-21-ios-flow-glass-card-stack-design.md` as the checklist. If any avatar, layer count, glass, interaction, or accessibility criterion lacks evidence, keep the report in a failed state and return to the relevant red-green task before documenting completion.

- [ ] **Step 2: Write the passing QA report only after the comparison passes**

Create `docs/qa/ios-flow-glass-card-stack-design-qa.md` with this exact evidence structure, replacing only result counts if the repository gains tests before execution:

```markdown
# iOS Flow Glass Card Stack Design QA

## Visual truth

- Approved reference: `/Users/luffylu/.codex/attachments/1e4c906b-cb0d-4690-9368-879a9de7239c/image-2.png`
- Live capture: `flow-glass-avatar-stack` in `/tmp/ChoraiFlowGlass-20260721.xcresult`
- Viewport: iPhone 17 Pro Simulator, dark appearance

## Findings

No actionable P0, P1, or P2 mismatch remains.

- Avatar: the Go-backed author photo renders from the backend-relative resource path; the generic person image remains only as loading/failure fallback.
- Stack: the foreground plus two truthful rear surfaces are visible, with the rear rims confined to the bottom/right and no rear content exposure.
- Glass: native Material, dark-violet tint, top-left edge highlight, and depth shadow match the approved reference's hierarchy while preserving text contrast.
- Interaction: author, menu, Spark, favorite, like, comment, detail, and swipe behavior remain in their existing locations and the focused swipe journey passes.
- Accessibility: rear layers are noninteractive and hidden from VoiceOver; Increase Contrast strengthens the rim; Reduce Transparency retains distinct opaque layers; Reduce Motion behavior is unchanged.

## Verification

- `swift test --package-path Packages/CoreFlow --filter FlowCardPresentationSourceContractTests`: 5 tests passed, 0 failed.
- `swift test --package-path Packages/CoreFlow`: full suite passed, 0 failed.
- Local `ArcNote` generic Simulator build: passed.
- `ArcNote Production` generic Simulator build: passed.
- Default relative-avatar and interaction journeys: 2 tests passed, 0 failed.
- `testFlowGlassDeckRendersUploadedRelativeAvatarAndThreeCardStack`, Increased Contrast: 1 test passed, 0 failed.
- `testFlowFavoriteIconActivatesWithoutAdvancingCard`, Accessibility XXXL: 1 test passed, 0 failed.
- Reduce Transparency visual inspection: passed.

## Requirement audit

- [x] Absolute and relative Flow avatar URLs use the canonical resource resolver.
- [x] Valid author imagery renders in the live Flow card.
- [x] A deck with at least three cards shows one foreground and two rear surfaces.
- [x] Rear surfaces contain no content and accept no input.
- [x] Foreground glass, rim, tint, and depth align with the approved reference.
- [x] Existing Flow content and interactions remain intact.
- [x] Increased Contrast, Reduce Transparency, and Accessibility XXXL remain readable.

final result: passed
```

- [ ] **Step 3: Check the final diff and report**

```bash
git diff --check
git status --short
rg -n "final result: passed|Avatar:|Stack:|Glass:|Accessibility:" docs/qa/ios-flow-glass-card-stack-design-qa.md
```

Expected: no whitespace errors; only the intended QA file remains uncommitted after the three preceding implementation/test commits; the report contains one passing result and all four evidence findings.

- [ ] **Step 4: Commit the QA evidence**

```bash
git add docs/qa/ios-flow-glass-card-stack-design-qa.md
git commit -m "docs: record iOS Flow glass QA"
```

- [ ] **Step 5: Run the final completion gate**

Freshly rerun:

```bash
swift test --package-path Packages/CoreFlow --filter FlowCardPresentationSourceContractTests
swift test --package-path Packages/CoreFlow
xcodebuild -project ArcNote.xcodeproj -scheme ArcNote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ArcNote.xcodeproj -scheme 'ArcNote Production' -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
git status --short
```

Expected: focused and full tests pass, both builds succeed, and the worktree is clean after the four implementation/test/QA commits.
