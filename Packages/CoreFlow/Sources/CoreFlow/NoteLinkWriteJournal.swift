import CryptoKit
import Foundation

public struct NoteLinkWriteAttempt: Codable, Equatable, Sendable {
    public enum Operation: String, Codable, Sendable { case link, unlink }
    public let version: Int
    public let apiBaseURL: String
    public let actorID: String
    public let operation: Operation
    public let sourceID: String
    public let targetID: String
    public let noteLinkID: String?
    public let requestID: String
}

public struct NoteLinkWriteReceipt: Sendable {
    public enum State: String, Sendable { case active = "ACTIVE", ended = "ENDED" }
    public let requestID: String
    public let sourceID: String
    public let targetID: String
    public let noteLinkID: String
    public let activityID: String
    public let actionLogID: String
    public let state: State

    public init(requestID: String, sourceID: String, targetID: String, noteLinkID: String,
                activityID: String, actionLogID: String, state: State) {
        self.requestID = requestID
        self.sourceID = sourceID
        self.targetID = targetID
        self.noteLinkID = noteLinkID
        self.activityID = activityID
        self.actionLogID = actionLogID
        self.state = state
    }
}

/// One unresolved command per account/environment/action/endpoint pair. File
/// work stays on this serial actor; it never runs on the UI actor. Its owner
/// sends the returned frozen request and checks current account authorization
/// around every suspension. This is not a background synchronization queue.
public actor NoteLinkWriteJournal {
    public enum Failure: Error, Equatable, Sendable {
        case invalidRequest, invalidRecord, mismatchedReceipt
    }

    private let directory: URL
    private let maximumRecordBytes = 4_096

    public init(directory: URL) { self.directory = directory }

    public func begin(apiBaseURL: String, actorID: String, operation: NoteLinkWriteAttempt.Operation,
                      sourceID: String, targetID: String, noteLinkID: String? = nil) throws -> NoteLinkWriteAttempt {
        try Task.checkCancellation()
        let proposed = NoteLinkWriteAttempt(version: 1, apiBaseURL: apiBaseURL, actorID: actorID,
            operation: operation, sourceID: sourceID, targetID: targetID, noteLinkID: noteLinkID,
            requestID: UUID().uuidString)
        guard valid(proposed) else { throw Failure.invalidRequest }
        let file = try location(proposed)
        if let retained = try read(file) {
            guard sameScope(retained, proposed) else { throw Failure.invalidRecord }
            return retained
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = try JSONEncoder().encode(proposed)
        guard bytes.count <= maximumRecordBytes else { throw Failure.invalidRequest }
        try bytes.write(to: file, options: .atomic)
        guard try read(file) == proposed else { throw Failure.invalidRecord }
        return proposed
    }

    public func complete(_ attempt: NoteLinkWriteAttempt, receipt: NoteLinkWriteReceipt) throws {
        guard valid(attempt), receipt.requestID == attempt.requestID,
              receipt.sourceID == attempt.sourceID, receipt.targetID == attempt.targetID,
              validID(receipt.noteLinkID), validID(receipt.activityID), validID(receipt.actionLogID),
              attempt.operation != .unlink || (receipt.noteLinkID == attempt.noteLinkID && receipt.state == .ended) else {
            throw Failure.mismatchedReceipt
        }
        try removeExact(attempt)
    }

    /// Only these server terminal reasons prove that this operation committed
    /// no LINK/UNLINK. Timeout, auth loss and key mismatch retain the request.
    public func reject(_ attempt: NoteLinkWriteAttempt, reason: String) throws {
        guard reason == "NOTE_LINK_ACTIVE_CONFLICT" || reason == "NOTE_LINK_ALREADY_ENDED" else { return }
        try removeExact(attempt)
    }

    private func removeExact(_ attempt: NoteLinkWriteAttempt) throws {
        guard valid(attempt) else { throw Failure.invalidRequest }
        let file = try location(attempt)
        guard let retained = try read(file), retained == attempt else { return }
        try FileManager.default.removeItem(at: file)
    }

    private func location(_ attempt: NoteLinkWriteAttempt) throws -> URL {
        let scope = try JSONEncoder().encode([attempt.apiBaseURL, attempt.actorID,
            attempt.operation.rawValue, attempt.sourceID, attempt.targetID])
        let key = SHA256.hash(data: scope).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key + ".json")
    }

    private func read(_ file: URL) throws -> NoteLinkWriteAttempt? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let size, size > 0, size <= maximumRecordBytes else { throw Failure.invalidRecord }
        let retained = try JSONDecoder().decode(NoteLinkWriteAttempt.self, from: Data(contentsOf: file))
        guard valid(retained) else { throw Failure.invalidRecord }
        return retained
    }

    private func sameScope(_ left: NoteLinkWriteAttempt, _ right: NoteLinkWriteAttempt) -> Bool {
        left.apiBaseURL == right.apiBaseURL && left.actorID == right.actorID
            && left.operation == right.operation && left.sourceID == right.sourceID && left.targetID == right.targetID
    }

    private func valid(_ attempt: NoteLinkWriteAttempt) -> Bool {
        attempt.version == 1 && !attempt.apiBaseURL.isEmpty && attempt.apiBaseURL.utf8.count <= 2_048
            && validID(attempt.actorID) && validID(attempt.sourceID) && validID(attempt.targetID)
            && attempt.sourceID != attempt.targetID && UUID(uuidString: attempt.requestID) != nil
            && (attempt.operation == .link ? attempt.noteLinkID == nil : attempt.noteLinkID.map(validID) == true)
    }

    private func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 64 && value.trimmingCharacters(in: .whitespacesAndNewlines) == value
    }
}
