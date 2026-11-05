import Foundation

/// A device-local record of a successful product access check. It grants only
/// access to this account's retained files, never cloud authorization.
public struct NoteOfflineAccess: Codable, Equatable, Sendable {
    private var lastAllowedScope: NoteStoreScope?
    public init() {}

    public func allows(_ scope: NoteStoreScope?) -> Bool {
        scope != nil && scope == lastAllowedScope
    }

    public mutating func recordConfirmed(_ access: AccessState, scope: NoteStoreScope) {
        guard access.isValid, access.mode != "unavailable" else { return }
        if access.status == "allowed" { lastAllowedScope = scope }
        else if lastAllowedScope == scope { lastAllowedScope = nil }
    }

    public mutating func clear() { lastAllowedScope = nil }
}
