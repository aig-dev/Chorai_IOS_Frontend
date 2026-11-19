import Foundation

public struct MergeArtifactPreparedProjection: Sendable {
    public let editable: MergeArtifactEditableDocument
    public let unresolvedMediaReferences: [String]
    public let displayURLsByMediaReference: [String: String]
}

public struct MergeArtifactPreparedDraft: Sendable {
    public let documentJSON: Data
    public let unresolvedMediaReferences: [String]
}

/// Pure document conversion. The caller retains identity, ordering and authority.
public actor MergeArtifactEditorWorker {
    enum Work: Sendable { case cleanDraft, project, prepareDraft }
    private let beforeWork: (@Sendable (Work) async throws -> Void)?
    private let probe: (@Sendable () -> Void)?
    private let decodeProbe: (@Sendable () -> Void)?
    private let cacheByteLimit: Int
    private var decoded: (input: Data, value: MergeArtifactEditableDocument)?

    public init() { beforeWork = nil; probe = nil; decodeProbe = nil; cacheByteLimit = 1_048_576 }

    init(beforeWork: (@Sendable (Work) async throws -> Void)?, probe: (@Sendable () -> Void)? = nil,
         decodeProbe: (@Sendable () -> Void)? = nil, cacheByteLimit: Int = 1_048_576) {
        self.beforeWork = beforeWork
        self.probe = probe
        self.decodeProbe = decodeProbe
        self.cacheByteLimit = max(0, cacheByteLimit)
    }

    public func cleanDraft(from artifact: MergeArtifact) async throws -> MergeArtifactDraftSnapshot {
        try await beforeWork?(.cleanDraft)
        try Task.checkCancellation()
        probe?()
        // Unsupported documents keep their original bytes and reach the existing
        // read-only compatibility path; only the optional edit manifest is empty.
        let manifest = (try? editableDocument(artifact.documentJSON).preservationManifest) ?? Data()
        return MergeArtifactDraftSnapshot(baseRevision: artifact.latestRevision,
            baseDocumentHash: artifact.latestHash, documentJSON: artifact.documentJSON,
            tags: CardEditingTag.normalize(artifact.presentation.tags), rate: artifact.presentation.rate,
            preservationManifest: manifest, pendingSave: nil)
    }

    private func editableDocument(_ input: Data) throws -> MergeArtifactEditableDocument {
        if let decoded, decoded.input == input { return decoded.value }
        decoded = nil
        decodeProbe?()
        let value = try MergeArtifactEditorCodec.decode(cardDocumentJSON: input)
        let bytes = input.count + value.blockNoteJSON.utf8.count + value.fallbackMarkdown.utf8.count
            + value.preservationManifest.count
        if bytes <= cacheByteLimit { decoded = (input, value) }
        return value
    }

    public func project(cardDocumentJSON: Data,
                        displayURLsByMediaReference: [String: String]) async throws -> MergeArtifactPreparedProjection {
        try await beforeWork?(.project)
        try Task.checkCancellation()
        probe?()
        let editable = try editableDocument(cardDocumentJSON)
        let urls = Self.validatedDisplayURLs(displayURLsByMediaReference)
        return MergeArtifactPreparedProjection(editable: editable,
            unresolvedMediaReferences: Self.unresolvedMediaReferences(in: editable.blockNoteJSON, authorized: urls),
            displayURLsByMediaReference: urls)
    }

    public func prepareDraft(blockNoteJSON: String, preserving manifest: Data,
                             displayURLsByMediaReference: [String: String]) async throws -> MergeArtifactPreparedDraft {
        try await beforeWork?(.prepareDraft)
        probe?()
        let document = try MergeArtifactEditorCodec.encode(blockNoteJSON: blockNoteJSON, preserving: manifest)
        return MergeArtifactPreparedDraft(documentJSON: document,
            unresolvedMediaReferences: Self.unresolvedMediaReferences(in: blockNoteJSON,
                authorized: Self.validatedDisplayURLs(displayURLsByMediaReference)))
    }

    public func fallbackMarkdown(from document: MergeDocument?) -> String {
        let text = document?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "Merge content is unavailable." : text
    }

    static func validatedDisplayURLs(
        _ values: [String: String]
    ) -> [String: String] {
        values.reduce(into: [:]) { result, entry in
            guard !entry.key.isEmpty,
                  let url = URL(string: entry.value),
                  let scheme = url.scheme?.lowercased(),
                  ["https", "http"].contains(scheme),
                  url.host != nil,
                  url.user == nil,
                  url.password == nil else {
                return
            }
            result[entry.key] = url.absoluteString
        }
    }

    static func unresolvedMediaReferences(
        in blockNoteJSON: String,
        authorized: [String: String]
    ) -> [String] {
        guard let data = blockNoteJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        var references = Set<String>()
        collectMediaReferences(in: root, into: &references)
        return references
            .filter { authorized[$0] == nil }
            .sorted()
    }

    static func collectMediaReferences(
        in value: Any,
        into references: inout Set<String>
    ) {
        if let values = value as? [Any] {
            values.forEach { collectMediaReferences(in: $0, into: &references) }
            return
        }
        guard let object = value as? [String: Any] else { return }
        if let mediaReference = object["mediaRef"] as? String,
           !mediaReference.isEmpty {
            references.insert(mediaReference)
        }
        object.values.forEach {
            collectMediaReferences(in: $0, into: &references)
        }
    }
}
