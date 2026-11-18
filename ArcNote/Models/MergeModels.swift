import Foundation
import CoreFlow

// MARK: Go merge API DTOs
struct MergeSourceRef: Codable {
    let assetId: String
    let versionId: String
}

struct MergeCardsRequest: Codable {
    let sources: [MergeSourceRef]
    let idemKey: String

    init(
        sources: [MergeSourceRef],
        idemKey: String
    ) {
        self.sources = sources
        self.idemKey = idemKey
    }
}

struct MergeJobResponse: Codable {
    let schemaVersion: String
    let jobId: String
    let status: String
    let route: String
    let surpriseKind: String
    let artifactId: String
}

typealias MergeBlockNodeDTO = CoreFlow.MergeBlockNodeDTO
typealias MergeArtifactResponse = CoreFlow.MergeArtifactResponseDTO
typealias MergeArtifactPresentationDTO = CoreFlow.MergeArtifactPresentation

struct MergeArtifactSaveRequestDTO {
    let baseRevision: Int
    let baseHash: String
    let idemKey: String
    let documentJSON: Data
    let tags: [String]

    init(
        baseRevision: Int,
        baseHash: String,
        idemKey: String,
        documentJSON: Data,
        tags: [String]
    ) throws {
        self.baseRevision = baseRevision
        self.baseHash = baseHash
        self.idemKey = idemKey
        let editable = try MergeArtifactEditorCodec.decode(
            cardDocumentJSON: documentJSON
        )
        self.documentJSON = try MergeArtifactEditorCodec.encode(
            blockNoteJSON: editable.blockNoteJSON,
            preserving: editable.preservationManifest
        )
        self.tags = tags
    }

    func canonicalBody() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]

        var body = Data(#"{"baseHash":"#.utf8)
        body.append(try encoder.encode(baseHash))
        body.append(Data(",\"baseRevision\":".utf8))
        body.append(Data(String(baseRevision).utf8))
        body.append(Data(",\"doc\":".utf8))
        body.append(documentJSON)
        body.append(Data(",\"idemKey\":".utf8))
        body.append(try encoder.encode(idemKey))
        body.append(Data(",\"tags\":".utf8))
        body.append(try encoder.encode(tags))
        body.append(Data("}".utf8))
        return body
    }
}

struct MergeArtifactSaveResponse: Codable {
    let schemaVersion: String
    let artifactId: String
    let revision: Int
    let docHash: String
    let presentationHash: String
    let presentation: MergeArtifactPresentationDTO
    let validationStatus: String
    let validationErrors: [String]
}

struct CommitMergeJobRequest: Codable {
    let revision: Int
    let artifactHash: String
    let idemKey: String
}

struct CancelMergeJobRequest: Codable {
    let idemKey: String
}

struct MergeCommitResponse: Codable {
    let schemaVersion: String
    let commitId: String
    let jobId: String
    let artifactId: String
    let revision: Int
    let artifactHash: String
    let projectionContract: String
    let noteAssetId: String
    let assetVersionId: String
    let noteDocumentVersionId: String
    let noteDocHash: String
    let activityId: String
    let actionLogId: String
}

struct MergeCapabilityDTO: Codable {
    let capabilityId: String
    let displayName: String?
    let outputKind: String
    let blockExport: Bool
    let slotCommit: Bool
    let enabled: Bool
    let rolloutStage: String?
}

struct MergeCapabilitiesResponse: Codable {
    let capabilities: [MergeCapabilityDTO]
}
