import Foundation

/// The immutable app bundle has one validation identity for this process.
/// Independent injected validators own independent resources and success caches.
actor BlockNoteResourceValidator {
    static let shared = BlockNoteResourceValidator()
    private let validate: @Sendable () throws -> BlockNoteEditorResourceManifest
    private var successful: BlockNoteEditorResourceManifest?
    private var inFlight: (id: UUID, task: Task<BlockNoteEditorResourceManifest, Error>)?

    init(validate: @escaping @Sendable () throws -> BlockNoteEditorResourceManifest = {
        try BlockNoteEditorResources.validateBundledResources()
    }) {
        self.validate = validate
    }

    func validateBundledResources() async throws -> BlockNoteEditorResourceManifest {
        try Task.checkCancellation()
        if let successful { return successful }
        let flight: (id: UUID, task: Task<BlockNoteEditorResourceManifest, Error>)
        if let inFlight { flight = inFlight }
        else {
            let validate = self.validate
            flight = (UUID(), Task.detached(priority: .userInitiated) { try validate() })
            inFlight = flight
        }
        do {
            let value = try await flight.task.value
            if inFlight?.id == flight.id {
                successful = value
                inFlight = nil
            }
            try Task.checkCancellation()
            return value
        } catch {
            if inFlight?.id == flight.id { inFlight = nil }
            throw error
        }
    }
}
