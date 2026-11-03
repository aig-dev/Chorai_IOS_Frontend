import Foundation

/// Resolves only an explicit deletion target; this does not authorize or perform
/// deletion. The caller still owns confirmation and the existing server request.
public enum CardDeletionConfirmationPolicy {
    public static func target<Card>(
        requestedID: String?,
        candidates: [Card],
        menuCandidate: Card?,
        id: KeyPath<Card, String>,
        isConfirmationPresented: Bool,
        isDeleting: Bool
    ) -> Card? {
        guard !isConfirmationPresented,
              !isDeleting,
              let requestedID,
              !requestedID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return candidates.first { $0[keyPath: id] == requestedID }
            ?? menuCandidate.flatMap {
                $0[keyPath: id] == requestedID ? $0 : nil
            }
    }
}
