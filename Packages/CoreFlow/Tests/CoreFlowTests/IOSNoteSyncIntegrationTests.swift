import Foundation
import XCTest

final class IOSNoteSyncIntegrationTests: XCTestCase {
    func testReachabilityLivesWithNetworkManager() throws {
        let source = try source("ArcNote/NetworkManager.swift")
        XCTAssertTrue(source.contains("private let reachabilityManager = NetworkReachabilityManager()"))
        XCTAssertFalse(source.contains("private func startNetworkMonitoring() {\n        let reachabilityManager"))
    }

    func testSyncTransportUsesFrozenBytesAndSessionFenceWithoutGlobalLogout() throws {
        let network = try source("ArcNote/NetworkManager.swift")
        let start = try XCTUnwrap(network.range(of: "// MARK: - Scoped note synchronization"))
        let sync = String(network[start.lowerBound...])
        XCTAssertTrue(sync.contains("httpBody = body"))
        XCTAssertTrue(sync.contains("sessionGeneration"))
        XCTAssertTrue(sync.contains("authToken == token"))
        XCTAssertTrue(sync.contains("NoteSyncHTTP.failure"))
        XCTAssertFalse(sync.contains("UnauthorizedError"))
        XCTAssertFalse(sync.contains("print("))
        let project = try source("ArcNote.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("NetworkNoteSyncService.swift in Sources"))
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
