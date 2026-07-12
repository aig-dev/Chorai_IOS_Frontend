import Foundation

public struct NoteImportFormat: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let markdown = Self(rawValue: "markdown")
    public static let html = Self(rawValue: "html")
}

public struct NoteImportFile: Codable, Equatable, Sendable {
    public let id: String
    public let sourceKey: String
    public let url: URL
    public let filename: String
    public let label: String
    public let format: NoteImportFormat
    public let byteCount: Int64

    public init(
        id: String,
        sourceKey: String,
        url: URL,
        filename: String,
        label: String,
        format: NoteImportFormat,
        byteCount: Int64
    ) {
        self.id = id
        self.sourceKey = sourceKey
        self.url = url
        self.filename = filename
        self.label = label
        self.format = format
        self.byteCount = byteCount
    }

    public var canonicalFormat: NoteImportFormat? {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "md", "markdown": .markdown
        case "html", "htm": .html
        default: nil
        }
    }
}

public struct NoteImportJobStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let queued = Self(rawValue: "queued")
    public static let running = Self(rawValue: "running")
    public static let done = Self(rawValue: "done")
    public static let failed = Self(rawValue: "failed")
    public static let cancelled = Self(rawValue: "cancelled")

    public var isTerminal: Bool {
        self == .done || self == .failed || self == .cancelled
    }
}

public struct NoteImportSoulStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let notRequested = Self(rawValue: "not_requested")
    public static let queued = Self(rawValue: "queued")
    public static let running = Self(rawValue: "running")
    public static let done = Self(rawValue: "done")
    public static let failed = Self(rawValue: "failed")
    public static let skipped = Self(rawValue: "skipped")
    public static let cancelled = Self(rawValue: "cancelled")

    public var isUnsettled: Bool {
        self == .queued || self == .running
    }

    public var isSettled: Bool {
        self == .notRequested
            || self == .done
            || self == .failed
            || self == .skipped
            || self == .cancelled
    }
}

public struct NoteImportItemStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let pending = Self(rawValue: "pending")
    public static let imported = Self(rawValue: "imported")
    public static let updated = Self(rawValue: "updated")
    public static let skipped = Self(rawValue: "skipped")
    public static let failed = Self(rawValue: "failed")
}

public struct NoteImportReceipt: Codable, Equatable, Sendable {
    public let jobID: String
    public let clientRequestID: String?
    public let status: NoteImportJobStatus
    public let totalFiles: Int
    public let acceptedFiles: Int
    public let rejectedFiles: Int

    public init(
        jobID: String,
        clientRequestID: String?,
        status: NoteImportJobStatus,
        totalFiles: Int,
        acceptedFiles: Int,
        rejectedFiles: Int
    ) {
        self.jobID = jobID
        self.clientRequestID = clientRequestID
        self.status = status
        self.totalFiles = totalFiles
        self.acceptedFiles = acceptedFiles
        self.rejectedFiles = rejectedFiles
    }
}

public struct NoteImportJobSummary: Codable, Equatable, Sendable {
    public let jobID: String
    public let clientRequestID: String?
    public let status: NoteImportJobStatus
    public let soulStatus: NoteImportSoulStatus
    public let soulStatusReason: String?
    public let totalFiles: Int
    public let importedCount: Int
    public let updatedCount: Int
    public let skippedCount: Int
    public let failedCount: Int
    public let createdAt: Date
    public let completedAt: Date?
    public let cancelRequestedAt: Date?
    public let cancelledAt: Date?

    public init(
        jobID: String,
        clientRequestID: String?,
        status: NoteImportJobStatus,
        soulStatus: NoteImportSoulStatus,
        soulStatusReason: String?,
        totalFiles: Int,
        importedCount: Int,
        updatedCount: Int,
        skippedCount: Int,
        failedCount: Int,
        createdAt: Date,
        completedAt: Date?,
        cancelRequestedAt: Date?,
        cancelledAt: Date?
    ) {
        self.jobID = jobID
        self.clientRequestID = clientRequestID
        self.status = status
        self.soulStatus = soulStatus
        self.soulStatusReason = soulStatusReason
        self.totalFiles = totalFiles
        self.importedCount = importedCount
        self.updatedCount = updatedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.cancelRequestedAt = cancelRequestedAt
        self.cancelledAt = cancelledAt
    }

    public var isSettled: Bool {
        status.isTerminal && soulStatus.isSettled
    }
}

public struct NoteImportJobItem: Codable, Equatable, Sendable {
    public let sourceKey: String
    public let originalFilename: String
    public let label: String
    public let originalFormat: NoteImportFormat
    public let assetID: String?
    public let assetVersionID: String?
    public let status: NoteImportItemStatus
    public let errorMessage: String?
    public let processedAt: Date?

    public init(
        sourceKey: String,
        originalFilename: String,
        label: String,
        originalFormat: NoteImportFormat,
        assetID: String?,
        assetVersionID: String?,
        status: NoteImportItemStatus,
        errorMessage: String?,
        processedAt: Date?
    ) {
        self.sourceKey = sourceKey
        self.originalFilename = originalFilename
        self.label = label
        self.originalFormat = originalFormat
        self.assetID = assetID
        self.assetVersionID = assetVersionID
        self.status = status
        self.errorMessage = errorMessage
        self.processedAt = processedAt
    }
}

public struct NoteImportJobDetail: Codable, Equatable, Sendable {
    public let jobID: String
    public let clientRequestID: String?
    public let status: NoteImportJobStatus
    public let soulStatus: NoteImportSoulStatus
    public let soulStatusReason: String?
    public let totalFiles: Int
    public let importedCount: Int
    public let updatedCount: Int
    public let skippedCount: Int
    public let failedCount: Int
    public let errorMessage: String?
    public let createdAt: Date
    public let completedAt: Date?
    public let cancelRequestedAt: Date?
    public let cancelledAt: Date?
    public let items: [NoteImportJobItem]

    public init(
        jobID: String,
        clientRequestID: String?,
        status: NoteImportJobStatus,
        soulStatus: NoteImportSoulStatus,
        soulStatusReason: String?,
        totalFiles: Int,
        importedCount: Int,
        updatedCount: Int,
        skippedCount: Int,
        failedCount: Int,
        errorMessage: String?,
        createdAt: Date,
        completedAt: Date?,
        cancelRequestedAt: Date?,
        cancelledAt: Date?,
        items: [NoteImportJobItem]
    ) {
        self.jobID = jobID
        self.clientRequestID = clientRequestID
        self.status = status
        self.soulStatus = soulStatus
        self.soulStatusReason = soulStatusReason
        self.totalFiles = totalFiles
        self.importedCount = importedCount
        self.updatedCount = updatedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.cancelRequestedAt = cancelRequestedAt
        self.cancelledAt = cancelledAt
        self.items = items
    }

    public var isSettled: Bool {
        status.isTerminal && soulStatus.isSettled
    }
}

public enum NoteImportSelectionError: Equatable, Sendable {
    case noFiles
    case unsupportedFormat(filename: String)
    case emptyFile(filename: String)
}

public enum NoteImportAmbiguity: Equatable, Sendable {
    case timeout
    case connectionLost
    case undecodableSuccess(statusCode: Int)
}

public enum NoteImportServiceError: Error, Equatable, Sendable {
    case selection(NoteImportSelectionError)
    case ambiguous(NoteImportAmbiguity)
    case contract(code: String)
    case requestFailed(code: String?)
}

public enum NoteImportPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case invalidSelection(NoteImportSelectionError)
    case submitting
    case reconciling
    case polling
    case ambiguous
    case cancelling
    case terminal
    case failed(NoteImportServiceError)
}
