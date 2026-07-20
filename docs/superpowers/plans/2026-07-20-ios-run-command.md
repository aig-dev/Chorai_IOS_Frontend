# iOS Command-Line Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `make ios-run` to build the latest Local ArcNote app, prepare an iPhone Simulator, install the app, and launch it without opening the Xcode GUI.

**Architecture:** A root Make target is the stable public interface and delegates to one focused zsh launcher. The launcher owns deterministic device selection and the `xcodebuild`/`simctl` sequence; a CoreFlow macOS test executes the sourceable device chooser against fixtures and contracts the orchestration surface.

**Tech Stack:** GNU/BSD Make, zsh, Xcode `xcodebuild`, `xcrun simctl`, Swift XCTest through CoreFlow.

## Global Constraints

- Work directly in `/Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend` on `main`; do not create a branch or worktree.
- `make ios-run` always builds scheme `ArcNote` with configuration `Debug`.
- The installed app must retain the compiled Local environment at `http://127.0.0.1:8180`.
- Device priority is explicit non-empty `IOS_DEVICE`, then the first booted available non-iPad iOS Simulator, then `iPhone 17 Pro`.
- `IOS_DERIVED_DATA` defaults to `/tmp/chorai-ios-local` and may be overridden.
- The bundle identifier remains `com.michen.arcnote`.
- Do not start or mutate the backend, change API configuration, add a production run target, or add an in-app environment switch.
- Real command failures must propagate as a non-zero make exit.
- Follow RED-GREEN-REFACTOR and commit the implementation separately from this plan.

---

## File Map

- Create `Packages/CoreFlow/Tests/CoreFlowTests/IOSRunCommandContractTests.swift`: executable device-selection tests and source contracts for the public make target and launcher.
- Create `Makefile`: public `ios-run` target and supported variable forwarding only.
- Create `scripts/ios-run.sh`: device selection, Simulator boot, Local build, installation, and launch orchestration.

---

### Task 1: Add the tested Local Simulator launcher

**Files:**
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/IOSRunCommandContractTests.swift`
- Create: `Makefile`
- Create: `scripts/ios-run.sh`

**Interfaces:**
- Consumes: `IOS_DEVICE` and `IOS_DERIVED_DATA` environment variables; `xcrun`, `xcodebuild`, and `open` command-line tools.
- Produces: phony Make target `ios-run`; sourceable zsh function `choose_ios_device(device_list: String) -> String`; a launched Local `com.michen.arcnote` app.

- [ ] **Step 1: Write the failing launcher contract**

Create `Packages/CoreFlow/Tests/CoreFlowTests/IOSRunCommandContractTests.swift`:

```swift
import Foundation
import XCTest

final class IOSRunCommandContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var launcherURL: URL {
        repositoryRoot.appendingPathComponent("scripts/ios-run.sh")
    }

    private func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func selectedDevice(
        from deviceList: String,
        override: String? = nil
    ) throws -> String {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-c",
            "source \"$1\"\nIOS_DEVICE=\"$2\"\nchoose_ios_device \"$3\"",
            "_",
            launcherURL.path,
            override ?? "",
            deviceList,
        ]
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()

        let output = String(
            data: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let error = String(
            data: standardError.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, error)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testMakeTargetDelegatesSupportedVariablesToLauncher() throws {
        let makefile = try read("Makefile")

        XCTAssertTrue(makefile.contains(".PHONY: ios-run"))
        XCTAssertTrue(makefile.contains("ios-run:"))
        XCTAssertTrue(makefile.contains("IOS_DEVICE=\"$(IOS_DEVICE)\""))
        XCTAssertTrue(
            makefile.contains("IOS_DERIVED_DATA=\"$(IOS_DERIVED_DATA)\"")
        )
        XCTAssertTrue(makefile.contains("./scripts/ios-run.sh"))
    }

    func testExplicitDeviceOverrideWins() throws {
        XCTAssertEqual(
            try selectedDevice(
                from: """
                == Devices ==
                -- iOS 26.2 --
                    iPhone 17 Pro (43E6164C-1F4B-47E4-9B65-D154C7281A56) (Booted)
                """,
                override: "iPhone 16e"
            ),
            "iPhone 16e"
        )
    }

    func testBootedIPhoneWinsWithoutOverride() throws {
        XCTAssertEqual(
            try selectedDevice(
                from: """
                == Devices ==
                -- iOS 26.2 --
                    iPad (A16) (62E58ABC-998B-4929-AF9B-888C6B076558) (Booted)
                    Chorai iPhone SE 3 QA (86CD9628-7C27-4799-B237-3EEC82E7E9B5) (Booted)
                -- watchOS 26.2 --
                    Apple Watch (11111111-1111-1111-1111-111111111111) (Booted)
                """
            ),
            "86CD9628-7C27-4799-B237-3EEC82E7E9B5"
        )
    }

    func testDefaultDeviceIsIPhone17ProWithoutBootedIPhone() throws {
        XCTAssertEqual(
            try selectedDevice(
                from: """
                == Devices ==
                -- iOS 26.2 --
                    iPhone 16e (8F00CE99-FEBE-4774-9A07-4BBAF8A0FD1D) (Shutdown)
                    iPad (A16) (62E58ABC-998B-4929-AF9B-888C6B076558) (Booted)
                """
            ),
            "iPhone 17 Pro"
        )
    }

    func testLauncherOwnsBuildInstallAndLaunchSequence() throws {
        let launcher = try read("scripts/ios-run.sh")
        let attributes = try FileManager.default.attributesOfItem(
            atPath: launcherURL.path
        )
        let permissions = try XCTUnwrap(
            (attributes[.posixPermissions] as? NSNumber)?.intValue
        )

        XCTAssertNotEqual(permissions & 0o111, 0)
        for requiredText in [
            "xcrun simctl list devices available",
            "xcrun simctl boot \"$device\"",
            "xcrun simctl bootstatus \"$device\" -b",
            "open -a Simulator",
            "xcodebuild build -quiet",
            "-scheme \"$IOS_SCHEME_NAME\"",
            "-configuration \"$IOS_CONFIGURATION_NAME\"",
            "-derivedDataPath \"$derived_data\"",
            "xcrun simctl install \"$device\" \"$app_path\"",
            "xcrun simctl launch --terminate-running-process",
            "\"$IOS_BUNDLE_IDENTIFIER\"",
        ] {
            XCTAssertTrue(launcher.contains(requiredText), requiredText)
        }
    }
}
```

- [ ] **Step 2: Run the contract and verify RED**

Run:

```bash
swift test \
  --package-path Packages/CoreFlow \
  --scratch-path /tmp/chorai-ios-run-red \
  --filter IOSRunCommandContractTests
```

Expected: FAIL. Five tests are discovered; they fail because `Makefile` and
`scripts/ios-run.sh` do not exist.

- [ ] **Step 3: Add the minimal public Make target**

Create `Makefile`:

```make
IOS_DEVICE ?=
IOS_DERIVED_DATA ?= /tmp/chorai-ios-local

.PHONY: ios-run
ios-run:
	@IOS_DEVICE="$(IOS_DEVICE)" \
		IOS_DERIVED_DATA="$(IOS_DERIVED_DATA)" \
		./scripts/ios-run.sh
```

- [ ] **Step 4: Add the launcher implementation**

Create `scripts/ios-run.sh`:

```zsh
#!/bin/zsh

set -euo pipefail

readonly DEFAULT_IOS_DEVICE="iPhone 17 Pro"
readonly DEFAULT_IOS_DERIVED_DATA="/tmp/chorai-ios-local"
readonly IOS_SCHEME_NAME="ArcNote"
readonly IOS_CONFIGURATION_NAME="Debug"
readonly IOS_PRODUCT_NAME="ArcNote.app"
readonly IOS_BUNDLE_IDENTIFIER="com.michen.arcnote"

choose_ios_device() {
    local device_list="${1:-}"
    local explicit_device="${IOS_DEVICE:-}"

    if [[ -n "${explicit_device//[[:space:]]/}" ]]; then
        print -r -- "$explicit_device"
        return 0
    fi

    local booted_device_id
    booted_device_id=$(
        print -r -- "$device_list" \
            | awk '
                /^-- iOS / { in_ios = 1; next }
                /^-- / { in_ios = 0 }
                in_ios && /\(Booted\)/ && $0 !~ /^[[:space:]]*iPad/ {
                    print
                    exit
                }
            ' \
            | sed -nE \
                's/.*\(([0-9A-Fa-f-]{36})\) \(Booted\)[[:space:]]*$/\1/p'
    )

    if [[ -n "$booted_device_id" ]]; then
        print -r -- "$booted_device_id"
    else
        print -r -- "$DEFAULT_IOS_DEVICE"
    fi
}

require_command() {
    local command_name="$1"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        print -u2 -- "[ios-run] Missing required command: $command_name"
        return 1
    fi
}

main() {
    require_command xcrun
    require_command xcodebuild
    require_command open

    local repository_root="${0:A:h:h}"
    local derived_data="${IOS_DERIVED_DATA:-$DEFAULT_IOS_DERIVED_DATA}"
    local device_list
    local device
    local destination
    local app_path

    device_list="$(xcrun simctl list devices available)"
    device="$(choose_ios_device "$device_list")"
    if [[ "$device" =~ '^[0-9A-Fa-f-]{36}$' ]]; then
        destination="platform=iOS Simulator,id=$device"
    else
        destination="platform=iOS Simulator,name=$device"
    fi
    app_path="$derived_data/Build/Products/Debug-iphonesimulator/$IOS_PRODUCT_NAME"

    print -r -- "[ios-run] Simulator: $device"
    xcrun simctl boot "$device" >/dev/null 2>&1 || true
    if ! xcrun simctl bootstatus "$device" -b; then
        print -u2 -- "[ios-run] Unable to boot Simulator: $device"
        return 1
    fi
    open -a Simulator

    print -r -- "[ios-run] Building latest Local ArcNote app..."
    xcodebuild build -quiet \
        -project "$repository_root/ArcNote.xcodeproj" \
        -scheme "$IOS_SCHEME_NAME" \
        -configuration "$IOS_CONFIGURATION_NAME" \
        -destination "$destination" \
        -derivedDataPath "$derived_data" \
        CODE_SIGNING_ALLOWED=NO

    if [[ ! -d "$app_path" ]]; then
        print -u2 -- "[ios-run] Built app not found: $app_path"
        return 1
    fi

    print -r -- "[ios-run] Installing and launching $IOS_BUNDLE_IDENTIFIER..."
    xcrun simctl install "$device" "$app_path"
    xcrun simctl launch --terminate-running-process \
        "$device" \
        "$IOS_BUNDLE_IDENTIFIER"
    print -r -- "[ios-run] ArcNote is running on $device"
}

if [[ "${ZSH_EVAL_CONTEXT:-}" == "toplevel" ]]; then
    main "$@"
fi
```

Make the script executable:

```bash
chmod +x scripts/ios-run.sh
```

- [ ] **Step 5: Run the contract and verify GREEN**

Run:

```bash
swift test \
  --package-path Packages/CoreFlow \
  --scratch-path /tmp/chorai-ios-run-green \
  --filter IOSRunCommandContractTests
```

Expected: PASS; 5 tests, 0 failures.

- [ ] **Step 6: Check the Make interface without launching**

Run:

```bash
make -n ios-run
make -n ios-run IOS_DEVICE="iPhone 16e" \
  IOS_DERIVED_DATA=/tmp/chorai-ios-run-custom
```

Expected: both commands exit 0. The first forwards empty `IOS_DEVICE` and the
default DerivedData path. The second forwards `iPhone 16e` and the custom path.

- [ ] **Step 7: Commit the launcher**

```bash
git add Makefile scripts/ios-run.sh \
  Packages/CoreFlow/Tests/CoreFlowTests/IOSRunCommandContractTests.swift
git commit -m "feat: add iOS command-line runner"
```

---

### Task 2: Run the real command and verify the latest Local app

**Files:**
- Verify only; no planned source changes.

**Interfaces:**
- Consumes: `make ios-run` from Task 1 and the installed Xcode Simulator runtime.
- Produces: a running latest-checkout Local ArcNote app in the selected Simulator.

- [ ] **Step 1: Run all focused contracts**

```bash
swift test \
  --package-path Packages/CoreFlow \
  --scratch-path /tmp/chorai-ios-run-final \
  --filter '(IOSRunCommandContractTests|LocalRunSchemeContractTests|IOSProjectGuidanceContractTests)'
```

Expected: PASS; 10 tests, 0 failures.

- [ ] **Step 2: Execute the real public command**

```bash
make ios-run IOS_DERIVED_DATA=/tmp/chorai-ios-run-acceptance
```

Expected: exit 0. With no iPhone booted, the command boots `iPhone 17 Pro`,
builds ArcNote Debug, installs it, launches `com.michen.arcnote`, and leaves the
Simulator visible without opening Xcode.

- [ ] **Step 3: Verify the installed Local bundle and running process**

Resolve the booted iOS device:

```bash
IOS_RUN_DEVICE_ID=$(
  xcrun simctl list devices available \
    | awk '
        /^-- iOS / { in_ios = 1; next }
        /^-- / { in_ios = 0 }
        in_ios && /\(Booted\)/ && $0 !~ /^[[:space:]]*iPad/ {
          print
          exit
        }
      ' \
    | sed -nE \
        's/.*\(([0-9A-Fa-f-]{36})\) \(Booted\)[[:space:]]*$/\1/p'
)
IOS_RUN_APP_PATH=$(xcrun simctl get_app_container \
  "$IOS_RUN_DEVICE_ID" com.michen.arcnote app)
/usr/libexec/PlistBuddy -c 'Print :ChoraiAPIEnvironment' \
  "$IOS_RUN_APP_PATH/Info.plist"
xcrun simctl spawn "$IOS_RUN_DEVICE_ID" launchctl list \
  | rg 'UIKitApplication:com\.michen\.arcnote'
```

Expected: the plist command prints `local`; `launchctl` finds the ArcNote
application process.

- [ ] **Step 4: Verify the endpoint diagnostic and backend health**

```bash
xcrun simctl spawn "$IOS_RUN_DEVICE_ID" log show --last 5m --style compact \
  --predicate 'subsystem == "com.michen.arcnote" AND category == "configuration"' \
  | tail -5
curl --fail --silent --show-error --write-out '\nHTTP %{http_code}\n' \
  http://127.0.0.1:8180/health
```

Expected: ArcNote logs `environment=local` and
`base_url=http://127.0.0.1:8180`; health returns HTTP 200.

- [ ] **Step 5: Run the final repository audit**

```bash
git diff --check
git branch --show-current
git status --short
git log -3 --oneline
```

Expected: diff check exits 0, branch is `main`, status is empty, and the launcher
commit is at HEAD.

---

## Final Implementation Results

Implemented and final-review corrections applied on 2026-07-20. The historical
RED/GREEN snippets and counts above document the original TDD sequence; their
unsafe recursive Make export, text device parsing, immediate boot-failure
return, and original test-count expectations are superseded by the tracked
implementation and strengthened contracts.

The current launcher freezes raw `IOS_DEVICE` and `IOS_DERIVED_DATA` values
before export, selects implicit iPhones from `simctl` JSON using the authoritative
`deviceTypeIdentifier`, leaves caller shell options unchanged when sourced, and
lets `bootstatus` decide readiness after a failed boot request. The fake-tool
contracts preserve argument boundaries and cover list, boot/bootstatus, open,
build, missing product, install, and launch failures, including a DerivedData
path containing spaces.

The final focused `IOSRunCommandContractTests` expectation is 15 tests. The
combined Local-run/guidance gate is 20 tests: those 15 plus four
`LocalRunSchemeContractTests` and one `IOSProjectGuidanceContractTests`. These
counts supersede the original 5-test and 10-test expectations above without
removing the useful initial TDD record.
