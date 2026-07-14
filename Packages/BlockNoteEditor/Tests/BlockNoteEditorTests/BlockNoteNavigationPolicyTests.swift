import Foundation
import XCTest
@testable import BlockNoteEditor

final class BlockNoteNavigationPolicyTests: XCTestCase {
    func testOnlyInitialIndexNavigationIsAllowedInMainFrame() {
        let root = URL(fileURLWithPath: "/tmp/BlockNoteResources", isDirectory: true)
        let index = root.appendingPathComponent("index.html")
        var gate = BlockNoteNavigationGate(resourceDirectory: root, indexURL: index)
        let bootstrapNavigation = NSObject()
        gate.bindBootstrapNavigation(bootstrapNavigation)

        XCTAssertEqual(
            gate.decision(for: index, isMainFrame: true),
            .allow
        )
        XCTAssertTrue(gate.completeBootstrapNavigation(
            bootstrapNavigation,
            to: index
        ))
        XCTAssertEqual(
            gate.decision(for: index, isMainFrame: true),
            .cancel
        )
        XCTAssertEqual(
            gate.decision(
                for: root.appendingPathComponent("editor.js"),
                isMainFrame: true
            ),
            .cancel
        )
        XCTAssertFalse(gate.completeBootstrapNavigation(
            bootstrapNavigation,
            to: index
        ))
    }

    func testEveryFrameRejectsResourcesOutsideLocalDirectory() {
        let root = URL(fileURLWithPath: "/tmp/BlockNoteResources", isDirectory: true)
        let index = root.appendingPathComponent("index.html")
        var gate = BlockNoteNavigationGate(resourceDirectory: root, indexURL: index)

        XCTAssertEqual(
            gate.decision(
                for: URL(fileURLWithPath: "/tmp/BlockNoteResources-escape/index.html"),
                isMainFrame: true
            ),
            .cancel
        )
        XCTAssertEqual(
            gate.decision(
                for: URL(string: "https://example.com/phishing")!,
                isMainFrame: true
            ),
            .cancel
        )
        XCTAssertEqual(
            gate.decision(
                for: URL(string: "http://example.com/phishing")!,
                isMainFrame: false
            ),
            .cancel
        )
        XCTAssertEqual(
            gate.decision(
                for: root.appendingPathComponent("local-frame.html"),
                isMainFrame: false
            ),
            .allow
        )
    }

    func testSymlinkInsideResourceDirectoryCannotEscapeContainment() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resources = temporaryDirectory.appendingPathComponent("Resources", isDirectory: true)
        let outside = temporaryDirectory.appendingPathComponent("Outside", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try FileManager.default.createDirectory(
            at: resources,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: resources.appendingPathComponent("escape", isDirectory: true),
            withDestinationURL: outside
        )
        try Data().write(to: outside.appendingPathComponent("secret.html"))

        let index = resources.appendingPathComponent("index.html")
        var gate = BlockNoteNavigationGate(
            resourceDirectory: resources,
            indexURL: index
        )

        XCTAssertEqual(
            gate.decision(
                for: resources.appendingPathComponent("escape/secret.html"),
                isMainFrame: false
            ),
            .cancel
        )
    }

    func testBootstrapRequiresExactURLWithoutQueryFragmentOrRemoteAuthority() throws {
        let root = URL(fileURLWithPath: "/tmp/BlockNoteResources", isDirectory: true)
        let index = root.appendingPathComponent("index.html")

        var queryComponents = try XCTUnwrap(
            URLComponents(url: index, resolvingAgainstBaseURL: false)
        )
        queryComponents.query = "reload=1"
        let queryURL = try XCTUnwrap(queryComponents.url)

        var fragmentComponents = try XCTUnwrap(
            URLComponents(url: index, resolvingAgainstBaseURL: false)
        )
        fragmentComponents.fragment = "editor"
        let fragmentURL = try XCTUnwrap(fragmentComponents.url)

        let remoteAuthorityURL = try XCTUnwrap(
            URL(string: "file://attacker.invalid\(index.path)")
        )

        for candidate in [queryURL, fragmentURL, remoteAuthorityURL] {
            var gate = BlockNoteNavigationGate(resourceDirectory: root, indexURL: index)
            XCTAssertEqual(
                gate.decision(for: candidate, isMainFrame: true),
                .cancel,
                "Unexpectedly allowed \(candidate.absoluteString)"
            )
        }
    }

    func testOnlyOneBootstrapDecisionCanBeAuthorizedBeforeCompletion() {
        let root = URL(fileURLWithPath: "/tmp/BlockNoteResources", isDirectory: true)
        let index = root.appendingPathComponent("index.html")
        var gate = BlockNoteNavigationGate(resourceDirectory: root, indexURL: index)

        XCTAssertEqual(gate.decision(for: index, isMainFrame: true), .allow)
        XCTAssertEqual(gate.decision(for: index, isMainFrame: true), .cancel)
    }

    func testOnlyTheBoundBootstrapNavigationCanCompleteInitialization() {
        let root = URL(fileURLWithPath: "/tmp/BlockNoteResources", isDirectory: true)
        let index = root.appendingPathComponent("index.html")
        var gate = BlockNoteNavigationGate(resourceDirectory: root, indexURL: index)
        let bootstrapNavigation = NSObject()
        let unrelatedNavigation = NSObject()

        gate.bindBootstrapNavigation(bootstrapNavigation)
        XCTAssertEqual(gate.decision(for: index, isMainFrame: true), .allow)
        XCTAssertFalse(gate.completeBootstrapNavigation(
            unrelatedNavigation,
            to: index
        ))
        XCTAssertTrue(gate.completeBootstrapNavigation(
            bootstrapNavigation,
            to: index
        ))
    }
}
