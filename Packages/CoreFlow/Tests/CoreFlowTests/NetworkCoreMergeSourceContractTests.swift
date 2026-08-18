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
        let commitDeclaration = try declaration(
            named: "func commit(",
            until: "private static func mapJob",
            in: serviceSource
        )

        XCTAssertFalse(modelSource.contains("let capability: String\n    let idemKey"))
        XCTAssertFalse(modelSource.contains("let context: [String: MergeJSONValue]"))
        XCTAssertTrue(modelSource.contains("let versionId: String"))
        XCTAssertTrue(modelSource.contains("let revision: Int\n    let artifactHash: String\n    let idemKey: String"))
        XCTAssertTrue(modelSource.contains("let noteAssetId: String"))
        XCTAssertTrue(modelSource.contains("let actionLogId: String"))

        XCTAssertTrue(serviceSource.contains("guard let versionID = $0.versionID"))
        XCTAssertFalse(commitDeclaration.contains("network.getMergeArtifact(jobId: jobID)"))
        XCTAssertTrue(commitDeclaration.contains("request.revision"))
        XCTAssertTrue(commitDeclaration.contains("request.artifactHash"))
        XCTAssertFalse(commitDeclaration.contains("artifact.latestRevision"))
        XCTAssertFalse(commitDeclaration.contains("artifact.latestHash"))
        XCTAssertTrue(serviceSource.contains("assetID: response.noteAssetId"))
        XCTAssertTrue(serviceSource.contains("logID: response.actionLogId"))
        XCTAssertTrue(serviceSource.contains("CancelMergeJobRequest("))
    }

    func testArtifactSaveUsesPutWithDocumentAndTagsAndNeverSendsRate() throws {
        let serviceSource = try source("ArcNote/CoreFlow/NetworkCoreMergeService.swift")
        let modelSource = try source("ArcNote/Models/MergeModels.swift")
        let networkSource = try source("ArcNote/NetworkManager.swift")
        let requestDeclaration = try declaration(
            named: "struct MergeArtifactSaveRequestDTO",
            until: "struct MergeArtifactSaveResponse",
            in: modelSource
        )

        XCTAssertTrue(requestDeclaration.contains("let baseRevision: Int"))
        XCTAssertTrue(requestDeclaration.contains("let baseHash: String"))
        XCTAssertTrue(requestDeclaration.contains("let idemKey: String"))
        XCTAssertTrue(requestDeclaration.contains("let documentJSON: Data"))
        XCTAssertTrue(requestDeclaration.contains("let tags: [String]"))
        XCTAssertTrue(requestDeclaration.contains("func canonicalBody() throws -> Data"))
        XCTAssertFalse(requestDeclaration.contains("rate"))

        XCTAssertTrue(networkSource.contains("func saveMergeArtifact("))
        XCTAssertTrue(networkSource.contains("jobID: String"))
        XCTAssertTrue(networkSource.contains("endpoint: \"/api/merge/jobs/\\(jobID)/artifact\""))
        XCTAssertTrue(networkSource.contains("method: .put"))
        XCTAssertTrue(networkSource.contains("responseType: MergeArtifactSaveResponse.self"))
        XCTAssertTrue(networkSource.contains("MergeRawJSONBodyEncoding("))
        XCTAssertTrue(networkSource.contains("body: try request.canonicalBody()"))
        XCTAssertTrue(networkSource.contains("suppressesPayloadLogging: true"))

        XCTAssertTrue(serviceSource.contains("func saveArtifact("))
        XCTAssertTrue(serviceSource.contains("network.saveMergeArtifact("))
        XCTAssertTrue(serviceSource.contains("documentJSON: request.documentJSON"))
        XCTAssertTrue(serviceSource.contains("presentationHash: response.presentationHash"))
    }

    func testArtifactReadKeepsRawDocumentBytesThroughTheNetworkBoundary() throws {
        let serviceSource = try source("ArcNote/CoreFlow/NetworkCoreMergeService.swift")
        let modelSource = try source("ArcNote/Models/MergeModels.swift")
        let networkSource = try source("ArcNote/NetworkManager.swift")
        let readDeclaration = try declaration(
            named: "func getMergeArtifact(jobId: String)",
            until: "func saveMergeArtifact(",
            in: networkSource
        )

        XCTAssertTrue(
            modelSource.contains(
                "typealias MergeArtifactResponse = CoreFlow.MergeArtifactResponseDTO"
            )
        )
        XCTAssertTrue(readDeclaration.contains("requestData("))
        XCTAssertTrue(
            readDeclaration.contains(
                "MergeArtifactResponse.decode(responseData: $0)"
            )
        )
        XCTAssertFalse(
            readDeclaration.contains("responseType: MergeArtifactResponse.self")
        )
        XCTAssertTrue(serviceSource.contains("documentJSON: response.documentJSON"))
        XCTAssertFalse(serviceSource.contains("response.document.canonicalJSON()"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func declaration(
        named start: String,
        until end: String,
        in source: String
    ) throws -> String {
        let startRange = try XCTUnwrap(source.range(of: start))
        let endRange = try XCTUnwrap(
            source.range(of: end, range: startRange.upperBound..<source.endIndex)
        )
        return String(source[startRange.lowerBound..<endRange.lowerBound])
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
