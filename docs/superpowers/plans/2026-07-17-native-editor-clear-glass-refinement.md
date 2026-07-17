# Native Editor Clear Glass Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the native editor body's flat gray slab with a visibly transparent Liquid Glass writing plane while preserving readable compact controls, image backgrounds, accessibility fallbacks, and editor interactions.

**Architecture:** Keep one native glass helper, but make its material choice semantic: large writing planes use clear interactive glass and compact chrome uses regular interactive glass. Place a continuous violet/indigo ambient scene behind the editor, move the image readability veil below the writing-plane glass, and preserve the already-transparent WKWebView/CSS chain. Use source contracts for material/layer invariants, supported simulator accessibility controls, and same-simulator screenshots for the authoritative visual gate.

**Tech Stack:** Swift 6, SwiftUI, iOS 16-26 compatibility, XCTest, XCUITest, Xcode 26 simulator tooling.

## Global Constraints

- This work is native iOS only; do not modify `chorai_web_frontend` or simulate glass inside the embedded web editor.
- iOS 26+: native clear glass for the writing plane and regular glass for compact chrome.
- iOS 16-25: an `ultraThinMaterial` fallback with the same ambient scene and directional edge hierarchy.
- Reduce Transparency: an opaque dark surface with sufficient text contrast.
- Increase Contrast: stronger edge and image veil without layout changes.
- The standard image veil is exactly `0.22`; it remains within the approved `0.18...0.26` range.
- Dynamic Type, VoiceOver order, selection, focus, scrolling, keyboard formatting, slash behavior, tags, links, and inline-image source selection remain unchanged.
- No blur, tint, highlight, shadow, or ambient decoration may intercept input or enter the accessibility tree.
- The supplied flat-gray screenshot and a fresh screenshot from simulator `86CD9628-7C27-4799-B237-3EEC82E7E9B5` are the visual before/after authority.
- The ArcNote target currently forces `INFOPLIST_KEY_UIUserInterfaceStyle = Light` in both build configurations. A capture taken after switching the simulator to system Dark therefore intentionally keeps the same app palette; it is a system-setting stability check, not independent dark-palette coverage. True dark-palette validation requires removing that product constraint in separate work.

---

## File Map

- Create `ArcNote/CardEditor/CardEditorAmbientBackdrop.swift`: render only the continuous page-level dark base and two restrained ambient light fields.
- Modify `ArcNote/CardEditor/CardEditorGlassSurface.swift`: own semantic `writingPlane`/`chrome` material selection, accessibility fallback, and edge treatment.
- Modify `ArcNote/CardEditor/CardEditorBackground.swift`: own image/veil/glass source order, accessibility-aware veil values, and the unclipped pane shadow.
- Modify `ArcNote/CardEditor/CardEditorShell.swift`: install the ambient scene and select chrome for floating controls.
- Modify `ArcNote/CardEditor/CardEditorFormattingBar.swift`: select chrome for the keyboard formatting bar.
- Modify `ArcNote.xcodeproj/project.pbxproj`: register the new ambient backdrop in the CardEditor group and ArcNote target.
- Modify `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift`: protect semantic glass selection, source order, ambient scene wiring, project membership, transparent composition, and accessibility fixture wiring.
- Modify `Packages/BlockNoteEditor/Tests/BlockNoteEditorTests/BlockNoteEditorResourceTests.swift`: characterize the bundled editor canvas as transparent without changing its resources.

### Task 1: Semantic Clear Writing Plane and Regular Chrome

**Files:**

- Modify: `Packages/BlockNoteEditor/Tests/BlockNoteEditorTests/BlockNoteEditorResourceTests.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift:388-434`
- Modify: `ArcNote/CardEditor/CardEditorGlassSurface.swift`
- Modify: `ArcNote/CardEditor/CardEditorBackground.swift:52-58`
- Modify: `ArcNote/CardEditor/CardEditorFormattingBar.swift:110-115`
- Modify: `ArcNote/CardEditor/CardEditorShell.swift:245-247`

**Interfaces:**

- Consumes: SwiftUI `Glass.clear`, `Glass.regular`, `Glass.interactive()`, `accessibilityReduceTransparency`, and `colorSchemeContrast`.
- Produces: `enum CardEditorGlassStyle: Equatable { case writingPlane, chrome }` and `CardEditorGlassSurface.init(shape:style:)` for Task 2 and all editor call sites.

- [ ] **Step 1: Add a passing characterization test for the embedded canvas transparency**

Add this test to `BlockNoteEditorResourceTests` before changing any production source:

```swift
func testBundledEditorCanvasIsTransparentForNativeComposition() throws {
    let editorCSSURL = try BlockNoteEditorResources.resourceDirectory()
        .appendingPathComponent("editor.css", isDirectory: false)
    let editorCSS = try String(contentsOf: editorCSSURL, encoding: .utf8)

    for marker in [
        ":root{color-scheme:dark",
        "html,body,#root",
        "background:transparent!important",
        ".ios-editor-root,.ios-blocknote-view",
    ] {
        XCTAssertTrue(
            editorCSS.contains(marker),
            "The native editor canvas lost transparent marker: \(marker)"
        )
    }
}
```

- [ ] **Step 2: Run the characterization test and verify the existing transparent chain is green**

Run:

```bash
swift test --package-path Packages/BlockNoteEditor --filter BlockNoteEditorResourceTests.testBundledEditorCanvasIsTransparentForNativeComposition
```

Expected: PASS before any material change. A failure means the bundled resources drifted and this plan must stop for diagnosis.

- [ ] **Step 3: Replace the old regular-glass source contract with semantic material expectations**

Replace `testEditorSurfacesUseAccessibilityAwareLiquidGlassFamily` with:

```swift
func testEditorSurfacesUseAccessibilityAwareLiquidGlassFamily() throws {
    let glass = try source(
        at: "ArcNote/CardEditor/CardEditorGlassSurface.swift"
    )
    let background = try source(
        at: "ArcNote/CardEditor/CardEditorBackground.swift"
    )
    let formatting = try source(
        at: "ArcNote/CardEditor/CardEditorFormattingBar.swift"
    )
    let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")
    let coordinator = try source(
        at: "Packages/BlockNoteEditor/Sources/BlockNoteEditor/BlockNoteEditorCoordinator.swift"
    )

    XCTAssertTrue(glass.contains("enum CardEditorGlassStyle: Equatable"))
    XCTAssertTrue(glass.contains("case writingPlane"))
    XCTAssertTrue(glass.contains("case chrome"))
    let materialStart = try XCTUnwrap(
        glass.range(of: "private var material: some View")
    )
    let material = String(glass[materialStart.lowerBound..<glass.endIndex])
    let writingPlaneMaterialStart = try XCTUnwrap(
        material.range(of: "case .writingPlane:")
    )
    let chromeMaterialStart = try XCTUnwrap(
        material.range(
            of: "case .chrome:",
            range: writingPlaneMaterialStart.upperBound..<material.endIndex
        )
    )
    let writingPlaneMaterial = String(
        material[
            writingPlaneMaterialStart.lowerBound..<chromeMaterialStart.lowerBound
        ]
    )
    let chromeMaterial = String(
        material[chromeMaterialStart.lowerBound..<material.endIndex]
    )

    XCTAssertTrue(glass.contains("if #available(iOS 26.0, *)"))
    XCTAssertTrue(
        writingPlaneMaterial.contains(
            ".glassEffect(.clear.interactive(), in: shape)"
        )
    )
    XCTAssertFalse(
        writingPlaneMaterial.contains(
            ".glassEffect(.regular.interactive(), in: shape)"
        )
    )
    XCTAssertTrue(
        chromeMaterial.contains(
            ".glassEffect(.regular.interactive(), in: shape)"
        )
    )
    XCTAssertFalse(
        chromeMaterial.contains(
            ".glassEffect(.clear.interactive(), in: shape)"
        )
    )
    XCTAssertTrue(glass.contains("shape.fill(.ultraThinMaterial)"))
    XCTAssertTrue(
        glass.contains("@Environment(\\.accessibilityReduceTransparency)")
    )
    XCTAssertTrue(glass.contains("@Environment(\\.colorSchemeContrast)"))
    XCTAssertTrue(glass.contains("if reduceTransparency"))
    XCTAssertFalse(glass.contains("isInteractive"))

    XCTAssertTrue(background.contains("style: .writingPlane"))
    XCTAssertTrue(formatting.contains("style: .chrome"))
    XCTAssertFalse(
        formatting.contains(".background(ZenVisualTokens.background.opacity(0.97))")
    )
    XCTAssertTrue(shell.contains("style: .chrome"))

    XCTAssertTrue(coordinator.contains("webView.isOpaque = false"))
    XCTAssertTrue(coordinator.contains("webView.backgroundColor = .clear"))
    XCTAssertTrue(
        coordinator.contains("webView.scrollView.backgroundColor = .clear")
    )
}
```

- [ ] **Step 4: Run the semantic material contract and verify it fails for the old API**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests.testEditorSurfacesUseAccessibilityAwareLiquidGlassFamily
```

Expected: FAIL because `CardEditorGlassStyle`, `.clear.interactive()`, and explicit styles do not exist yet.

- [ ] **Step 5: Implement the semantic glass helper and directional writing-plane edge**

Replace `CardEditorGlassSurface.swift` with:

```swift
import SwiftUI

enum CardEditorGlassStyle: Equatable {
    case writingPlane
    case chrome
}

struct CardEditorGlassSurface<SurfaceShape: Shape>: View {
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorSchemeContrast)
    private var contrast

    let shape: SurfaceShape
    let style: CardEditorGlassStyle

    init(
        shape: SurfaceShape,
        style: CardEditorGlassStyle
    ) {
        self.shape = shape
        self.style = style
    }

    var body: some View {
        ZStack {
            material
            edge
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var edge: some View {
        switch style {
        case .writingPlane:
            shape.stroke(
                contrast == .increased
                    ? Color.white.opacity(0.42)
                    : Color.white.opacity(0.25),
                lineWidth: contrast == .increased ? 1.2 : 0.8
            )
            .mask(
                LinearGradient(
                    colors: [
                        Color.white,
                        Color.white.opacity(
                            contrast == .increased ? 0.56 : 0.34
                        ),
                        Color.white.opacity(
                            contrast == .increased ? 0.14 : 0.02
                        ),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

        case .chrome:
            shape.stroke(
                contrast == .increased
                    ? Color.white.opacity(0.34)
                    : Color.white.opacity(0.16),
                lineWidth: contrast == .increased ? 1.4 : 0.8
            )
        }
    }

    @ViewBuilder
    private var material: some View {
        if reduceTransparency {
            shape.fill(ZenVisualTokens.background.opacity(0.97))
        } else if #available(iOS 26.0, *) {
            switch style {
            case .writingPlane:
                shape
                    .fill(Color.clear)
                    .glassEffect(.clear.interactive(), in: shape)
                    .mask {
                        ZStack {
                            shape.fill(Color.white).padding(1.4)

                            shape.stroke(
                                LinearGradient(
                                    stops: [
                                        .init(
                                            color: Color.white.opacity(1.0),
                                            location: 0.0
                                        ),
                                        .init(
                                            color: Color.white.opacity(0.72),
                                            location: 0.46
                                        ),
                                        .init(
                                            color: Color.white.opacity(
                                                contrast == .increased
                                                    ? 0.28
                                                    : 0.08
                                            ),
                                            location: 0.86
                                        ),
                                        .init(
                                            color: Color.white.opacity(
                                                contrast == .increased
                                                    ? 0.18
                                                    : 0.02
                                            ),
                                            location: 1.0
                                        ),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 2.8
                            )
                        }
                    }

            case .chrome:
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular.interactive(), in: shape)
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}
```

Update the body background call site to:

```swift
CardEditorGlassSurface(
    shape: RoundedRectangle(
        cornerRadius: 24,
        style: .continuous
    ),
    style: .writingPlane
)
```

Update the formatting-bar background to:

```swift
CardEditorGlassSurface(
    shape: Rectangle(),
    style: .chrome
)
```

Update the floating-control background to:

```swift
private var controlBackground: some View {
    CardEditorGlassSurface(shape: Circle(), style: .chrome)
}
```

- [ ] **Step 6: Run focused contracts and compile the native app**

Run:

```bash
swift test --package-path Packages/BlockNoteEditor --filter BlockNoteEditorResourceTests.testBundledEditorCanvasIsTransparentForNativeComposition
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests.testEditorSurfacesUseAccessibilityAwareLiquidGlassFamily
xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote -configuration Debug -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-clear-glass-derived CODE_SIGNING_ALLOWED=NO
```

Expected: both focused tests PASS and Xcode ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit the semantic material slice**

```bash
git add ArcNote/CardEditor/CardEditorGlassSurface.swift ArcNote/CardEditor/CardEditorBackground.swift ArcNote/CardEditor/CardEditorFormattingBar.swift ArcNote/CardEditor/CardEditorShell.swift Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift Packages/BlockNoteEditor/Tests/BlockNoteEditorTests/BlockNoteEditorResourceTests.swift
git diff --cached --check
git commit -m "feat(editor): separate clear glass from chrome"
```

### Task 2: Continuous Ambient Scene and Correct Image Composition

**Files:**

- Create: `ArcNote/CardEditor/CardEditorAmbientBackdrop.swift`
- Modify: `ArcNote.xcodeproj/project.pbxproj`
- Modify: `ArcNote/CardEditor/CardEditorShell.swift:60-64`
- Modify: `ArcNote/CardEditor/CardEditorBackground.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift`

**Interfaces:**

- Consumes: `CardEditorGlassSurface(shape:style:)` from Task 1 and existing `ZenVisualTokens.background`.
- Produces: `CardEditorAmbientBackdrop: View`, a standard image veil of `0.22`, an increased-contrast veil of `0.34`, a reduce-transparency veil of `0.58`, source order `backgroundImage -> Color.black -> CardEditorGlassSurface`, and a pane shadow applied after the rounded background clip.

- [ ] **Step 1: Add the ambient file to the project file contract and write the layer-order test**

Add `"CardEditorAmbientBackdrop.swift"` to `cardEditorFiles`, then add:

```swift
func testWritingPlaneUsesContinuousAmbientSceneAndVeilBelowGlass() throws {
    let ambientPath = "ArcNote/CardEditor/CardEditorAmbientBackdrop.swift"
    let ambientURL = Self.repositoryRoot.appendingPathComponent(ambientPath)
    guard FileManager.default.fileExists(atPath: ambientURL.path) else {
        XCTFail("Missing CardEditorAmbientBackdrop.swift")
        return
    }

    let ambient = try source(at: ambientPath)
    let background = try source(
        at: "ArcNote/CardEditor/CardEditorBackground.swift"
    )
    let shell = try source(at: "ArcNote/CardEditor/CardEditorShell.swift")
    let project = try source(at: "ArcNote.xcodeproj/project.pbxproj")

    XCTAssertTrue(shell.contains("CardEditorAmbientBackdrop()"))
    XCTAssertEqual(
        ambient.components(separatedBy: "RadialGradient(").count - 1,
        2
    )
    XCTAssertTrue(ambient.contains("center: upperLightCenter"))
    XCTAssertTrue(ambient.contains("center: lowerLightCenter"))
    XCTAssertTrue(ambient.contains("if !reduceTransparency"))
    XCTAssertTrue(ambient.contains(".allowsHitTesting(false)"))
    XCTAssertTrue(ambient.contains(".accessibilityHidden(true)"))
    XCTAssertTrue(
        project.contains("/* CardEditorAmbientBackdrop.swift in Sources */")
    )

    XCTAssertTrue(background.contains("return 0.22"))
    XCTAssertTrue(background.contains("return 0.34"))
    XCTAssertTrue(background.contains("return 0.58"))
    XCTAssertFalse(background.contains("0.42"))

    let bodyStart = try XCTUnwrap(
        background.range(of: "var body: some View")
    )

    let layerStart = try XCTUnwrap(
        background.range(of: "private var backgroundLayer: some View")
    )
    let body = background[bodyStart.lowerBound..<layerStart.lowerBound]
    let contentClip = try XCTUnwrap(body.range(of: ".clipShape(paneShape)"))
    let backgroundModifier = try XCTUnwrap(body.range(of: ".background {"))
    let shadow = try XCTUnwrap(body.range(of: ".shadow("))
    XCTAssertLessThan(contentClip.lowerBound, backgroundModifier.lowerBound)
    XCTAssertLessThan(backgroundModifier.lowerBound, shadow.lowerBound)

    let layerEnd = try XCTUnwrap(
        background.range(
            of: "private var backgroundImage: some View",
            range: layerStart.upperBound..<background.endIndex
        )
    )
    let layer = background[layerStart.lowerBound..<layerEnd.lowerBound]
    let image = try XCTUnwrap(layer.range(of: "backgroundImage"))
    let veil = try XCTUnwrap(layer.range(of: "Color.black"))
    let glass = try XCTUnwrap(layer.range(of: "CardEditorGlassSurface("))
    XCTAssertLessThan(image.lowerBound, veil.lowerBound)
    XCTAssertLessThan(veil.lowerBound, glass.lowerBound)
    XCTAssertTrue(layer.contains("style: .writingPlane"))
}
```

Also add `testAmbientLightUsesViewportRelativeCentersInsideTheScene` to lock
the final compact-screen geometry: `UnitPoint(x: 0.82, y: 0.18)`,
`UnitPoint(x: 0.16, y: 0.70)`, radii derived from
`max(proxy.size.width, proxy.size.height)` with multipliers `0.58` and `0.54`,
and no `.offset(` modifier anywhere in the ambient source.

In `testEditorRespectsMotionTransparencyAndContrastPreferences`, replace the old combined-opacity assertion with:

```swift
let ambient = try source(
    at: "ArcNote/CardEditor/CardEditorAmbientBackdrop.swift"
)

XCTAssertTrue(background.contains("if reduceTransparency"))
XCTAssertTrue(background.contains("if contrast == .increased"))
XCTAssertTrue(
    ambient.contains("@Environment(\\.accessibilityReduceTransparency)")
)
XCTAssertTrue(ambient.contains("if !reduceTransparency"))
```

- [ ] **Step 2: Run the ambient/layer contract and verify it fails before implementation**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests.testWritingPlaneUsesContinuousAmbientSceneAndVeilBelowGlass
```

Expected: FAIL with `Missing CardEditorAmbientBackdrop.swift`.

- [ ] **Step 3: Create the continuous ambient backdrop**

Create `CardEditorAmbientBackdrop.swift` with:

```swift
import SwiftUI

struct CardEditorAmbientBackdrop: View {
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    private let upperLightCenter = UnitPoint(x: 0.82, y: 0.18)
    private let lowerLightCenter = UnitPoint(x: 0.16, y: 0.70)

    var body: some View {
        ZStack {
            ZenVisualTokens.background

            if !reduceTransparency {
                GeometryReader { proxy in
                    let sceneExtent = max(proxy.size.width, proxy.size.height)

                    ZStack {
                        RadialGradient(
                            colors: [
                                Color(red: 0.44, green: 0.25, blue: 0.88)
                                    .opacity(0.34),
                                Color.clear,
                            ],
                            center: upperLightCenter,
                            startRadius: 0,
                            endRadius: sceneExtent * 0.58
                        )

                        RadialGradient(
                            colors: [
                                Color(red: 0.14, green: 0.30, blue: 0.70)
                                    .opacity(0.28),
                                Color.clear,
                            ],
                            center: lowerLightCenter,
                            startRadius: 0,
                            endRadius: sceneExtent * 0.54
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 4: Register the new Swift source in the Xcode project**

Add these exact entries to the matching `project.pbxproj` sections; the IDs are currently unused:

```text
C0DEF3002F8000010000001B /* CardEditorAmbientBackdrop.swift in Sources */ = {isa = PBXBuildFile; fileRef = C0DEF3002F8000010000002B /* CardEditorAmbientBackdrop.swift */; };
C0DEF3002F8000010000002B /* CardEditorAmbientBackdrop.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CardEditorAmbientBackdrop.swift; sourceTree = "<group>"; };
```

Add the file reference to the `CardEditor` group:

```text
C0DEF3002F8000010000002B /* CardEditorAmbientBackdrop.swift */,
```

Add the build file to the ArcNote Sources phase:

```text
C0DEF3002F8000010000001B /* CardEditorAmbientBackdrop.swift in Sources */,
```

- [ ] **Step 5: Install the ambient scene and reorder the body background stack**

In `CardEditorShell.body`, replace the solid page color with:

```swift
CardEditorAmbientBackdrop()
```

Replace `CardEditorBackground.swift` with:

```swift
import SwiftUI
import UIKit

enum CardEditorBackgroundSource: Equatable {
    case none
    case local(Data)
    case remote(URL)
}

struct CardEditorBackground<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let background: CardEditorBackgroundSource
    @ViewBuilder let content: () -> Content

    init(
        background: CardEditorBackgroundSource,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.background = background
        self.content = content
    }

    private var paneShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var veilOpacity: Double {
        if reduceTransparency {
            return 0.58
        }
        if contrast == .increased {
            return 0.34
        }
        return 0.22
    }

    private var paneShadowOpacity: Double {
        contrast == .increased ? 0.30 : 0.20
    }

    var body: some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipShape(paneShape)
            .background {
                backgroundLayer
                    .clipShape(paneShape)
                    .shadow(
                        color: Color.black.opacity(paneShadowOpacity),
                        radius: 18,
                        x: 0,
                        y: 10
                    )
            }
    }

    private var backgroundLayer: some View {
        ZStack {
            if background != .none {
                backgroundImage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .accessibilityHidden(true)

                Color.black
                    .opacity(veilOpacity)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }

            CardEditorGlassSurface(
                shape: paneShape,
                style: .writingPlane
            )
        }
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var backgroundImage: some View {
        switch background {
        case .none:
            EmptyView()

        case let .local(data):
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZenVisualTokens.background
            }

        case let .remote(url):
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    ZenVisualTokens.background
                @unknown default:
                    ZenVisualTokens.background
                }
            }
        }
    }
}
```

- [ ] **Step 6: Run all affected contracts and compile the layered scene**

Run:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests
xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote -configuration Debug -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-clear-glass-derived CODE_SIGNING_ALLOWED=NO
```

Expected: all `CardEditorShellSourceContractTests` PASS and Xcode ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit the ambient scene and image composition slice**

```bash
git add ArcNote/CardEditor/CardEditorAmbientBackdrop.swift ArcNote/CardEditor/CardEditorBackground.swift ArcNote/CardEditor/CardEditorShell.swift ArcNote.xcodeproj/project.pbxproj Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift
git diff --cached --check
git commit -m "feat(editor): reveal ambient light through glass"
```

### Task 2A: Simulator-led visual refinements

The native screenshot gate produced focused follow-ups after the initial Task 2
commit: lower the standard image veil to its final `0.22`, move both ambient
origins inside the viewport with adaptive radii and lock that geometry in source
contracts, then fade the writing-plane edge from top to bottom. The final native
rim correction is commit `0286dce` (`fix(editor): mask native glass lower rim`):
after clear glass, a white interior inset by `1.4pt` preserves the pane body while
a separate `2.8pt` perimeter mask fades from top to bottom. Its lower stops use
`0.08` and `0.02` normally, strengthened to `0.28` and `0.18` with Increase
Contrast. Keep these as separate fix/test commits so the visual evidence and
regression protection remain auditable rather than rewriting the original
implementation commits.

The scoped material contract must assert exactly one writing-plane mask,
interior-before-perimeter source order, the `1.4pt` inset, the four directional
stops and `2.8pt` perimeter, including both contrast branches. It must also prove
that chrome retains regular glass with none of this writing-plane mask geometry.
Verify the completed refinement with:

```bash
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests
git show --check 0286dce
```

### Task 3: Native Visual Gate and Interaction Regression

**Files:**

- Inspect only: `/Users/luffylu/.codex/attachments/54bd6af5-efb1-432a-85bc-e64d841ac586/image-1.png`
- Generate outside the repository: `/tmp/chorai-clear-glass/*.png`
- Verify: all modified files from Tasks 1-2

**Interfaces:**

- Consumes: the compiled `ArcNote.app`, existing `populated`/`background`/`keyboard` fixtures, simulator `86CD9628-7C27-4799-B237-3EEC82E7E9B5`, supported simulator UI settings, and bundle identifier `com.michen.arcnote`.
- Produces: fresh no-background, image-background, system-Dark-setting stability, Increase Contrast, and Reduce Transparency screenshots; a passing editor interaction regression; and a simulator left open on the standard native editor.

- [ ] **Step 1: Run every affected source/resource contract**

```bash
swift test --package-path Packages/BlockNoteEditor --filter BlockNoteEditorResourceTests
swift test --package-path Packages/CoreFlow --filter CardEditorShellSourceContractTests
```

Expected: both suites PASS with zero failures.

- [ ] **Step 2: Build the Debug app for the QA simulator**

```bash
xcodebuild build -project ArcNote.xcodeproj -scheme ArcNote -configuration Debug -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-clear-glass-derived CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` and app at `/tmp/chorai-clear-glass-derived/Build/Products/Debug-iphonesimulator/ArcNote.app`.

- [ ] **Step 3: Run the focused native editor interaction suite**

```bash
xcodebuild test -project ArcNote.xcodeproj -scheme ArcNoteUITests -destination 'platform=iOS Simulator,id=86CD9628-7C27-4799-B237-3EEC82E7E9B5' -derivedDataPath /tmp/chorai-clear-glass-derived -parallel-testing-enabled NO -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorShellEmptyHierarchyIsHeaderlessAndAccessible -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorShellBackgroundStopsBeforeMetadata -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorFormattingBarKeepsDismissFixedAndReflectsSelection -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorInlineImageChooserDismissesKeyboardAndShowsSources -only-testing:ArcNoteUITests/ArcNoteUITests/testCardEditorSlashTypesWithoutOpeningCommandMenu -only-testing:ArcNoteUITests/ArcNoteUITests/testNativeTagInputDoesNotShowBodyFormattingBar
```

Expected: six tests PASS with zero failures. This proves the native surface still owns the keyboard toolbar, image source dialog, slash behavior, and tag input.

- [ ] **Step 4: Install the app and capture five same-viewport native screenshots**

Run each command from the repository root in the order shown:

```bash
mkdir -p /tmp/chorai-clear-glass
xcrun simctl install 86CD9628-7C27-4799-B237-3EEC82E7E9B5 /tmp/chorai-clear-glass-derived/Build/Products/Debug-iphonesimulator/ArcNote.app
xcrun simctl get_app_container 86CD9628-7C27-4799-B237-3EEC82E7E9B5 com.michen.arcnote app
xcrun simctl status_bar 86CD9628-7C27-4799-B237-3EEC82E7E9B5 override --time "9:41" --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl ui 86CD9628-7C27-4799-B237-3EEC82E7E9B5 appearance light
xcrun simctl ui 86CD9628-7C27-4799-B237-3EEC82E7E9B5 increase_contrast disabled
xcrun simctl ui 86CD9628-7C27-4799-B237-3EEC82E7E9B5 content_size large
SIMCTL_CHILD_CHORAI_CARD_EDITOR_FIXTURE_MODE=populated xcrun simctl launch --terminate-running-process 86CD9628-7C27-4799-B237-3EEC82E7E9B5 com.michen.arcnote --ui-test-card-editor-shell
xcrun simctl spawn 86CD9628-7C27-4799-B237-3EEC82E7E9B5 launchctl list | rg 'UIKitApplication:com\.michen\.arcnote'
sleep 2
xcrun simctl io 86CD9628-7C27-4799-B237-3EEC82E7E9B5 screenshot /tmp/chorai-clear-glass/populated-light.png
SIMCTL_CHILD_CHORAI_CARD_EDITOR_FIXTURE_MODE=background xcrun simctl launch --terminate-running-process 86CD9628-7C27-4799-B237-3EEC82E7E9B5 com.michen.arcnote --ui-test-card-editor-shell
sleep 2
xcrun simctl io 86CD9628-7C27-4799-B237-3EEC82E7E9B5 screenshot /tmp/chorai-clear-glass/background-light.png
xcrun simctl ui 86CD9628-7C27-4799-B237-3EEC82E7E9B5 appearance dark
SIMCTL_CHILD_CHORAI_CARD_EDITOR_FIXTURE_MODE=populated xcrun simctl launch --terminate-running-process 86CD9628-7C27-4799-B237-3EEC82E7E9B5 com.michen.arcnote --ui-test-card-editor-shell
sleep 2
xcrun simctl io 86CD9628-7C27-4799-B237-3EEC82E7E9B5 screenshot /tmp/chorai-clear-glass/populated-dark.png
xcrun simctl ui 86CD9628-7C27-4799-B237-3EEC82E7E9B5 appearance light
xcrun simctl ui 86CD9628-7C27-4799-B237-3EEC82E7E9B5 increase_contrast enabled
SIMCTL_CHILD_CHORAI_CARD_EDITOR_FIXTURE_MODE=populated xcrun simctl launch --terminate-running-process 86CD9628-7C27-4799-B237-3EEC82E7E9B5 com.michen.arcnote --ui-test-card-editor-shell
sleep 2
xcrun simctl io 86CD9628-7C27-4799-B237-3EEC82E7E9B5 screenshot /tmp/chorai-clear-glass/populated-increased-contrast.png
xcrun simctl ui 86CD9628-7C27-4799-B237-3EEC82E7E9B5 increase_contrast disabled
```

Because ArcNote forces Light via `UIUserInterfaceStyle`,
`populated-dark.png` is expected to retain the same application palette. Its
purpose is to prove that changing the surrounding system appearance does not
destabilize readability or composition; it does not establish independent dark
theme coverage.

For Reduce Transparency, Xcode 26.2 has no supported `simctl ui` switch. Launch Settings with:

```bash
xcrun simctl launch 86CD9628-7C27-4799-B237-3EEC82E7E9B5 com.apple.Preferences
```

Using the simulator UI, open `Accessibility > Display & Text Size` and enable `Reduce Transparency`. Then relaunch and capture the native `populated` fixture with these exact commands:

```bash
SIMCTL_CHILD_CHORAI_CARD_EDITOR_FIXTURE_MODE=populated xcrun simctl launch --terminate-running-process 86CD9628-7C27-4799-B237-3EEC82E7E9B5 com.michen.arcnote --ui-test-card-editor-shell
sleep 2
xcrun simctl io 86CD9628-7C27-4799-B237-3EEC82E7E9B5 screenshot /tmp/chorai-clear-glass/populated-reduce-transparency.png
xcrun simctl launch 86CD9628-7C27-4799-B237-3EEC82E7E9B5 com.apple.Preferences
```

Return to `Accessibility > Display & Text Size` and disable `Reduce Transparency` immediately after the capture. Do not use a `defaults write` workaround as accessibility evidence.

Expected: `get_app_container` resolves an `ArcNote.app` path, `launchctl` reports `UIKitApplication:com.michen.arcnote`, and five PNG files appear at the exact paths above with no Safari address bar.

- [ ] **Step 5: Inspect the reference and all fresh screenshots at original detail**

Use the image-viewing tool on the supplied reference and every `/tmp/chorai-clear-glass/*.png`. Verify all of these exact gates:

- `populated-light.png` visibly transmits non-uniform violet/indigo ambient color and no longer reads as a uniform gray card.
- Ambient fields continue outside the pane; they are not painted only inside its rounded rectangle.
- The top pane edge is brighter than the bottom edge through the final top-to-bottom mask, without a uniform white box.
- `background-light.png` keeps image color visible through the writing plane while body text remains readable.
- Compact top controls remain visually stronger than the writing plane.
- `populated-increased-contrast.png` has a stronger edge without geometry changes.
- `populated-reduce-transparency.png` is deliberately opaque and readable.
- The Light capture is readable, and the system-Dark-setting stability capture preserves the same forced-Light text/caret palette without regressions.

The visual gate is failed if the writing plane is still a flat gray slab, even when every automated test passes.

- [ ] **Step 6: Restore the standard simulator state and leave the native editor open for user review**

```bash
xcrun simctl ui 86CD9628-7C27-4799-B237-3EEC82E7E9B5 appearance light
xcrun simctl ui 86CD9628-7C27-4799-B237-3EEC82E7E9B5 increase_contrast disabled
SIMCTL_CHILD_CHORAI_CARD_EDITOR_FIXTURE_MODE=populated xcrun simctl launch --terminate-running-process 86CD9628-7C27-4799-B237-3EEC82E7E9B5 com.michen.arcnote --ui-test-card-editor-shell
```

Expected: the simulator remains booted on the standard native populated editor, ready for direct inspection.

- [ ] **Step 7: Audit the final repository state**

```bash
git diff --check
git status --short
git log --oneline --reverse ca69574..HEAD
```

Expected: no uncommitted implementation files or whitespace errors. The focused history should show the approved design/plan, semantic material and veil work, ambient scene plus adaptive-geometry hardening, top-to-bottom edge refinement, scoped material-contract hardening, and `0286dce fix(editor): mask native glass lower rim` in that order. The tests attached to `0286dce` must lock the preserved interior, four-stop `2.8pt` perimeter fade, standard/increased bottom opacity pairs, and absence of that mask from chrome.
