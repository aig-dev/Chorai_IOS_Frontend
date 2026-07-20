import Foundation
import XCTest

final class IOSRunCommandContractTests: XCTestCase {
    private struct CommandResult {
        let terminationStatus: Int32
        let standardOutput: String
        let standardError: String
    }

    private struct ToolInvocation: Equatable {
        let tool: String
        let arguments: [String]
    }

    private struct FakeLauncherResult {
        let command: CommandResult
        let invocations: [ToolInvocation]
        let derivedDataURL: URL
    }

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

    private var shutdownIPhoneDeviceList: String {
        """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
              {
                "name": "iPhone 17 Pro",
                "udid": "43E6164C-1F4B-47E4-9B65-D154C7281A56",
                "state": "Shutdown",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
              }
            ]
          }
        }
        """
    }

    private func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func runCommand(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryURL: URL? = nil
    ) throws -> CommandResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()

        return CommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: String(
                data: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            standardError: String(
                data: standardError.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chorai-ios-run-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func createFakeToolchain(in temporaryDirectory: URL) throws -> URL {
        let toolDirectory = temporaryDirectory.appendingPathComponent("bin")
        try FileManager.default.createDirectory(
            at: toolDirectory,
            withIntermediateDirectories: true
        )

        try writeExecutable(
            """
            #!/bin/zsh
            set -eu

            log_invocation() {
                local tool="$1"
                shift
                print -r -- "BEGIN:$tool" >> "$IOS_RUN_LOG"
                local argument
                for argument in "$@"; do
                    print -r -- "ARG:$argument" >> "$IOS_RUN_LOG"
                done
                print -r -- "END" >> "$IOS_RUN_LOG"
            }

            log_invocation xcrun "$@"

            if [[ "$1" == "simctl" && "$2" == "list" && "$3" == "devices" && "$4" == "available" ]]; then
                if [[ "${IOS_RUN_FAIL_TOOL:-}" == "list" ]]; then
                    print -u2 -- "fake list failure"
                    exit 22
                fi
                print -r -- "$IOS_RUN_DEVICE_LIST"
                exit 0
            fi

            if [[ "$1" == "simctl" && "$2" == "boot" ]] \
                && [[ "${IOS_RUN_FAIL_TOOL:-}" == "boot" \
                    || "${IOS_RUN_FAIL_TOOL:-}" == "boot-and-bootstatus" ]]; then
                print -u2 -- "fake boot failure"
                exit 23
            fi

            if [[ "$1" == "simctl" && "$2" == "bootstatus" ]] \
                && [[ "${IOS_RUN_FAIL_TOOL:-}" == "bootstatus" \
                    || "${IOS_RUN_FAIL_TOOL:-}" == "boot-and-bootstatus" ]]; then
                print -u2 -- "fake bootstatus failure"
                exit 24
            fi

            if [[ "$1" == "simctl" && "$2" == "install" && "${IOS_RUN_FAIL_TOOL:-}" == "install" ]]; then
                print -u2 -- "fake install failure"
                exit 25
            fi

            if [[ "$1" == "simctl" && "$2" == "launch" && "${IOS_RUN_FAIL_TOOL:-}" == "launch" ]]; then
                print -u2 -- "fake launch failure"
                exit 26
            fi
            """,
            to: toolDirectory.appendingPathComponent("xcrun")
        )
        try writeExecutable(
            """
            #!/bin/zsh
            set -eu

            print -r -- "BEGIN:xcodebuild" >> "$IOS_RUN_LOG"
            argument=""
            for argument in "$@"; do
                print -r -- "ARG:$argument" >> "$IOS_RUN_LOG"
            done
            print -r -- "END" >> "$IOS_RUN_LOG"

            if [[ "${IOS_RUN_FAIL_TOOL:-}" == "build" ]]; then
                print -u2 -- "fake build failure"
                exit 27
            fi

            derived_data=""
            while (( $# > 0 )); do
                if [[ "$1" == "-derivedDataPath" ]]; then
                    derived_data="$2"
                    shift 2
                else
                    shift
                fi
            done
            if [[ "${IOS_RUN_FAIL_TOOL:-}" == "missing-app" ]]; then
                exit 0
            fi
            mkdir -p "$derived_data/Build/Products/Debug-iphonesimulator/ArcNote.app"
            """,
            to: toolDirectory.appendingPathComponent("xcodebuild")
        )
        try writeExecutable(
            """
            #!/bin/zsh
            set -eu
            print -r -- "BEGIN:open" >> "$IOS_RUN_LOG"
            argument=""
            for argument in "$@"; do
                print -r -- "ARG:$argument" >> "$IOS_RUN_LOG"
            done
            print -r -- "END" >> "$IOS_RUN_LOG"
            if [[ "${IOS_RUN_FAIL_TOOL:-}" == "open" ]]; then
                print -u2 -- "fake open failure"
                exit 28
            fi
            """,
            to: toolDirectory.appendingPathComponent("open")
        )
        return toolDirectory
    }

    private func launcherEnvironment(
        toolDirectory: URL,
        logURL: URL,
        deviceList: String,
        derivedDataURL: URL,
        deviceOverride: String? = nil,
        failingTool: String? = nil
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(toolDirectory.path):\(environment["PATH"] ?? "")"
        environment["IOS_RUN_LOG"] = logURL.path
        environment["IOS_RUN_DEVICE_LIST"] = deviceList
        environment["IOS_DERIVED_DATA"] = derivedDataURL.path
        environment["IOS_DEVICE"] = deviceOverride
        environment["IOS_RUN_FAIL_TOOL"] = failingTool
        return environment
    }

    private func readLog(at url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    private func readInvocations(at url: URL) throws -> [ToolInvocation] {
        let lines = try readLog(at: url)
        var invocations: [ToolInvocation] = []
        var currentTool: String?
        var currentArguments: [String] = []

        for line in lines {
            if line.hasPrefix("BEGIN:") {
                guard currentTool == nil else {
                    throw NSError(
                        domain: "IOSRunCommandContractTests",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Nested tool log entry"]
                    )
                }
                currentTool = String(line.dropFirst("BEGIN:".count))
                currentArguments = []
            } else if line.hasPrefix("ARG:") {
                guard currentTool != nil else {
                    throw NSError(
                        domain: "IOSRunCommandContractTests",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Argument outside tool log entry"]
                    )
                }
                currentArguments.append(String(line.dropFirst("ARG:".count)))
            } else if line == "END" {
                guard let tool = currentTool else {
                    throw NSError(
                        domain: "IOSRunCommandContractTests",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "End outside tool log entry"]
                    )
                }
                invocations.append(
                    ToolInvocation(tool: tool, arguments: currentArguments)
                )
                currentTool = nil
                currentArguments = []
            } else {
                throw NSError(
                    domain: "IOSRunCommandContractTests",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Unknown tool log line: \(line)"]
                )
            }
        }

        guard currentTool == nil else {
            throw NSError(
                domain: "IOSRunCommandContractTests",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Unterminated tool log entry"]
            )
        }
        return invocations
    }

    private func runFakeLauncher(
        deviceList: String? = nil,
        derivedDataDirectoryName: String = "derived-data",
        deviceOverride: String? = nil,
        failingTool: String? = nil
    ) throws -> FakeLauncherResult {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let toolDirectory = try createFakeToolchain(in: temporaryDirectory)
        let logURL = temporaryDirectory.appendingPathComponent("tool.log")
        let derivedDataURL = temporaryDirectory
            .appendingPathComponent(derivedDataDirectoryName)
        let command = try runCommand(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [launcherURL.path],
            environment: launcherEnvironment(
                toolDirectory: toolDirectory,
                logURL: logURL,
                deviceList: deviceList ?? shutdownIPhoneDeviceList,
                derivedDataURL: derivedDataURL,
                deviceOverride: deviceOverride,
                failingTool: failingTool
            )
        )
        return FakeLauncherResult(
            command: command,
            invocations: try readInvocations(at: logURL),
            derivedDataURL: derivedDataURL
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
        XCTAssertTrue(
            makefile.contains("override IOS_DEVICE := $(value IOS_DEVICE)")
        )
        XCTAssertTrue(
            makefile.contains(
                "override IOS_DERIVED_DATA := $(value IOS_DERIVED_DATA)"
            )
        )
        XCTAssertTrue(makefile.contains("export IOS_DEVICE IOS_DERIVED_DATA"))
        XCTAssertTrue(makefile.contains("\t@./scripts/ios-run.sh"))
        XCTAssertFalse(makefile.contains("IOS_DEVICE=\"$(IOS_DEVICE)\""))
        XCTAssertFalse(makefile.contains("IOS_DERIVED_DATA=\"$(IOS_DERIVED_DATA)\""))
    }

    func testMakePreservesRawCommandLineValuesWithoutExecutingFunctions() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let makefileURL = temporaryDirectory.appendingPathComponent("Probe.mk")
        let outputURL = temporaryDirectory.appendingPathComponent("values.txt")
        let deviceSentinelURL = temporaryDirectory
            .appendingPathComponent("device-expanded")
        let derivedDataSentinelURL = temporaryDirectory
            .appendingPathComponent("derived-data-expanded")
        let deviceValue = "$(shell /usr/bin/touch \(deviceSentinelURL.path); /usr/bin/printf raw-device)"
        let derivedDataValue = "$(shell /usr/bin/touch \(derivedDataSentinelURL.path); /usr/bin/printf raw-derived-data)"

        try """
        include \(repositoryRoot.path)/Makefile

        .PHONY: raw-value-probe
        raw-value-probe:
        \t@/usr/bin/printf '%s\\n%s\\n' "$$IOS_DEVICE" "$$IOS_DERIVED_DATA" > "\(outputURL.path)"
        """.write(to: makefileURL, atomically: true, encoding: .utf8)

        let result = try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/make"),
            arguments: [
                "-f",
                makefileURL.path,
                "raw-value-probe",
                "IOS_DEVICE=\(deviceValue)",
                "IOS_DERIVED_DATA=\(derivedDataValue)",
            ],
            currentDirectoryURL: repositoryRoot
        )

        XCTAssertEqual(result.terminationStatus, 0, result.standardError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: deviceSentinelURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: derivedDataSentinelURL.path)
        )
        XCTAssertEqual(
            try String(contentsOf: outputURL, encoding: .utf8),
            "\(deviceValue)\n\(derivedDataValue)\n"
        )
    }

    func testMakePreservesRawEnvironmentValuesWithoutExecutingFunctions() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let makefileURL = temporaryDirectory.appendingPathComponent("Probe.mk")
        let outputURL = temporaryDirectory.appendingPathComponent("values.txt")
        let sentinelURL = temporaryDirectory.appendingPathComponent("expanded")
        let rawValue = "$(shell /usr/bin/touch \(sentinelURL.path); /usr/bin/printf expanded)"

        try """
        include \(repositoryRoot.path)/Makefile

        .PHONY: raw-environment-probe
        raw-environment-probe:
        \t@/usr/bin/printf '%s\\n' "$$IOS_DEVICE" > "\(outputURL.path)"
        """.write(to: makefileURL, atomically: true, encoding: .utf8)
        var environment = ProcessInfo.processInfo.environment
        environment["IOS_DEVICE"] = rawValue

        let result = try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/make"),
            arguments: ["-f", makefileURL.path, "raw-environment-probe"],
            environment: environment,
            currentDirectoryURL: repositoryRoot
        )

        XCTAssertEqual(result.terminationStatus, 0, result.standardError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinelURL.path))
        XCTAssertEqual(
            try String(contentsOf: outputURL, encoding: .utf8),
            "\(rawValue)\n"
        )
    }

    func testMakeDryRunDoesNotInterpolateMaliciousOverrideIntoShell() throws {
        let result = try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/make"),
            arguments: [
                "-n",
                "ios-run",
                "IOS_DEVICE=\"; touch /tmp/chorai-ios-run-injection; #",
            ],
            currentDirectoryURL: repositoryRoot
        )

        XCTAssertEqual(result.terminationStatus, 0, result.standardError)
        XCTAssertEqual(result.standardOutput, "./scripts/ios-run.sh\n")
        XCTAssertFalse(result.standardOutput.contains("touch"))
    }

    func testExplicitDeviceOverrideWins() throws {
        XCTAssertEqual(
            try selectedDevice(
                from: shutdownIPhoneDeviceList,
                override: "iPhone 16e"
            ),
            "iPhone 16e"
        )
    }

    func testBootedIPhoneWinsWithoutOverride() throws {
        XCTAssertEqual(
            try selectedDevice(
                from: """
                {
                  "devices": {
                    "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
                      {
                        "name": "QA Phone Lab",
                        "udid": "62E58ABC-998B-4929-AF9B-888C6B076558",
                        "state": "Booted",
                        "isAvailable": true,
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M4"
                      },
                      {
                        "name": "Chorai iPhone SE 3 QA",
                        "udid": "86CD9628-7C27-4799-B237-3EEC82E7E9B5",
                        "state": "Booted",
                        "isAvailable": true,
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation"
                      }
                    ],
                    "com.apple.CoreSimulator.SimRuntime.watchOS-26-2": [
                      {
                        "name": "Apple Watch",
                        "udid": "11111111-1111-1111-1111-111111111111",
                        "state": "Booted",
                        "isAvailable": true,
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm"
                      }
                    ]
                  }
                }
                """
            ),
            "86CD9628-7C27-4799-B237-3EEC82E7E9B5"
        )
    }

    func testDefaultDeviceIsIPhone17ProWithoutBootedIPhone() throws {
        XCTAssertEqual(
            try selectedDevice(
                from: """
                {
                  "devices": {
                    "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
                      {
                        "name": "iPhone 16e",
                        "udid": "8F00CE99-FEBE-4774-9A07-4BBAF8A0FD1D",
                        "state": "Shutdown",
                        "isAvailable": true,
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-16e"
                      },
                      {
                        "name": "Renamed Tablet",
                        "udid": "62E58ABC-998B-4929-AF9B-888C6B076558",
                        "state": "Booted",
                        "isAvailable": true,
                        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad-A16"
                      }
                    ]
                  }
                }
                """
            ),
            "iPhone 17 Pro"
        )
    }

    func testSourcingLauncherDoesNotChangeCallerShellOptions() throws {
        let result = try runCommand(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [
                "-c",
                """
                unsetopt errexit nounset pipefail
                source "$1"
                print -r -- "${options[errexit]} ${options[nounset]} ${options[pipefail]}"
                """,
                "_",
                launcherURL.path,
            ]
        )

        XCTAssertEqual(result.terminationStatus, 0, result.standardError)
        XCTAssertEqual(result.standardOutput, "off off off\n")
    }

    func testFakeToolchainLogPreservesArgumentBoundaries() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let toolDirectory = try createFakeToolchain(in: temporaryDirectory)
        let logURL = temporaryDirectory.appendingPathComponent("tool.log")
        let derivedDataURL = temporaryDirectory
            .appendingPathComponent("derived data with spaces")
        var environment = ProcessInfo.processInfo.environment
        environment["IOS_RUN_LOG"] = logURL.path

        let result = try runCommand(
            executableURL: toolDirectory.appendingPathComponent("xcodebuild"),
            arguments: [
                "build",
                "-derivedDataPath",
                derivedDataURL.path,
            ],
            environment: environment
        )

        XCTAssertEqual(result.terminationStatus, 0, result.standardError)
        XCTAssertEqual(
            try readLog(at: logURL),
            [
                "BEGIN:xcodebuild",
                "ARG:build",
                "ARG:-derivedDataPath",
                "ARG:\(derivedDataURL.path)",
                "END",
            ]
        )
    }

    func testLauncherIsExecutable() throws {
        let launcher = try read("scripts/ios-run.sh")
        let attributes = try FileManager.default.attributesOfItem(
            atPath: launcherURL.path
        )
        let permissions = try XCTUnwrap(
            (attributes[.posixPermissions] as? NSNumber)?.intValue
        )

        XCTAssertNotEqual(permissions & 0o111, 0)
        for requiredText in [
            "xcrun simctl list devices available --json",
            "deviceTypeIdentifier",
            "choose_ios_device()",
            "main()",
        ] {
            XCTAssertTrue(launcher.contains(requiredText), requiredText)
        }
    }

    func testLauncherRunsBuildInstallAndLaunchWithFakeToolsInOrder() throws {
        let run = try runFakeLauncher(
            derivedDataDirectoryName: "derived data with spaces"
        )

        XCTAssertEqual(
            run.command.terminationStatus,
            0,
            run.command.standardError
        )
        XCTAssertEqual(
            run.invocations,
            [
                ToolInvocation(
                    tool: "xcrun",
                    arguments: ["simctl", "list", "devices", "available", "--json"]
                ),
                ToolInvocation(
                    tool: "xcrun",
                    arguments: ["simctl", "boot", "iPhone 17 Pro"]
                ),
                ToolInvocation(
                    tool: "xcrun",
                    arguments: ["simctl", "bootstatus", "iPhone 17 Pro", "-b"]
                ),
                ToolInvocation(tool: "open", arguments: ["-a", "Simulator"]),
                ToolInvocation(
                    tool: "xcodebuild",
                    arguments: [
                        "build",
                        "-quiet",
                        "-project",
                        "\(repositoryRoot.path)/ArcNote.xcodeproj",
                        "-scheme",
                        "ArcNote",
                        "-configuration",
                        "Debug",
                        "-destination",
                        "platform=iOS Simulator,name=iPhone 17 Pro",
                        "-derivedDataPath",
                        run.derivedDataURL.path,
                        "CODE_SIGNING_ALLOWED=NO",
                    ]
                ),
                ToolInvocation(
                    tool: "xcrun",
                    arguments: [
                        "simctl",
                        "install",
                        "iPhone 17 Pro",
                        "\(run.derivedDataURL.path)/Build/Products/Debug-iphonesimulator/ArcNote.app",
                    ]
                ),
                ToolInvocation(
                    tool: "xcrun",
                    arguments: [
                        "simctl",
                        "launch",
                        "--terminate-running-process",
                        "iPhone 17 Pro",
                        "com.michen.arcnote",
                    ]
                ),
            ]
        )
    }

    func testLauncherReturnsFailureWhenBootAndBootstatusFail() throws {
        let run = try runFakeLauncher(
            failingTool: "boot-and-bootstatus"
        )

        XCTAssertNotEqual(run.command.terminationStatus, 0)
        XCTAssertTrue(run.command.standardError.contains("status 23"))
        XCTAssertTrue(run.command.standardError.contains("fake boot failure"))
        XCTAssertTrue(run.command.standardError.contains("fake bootstatus failure"))
        XCTAssertTrue(
            run.command.standardError.contains("Unable to boot Simulator")
        )
        XCTAssertTrue(
            run.invocations.contains {
                $0.tool == "xcrun" && $0.arguments.prefix(2) == ["simctl", "bootstatus"]
            }
        )
        XCTAssertFalse(run.invocations.contains { $0.tool == "open" })
        XCTAssertFalse(run.invocations.contains { $0.tool == "xcodebuild" })
    }

    func testLauncherContinuesWhenBootFailsButBootstatusSucceeds() throws {
        let run = try runFakeLauncher(failingTool: "boot")

        XCTAssertEqual(
            run.command.terminationStatus,
            0,
            run.command.standardError
        )
        XCTAssertTrue(
            run.invocations.contains {
                $0.tool == "xcrun" && $0.arguments.prefix(2) == ["simctl", "bootstatus"]
            }
        )
        XCTAssertTrue(run.invocations.contains { $0.tool == "xcodebuild" })
    }

    func testLauncherStopsAtEachFailureGate() throws {
        struct FailureCase {
            let mode: String
            let expectedError: String
            let forbiddenTool: String
            let forbiddenArgumentPrefix: [String]
        }

        let failureCases = [
            FailureCase(
                mode: "list",
                expectedError: "fake list failure",
                forbiddenTool: "xcrun",
                forbiddenArgumentPrefix: ["simctl", "boot"]
            ),
            FailureCase(
                mode: "bootstatus",
                expectedError: "fake bootstatus failure",
                forbiddenTool: "open",
                forbiddenArgumentPrefix: []
            ),
            FailureCase(
                mode: "open",
                expectedError: "fake open failure",
                forbiddenTool: "xcodebuild",
                forbiddenArgumentPrefix: []
            ),
            FailureCase(
                mode: "build",
                expectedError: "fake build failure",
                forbiddenTool: "xcrun",
                forbiddenArgumentPrefix: ["simctl", "install"]
            ),
            FailureCase(
                mode: "missing-app",
                expectedError: "Built app not found",
                forbiddenTool: "xcrun",
                forbiddenArgumentPrefix: ["simctl", "install"]
            ),
            FailureCase(
                mode: "install",
                expectedError: "fake install failure",
                forbiddenTool: "xcrun",
                forbiddenArgumentPrefix: ["simctl", "launch"]
            ),
        ]

        for failureCase in failureCases {
            let run = try runFakeLauncher(
                derivedDataDirectoryName: "derived data with spaces",
                failingTool: failureCase.mode
            )

            XCTAssertNotEqual(
                run.command.terminationStatus,
                0,
                "\(failureCase.mode) unexpectedly succeeded"
            )
            XCTAssertTrue(
                (run.command.standardOutput + run.command.standardError)
                    .contains(failureCase.expectedError),
                "\(failureCase.mode) did not report \(failureCase.expectedError)"
            )
            XCTAssertFalse(
                run.invocations.contains {
                    $0.tool == failureCase.forbiddenTool
                        && $0.arguments.starts(
                            with: failureCase.forbiddenArgumentPrefix
                        )
                },
                "\(failureCase.mode) ran a later command"
            )
        }

        let launchRun = try runFakeLauncher(
            derivedDataDirectoryName: "derived data with spaces",
            failingTool: "launch"
        )
        XCTAssertNotEqual(launchRun.command.terminationStatus, 0)
        XCTAssertTrue(
            launchRun.command.standardError.contains("fake launch failure")
        )
        XCTAssertFalse(
            launchRun.command.standardOutput.contains("ArcNote is running")
        )
    }

    func testDocumentationMarksFinalImplementationAndSupersededSnippets() throws {
        let design = try read(
            "docs/superpowers/specs/2026-07-20-ios-run-command-design.md"
        )
        let plan = try read(
            "docs/superpowers/plans/2026-07-20-ios-run-command.md"
        )

        XCTAssertTrue(
            design.lowercased().contains("reviewed and implemented")
        )
        XCTAssertTrue(plan.contains("## Final Implementation Results"))
        XCTAssertTrue(plan.contains("superseded"))
        XCTAssertTrue(plan.contains("IOSRunCommandContractTests"))
    }
}
