# V6 · Merge feature journey

This is a native, clickable design-review workflow. It uses prepared local content and the existing `PrototypeState`; it does not start a Merge service job, generate an insight, synchronize a document, or contact an API.

## Entry and scope

```swift
MergeJourney(state: $state, source: note, initialStep: "selection")
```

`MergeJourney` owns its `NavigationStack` and is intended to be presented as a sheet. The parent supplies the existing note and shared state. The chosen warm-white / forest / gold theme is inherited from `prototypeTheme`; the layout follows the system appearance.

The entry supports the ten states listed below. `initialStep` seeds a new local session. Reopening an existing session for the same `source.id` restores that session instead of resetting it to the entry argument. The toolbar’s **Preview states** menu provides explicit access to every review state.

The implementation is [MergeJourney.swift](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/docs/design/2026-10-21-native-visual-reform/revisions/v6-feature-journeys/prototype/MergeJourney.swift).

## Native source contracts reviewed

These are observed contracts in the existing native app, rather than claims about a running service.

| Contract | Source evidence | V6 treatment |
| --- | --- | --- |
| Candidates come from own and favorited notes; the starting card is excluded from candidates. | [MergeCandidateStore, lines 375–411](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeLifecycleViews.swift:375) uses `searchType: "own+favorited"`, combines results, and excludes the anchor. | Candidates are other owned notes and notes in `state.collected`. Local search covers their existing searchable content. |
| The anchor cannot be deselected. | [MergeSessionStore.toggleSelection](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:188) rejects the anchor ID and orders companions after it. | The starting note is a fixed, noninteractive source row. |
| Native creation requires at least two selected sources. | [MergeSessionStore.canCreate](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:56) checks `selectedSources.count >= 2`; [toggleSelection](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:188) contains no eight-source cap. | **2–8 is an additional rule in this review prototype. It is not an already-enforced native maximum.** No production constraint or backend contract was changed. |
| Creation persists a request, then enters a creating phase before weaving. | [MergeSessionStore.create](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:210); [native phase rendering](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeLifecycleViews.swift:668). | Create moves to one explicit progress preview. Native creating/weaving are visually represented together; no asynchronous request or acknowledgement is imitated. |
| Leaving presentation and cancelling the canonical job are separate actions. | [suspend / resume](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:522), [cancel](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:293), and [cancellation confirmation](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeLifecycleViews.swift:559). | Close retains the in-memory session. Cancel requires explicit confirmation. |
| Merge artifacts have one titleless body plus editable tags. | [titleless artifact contract](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:1524), [tag editor](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeArtifactEditorSurface.swift:354). | One `TextEditor` holds the complete body. “New Insight” is a screen title, not a separate title input or generated field. Tags can be added or removed. |
| Accept commits an artifact; discard removes the Merge task/draft. | [commit](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:451), [discardArtifact](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:308), [artifact mutation actions](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeArtifactEditorSurface.swift:474), and [discard confirmation](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeArtifactEditorSurface.swift:151). | Accept is the only path that inserts a private local note. Discard clears the sample draft and enters the cancelled state. Neither changes any source note. |
| Draft synchronization failures and conflicts have explicit recovery actions. | [sync state UI](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeArtifactEditorSurface.swift:376), [conflict actions](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/ArcNote/CoreFlow/MergeArtifactEditorSurface.swift:452), [conflict resolution behavior](/Users/didi/Documents/ChatGPT/Chorai_IOS_Frontend/Packages/CoreFlow/Sources/CoreFlow/MergeSessionStore.swift:379). | Retry previews recovery without a request. Reload replaces the local body/tags with an alternate prepared draft; Keep preserves the current edited body/tags. |

The upper bound is shown as “This review uses 2–8 sources” in selection. The default sample contains a smaller real eligible set; the prototype does not invent owned/collected status to fill eight slots.

## States and clickable transitions

| `initialStep` | Visible state | Available next steps | Effect on notes |
| --- | --- | --- | --- |
| `selection` | One fixed source, searchable eligible candidates, selected count | Select candidates; Create enabled at 2–8; Close | None |
| `selected` | Fixed source plus first eligible candidate already selected | Edit selection; Create; Close | None |
| `progress` | “Weaving ideas,” explicitly simulated progress and source disclosure | Review sample insight → ready; Leave in background → background; Cancel confirmation; Close | None |
| `background` | A local task review card and resume action | Resume → progress; Done/Close; reopen the same note later | None |
| `ready` | Editable complete body, tags, source disclosure | Accept; Discard confirmation; Close | Only Accept inserts a note |
| `sync-error` | Editable artifact plus a clearly labelled sample sync issue | Retry sample sync → ready, preserving edits; Discard; Close | None until subsequent Accept |
| `conflict` | Editable artifact plus two version choices | Reload → alternate prepared body/tags; Keep → existing body/tags; both return to ready | None until subsequent Accept |
| `saved` | If launched directly: “Saved state preview” | Return to insight → ready; Done | Direct entry creates **no** note |
| `failed` | Recoverable generation-failure preview with retained sources | Retry Merge → progress; Review selected sources → selected; Cancel confirmation; Close | None |
| `cancelled` | Cancelled/discarded state | Start a new Merge → clean selection; Done | Source notes remain unchanged |

The progress fraction is a fixed visual fixture, not elapsed work or completion of a real model request. The prepared insight is not derived from whichever sources the reviewer selects. Both facts are disclosed on the screen.

## Saving, dismissal, and recovery invariants

- `accept()` is the only insertion point. It copies the current body and tags into a new `SampleNote` with `author: "You"`, `isOwned: true`, `isPublic: false`, and `sampleKey: "merge-result"`.
- The result marker lets the parent’s journey launcher keep selecting the original source rather than drifting to a newly inserted result.
- Accept is unavailable for an empty body, fewer than two or more than eight eligible selected sources, unresolved sync-error/conflict states, or an already-accepted task.
- An accepted task keeps the inserted ID, so repeated entry or previewing another state cannot insert duplicates. Saved rendering reads the actual inserted note body when that ID exists.
- Jumping to `saved` from the CLI or Preview menu is not a save action. Without an accepted result ID, the screen says **Saved state preview** and explains that no note has been created.
- Closing the sheet does not discard or cancel. Sessions are retained in a private in-memory registry keyed by the original source ID; body, tags, selected IDs, and current task state survive reopening in the same process.
- Retention is **app-session memory only**. This prototype does not provide disk persistence, app-relaunch restoration, background generation, notifications, or backend task reconciliation.
- “Leave in background” first shows the task-review screen. Resume returns to the progress preview. Done closes the sheet; opening Merge again from the same source resumes the retained state.
- Discard and Cancel require native confirmation. They clear the sample task’s body/tags and enter the cancelled screen. They never delete or modify source notes, collection membership, or a previously accepted note.
- Reload uses a second prepared draft to make the destructive version choice visible. Keep preserves the reviewer’s current text and tags. Neither action calls a server.

## Native layout and controls

The journey uses native navigation, sheet dismissal, `ScrollView`, `TextEditor`, text fields, disclosure groups, context menus, confirmation dialogs, and glass buttons. Important action labels have explicit 44–48 pt minimum tap heights. The candidate rows have larger targets.

The bottom Create/Accept dock is attached with `safeAreaInset`, outside the scroll view. The editor is inside the scroll view and does not ignore the keyboard safe area. The keyboard toolbar includes Done. This prevents the fixed dock from occupying the editor’s layout area; final keyboard, large-text, and scroll behavior still requires simulator verification.

The editor has one text body. There is no independent title field, automatic heading conversion, publishing control, or change to the source notes’ ownership/privacy.

## Accessibility and test hooks

| Identifier | Control / state |
| --- | --- |
| `journey.merge.sample` | Local workflow sample disclosure |
| `journey.merge.close` | Presentation-only close |
| `journey.merge.preview` | Native menu of the ten review states |
| `journey.merge.anchor` | Fixed source row |
| `journey.merge.search` | Search eligible sources |
| `journey.merge.candidate.{index}` | Candidate selection button; index comes from the full eligible list, so filtering does not renumber it |
| `journey.merge.count` | Total selected count, including fixed source |
| `journey.merge.create` | Create Merge, disabled outside 2–8 sources |
| `journey.merge.progress` | Progress preview content |
| `journey.merge.continue` | Review sample insight |
| `journey.merge.background` | Leave in background |
| `journey.merge.resume` | Resume retained task |
| `journey.merge.body` | Complete editable artifact body |
| `journey.merge.tag` | Tag input; remove buttons are labelled “Remove tag …” |
| `journey.merge.sync-status` | Current local draft/recovery message |
| `journey.merge.accept` | The only local insertion action |
| `journey.merge.discard` | Open discard confirmation |
| `journey.merge.discard-confirm` | Confirm discard |
| `journey.merge.retry` | Retry generation or sample draft sync, depending on the displayed state |
| `journey.merge.reload` | Replace current draft with alternate prepared version |
| `journey.merge.keep` | Retain current body and tags |
| `journey.merge.saved` | Saved result or explicitly labelled saved-state preview |

## Verification and suggested regression coverage

Completed for this component: Swift SDK type checking of `MergeJourney.swift` with `Model.swift`, `RichModel.swift`, and `Theme.swift`, using an `arm64-apple-ios26.0-simulator` target and the installed iPhoneSimulator 27.1 SDK. Exit status was 0, with the module cache outside the repository. This is compilation evidence, not a launch or service validation.

Root integration is responsible for the full application build and UI tests. Recommended focused assertions:

1. Selection starts at one fixed source with Create disabled. Selecting and deselecting a candidate updates count and Create. Searching does not remove existing selections or change stable candidate identifiers.
2. Create → background → Resume → ready preserves selected sources. Close and reopen with the same source retains task state, body, and tags.
3. Editing the body and tags then Accept adds exactly one owned, private `merge-result` note with the edited values. Original source bodies/tags/privacy and collection membership are unchanged. Reopening an accepted task cannot create a duplicate.
4. Direct `saved` entry and Preview → Saved add zero notes. The text explicitly distinguishes state preview from an actual local save.
5. Discard confirmation can be cancelled. Confirmed Discard creates no note and leaves sources intact. A fresh Merge can be started afterwards.
6. Sync-error Retry preserves current draft. Conflict Keep preserves exact body/tags; Reload replaces them with the alternate fixture. Accept remains disabled until recovery is chosen.
7. In the ready state, edit at the bottom of the body with the keyboard visible; confirm the caret, Done action, and Accept dock are reachable. Repeat in dark mode and accessibility text sizes.
8. Every demonstrated state remains clearly labelled a local workflow sample. No state or assertion claims live generation, successful server synchronization, publishing, or service readiness.
