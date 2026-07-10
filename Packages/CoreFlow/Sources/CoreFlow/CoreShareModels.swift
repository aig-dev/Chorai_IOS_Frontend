import Foundation

public struct ShareActions: Equatable, Sendable {
    public let canDownload: Bool
    public let canNativeShare: Bool
    public let canCopyLink: Bool
    public let canShareToX: Bool

    public init(
        canDownload: Bool,
        canNativeShare: Bool,
        canCopyLink: Bool,
        canShareToX: Bool
    ) {
        self.canDownload = canDownload
        self.canNativeShare = canNativeShare
        self.canCopyLink = canCopyLink
        self.canShareToX = canShareToX
    }
}

public struct ShareArtifact: Equatable, Sendable {
    public let id: String
    public let kind: String
    public let imageURL: String
    public let contentType: String
    public let width: Int
    public let height: Int
    public let status: String

    public init(
        id: String,
        kind: String,
        imageURL: String,
        contentType: String,
        width: Int,
        height: Int,
        status: String
    ) {
        self.id = id
        self.kind = kind
        self.imageURL = imageURL
        self.contentType = contentType
        self.width = width
        self.height = height
        self.status = status
    }
}

public struct ShareCardPreview: Equatable, Sendable {
    public let noteID: String
    public let noteVersionID: String
    public let artifactKind: String
    public let artifact: ShareArtifact
    public let actions: ShareActions

    public init(
        noteID: String,
        noteVersionID: String,
        artifactKind: String,
        artifact: ShareArtifact,
        actions: ShareActions
    ) {
        self.noteID = noteID
        self.noteVersionID = noteVersionID
        self.artifactKind = artifactKind
        self.artifact = artifact
        self.actions = actions
    }
}

public struct ShareArtifactPin: Equatable, Sendable {
    public let noteID: String
    public let noteVersionID: String
    public let artifactID: String
    public let artifactKind: String

    public init(
        noteID: String,
        noteVersionID: String,
        artifactID: String,
        artifactKind: String
    ) {
        self.noteID = noteID
        self.noteVersionID = noteVersionID
        self.artifactID = artifactID
        self.artifactKind = artifactKind
    }
}

public struct NativeSharePayload: Equatable, Identifiable, Sendable {
    public let id: String
    public let artifactID: String
    public let imageData: Data

    public init(
        id: String = UUID().uuidString,
        artifactID: String,
        imageData: Data
    ) {
        self.id = id
        self.artifactID = artifactID
        self.imageData = imageData
    }
}

public enum CoreShareError: Error, Equatable, Sendable {
    case transport(code: String)
    case invalidResponse(code: String)
    case actionUnavailable(code: String)

    public var code: String {
        switch self {
        case .transport(let code),
             .invalidResponse(let code),
             .actionUnavailable(let code):
            return code
        }
    }
}

public enum ShareCardPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case preparingNativeShare
    case failed(CoreShareError)
}
