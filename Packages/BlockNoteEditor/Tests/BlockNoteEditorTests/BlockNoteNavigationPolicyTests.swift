import Foundation
import XCTest
@testable import BlockNoteEditor

final class BlockNoteNavigationPolicyTests: XCTestCase {
    func testOnlyInitialIndexNavigationIsAllowedInMainFrame() {
        let root = URL(fileURLWithPath: "/tmp/BlockNoteResources", isDirectory: true)
        let index = root.appendingPathComponent("index.html")
        var gate = BlockNoteNavigationGate(resourceDirectory: root, indexURL: index)

        XCTAssertEqual(
            gate.decision(for: index, isMainFrame: true),
            .allow
        )
        XCTAssertTrue(gate.completeBootstrapNavigation(to: index))
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
        XCTAssertFalse(gate.completeBootstrapNavigation(to: index))
    }

    func testEveryFrameRejectsResourcesOutsideLocalDirectory() {
        let root = URL(fileURLWithPath: "/tmp/BlockNoteResources", isDirectory: true)
        let index = root.appendingPathComponent("index.html")
        let gate = BlockNoteNavigationGate(resourceDirectory: root, indexURL: index)

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
}
