import Foundation
import XCTest

final class IOSRunCommandContractTests: XCTestCase {
    private struct CommandResult {
        let terminationStatus: Int32
        let standardOutput: String
        let standardError: String
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
            print -r -- "xcrun:$*" >> "$IOS_RUN_LOG"

            if [[ "$1" == "simctl" && "$2" == "list" && "$3" == "devices" && "$4" == "available" ]]; then
                print -r -- "$IOS_RUN_DEVICE_LIST"
                exit 0
            fi

            if [[ "$1" == "simctl" && "$2" == "boot" && "${IOS_RUN_FAIL_TOOL:-}" == "boot" ]]; then
                print -u2 -- "fake boot failure"
                exit 23
            fi

            if [[ "$1" == "simctl" && "$2" == "bootstatus" && "${IOS_RUN_FAIL_TOOL:-}" == "bootstatus" ]]; then
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
            print -r -- "xcodebuild:$*" >> "$IOS_RUN_LOG"
            if [[ "${IOS_RUN_FAIL_TOOL:-}" == "xcodebuild" ]]; then
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
            mkdir -p "$derived_data/Build/Products/Debug-iphonesimulator/ArcNote.app"
            """,
            to: toolDirectory.appendingPathComponent("xcodebuild")
        )
        try writeExecutable(
            """
            #!/bin/zsh
            set -eu
            print -r -- "open:$*" >> "$IOS_RUN_LOG"
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
        XCTAssertTrue(makefile.contains("export IOS_DEVICE IOS_DERIVED_DATA"))
        XCTAssertTrue(makefile.contains("\t@./scripts/ios-run.sh"))
        XCTAssertFalse(makefile.contains("IOS_DEVICE=\"$(IOS_DEVICE)\""))
        XCTAssertFalse(makefile.contains("IOS_DERIVED_DATA=\"$(IOS_DERIVED_DATA)\""))
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
            "xcrun simctl list devices available",
            "choose_ios_device()",
            "main()",
        ] {
            XCTAssertTrue(launcher.contains(requiredText), requiredText)
        }
    }

    func testLauncherRunsBuildInstallAndLaunchWithFakeToolsInOrder() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let toolDirectory = try createFakeToolchain(in: temporaryDirectory)
        let logURL = temporaryDirectory.appendingPathComponent("tool.log")
        let derivedDataURL = temporaryDirectory.appendingPathComponent("derived-data")
        let deviceList = """
        == Devices ==
        -- iOS 26.2 --
            iPhone 17 Pro (43E6164C-1F4B-47E4-9B65-D154C7281A56) (Shutdown)
        """

        let result = try runCommand(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [launcherURL.path],
            environment: launcherEnvironment(
                toolDirectory: toolDirectory,
                logURL: logURL,
                deviceList: deviceList,
                derivedDataURL: derivedDataURL
            )
        )

        XCTAssertEqual(result.terminationStatus, 0, result.standardError)
        XCTAssertEqual(
            try readLog(at: logURL),
            [
                "xcrun:simctl list devices available",
                "xcrun:simctl boot iPhone 17 Pro",
                "xcrun:simctl bootstatus iPhone 17 Pro -b",
                "open:-a Simulator",
                "xcodebuild:build -quiet -project \(repositoryRoot.path)/ArcNote.xcodeproj -scheme ArcNote -configuration Debug -destination platform=iOS Simulator,name=iPhone 17 Pro -derivedDataPath \(derivedDataURL.path) CODE_SIGNING_ALLOWED=NO",
                "xcrun:simctl install iPhone 17 Pro \(derivedDataURL.path)/Build/Products/Debug-iphonesimulator/ArcNote.app",
                "xcrun:simctl launch --terminate-running-process iPhone 17 Pro com.michen.arcnote",
            ]
        )
    }

    func testLauncherSkipsBootWhenExplicitlySelectedDeviceIsAlreadyBooted() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let toolDirectory = try createFakeToolchain(in: temporaryDirectory)
        let logURL = temporaryDirectory.appendingPathComponent("tool.log")
        let deviceList = """
        == Devices ==
        -- iOS 26.2 --
            iPhone 16e (8F00CE99-FEBE-4774-9A07-4BBAF8A0FD1D) (Booted)
        """

        let result = try runCommand(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [launcherURL.path],
            environment: launcherEnvironment(
                toolDirectory: toolDirectory,
                logURL: logURL,
                deviceList: deviceList,
                derivedDataURL: temporaryDirectory.appendingPathComponent("derived-data"),
                deviceOverride: "iPhone 16e"
            )
        )

        XCTAssertEqual(result.terminationStatus, 0, result.standardError)
        XCTAssertFalse(
            try readLog(at: logURL).contains { $0.hasPrefix("xcrun:simctl boot ") }
        )
    }

    func testLauncherReturnsFailureWhenBootFails() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let toolDirectory = try createFakeToolchain(in: temporaryDirectory)
        let logURL = temporaryDirectory.appendingPathComponent("tool.log")
        let deviceList = """
        == Devices ==
        -- iOS 26.2 --
            iPhone 17 Pro (43E6164C-1F4B-47E4-9B65-D154C7281A56) (Shutdown)
        """

        let result = try runCommand(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [launcherURL.path],
            environment: launcherEnvironment(
                toolDirectory: toolDirectory,
                logURL: logURL,
                deviceList: deviceList,
                derivedDataURL: temporaryDirectory.appendingPathComponent("derived-data"),
                failingTool: "boot"
            )
        )

        XCTAssertNotEqual(result.terminationStatus, 0)
        XCTAssertTrue(result.standardError.contains("Unable to boot Simulator"))
        XCTAssertFalse(try readLog(at: logURL).contains { $0.hasPrefix("xcodebuild:") })
    }
}
