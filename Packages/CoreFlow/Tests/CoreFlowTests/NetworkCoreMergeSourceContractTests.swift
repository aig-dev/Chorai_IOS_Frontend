import Foundation
import XCTest

final class NetworkCoreMergeSourceContractTests: XCTestCase {
    func testAvailabilityMatchesTheCurrentJobOnlyBackendContract() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "ArcNote/CoreFlow/NetworkCoreMergeService.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("listMergeCapabilities()"))
        XCTAssertTrue(source.contains("capabilityID: \"auto\""))
        XCTAssertTrue(source.contains("outputKind: .document"))
        XCTAssertTrue(source.contains("isEnabled: true"))
    }

    func testCreateCommitAndCancelMatchTheStrictVNextWireContract() throws {
        let serviceSource = try source("ArcNote/CoreFlow/NetworkCoreMergeService.swift")
        let modelSource = try source("ArcNote/Models/MergeModels.swift")

        XCTAssertFalse(modelSource.contains("let capability: String\n    let idemKey"))
        XCTAssertFalse(modelSource.contains("let context: [String: MergeJSONValue]"))
        XCTAssertTrue(modelSource.contains("let versionId: String"))
        XCTAssertTrue(modelSource.contains("let latestRevision: Int"))
        XCTAssertTrue(modelSource.contains("let latestHash: String"))
        XCTAssertTrue(modelSource.contains("let document: MergeCardDocumentDTO"))
        XCTAssertTrue(modelSource.contains("let revision: Int\n    let artifactHash: String\n    let idemKey: String"))
        XCTAssertTrue(modelSource.contains("let noteAssetId: String"))
        XCTAssertTrue(modelSource.contains("let actionLogId: String"))

        XCTAssertTrue(serviceSource.contains("guard let versionID = $0.versionID"))
        XCTAssertTrue(serviceSource.contains("network.getMergeArtifact(jobId: jobID)"))
        XCTAssertTrue(serviceSource.contains("revision: artifact.latestRevision"))
        XCTAssertTrue(serviceSource.contains("artifactHash: artifact.latestHash"))
        XCTAssertTrue(serviceSource.contains("assetID: response.noteAssetId"))
        XCTAssertTrue(serviceSource.contains("logID: response.actionLogId"))
        XCTAssertTrue(serviceSource.contains("CancelMergeJobRequest("))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
