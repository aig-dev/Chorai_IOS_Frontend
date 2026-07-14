# Library Plus Onboarding and Record Removal Design

## Status

Approved direction, awaiting implementation.

## Context

The iOS shell currently exposes two creation paths:

1. a global `+ Record` capsule that opens Quick Capture; and
2. the existing circular `+` in Library that opens `NewNoteView`.

This duplicates the same product intent and makes Record look like a fourth primary navigation action. The current iOS onboarding is also pinned to Go onboarding flow version 1, where `elicit_signal` auto-opens Quick Capture and `product_quick_capture_intro` introduces Quick Capture again near the end. Go flow version 2 and the web reference already model note creation from Library instead.

The product decision is that Library `+` is the only note-creation entry on iOS. Quick Capture is not a reduced editor or an alternate path; it is removed.

## Goals

- Remove the global Record capsule from every primary tab.
- Remove the complete iOS Quick Capture implementation, including draft recovery and Record-specific acknowledgements.
- Keep the existing Library `+` visual and its `NewNoteView` destination unchanged.
- Start the iOS onboarding action loop in Library and guide the user to create a first note with `+`.
- Remove the Quick Capture/Record onboarding step from the canonical Go v1 path used by iOS.
- Preserve progress for users with active legacy v1 sessions.
- Keep Go as the canonical onboarding state machine and keep the web frontend reference-only.

## Non-goals

- Redesigning `NewNoteView`.
- Adding a new lightweight editor, sheet, draft surface, or keyboard shortcut.
- Switching iOS to the much larger Go v2 onboarding in this change.
- Changing the web frontend.
- Changing note visibility, save semantics, or API contracts used by `NewNoteView`.

## User Experience

### Primary navigation

The bottom shell contains only Flow, Library, and Chat. There is no control above the tab bar.

### Creating a note

The user enters Library and taps the existing circular `+`. It pushes `NewNoteView` through the existing `NavigationLink`. Cancelling returns to Library without completing the onboarding action. A successful first note creation reports onboarding evidence and allows the guide to continue.

### Onboarding start

For a new iOS v1 onboarding session:

1. The app selects Library and clears conflicting navigation overlays.
2. Chora explains that Library is where the user's own material begins and asks the user to tap `+` to create a first note.
3. The Library `+` receives a visible onboarding emphasis while retaining its current shape, icon, size, and destination.
4. Tapping `+` opens `NewNoteView`.
5. Successful note creation emits `noteCreated(cardID:content:)` evidence.
6. The evidence is sent to Go as the first text signal, preserving the useful recommendation context without retaining Record terminology or UI.
7. Go advances directly to `product_curator_intro`; iOS routes to Flow and continues the existing Spark/Merge loop.

The later `product_library_intro` still returns the user to Library after Merge. It now advances directly to `build_ignite`; `product_quick_capture_intro` is not part of the new path.

## Contract Changes

### iOS onboarding evidence

`OnboardingGuideEvidence.recordCreated(cardID:content:)` becomes `noteCreated(cardID:content:)`.

The evidence is valid only for the first Library creation state. It is not replayed at the end of onboarding. Normal pending-evidence persistence remains responsible for retrying a failed network response.

Record-specific persistence APIs and storage keys are deleted:

- `recordedCardEvidence`
- `saveRecordedCardEvidence`
- the `.record` UserDefaults key

Old undecodable local Record evidence may be discarded. The server session remains authoritative and will present the new Library action again if necessary.

### Go v1 state path

The persisted `elicit_signal` identifier is retained for compatibility, but its v1 scene becomes a Library-create scene:

- `next_route`: `home`
- `target_anchor`: `library.create_note`
- `presentation`: `guide_overlay`
- `spotlight`: `true`
- completion occurs after the first note is successfully created

The new v1 transition path is:

`elicit_signal -> product_curator_intro -> ... -> product_library_intro -> build_ignite`

`deepen_signal` and `product_quick_capture_intro` remain readable only as legacy persisted state identifiers. They are not reachable from a new v1 session.

### Legacy session compatibility

- Active `elicit_signal` sessions receive the new Library-create scene.
- Active `deepen_signal` sessions continue from their current point; these users have already passed the removed Record action.
- Active `product_quick_capture_intro` sessions are exposed to clients as ready-to-complete `build_ignite` sessions. Completion accepts that legacy stored state and persists the normal completed result.
- No iOS Quick Capture type, view, callback, or state is retained solely for migration.

This compatibility belongs in Go because Go owns the canonical session state. It avoids shipping deleted product behavior as client migration code.

## iOS Removal Boundary

Delete all Quick Capture-only code:

- `QuickCaptureSheet`
- `QuickCaptureStore`
- `CaptureDraftStore` and its UserDefaults implementation
- `createPrivateCard` service surface and Quick Capture-only `CreatedCard` model if no remaining caller exists
- capture presentation state and methods in `CoreFlowCoordinator`
- Record acknowledgement state and overlay
- `record.open`, `record.sheet`, and other Record-specific automation identifiers
- Quick Capture unit tests and UI journeys

Retain coordinator state that is still required by Merge or Library refresh, but rename or narrow it if it carries Record terminology.

## iOS Integration

`HomeView` continues injecting its existing `onNoteCreated` callback into `NewNoteView`. `TabBarView` supplies a callback that reports `.noteCreated` to `OnboardingGuideStore` and performs any existing Library refresh behavior.

The Library create control retains `accessibilityIdentifier("note.create")`. Its onboarding emphasis is conditional on the first Library-create state and must not block taps, VoiceOver, or Reduce Motion.

`TabBarView` routes these relevant v1 states:

- first Library-create state -> Library
- curator/explore introduction -> Flow
- merge introduction -> Library/Merge as today
- later Library introduction -> Library as today

## Error and Cancellation Behavior

- Cancelling `NewNoteView` leaves onboarding at the Library-create step.
- A note-save failure leaves the editor error visible and emits no onboarding evidence.
- If the note succeeds but onboarding reporting fails, pending evidence is persisted and retried through the existing store behavior.
- If onboarding is unavailable, Library `+` and note creation still work normally.
- Skipping onboarding never disables Library creation.

## Validation

### CoreFlow unit tests

- No Quick Capture source files or Record shell identifiers remain.
- `noteCreated` queues only at the first Library-create state.
- Successful note evidence sends the note content as text and advances.
- Failed onboarding responses persist and retry note evidence.
- Record-specific persistence APIs and keys are absent.
- Coordinator tests cover only remaining Merge/refresh behavior.

### iOS UI tests

- Flow, Library, and Chat show no global Record control.
- Library still exposes `note.create`.
- Tapping `note.create` opens `screen.card-editor`.
- A new v1 onboarding session selects Library and displays the Library-create guide.
- Cancelling the editor does not advance onboarding.
- Saving a note advances onboarding and routes to Flow.
- No `record.*` surface is discoverable.

### Go tests

- v1 starts with a Library-create scene and anchor.
- v1 first note content advances directly to `product_curator_intro`.
- `product_library_intro` advances directly to `build_ignite`.
- new v1 sessions never reach `product_quick_capture_intro`.
- legacy `product_quick_capture_intro` sessions can complete without client Quick Capture support.

### Build and smoke checks

- Run the focused CoreFlow test suite.
- Build the iOS app for the available simulator.
- Run focused onboarding and Library UI tests.
- Run the Go onboarding service tests.
- With the local Go stack healthy on port 8080, verify the first-note onboarding journey against the real API.

## Rollout Risk

The main risk is changing the v1 state semantics while sessions already exist. Keeping persisted identifiers and normalizing only the removed terminal Quick Capture state avoids a database migration and prevents users from becoming stuck. The iOS and Go changes must ship together; releasing the iOS deletion against the old v1 state machine would strand onboarding at `product_quick_capture_intro`.
