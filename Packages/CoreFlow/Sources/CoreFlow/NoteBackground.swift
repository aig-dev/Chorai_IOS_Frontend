import CoreData
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum NoteBackgroundError: Error, Equatable, Sendable {
    case invalidImage, unreadable, changed, unresolved, stale, rejected, expired, unknown
}

public struct NoteBackgroundObservation: Equatable, Sendable {
    public let revision: Int64
    public let displayRef: String?
    public init(revision: Int64, displayRef: String?) {
        self.revision = revision
        self.displayRef = displayRef
    }
}

public struct NoteBackgroundCommand: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case staged, submitted, attachedRef, refreshUpload, rejected }
    public let scope: NoteStoreScope
    public let localID: String
    public let id: UUID
    public var assetID: String?
    public let baseline: Int64
    public let image: NoteLocalAttachment?
    public let width: Int?
    public let height: Int?
    public var requiredBodyRevision: Int64? = nil
    public var logicalRef: String?
    public var phase: Phase
    public var canCancel: Bool { phase == .staged || phase == .rejected }
    public static let maxRevision: Int64 = 9_007_199_254_740_991
    public static func validRef(_ value: String) -> Bool {
        value.utf8.count == 20 && value.hasPrefix("med_") &&
            value.utf8.dropFirst(4).allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    fileprivate func validate(scope: NoteStoreScope, localID: String) throws {
        guard self.scope == scope, self.localID == localID, !localID.isEmpty,
              (0...Self.maxRevision).contains(baseline), requiredBodyRevision.map({ $0 > 0 }) ?? true,
              assetID.map(NotePrivacyWire.validID) ?? (baseline == 0),
              logicalRef.map(Self.validRef) ?? true,
              (logicalRef != nil) == (phase == .attachedRef || phase == .refreshUpload),
              logicalRef == nil || (assetID != nil && image != nil) else { throw NoteBackgroundError.unreadable }
        if let image {
            let safePath = SHA256.hash(data: Data(id.uuidString.utf8)).map { String(format: "%02x", $0) }.joined() + ".data"
            let filenames = ["image/png": "card-background.png", "image/jpeg": "card-background.jpg",
                             "image/gif": "card-background.gif", "image/webp": "card-background.webp"]
            guard image.uploadID == id.uuidString, image.relativePath == safePath, image.mediaRef == nil,
                  filenames[image.mimeType] == image.originalFilename,
                  image.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  (1...CardEditingImage.maxBackgroundBytes).contains(image.byteCount),
                  image.sha256.utf8.count == 64, (width ?? 0) > 0, (height ?? 0) > 0 else {
                throw NoteBackgroundError.unreadable
            }
        } else if width != nil || height != nil || logicalRef != nil || phase == .rejected {
            throw NoteBackgroundError.unreadable
        }
    }
}

extension NoteLocalStore {
    private static func backgroundName(_ localID: String) -> String {
        SHA256.hash(data: Data(localID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func backgroundFile(_ localID: String) throws -> URL {
        guard !localID.isEmpty else { throw NoteLocalStoreError.invalidIdentity }
        let directory = directoryURL.appendingPathComponent("background-commands", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(Self.backgroundName(localID))
    }

    private func backgroundBytes(_ localID: String) throws -> NoteAttachmentFiles {
        try NoteAttachmentFiles(directoryURL: directoryURL.appendingPathComponent("background-images").appendingPathComponent(Self.backgroundName(localID)))
    }

    static func removePurgedBackground(directory: URL, localID: String) throws {
        for folder in ["background-commands", "background-images"] {
            let path = directory.appendingPathComponent(folder).appendingPathComponent(backgroundName(localID))
            do { try FileManager.default.removeItem(at: path) }
            catch let error as CocoaError where error.code == .fileNoSuchFile { continue }
        }
    }

    private static func readBackground(at url: URL, scope: NoteStoreScope, localID: String) throws -> NoteBackgroundCommand? {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        guard let cmd = try? JSONDecoder().decode(NoteBackgroundCommand.self, from: data) else {
            throw NoteBackgroundError.unreadable
        }
        try cmd.validate(scope: scope, localID: localID)
        return cmd
    }

    public func background(localID: String) throws -> NoteBackgroundCommand? {
        try Self.readBackground(at: backgroundFile(localID), scope: scope, localID: localID)
    }

    public func backgroundImage(_ command: NoteBackgroundCommand) throws -> CardEditingImage? {
        guard try background(localID: command.localID) == command else { throw NoteBackgroundError.changed }
        guard let image = command.image else { return nil }
        let data = try backgroundBytes(command.localID).read(image)
        return CardEditingImage(data: data, filename: image.originalFilename, mimeType: image.mimeType)
    }

    private static func writeBackground(_ command: NoteBackgroundCommand, to url: URL) throws {
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(command).write(to: url, options: options)
    }

    public func stageBackground(localID: String, assetID: String?, baseline: Int64, image: CardEditingImage?,
                                expected: NoteBackgroundCommand?, createPlaceholder: Bool) async throws -> NoteBackgroundCommand {
        guard (0...NoteBackgroundCommand.maxRevision).contains(baseline), assetID.map(NotePrivacyWire.validID) ?? (baseline == 0) else {
            throw NoteBackgroundError.changed
        }
        guard expected == nil || expected?.phase == .staged else { throw NoteBackgroundError.unresolved }
        let url = try backgroundFile(localID)
        let scope = scope
        let id = UUID()
        var retained: NoteLocalAttachment?
        var width: Int?, height: Int?
        let files = try backgroundBytes(localID)
        if let image {
            guard image.isValidBackground,
                  let source = CGImageSourceCreateWithData(image.data as CFData, nil),
                  let type = CGImageSourceGetType(source) as String?,
                  let ext = ["public.png":"png", "public.jpeg":"jpg", "com.compuserve.gif":"gif", "org.webmproject.webp":"webp"][type],
                  let mime = UTType(type)?.preferredMIMEType,
                  let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let w = info[kCGImagePropertyPixelWidth] as? Int, w > 0,
                  let h = info[kCGImagePropertyPixelHeight] as? Int, h > 0 else { throw NoteBackgroundError.invalidImage }
            // PhotosPicker can advertise a different image representation from its transferred bytes.
            retained = try files.retain(data: image.data, filename: "card-background." + ext, mimeType: mime, uploadID: id.uuidString)
            width = w; height = h
        }
        let command = NoteBackgroundCommand(scope: scope, localID: localID, id: id, assetID: assetID, baseline: baseline,
            image: retained, width: width, height: height, logicalRef: nil, phase: .staged)
        try command.validate(scope: scope, localID: localID)
        do {
            try await transaction { context in
                guard try Self.readBackground(at: url, scope: scope, localID: localID) == expected else { throw NoteBackgroundError.changed }
                if let row = try Self.row(localID: localID, in: context) {
                    let note = try Self.decode(row, scope: scope)
                    guard note.serverAssetID == assetID, note.desiredLifecycle == .active, note.pendingPurge == nil else {
                        throw NoteBackgroundError.changed
                    }
                } else {
                    guard createPlaceholder, assetID == nil, expected == nil else { throw NoteBackgroundError.changed }
                    try Self.write(OfflineNote(localID: localID, body: .init(content: "")), scope: scope, in: context)
                }
                try Self.writeBackground(command, to: url)
                if context.hasChanges {
                    do { try context.save() }
                    catch {
                        try FileManager.default.removeItem(at: url)
                        throw error
                    }
                }
            }
        } catch {
            if let image = command.image { try? FileManager.default.removeItem(at: files.directoryURL.appendingPathComponent(image.relativePath)) }
            throw error
        }
        if let old = expected?.image { try? FileManager.default.removeItem(at: files.directoryURL.appendingPathComponent(old.relativePath)) }
        return command
    }

    public func advanceBackground(_ command: NoteBackgroundCommand, assetID: String?, phase: NoteBackgroundCommand.Phase,
                                  ref: String? = nil, bindBody: Bool = false) async throws -> NoteBackgroundCommand {
        guard ref == nil || command.logicalRef == nil || ref == command.logicalRef else { throw NoteBackgroundError.changed }
        let url = try backgroundFile(command.localID)
        let scope = scope
        switch (command.phase, phase) {
        case (.staged, .submitted), (.submitted, .attachedRef), (.submitted, .rejected),
             (.attachedRef, .refreshUpload), (.refreshUpload, .attachedRef):
            break
        case (.submitted, .submitted) where (command.assetID == nil && assetID != nil) || (bindBody && command.requiredBodyRevision == nil):
            break
        default:
            throw NoteBackgroundError.changed
        }
        var next = command
        next.assetID = assetID
        next.phase = phase
        next.logicalRef = ref ?? command.logicalRef
        let update = next
        try update.validate(scope: scope, localID: command.localID)
        return try await transaction { context in
            guard try Self.readBackground(at: url, scope: scope, localID: command.localID) == command,
                  let row = try Self.row(localID: command.localID, in: context) else { throw NoteBackgroundError.changed }
            let note = try Self.decode(row, scope: scope)
            guard note.desiredLifecycle == .active, note.pendingPurge == nil,
                  note.serverAssetID == assetID, command.assetID == nil || command.assetID == assetID else {
                throw NoteBackgroundError.changed
            }
            var frozen = update
            if bindBody, frozen.requiredBodyRevision == nil { frozen.requiredBodyRevision = note.bodyRevision }
            try Self.writeBackground(frozen, to: url)
            return frozen
        }
    }

    public func requireBackgroundDelivery(_ command: NoteBackgroundCommand) async throws {
        let url = try backgroundFile(command.localID)
        let scope = scope
        try await transaction { context in
            guard let row = try Self.row(localID: command.localID, in: context),
                  try Self.readBackground(at: url, scope: scope, localID: command.localID) == command else { throw NoteBackgroundError.changed }
            let note = try Self.decode(row, scope: scope)
            guard let asset = command.assetID, note.serverAssetID == asset, note.baseSyncToken != nil,
                  note.desiredLifecycle == .active, note.confirmedLifecycle == .active, note.pendingPurge == nil,
                  let required = command.requiredBodyRevision, note.acknowledgedBodyRevision >= required else {
                throw NoteBackgroundError.unresolved
            }
        }
    }

    public func retireBackground(_ command: NoteBackgroundCommand, current: NoteBackgroundObservation?,
                                 cancel: Bool = false) async throws {
        let url = try backgroundFile(command.localID)
        let files = try backgroundBytes(command.localID)
        let scope = scope
        try await transaction { context in
            guard try Self.readBackground(at: url, scope: scope, localID: command.localID) == command,
                  let row = try Self.row(localID: command.localID, in: context) else { throw NoteBackgroundError.changed }
            var note = try Self.decode(row, scope: scope)
            guard note.pendingPurge == nil, note.desiredLifecycle == .active,
                  command.assetID == nil || note.serverAssetID == command.assetID,
                  cancel ? command.canCancel : current != nil && command.assetID != nil else { throw NoteBackgroundError.changed }
            if let current {
                note.backgroundMediaRef = current.displayRef
                note.generation += 1
                try Self.write(note, scope: scope, in: context)
                // A crash after the confirmed metadata write leaves the original command replayable.
                try context.save()
            }
            try FileManager.default.removeItem(at: url)
            if cancel, note.serverAssetID == nil, note.bodyRevision == 1, note.body == OfflineNoteBody(content: ""),
               note.attachments.isEmpty, note.pendingOperation == nil, note.remoteSnapshot == nil, note.syncIssue == nil {
                context.delete(row)
            }
        }
        if let image = command.image {
            try? FileManager.default.removeItem(at: files.directoryURL.appendingPathComponent(image.relativePath))
        }
    }
}

public enum NoteBackgroundWire {
    private static func boolean(_ value: Any?, _ expected: Bool) -> Bool {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return value.boolValue == expected
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              !["f","d"].contains(String(cString: value.objCType)),
              let result = Int64(value.stringValue), (0...NoteBackgroundCommand.maxRevision).contains(result) else { return nil }
        return result
    }

    private static func payload(status: Int, data: Data, successStatus: Int, initialUpload: Bool = false) throws -> [String: Any] {
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NoteBackgroundError.unknown }
        if status == successStatus, Set(envelope.keys) == ["success","data"], boolean(envelope["success"], true),
           let value = envelope["data"] as? [String: Any] { return value }
        guard Set(envelope.keys) == ["success","error"], boolean(envelope["success"], false),
              let error = envelope["error"] as? [String: Any], let code = error["code"] as? String,
              let message = error["message"] as? String else { throw NoteBackgroundError.unknown }
        if initialUpload, status == 400, code == "VALIDATION_ERROR", Set(error.keys) == ["code","message"],
           message == "Please check your input and try again." { throw NoteBackgroundError.rejected }
        guard Set(error.keys) == ["code","message","reason"], let reason = error["reason"] as? String else { throw NoteBackgroundError.unknown }
        if status == 409, code == "CONFLICT",
           ["media_integrity_mismatch","idempotency_conflict"].contains(reason) || (successStatus == 200 && reason == "stale_background") {
            throw NoteBackgroundError.stale
        }
        if successStatus == 200, status == 400, code == "VALIDATION_ERROR", reason == "media_expired" { throw NoteBackgroundError.expired }
        throw NoteBackgroundError.unknown
    }

    public static func observation(status: Int, data: Data, scope: NoteStoreScope, asset: String,
                                   contentPath: (String) -> String) throws -> NoteBackgroundObservation {
        let v = try payload(status: status, data: data, successStatus: 200)
        guard v["id"] as? String == asset, v["owner_actor_id"] as? String == scope.actorID,
              let revision = integer(v["background_revision"]) else { throw NoteBackgroundError.unknown }
        var display: String?
        if let field = v["background_media_ref"] {
            guard let value = field as? String, !value.isEmpty, let url = URLComponents(string: value),
                  url.user == nil, url.password == nil, url.fragment == nil,
                  (url.scheme == nil && url.host == nil && value.hasPrefix("/") && !value.hasPrefix("//")) ||
                    (["https","http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil) else { throw NoteBackgroundError.unknown }
            if url.path.hasSuffix("/content") {
                let parts = url.path.split(separator: "/")
                guard parts.count >= 2 else { throw NoteBackgroundError.unknown }
                let ref = String(parts[parts.count - 2])
                if url.path == contentPath(ref) {
                    guard NoteBackgroundCommand.validRef(ref), value == contentPath(ref) + "?asset_id=" + asset else {
                        throw NoteBackgroundError.unknown
                    }
                }
            }
            display = value
        }
        return NoteBackgroundObservation(revision: revision, displayRef: display)
    }

    public static func upload(status: Int, data: Data, command: NoteBackgroundCommand,
                              contentPath: (String) -> String) throws -> String {
        let v = try payload(status: status, data: data, successStatus: 201, initialUpload: command.logicalRef == nil)
        guard let image = command.image,
              Set(v.keys) == ["bucket","object_key","media_ref","public_url","mime","size_bytes","width","height","sha256","upload_kind"],
              v["bucket"] is String, v["object_key"] is String,
              let ref = v["media_ref"] as? String, NoteBackgroundCommand.validRef(ref),
              command.logicalRef == nil || command.logicalRef == ref,
              v["public_url"] as? String == contentPath(ref), v["mime"] as? String == image.mimeType,
              let w = command.width, let h = command.height,
              integer(v["width"]) == Int64(w), integer(v["height"]) == Int64(h),
              integer(v["size_bytes"]) == Int64(image.byteCount), v["sha256"] as? String == image.sha256,
              v["upload_kind"] as? String == "background" else { throw NoteBackgroundError.unknown }
        return ref
    }
}
