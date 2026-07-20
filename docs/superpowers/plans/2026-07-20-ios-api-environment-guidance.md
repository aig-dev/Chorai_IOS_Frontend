# iOS API Environment and Project Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Simulator development reliably use the local Go backend by default, provide an explicit production-backed Xcode scheme, and add concise project-level iOS guidance that preserves Chorai's Zen Aesthetic.

**Architecture:** A shared `APIEnvironment` catalog owns the two canonical endpoints. Xcode build configurations compile only the selected environment name into `Info.plist`; `APIConfiguration` resolves an explicit test override first and the compiled environment second. The existing `ArcNote` scheme remains local, a new shared `ArcNote Production` scheme selects `Debug-Production`, and no scheme contains an endpoint literal.

**Tech Stack:** Swift 5, SwiftUI, Foundation `URLComponents`, XCTest/XCUITest, Xcode build configurations and shared schemes, `.xcconfig`, OSLog, Swift Package Manager.

## Global Constraints

- Work directly in `/Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend` on `main`; do not create a branch or worktree.
- Preserve unrelated outer-repository changes and do not stage the parent repository's gitlink.
- Deployment target remains iOS 16.0 and `TARGETED_DEVICE_FAMILY = 1`.
- `ArcNote` Debug is the default local Simulator workflow and resolves to `http://127.0.0.1:8180`.
- `ArcNote Production` is an explicit Debug scheme and resolves to `https://api.chorai.top`.
- Release and Archive always select Production.
- `CHORAI_API_BASE_URL` remains the highest-priority override for tests and diagnostics, not the daily environment selector.
- Runtime endpoint literals exist only in `ArcNote/APIEnvironment.swift`; schemes, `.xcconfig`, `Info.plist`, `APIConfiguration.swift`, and UI-test helpers do not duplicate them.
- Do not add a customer-facing or runtime environment switch.
- Do not redesign authentication storage; existing token verification may sign the developer out after an environment change.
- Keep `AGENTS.md` concise, general, native-iOS-focused, and aligned with `Zen Aesthetic + social knowledge flow + native, intuitive iOS behavior`.
- Every behavior change follows RED-GREEN-REFACTOR, and each task is committed separately on `main`.

---

## File Map

- Create `ArcNote/APIEnvironment.swift`: canonical environment names, endpoints, and override normalization.
- Create `ArcNoteUITests/APIEnvironmentTests.swift`: executable catalog and normalization tests.
- Create `Config/Local.xcconfig`: compile `local` into the default Debug app.
- Create `Config/Production.xcconfig`: compile `production` into Debug-Production and Release.
- Create `ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote Production.xcscheme`: explicit production-backed Debug runner.
- Create `Packages/CoreFlow/Tests/CoreFlowTests/IOSProjectGuidanceContractTests.swift`: contract for the project guide.
- Create `AGENTS.md`: environment, architecture, Zen Aesthetic, native UX, workflow, and completion guidance.
- Modify `ArcNote/APIConfiguration.swift`: resolve override then compiled environment; remove compile-condition endpoint fallbacks.
- Modify `ArcNote/Info.plist`: expose `ChoraiAPIEnvironment` from the build setting.
- Modify `ArcNote/ArcNoteApp.swift`: emit one Debug OSLog diagnostic containing environment and base URL.
- Modify `ArcNoteUITests/ArcNoteUITests.swift`: use the shared local catalog instead of repeated `8080` fallbacks.
- Modify `Packages/CoreFlow/Tests/CoreFlowTests/LocalRunSchemeContractTests.swift`: enforce build, scheme, and single-source contracts.
- Modify `ArcNote.xcodeproj/project.pbxproj`: target membership, xcconfig references, and Debug-Production configuration wiring.
- Modify `ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote.xcscheme`: remove the launch-only endpoint variable.

---

### Task 1: Add the executable endpoint catalog

**Files:**
- Create: `ArcNoteUITests/APIEnvironmentTests.swift`
- Create: `ArcNote/APIEnvironment.swift`
- Modify: `ArcNote.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Foundation `URL`, `URLComponents`, and `CharacterSet`.
- Produces: `APIEnvironment`, `APIEnvironment.infoDictionaryKey`, `APIEnvironment.overrideEnvironmentKey`, `APIEnvironment.baseURL`, and `APIEnvironment.normalizedBaseURL(from:)` for the app and UI-test targets.

- [ ] **Step 1: Add the failing endpoint tests to the UI-test target**

Create `ArcNoteUITests/APIEnvironmentTests.swift` with this complete content:

```swift
import XCTest

final class APIEnvironmentTests: XCTestCase {
    private let expectedLocal = ["http://", "127.0.0.1:8180"].joined()
    private let expectedProduction = ["https://", "api.chorai.top"].joined()

    func testCatalogMapsStableEnvironmentNamesToCanonicalURLs() {
        XCTAssertEqual(APIEnvironment.local.rawValue, "local")
        XCTAssertEqual(APIEnvironment.production.rawValue, "production")
        XCTAssertEqual(APIEnvironment.local.baseURL.absoluteString, expectedLocal)
        XCTAssertEqual(
            APIEnvironment.production.baseURL.absoluteString,
            expectedProduction
        )
    }

    func testCatalogRejectsUnknownEnvironmentNames() {
        XCTAssertNil(APIEnvironment(rawValue: "staging"))
        XCTAssertNil(APIEnvironment(rawValue: ""))
    }

    func testOverrideNormalizationRemovesOnlyATrailingRootSlash() {
        XCTAssertEqual(
            APIEnvironment.normalizedBaseURL(from: expectedLocal + "/")?
                .absoluteString,
            expectedLocal
        )
        XCTAssertEqual(
            APIEnvironment.normalizedBaseURL(from: "  \(expectedProduction)  ")?
                .absoluteString,
            expectedProduction
        )
    }

    func testOverrideNormalizationRejectsUnsafeOrAmbiguousValues() {
        XCTAssertNil(APIEnvironment.normalizedBaseURL(from: ""))
        XCTAssertNil(APIEnvironment.normalizedBaseURL(from: "ftp://127.0.0.1:8180"))
        XCTAssertNil(
            APIEnvironment.normalizedBaseURL(
                from: expectedProduction + "/unexpected-path"
            )
        )
        XCTAssertNil(
            APIEnvironment.normalizedBaseURL(from: expectedProduction + "?debug=1")
        )
        XCTAssertNil(
            APIEnvironment.normalizedBaseURL(from: "https://user:secret@api.chorai.top")
        )
    }
}
```

Add only this test file to the `ArcNoteUITests` Sources phase. Do not create the production catalog yet.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
xcodebuild test \
  -project ArcNote.xcodeproj \
  -scheme ArcNoteUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:ArcNoteUITests/APIEnvironmentTests
```

Expected: FAIL during Swift compilation because `APIEnvironment` does not exist.

- [ ] **Step 3: Implement the minimal shared catalog**

Create `ArcNote/APIEnvironment.swift`:

```swift
import Foundation

enum APIEnvironment: String, CaseIterable {
    case local
    case production

    static let infoDictionaryKey = "ChoraiAPIEnvironment"
    static let overrideEnvironmentKey = "CHORAI_API_BASE_URL"

    var baseURL: URL {
        switch self {
        case .local:
            return URL(string: "http://127.0.0.1:8180")!
        case .production:
            return URL(string: "https://api.chorai.top")!
        }
    }

    static func normalizedBaseURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else {
            return nil
        }

        components.scheme = scheme
        components.path = ""
        return components.url
    }
}
```

Add the same `APIEnvironment.swift` file reference to both the `ArcNote` and `ArcNoteUITests` Sources phases. It must compile into each target; do not duplicate the file.

- [ ] **Step 4: Run the test and verify GREEN**

Re-run the Step 2 command.

Expected: `APIEnvironmentTests` PASS with 4 tests and no warnings from the new files.

- [ ] **Step 5: Commit the catalog**

```bash
git add ArcNote/APIEnvironment.swift \
  ArcNoteUITests/APIEnvironmentTests.swift \
  ArcNote.xcodeproj/project.pbxproj
git commit -m "feat(config): add API environment catalog"
```

---

### Task 2: Compile Local and Production selections into the app

**Files:**
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/LocalRunSchemeContractTests.swift`
- Create: `Config/Local.xcconfig`
- Create: `Config/Production.xcconfig`
- Modify: `ArcNote/Info.plist`
- Modify: `ArcNote.xcodeproj/project.pbxproj`
- Modify: `ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote.xcscheme`
- Create: `ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote Production.xcscheme`

**Interfaces:**
- Consumes: `APIEnvironment` names `local` and `production` from Task 1.
- Produces: bundle key `ChoraiAPIEnvironment`, build setting `CHORAI_API_ENVIRONMENT`, build configuration `Debug-Production`, and shared scheme `ArcNote Production`.

- [ ] **Step 1: Replace the old scheme-only contract with failing build contracts**

Replace `Packages/CoreFlow/Tests/CoreFlowTests/LocalRunSchemeContractTests.swift` with:

```swift
import Foundation
import XCTest

final class LocalRunSchemeContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func launchAction(in scheme: String) throws -> Substring {
        let start = try XCTUnwrap(scheme.range(of: "<LaunchAction"))
        let end = try XCTUnwrap(
            scheme.range(
                of: "</LaunchAction>",
                range: start.upperBound..<scheme.endIndex
            )
        )
        return scheme[start.lowerBound..<end.upperBound]
    }

    func testSharedSchemesSelectCompiledLocalAndProductionConfigurations() throws {
        let localScheme = try read(
            "ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote.xcscheme"
        )
        let productionScheme = try read(
            "ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote Production.xcscheme"
        )

        XCTAssertTrue(try launchAction(in: localScheme).contains(
            "buildConfiguration = \"Debug\""
        ))
        XCTAssertTrue(try launchAction(in: productionScheme).contains(
            "buildConfiguration = \"Debug-Production\""
        ))

        for scheme in [localScheme, productionScheme] {
            XCTAssertFalse(scheme.contains("CHORAI_API_BASE_URL"))
            XCTAssertFalse(scheme.contains("http://"))
            XCTAssertFalse(scheme.contains("https://"))
        }
    }

    func testBuildConfigurationFilesSelectNamesNotEndpointLiterals() throws {
        let local = try read("Config/Local.xcconfig")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let production = try read("Config/Production.xcconfig")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(local, "CHORAI_API_ENVIRONMENT = local")
        XCTAssertEqual(production, "CHORAI_API_ENVIRONMENT = production")

        let infoPlist = try read("ArcNote/Info.plist")
        XCTAssertTrue(infoPlist.contains("<key>ChoraiAPIEnvironment</key>"))
        XCTAssertTrue(
            infoPlist.contains("<string>$(CHORAI_API_ENVIRONMENT)</string>")
        )

        let project = try read("ArcNote.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("path = Local.xcconfig;"))
        XCTAssertTrue(project.contains("path = Production.xcconfig;"))
        XCTAssertTrue(project.contains("name = Debug-Production;"))
    }
}
```

- [ ] **Step 2: Run the contract and verify RED**

```bash
swift test \
  --package-path Packages/CoreFlow \
  --scratch-path /tmp/chorai-api-build-config-red \
  --filter LocalRunSchemeContractTests
```

Expected: FAIL because the config files and Production scheme do not exist and the Local scheme still injects a URL.

- [ ] **Step 3: Add the named configuration files and bundle substitution**

Create `Config/Local.xcconfig`:

```xcconfig
CHORAI_API_ENVIRONMENT = local
```

Create `Config/Production.xcconfig`:

```xcconfig
CHORAI_API_ENVIRONMENT = production
```

Add this pair to the root dictionary in `ArcNote/Info.plist`:

```xml
<key>ChoraiAPIEnvironment</key>
<string>$(CHORAI_API_ENVIRONMENT)</string>
```

- [ ] **Step 4: Wire the build configurations in the project**

Update `project.pbxproj` to produce this exact matrix:

```text
PBXProject ArcNote
  Debug             -> existing Debug build settings
  Debug-Production  -> Debug build settings, name Debug-Production
  Release           -> existing Release build settings

PBXNativeTarget ArcNote
  Debug             -> baseConfigurationReference Local.xcconfig
  Debug-Production  -> Debug build settings + Production.xcconfig
  Release           -> baseConfigurationReference Production.xcconfig

PBXNativeTarget ArcNoteUITests
  Debug             -> existing Debug build settings
  Debug-Production  -> Debug build settings, TEST_TARGET_NAME = ArcNote
  Release           -> existing Release build settings
```

Add a `Config` PBX group containing the two file references. Add `Debug-Production` to all three `XCConfigurationList` sections so `xcodebuild -list` reports it once at project level and both targets can build under it. Preserve every existing Debug compiler, signing, deployment, package, and target setting.

- [ ] **Step 5: Remove the Local launch override and add the Production scheme**

Delete the entire `<EnvironmentVariables>...</EnvironmentVariables>` block from `ArcNote.xcscheme`.

Create `ArcNote Production.xcscheme` with this complete content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "1B48AE302E30967F0090CF86"
               BuildableName = "ArcNote.app"
               BlueprintName = "ArcNote"
               ReferencedContainer = "container:ArcNote.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug-Production"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug-Production"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "1B48AE302E30967F0090CF86"
            BuildableName = "ArcNote.app"
            BlueprintName = "ArcNote"
            ReferencedContainer = "container:ArcNote.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "1B48AE302E30967F0090CF86"
            BuildableName = "ArcNote.app"
            BlueprintName = "ArcNote"
            ReferencedContainer = "container:ArcNote.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug-Production">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

- [ ] **Step 6: Verify GREEN and resolved build settings**

Run:

```bash
swift test \
  --package-path Packages/CoreFlow \
  --scratch-path /tmp/chorai-api-build-config-green \
  --filter LocalRunSchemeContractTests

xcodebuild -project ArcNote.xcodeproj -list

xcodebuild -project ArcNote.xcodeproj -scheme ArcNote \
  -showBuildSettings | rg 'CONFIGURATION =|CHORAI_API_ENVIRONMENT ='

xcodebuild -project ArcNote.xcodeproj -scheme 'ArcNote Production' \
  -showBuildSettings | rg 'CONFIGURATION =|CHORAI_API_ENVIRONMENT ='
```

Expected:

```text
LocalRunSchemeContractTests: PASS
Build Configurations: Debug, Debug-Production, Release
Schemes include: ArcNote, ArcNote Production
ArcNote: CONFIGURATION = Debug; CHORAI_API_ENVIRONMENT = local
ArcNote Production: CONFIGURATION = Debug-Production; CHORAI_API_ENVIRONMENT = production
```

- [ ] **Step 7: Commit build selection**

```bash
git add Config/Local.xcconfig Config/Production.xcconfig \
  ArcNote/Info.plist \
  ArcNote.xcodeproj/project.pbxproj \
  ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote.xcscheme \
  'ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote Production.xcscheme' \
  Packages/CoreFlow/Tests/CoreFlowTests/LocalRunSchemeContractTests.swift
git commit -m "feat(config): add Local and Production schemes"
```

---

### Task 3: Resolve the compiled environment and remove all `8080` fallbacks

**Files:**
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/LocalRunSchemeContractTests.swift`
- Modify: `ArcNote/APIConfiguration.swift`
- Modify: `ArcNote/ArcNoteApp.swift`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: `APIEnvironment` and bundle key `ChoraiAPIEnvironment` from Tasks 1–2.
- Produces: `APIConfiguration.configuredEnvironment`, `APIConfiguration.baseURL`, `APIConfiguration.environmentLabel`, `UITestAPIConfiguration.baseURL`, and the Debug OSLog category `configuration`.

- [ ] **Step 1: Add failing single-source and precedence contracts**

Append these methods inside `LocalRunSchemeContractTests`:

```swift
func testApplicationResolvesOverrideBeforeCompiledEnvironment() throws {
    let source = try read("ArcNote/APIConfiguration.swift")
    let baseURLStart = try XCTUnwrap(source.range(of: "static var baseURL"))
    let baseURLEnd = try XCTUnwrap(
        source.range(
            of: "static var environmentLabel",
            range: baseURLStart.upperBound..<source.endIndex
        )
    )
    let baseURLSource = source[
        baseURLStart.lowerBound..<baseURLEnd.lowerBound
    ]
    let overrideRange = try XCTUnwrap(
        baseURLSource.range(of: "overrideEnvironmentKey")
    )
    let compiledRange = try XCTUnwrap(
        baseURLSource.range(of: "return configuredEnvironment.baseURL")
    )

    XCTAssertLessThan(overrideRange.lowerBound, compiledRange.lowerBound)
    XCTAssertTrue(source.contains("APIEnvironment.normalizedBaseURL"))
    XCTAssertFalse(source.contains("#if DEBUG\n        return \"http://"))
    XCTAssertFalse(source.contains("127.0.0.1:8080"))
}

func testRuntimeEndpointLiteralsExistOnlyInTheCatalog() throws {
    let localLiteral = ["http://", "127.0.0.1:8180"].joined()
    let productionLiteral = ["https://", "api.chorai.top"].joined()
    let catalog = try read("ArcNote/APIEnvironment.swift")
    XCTAssertTrue(catalog.contains(localLiteral))
    XCTAssertTrue(catalog.contains(productionLiteral))

    for path in [
        "ArcNote/APIConfiguration.swift",
        "ArcNoteUITests/ArcNoteUITests.swift",
        "Config/Local.xcconfig",
        "Config/Production.xcconfig",
        "ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote.xcscheme",
        "ArcNote.xcodeproj/xcshareddata/xcschemes/ArcNote Production.xcscheme",
    ] {
        let source = try read(path)
        XCTAssertFalse(source.contains(localLiteral), path)
        XCTAssertFalse(source.contains(productionLiteral), path)
        XCTAssertFalse(source.contains("127.0.0.1:8080"), path)
    }
}
```

- [ ] **Step 2: Run the contracts and verify RED**

```bash
swift test \
  --package-path Packages/CoreFlow \
  --scratch-path /tmp/chorai-api-resolution-red \
  --filter LocalRunSchemeContractTests
```

Expected: FAIL because `APIConfiguration` still owns Debug and Release endpoint literals and UI tests still fall back to `8080`.

- [ ] **Step 3: Replace compile-condition routing in `APIConfiguration`**

Replace the current `baseURL` implementation and compile-condition `current` implementation with:

```swift
static var configuredEnvironment: APIEnvironment {
    guard let rawValue = Bundle.main.object(
        forInfoDictionaryKey: APIEnvironment.infoDictionaryKey
    ) as? String,
    let environment = APIEnvironment(rawValue: rawValue)
    else {
        preconditionFailure(
            "Missing or invalid \(APIEnvironment.infoDictionaryKey) build setting"
        )
    }
    return environment
}

static var baseURL: String {
    if let rawOverride = ProcessInfo.processInfo.environment[
        APIEnvironment.overrideEnvironmentKey
    ],
    !rawOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        guard let override = APIEnvironment.normalizedBaseURL(
            from: rawOverride
        ) else {
            preconditionFailure(
                "Invalid \(APIEnvironment.overrideEnvironmentKey) value"
            )
        }
        return override.absoluteString
    }

    return configuredEnvironment.baseURL.absoluteString
}

static var environmentLabel: String {
    if let rawOverride = ProcessInfo.processInfo.environment[
        APIEnvironment.overrideEnvironmentKey
    ],
    !rawOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return "override"
    }
    return configuredEnvironment.rawValue
}
```

Keep the existing nested `Environment` timeout enum, but change `current` to:

```swift
static var current: Environment {
    configuredEnvironment == .production ? .production : .development
}
```

Do not retain a URL fallback in `APIConfiguration.swift`.

- [ ] **Step 4: Add a Debug startup diagnostic**

Add `import OSLog` to `ArcNoteApp.swift`. Add this file-private logger above `@main`:

```swift
private let configurationLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.michen.arcnote",
    category: "configuration"
)
```

At the beginning of `ArcNoteApp.init()`, inside `#if DEBUG`, add:

```swift
configurationLogger.notice(
    "API environment=\(APIConfiguration.environmentLabel, privacy: .public) base_url=\(APIConfiguration.baseURL, privacy: .public)"
)
```

Update the API migration smoke start line to include the label without changing the smoke flow:

```swift
log(
    "START environment=\(APIConfiguration.environmentLabel) "
        + "base_url=\(APIConfiguration.baseURL)"
)
```

- [ ] **Step 5: Centralize UI-test local routing**

Add this helper near the top of `ArcNoteUITests.swift`, above the test class:

```swift
private enum UITestAPIConfiguration {
    static var baseURL: String {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment[APIEnvironment.overrideEnvironmentKey],
           !override.isEmpty {
            return override
        }
        return APIEnvironment.local.baseURL.absoluteString
    }

    static func baseURL(in environment: [String: String]) -> String {
        environment[APIEnvironment.overrideEnvironmentKey]
            ?? APIEnvironment.local.baseURL.absoluteString
    }
}
```

Replace every `ProcessInfo` fallback ending in `"http://127.0.0.1:8080"` with `UITestAPIConfiguration.baseURL`. Replace helpers that receive an explicit environment dictionary with `UITestAPIConfiguration.baseURL(in: environment)`. Preserve tests that deliberately assign `http://127.0.0.1:1` and the dedicated live smoke value `http://127.0.0.1:8081`; those are explicit fixtures rather than fallbacks.

- [ ] **Step 6: Verify GREEN**

Run:

```bash
swift test \
  --package-path Packages/CoreFlow \
  --scratch-path /tmp/chorai-api-resolution-green \
  --filter LocalRunSchemeContractTests

xcodebuild test \
  -project ArcNote.xcodeproj \
  -scheme ArcNoteUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:ArcNoteUITests/APIEnvironmentTests

rg -n '127\.0\.0\.1:8080' \
  ArcNote ArcNoteUITests Packages/CoreFlow/Tests/CoreFlowTests
```

Expected: both test commands PASS. The final `rg` exits with status 1 and prints no matches.

- [ ] **Step 7: Commit runtime resolution**

```bash
git add ArcNote/APIConfiguration.swift ArcNote/ArcNoteApp.swift \
  ArcNoteUITests/ArcNoteUITests.swift \
  Packages/CoreFlow/Tests/CoreFlowTests/LocalRunSchemeContractTests.swift
git commit -m "fix(config): persist selected API environment"
```

---

### Task 4: Add concise iOS project guidance

**Files:**
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/IOSProjectGuidanceContractTests.swift`
- Create: `AGENTS.md`

**Interfaces:**
- Consumes: the approved design and the final environment matrix from Tasks 1–3.
- Produces: a repository-level instruction contract for contributors and agents.

- [ ] **Step 1: Write the failing documentation contract**

Create `Packages/CoreFlow/Tests/CoreFlowTests/IOSProjectGuidanceContractTests.swift`:

```swift
import Foundation
import XCTest

final class IOSProjectGuidanceContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testGuideCoversEnvironmentDesignAndDeliveryContracts() throws {
        let guide = try String(
            contentsOf: repositoryRoot.appendingPathComponent("AGENTS.md"),
            encoding: .utf8
        )

        for requiredText in [
            "## API Environments",
            "ArcNote Production",
            "make run-stack",
            "make env-show",
            "127.0.0.1:8180/health",
            "single source of truth",
            "## Zen Aesthetic",
            "Dynamic Type",
            "44 x 44 pt",
            "VoiceOver",
            "Reduce Motion",
            "## Definition of Done",
        ] {
            XCTAssertTrue(guide.contains(requiredText), requiredText)
        }

        XCTAssertFalse(guide.contains("127.0.0.1:8080"))
        XCTAssertLessThan(guide.split(separator: "\n").count, 150)
    }
}
```

- [ ] **Step 2: Run the contract and verify RED**

```bash
swift test \
  --package-path Packages/CoreFlow \
  --scratch-path /tmp/chorai-ios-guide-red \
  --filter IOSProjectGuidanceContractTests
```

Expected: FAIL because `Chorai_IOS_Frontend/AGENTS.md` does not exist.

- [ ] **Step 3: Create the concise project guide**

Create `AGENTS.md` with this complete content:

```markdown
# Chorai iOS Guide

## Scope

This repository contains the native iPhone app. Work in `ArcNote/` for app code,
`ArcNoteUITests/` for simulator flows, and `Packages/CoreFlow/` for testable domain
and source contracts. Work on `main` unless the user explicitly requests another
workflow. Preserve unrelated changes.

## API Environments

Local Simulator development is the default.

| Scheme | API | Use |
| --- | --- | --- |
| `ArcNote` | `http://127.0.0.1:8180` | normal local development |
| `ArcNote Production` | `https://api.chorai.top` | explicit production-backed debugging |
| Archive / Release | production | distribution |

Start and inspect the local backend from the outer Chorai workspace root:

```bash
cd Chorai_Go/chorai-go
make run-stack
make env-show
curl http://127.0.0.1:8180/health
```

Switch Local and Production from Xcode's Scheme picker, then rebuild. The selected
environment is compiled into the app and survives a Simulator-icon relaunch.
`127.0.0.1` is a Simulator default; a physical iPhone needs an explicit reachable
Mac address through `CHORAI_API_BASE_URL`.

API routing has one runtime single source of truth: `ArcNote/APIEnvironment.swift`.
Build configurations select only `local` or `production`. Do not hard-code API
hosts or ports in views, services, schemes, tests, or additional config files.
`CHORAI_API_BASE_URL` is reserved for tests and temporary diagnostics.

When data appears missing, first confirm the app's logged environment and URL,
then check `/health` and backend access logs. Do not assume the database is empty.

## Engineering Boundaries

- Prefer small, local changes that preserve existing navigation and data flow.
- Keep networking behind `APIConfiguration` and `NetworkManager`.
- Never log tokens, credentials, private note bodies, or full sensitive payloads.
- Reuse existing SwiftUI, CoreFlow, and editor primitives before adding variants.
- Use test-first changes for behavior and regression fixes.
- Do not edit generated or vendored package output.

## Zen Aesthetic

North star: `Zen Aesthetic + social knowledge flow + native, intuitive iOS behavior`.

- Content and writing are the protagonist: quiet, restrained, spacious, readable.
- Give each screen one visual focus; establish hierarchy before atmosphere.
- The editor is a calm, focused workspace, not a form. Keep tools secondary but
  immediately reachable.
- Glass communicates depth and hierarchy, not decoration. Never trade contrast or
  click clarity for material effects.
- Prefer semantic colors, system typography, Dynamic Type, safe areas, and native
  controls over custom novelty.
- Keep effective tap targets at least `44 x 44 pt`; provide clear VoiceOver labels.
- Respect Reduce Motion and Reduce Transparency. Motion stays short, soft,
  predictable, and functional.
- Prefer native keyboard focus, dismissal, navigation, menus, and sheet behavior.
- Keep copy brief, precise, calm, and actionable.

## Workflow

Before editing, inspect the owning view, its state owner, related CoreFlow contract,
and current scheme. During implementation, avoid parallel sources of truth and
unrelated refactors. Afterward, run the narrowest relevant tests, then build the
affected scheme and inspect the real Simulator flow.

## Definition of Done

- Behavior is correct in the intended Local or Production configuration.
- Default `ArcNote` and explicit `ArcNote Production` both build.
- Local survives termination and a Simulator-icon relaunch without changing ports.
- Relevant unit, source-contract, and UI tests pass.
- UI remains native, accessible, readable, and consistent with Zen Aesthetic.
- No new endpoint literal, visual noise, sensitive log, or undocumented exception
  was introduced.
```

- [ ] **Step 4: Verify GREEN and document clarity**

```bash
swift test \
  --package-path Packages/CoreFlow \
  --scratch-path /tmp/chorai-ios-guide-green \
  --filter IOSProjectGuidanceContractTests

wc -l AGENTS.md
```

Expected: contract PASS; `AGENTS.md` remains below 150 lines and contains no `8080` reference.

- [ ] **Step 5: Commit the guide**

```bash
git add AGENTS.md \
  Packages/CoreFlow/Tests/CoreFlowTests/IOSProjectGuidanceContractTests.swift
git commit -m "docs: add iOS project guidance"
```

---

### Task 5: Build, cold-launch, and audit every requirement

**Files:**
- Verify only; no planned source changes.

**Interfaces:**
- Consumes: all outputs from Tasks 1–4 and the running local Go stack.
- Produces: test, build, bundle, Simulator, and source-audit evidence for completion.

- [ ] **Step 1: Run all focused and package tests**

```bash
swift test \
  --package-path Packages/CoreFlow \
  --scratch-path /tmp/chorai-api-environment-full

xcodebuild test \
  -project ArcNote.xcodeproj \
  -scheme ArcNoteUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:ArcNoteUITests/APIEnvironmentTests
```

Expected: the complete CoreFlow suite and all 4 endpoint-catalog tests PASS.

- [ ] **Step 2: Build both schemes into isolated DerivedData paths**

```bash
xcodebuild build \
  -project ArcNote.xcodeproj \
  -scheme ArcNote \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -derivedDataPath /tmp/chorai-api-local

xcodebuild build \
  -project ArcNote.xcodeproj \
  -scheme 'ArcNote Production' \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -derivedDataPath /tmp/chorai-api-production
```

Expected: both commands end with `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Prove the bundle selections**

```bash
plutil -p \
  /tmp/chorai-api-local/Build/Products/Debug-iphonesimulator/ArcNote.app/Info.plist \
  | rg 'ChoraiAPIEnvironment|local'

plutil -p \
  /tmp/chorai-api-production/Build/Products/Debug-Production-iphonesimulator/ArcNote.app/Info.plist \
  | rg 'ChoraiAPIEnvironment|production'

xcodebuild -project ArcNote.xcodeproj -target ArcNote \
  -configuration Release -showBuildSettings \
  | rg 'CONFIGURATION =|CHORAI_API_ENVIRONMENT ='
```

Expected: Local bundle reports `local`, Production bundle reports `production`, and Release reports `CHORAI_API_ENVIRONMENT = production`.

- [ ] **Step 4: Verify the local backend before launching**

```bash
cd ../Chorai_Go/chorai-go
make env-show
curl --fail http://127.0.0.1:8180/health
```

Expected: resolved server port is `8180` and health returns HTTP 200. Return to `Chorai_IOS_Frontend` before continuing.

- [ ] **Step 5: Prove Local survives a plain Simulator relaunch**

```bash
xcrun simctl install booted \
  /tmp/chorai-api-local/Build/Products/Debug-iphonesimulator/ArcNote.app
xcrun simctl launch booted com.michen.arcnote --ui-test-adaptive-layout
xcrun simctl terminate booted com.michen.arcnote
xcrun simctl launch booted com.michen.arcnote --ui-test-adaptive-layout
xcrun simctl spawn booted log show --last 2m --style compact \
  --predicate 'subsystem == "com.michen.arcnote" AND category == "configuration"'
```

Expected: two plain launches log `environment=local` and `base_url=http://127.0.0.1:8180`. No launch environment variable is required.

- [ ] **Step 6: Prove Production and restore Local**

```bash
xcrun simctl terminate booted com.michen.arcnote
xcrun simctl install booted \
  /tmp/chorai-api-production/Build/Products/Debug-Production-iphonesimulator/ArcNote.app
xcrun simctl launch booted com.michen.arcnote --ui-test-adaptive-layout
xcrun simctl spawn booted log show --last 1m --style compact \
  --predicate 'subsystem == "com.michen.arcnote" AND category == "configuration"'
xcrun simctl terminate booted com.michen.arcnote
xcrun simctl install booted \
  /tmp/chorai-api-local/Build/Products/Debug-iphonesimulator/ArcNote.app
xcrun simctl launch booted com.michen.arcnote --ui-test-adaptive-layout
```

Expected: Production logs `environment=production` and `base_url=https://api.chorai.top`. The fixture route performs no mutating API action. The final launch restores Local.

- [ ] **Step 7: Run the final source and repository audit**

```bash
rg -n '127\.0\.0\.1:8080' \
  ArcNote ArcNoteUITests Packages/CoreFlow/Tests/CoreFlowTests

rg -n '127\.0\.0\.1:8180|api\.chorai\.top' \
  ArcNote ArcNoteUITests ArcNote.xcodeproj Config

git status --short
git log -5 --oneline --decorate
```

Expected:

- the `8080` search has no matches;
- runtime endpoint literals appear only in `ArcNote/APIEnvironment.swift`;
- `git status --short` is clean;
- the task commits are on `main`, with no branch or worktree created.

- [ ] **Step 8: Completion audit against the approved design**

Inspect `docs/superpowers/specs/2026-07-20-ios-api-environment-guidance-design.md` and map every acceptance criterion to the evidence from Steps 1–7. Do not claim completion if either bundle value, either scheme build, the plain relaunch, the guide contract, or the single-source search is missing.
