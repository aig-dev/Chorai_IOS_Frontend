# Native Editor Commit, Inline Tag, and Background Management Design

## Status

Design approved in conversation on 2026-07-18. This document is the review checkpoint before implementation planning.

## Context

The native iOS card editor currently separates several interactions that should read as one editing session:

- tapping Add Tag opens a system alert instead of editing the compact tag capsule in place;
- the upper-left control always looks like Back, while save and retry feedback can appear as a separate button inside the editor;
- Back currently snapshots, saves, and exits in one action, so the user cannot see whether the draft has been committed before leaving;
- background replacement is technically available through the generic Background action, but it is not discoverable, and committed backgrounds have no removal entry point;
- the store can remove a background immediately, but immediate persistence conflicts with the requested explicit checkmark-to-save model.

The editor already has strong snapshot, revision, idempotency, retry, and background-upload foundations. This design preserves those guarantees while making the interaction state visible and native.

## Goals

- Turn the existing Add Tag capsule into an inline native text field without changing its position or visual rhythm.
- Finish tag entry on Return or focus loss, creating a tag only when the normalized value is non-empty.
- Remove the standalone Save or Retry button from the editor body.
- Make the upper-left control communicate clean, dirty, saving, and failed states.
- Save without dismissing; after a successful save, restore Back so a second deliberate action exits.
- Make background replacement and removal discoverable and stage both operations until the user taps the checkmark.
- Preserve current document revision, retry, and no-data-loss guarantees.

## Non-goals

- No change to desktop or mobile web editor behavior.
- No new backend endpoint or media schema.
- No redesign of card actions other than the Background branch.
- No change to link or pin persistence semantics; they remain independent canonical actions.
- No camera route for background images. Background selection remains photo-library-only.
- No broad rewrite of `CardEditingStore` into a general application state machine.

## Architecture

Use a session-level semantic state composed from the existing editor model and store, rather than an independent UI dirty flag.

`CardEditorSessionView` remains the orchestration boundary. It owns transient tag-entry state, requests exact BlockNote snapshots, computes the leading-control state, invokes persistence, and coordinates background presentations. `CardEditorShell` remains presentation-only and receives a semantic leading action instead of unrelated Back and Save callbacks.

The leading-control model has these states:

- `back`: the current meaningful draft matches the committed or untouched baseline;
- `save`: at least one body, metadata, or background change is pending;
- `saving`: a snapshot or persistence operation is active;
- `retry`: the last save attempt failed and the desired draft remains pending;
- `readOnly`: compatibility mode cannot mutate and may only close;
- `bridgeFailed`: the exact body cannot be read and the existing close-without-saving confirmation remains available.

For existing cards, draft/revision differences and staged background changes are the dirty truth. A valid, not-yet-committed inline tag candidate also counts as pending so the leading control changes to Save while the user is typing it. Empty, duplicate, and over-limit tag candidates do not. For a new card, the initial empty draft is treated as untouched even though it has not yet received a server ID. This preserves the existing behavior where opening and closing an empty new note does not create a card.

Do not maintain a separate `hasUnsavedChanges` boolean. A parallel flag would drift from revision-aware store state after retries, normalization, or edits made during a save.

## Inline Tag Entry

### Presentation

The trailing Add Tag capsule occupies the same position, visible height, border, typography, and material family as existing tags. Its interactive hit target remains at least 44 by 44 points.

Tapping it replaces that capsule in place with a single-line native `TextField` and immediately gives the field focus. It must not open a sheet or alert and must not show the BlockNote body-formatting accessory.

The production editor and DEBUG fixture use the same component and accessibility identifiers:

- `cardEditorAddTag` for the idle capsule;
- `cardEditorTagInput` for the active text field;
- `cardEditorTag.<normalized-tag>` for committed tag capsules.

### Completion rules

Tag entry finishes when any of the following occurs:

- the user presses Return;
- focus leaves the native field because another screen area or control is tapped;
- the upper-left Save or Back action begins;
- another modal editor action begins.

Completion applies the same normalization used by `CardEditingDraft`: trim surrounding whitespace, remove leading `#` characters and following whitespace, reject an empty result, remove exact duplicates, preserve order, and keep the existing maximum of ten tags.

If normalization produces no new tag, the field simply returns to Add Tag. Empty input, whitespace-only input, hash-only input, a duplicate, or an eleventh tag does not mark the note dirty. A valid result updates only the in-memory draft; persistence remains controlled by the leading checkmark.

The tag candidate normalization must be exposed as a shared CoreFlow operation so the UI does not duplicate private model rules.

## Leading Save and Exit Interaction

### Visual behavior

The upper-left control is the only save/exit action:

- clean or untouched: `chevron.left`, VoiceOver label “Close note”;
- dirty: `checkmark`, VoiceOver label “Save note”;
- saving: progress indicator in the same control location, disabled;
- failed: `checkmark`, VoiceOver label “Retry saving note”.

The editor-body Save/Retry button and its accessibility element are removed. Recoverable error text may remain near the editor content, but its action is the upper-left checkmark.

### Save flow

Tapping the checkmark:

1. finishes any inline tag entry;
2. dismisses the active keyboard without discarding the BlockNote selection state;
3. requests an exact body snapshot using the existing revision-aware bridge;
4. applies the accepted snapshot to the store;
5. persists the draft, followed by any staged background mutation;
6. stays on the editor screen;
7. changes to Back only when the latest body revision, metadata, and background intent are all clean.

Repeated taps during saving are ignored. If the user produces a later body revision while an older revision is saving, the successful response may commit only the captured revision. The control returns to Save rather than Back because newer content is still dirty. This is a normal pending-edit condition, not a save failure.

### Exit flow

Tapping Back never silently saves. Before dismissing, it requests a final exact snapshot to defend against a delayed WebView change event:

- if the snapshot still matches the committed or untouched baseline, dismiss;
- if it reveals an uncommitted change, remain in the editor and change the control to Save;
- if the bridge cannot provide an exact snapshot, retain the existing explicit close-without-saving confirmation.

This preserves the requested two-step interaction—checkmark commits, Back exits—without reintroducing data loss through a timing race.

## Background Interaction

### Entry and presentation

The fixed eight-item Card Action Box keeps one Background tile. Tapping it dismisses the action box before presenting the next native surface.

- When neither a committed nor staged background exists, open the single-image `PhotosPicker` directly.
- When the unchanged committed background is visible, present a native confirmation dialog with **Replace Background**, **Remove Background**, and **Cancel**.
- When a staged replacement is visible, present **Replace Background**, **Remove Background**, and **Cancel**. If it replaced a committed background, also present **Restore Original Background**.
- When removal is staged for a previously committed background, present **Choose New Background**, **Restore Background**, and **Cancel**.

Accessibility identifiers distinguish `cardEditorReplaceBackgroundButton`, `cardEditorRemoveBackgroundButton`, and `cardEditorRestoreBackgroundButton`.

### Staged background state

Replace the store's replacement-only pending representation with one explicit background intent:

- `unchanged`;
- `replace(CardEditingImage)`;
- `remove`.

The committed `backgroundMediaRef` remains separate from this intent.

Preview resolution is deterministic:

- `replace(image)` displays the local image immediately;
- `remove` displays no background;
- `unchanged` displays the committed remote background, if any.

Choosing a new photo validates and stages `replace(image)`. Cancelling the picker changes nothing. Removing a newly staged background on a card with no committed background returns to `unchanged`; it does not create a pointless remove operation. Restoring a committed background clears the staged intent and can return the editor to Back when no other changes remain.

### Persistence

The checkmark persists background intent only after the card draft has a canonical ID:

- `replace(image)` reuses the current upload-then-background-update service;
- `remove` reuses the current background deletion service;
- success clears the intent and updates the committed reference;
- failure retains the exact intended mutation for retry.

The current public immediate-removal method is replaced or wrapped by a staging API for editor use. No production UI path should delete the background before an explicit save.

## Error Handling

- Invalid or oversized background data does not replace the preview and shows the existing recoverable editor message.
- Cancelling tag entry through empty content, cancelling the photo picker, or cancelling the background dialog is a no-op.
- Snapshot, draft, replacement, or removal failure keeps the desired local state, leaves the leading control as Retry, and displays a concise error message.
- A failed background replacement keeps the previous committed server reference until retry succeeds, while the local desired preview remains visible.
- A failed background removal keeps the desired no-background preview and staged removal intent; retry remains explicit through the checkmark.
- A create response lost after the server accepted it continues to use the stable create request ID, preventing duplicate cards.
- Read-only compatibility and bridge-failure behavior remain distinct from ordinary save failure.

## Data Flow

```text
Body / Tag / Privacy / Background edit
                  |
                  v
       session derives pending change
                  |
                  v
         upper-left shows checkmark
                  |
                  v
 finish tag -> exact body snapshot -> save draft
                                      |
                                      v
                         persist background intent
                            /                 \
                         success             failure
                            |                    |
                            v                    v
                   clear intent + Back   retain intent + Retry
                            |
                            v
                 explicit second tap exits
```

## Component Boundaries

- `CardEditorTagRow`: renders committed tags plus the inline entry state; owns no persistence.
- `CardEditorSessionView`: owns tag text/focus orchestration, semantic leading state, exact snapshot/save/close actions, background dialog routing, and user-facing errors.
- `CardEditorShell` and floating controls: render semantic state and route one leading action; contain no dirty-state rules.
- `CardEditingDraft`: owns reusable tag normalization.
- `CardEditingStore`: owns revision-aware draft dirty state, committed background identity, staged background intent, persistence ordering, and exact retry payloads.
- `CoreCardEditingServing`: continues to provide create/update/replace/remove operations; no API shape change is required.

## Testing Strategy

### CoreFlow unit tests

- Verify shared tag normalization for whitespace, leading hashes, empty input, duplicates, order, and the ten-tag cap.
- Verify valid tag completion changes the draft while invalid completion does not.
- Verify `unchanged`, `replace`, and `remove` background intents drive dirty state and preview state correctly.
- Verify removing a replacement with no committed background returns to clean.
- Verify restore clears a staged remove or replacement and exposes the committed background.
- Verify Save persists draft before replace/remove, clears only a successful captured intent, and preserves newer staged intent.
- Verify replacement and removal failures retain exact retry payloads and committed server references.

### Source and shell tests

- Verify the shell has one semantic leading control and no standalone Save/Retry action.
- Verify Add Tag and active input are mutually exclusive and use the shared compact capsule dimensions.
- Verify Background routes none, visible, and staged-removal states to the intended native presentations.
- Replace existing contracts that explicitly prohibit a remove-background control.

### UI tests

- Tap Add Tag and verify the capsule becomes an automatically focused inline field.
- Submit a valid tag with Return and verify it appears as a capsule.
- Tap outside after valid input and verify completion; repeat with blank/hash-only input and verify no tag appears.
- Verify body, tag, privacy, replacement, and removal edits each change Back to Save.
- Tap Save and verify success stays in the editor and changes Save to Back; tap Back and verify dismissal.
- Verify a save failure leaves Retry in the leading position and a retry can succeed.
- Verify an edit arriving during save keeps the checkmark after the captured save succeeds.
- Verify no-background selection, existing-background replacement, staged removal, restore, cancellation, persistence, and failure flows.
- Verify VoiceOver labels and identifiers for Back, Save, Retry, tag entry, Replace, Remove, and Restore.

### Runtime validation

- Build and launch the native app in an iOS simulator.
- Exercise the real editor rather than a browser-hosted preview.
- Visually inspect tag-field replacement, keyboard Return behavior, tap-out completion, leading-control transitions, and background dialogs.
- Verify persisted Tag and background mutations by reopening the card.

## Acceptance Criteria

- Add Tag transforms in place into a native focused field; Return and tapping elsewhere finish entry.
- Only a non-empty normalized, non-duplicate candidate creates a tag.
- There is no standalone Save or Retry button in the editor body.
- Any meaningful body, metadata, or background change turns the upper-left Back control into a checkmark.
- Tapping the checkmark saves without dismissing and restores Back only when the latest draft is fully clean.
- Tapping Back after a successful save exits; an uncommitted final snapshot prevents accidental exit.
- A visible background exposes native Replace and Remove actions.
- Replace and Remove update the preview immediately but make no server mutation until the checkmark is tapped.
- A staged removal of a committed background can be restored before saving.
- Save failures preserve the desired draft and are retried through the upper-left checkmark.
- The native iOS app builds, launches in the simulator, and passes focused unit, source-contract, and UI verification for all three requested interaction groups.
