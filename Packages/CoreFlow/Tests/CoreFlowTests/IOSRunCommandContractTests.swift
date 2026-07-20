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
