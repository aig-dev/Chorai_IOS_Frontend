#if DEBUG
import SwiftUI

/// Optional local instrumentation. No content, logging or telemetry is collected by default.
private struct NotesCardRenderObserverKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (String) -> Void)? = nil
}

private struct NotesCardGuideObserverKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (Bool) -> Void)? = nil
}

extension EnvironmentValues {
    var notesCardGuideVisibilityObserver: (@MainActor @Sendable (Bool) -> Void)? {
        get { self[NotesCardGuideObserverKey.self] }
        set { self[NotesCardGuideObserverKey.self] = newValue }
    }
    var notesCardRenderObserver: (@MainActor @Sendable (String) -> Void)? {
        get { self[NotesCardRenderObserverKey.self] }
        set { self[NotesCardRenderObserverKey.self] = newValue }
    }
}
#endif
