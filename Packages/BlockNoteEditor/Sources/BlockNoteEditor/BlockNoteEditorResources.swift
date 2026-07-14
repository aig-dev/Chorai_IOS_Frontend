import CryptoKit
import Foundation

public struct BlockNoteEditorResourceManifest: Codable, Equatable, Sendable {
    public struct Hashes: Codable, Equatable, Sendable {
        public let editorCSS: String
        public let editorJS: String
        public let indexHTML: String

        enum CodingKeys: String, CodingKey {
            case editorCSS = "editor.css"
            case editorJS = "editor.js"
            case indexHTML = "index.html"
        }

        public init(editorCSS: String, editorJS: String, indexHTML: String) {
            self.editorCSS = editorCSS
            self.editorJS = editorJS
            self.indexHTML = indexHTML
        }
    }

    public let protocolVersion: Int
    public let schemaVersion: Int
    public let blockNoteVersion: String
    public let hashes: Hashes

    public init(
        protocolVersion: Int,
        schemaVersion: Int,
        blockNoteVersion: String,
        hashes: Hashes
    ) {
        self.protocolVersion = protocolVersion
        self.schemaVersion = schemaVersion
        self.blockNoteVersion = blockNoteVersion
        self.hashes = hashes
    }
}

public enum BlockNoteEditorResourceError: Error, Equatable, Sendable {
    case missingResource(String)
    case unsupportedProtocolVersion(Int)
    case unsupportedSchemaVersion(Int)
    case invalidBlockNoteVersion
    case invalidHash(file: String)
    case hashMismatch(file: String)
}

extension BlockNoteEditorResourceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .missingResource(file):
            return "The bundled BlockNote resource is missing: \(file)."
        case let .unsupportedProtocolVersion(version):
            return "The BlockNote bundle uses unsupported protocol version \(version)."
        case let .unsupportedSchemaVersion(version):
            return "The BlockNote bundle uses unsupported schema version \(version)."
        case .invalidBlockNoteVersion:
            return "The BlockNote bundle manifest has no dependency version."
        case let .invalidHash(file):
            return "The BlockNote bundle manifest has an invalid SHA-256 for \(file)."
        case let .hashMismatch(file):
            return "The bundled BlockNote resource does not match its manifest: \(file)."
        }
    }
}

public enum BlockNoteEditorResources {
    public static func validateBundledResources() throws -> BlockNoteEditorResourceManifest {
        let directory = try resourceDirectory()
        let manifestURL = directory.appendingPathComponent("manifest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw BlockNoteEditorResourceError.missingResource("manifest.json")
        }

        let manifest = try decodeManifest(Data(contentsOf: manifestURL))
        try validateManifest(manifest)
        try validateResourceHashes(manifest, in: directory)
        return manifest
    }

    static func decodeManifest(_ data: Data) throws -> BlockNoteEditorResourceManifest {
        try JSONDecoder().decode(BlockNoteEditorResourceManifest.self, from: data)
    }

    static func validateManifest(_ manifest: BlockNoteEditorResourceManifest) throws {
        guard manifest.protocolVersion == BlockNoteEditorProtocol.version else {
            throw BlockNoteEditorResourceError.unsupportedProtocolVersion(manifest.protocolVersion)
        }
        guard manifest.schemaVersion == BlockNoteEditorProtocol.schemaVersion else {
            throw BlockNoteEditorResourceError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        guard !manifest.blockNoteVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BlockNoteEditorResourceError.invalidBlockNoteVersion
        }

        for (file, hash) in manifest.expectedHashes {
            guard hash.count == 64,
                  hash.unicodeScalars.allSatisfy({
                      (48 ... 57).contains($0.value) || (97 ... 102).contains($0.value)
                  }) else {
                throw BlockNoteEditorResourceError.invalidHash(file: file)
            }
        }
    }

    static func validateResourceHashes(
        _ manifest: BlockNoteEditorResourceManifest,
        in directory: URL
    ) throws {
        for (file, expectedHash) in manifest.expectedHashes {
            let fileURL = directory.appendingPathComponent(file, isDirectory: false)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw BlockNoteEditorResourceError.missingResource(file)
            }
            let actualHash = sha256(try Data(contentsOf: fileURL))
            guard actualHash == expectedHash else {
                throw BlockNoteEditorResourceError.hashMismatch(file: file)
            }
        }
    }

    static func resourceDirectory() throws -> URL {
        guard let manifestURL = Bundle.module.url(
            forResource: "manifest",
            withExtension: "json"
        ) else {
            throw BlockNoteEditorResourceError.missingResource("manifest.json")
        }
        return manifestURL.deletingLastPathComponent().standardizedFileURL
    }

    static func indexURL() throws -> URL {
        let url = try resourceDirectory().appendingPathComponent("index.html", isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BlockNoteEditorResourceError.missingResource("index.html")
        }
        return url
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension BlockNoteEditorResourceManifest {
    var expectedHashes: [(String, String)] {
        [
            ("editor.css", hashes.editorCSS),
            ("editor.js", hashes.editorJS),
            ("index.html", hashes.indexHTML),
        ]
    }
}
