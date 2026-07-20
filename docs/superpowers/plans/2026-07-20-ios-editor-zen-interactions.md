# iOS Editor Zen Interaction Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native iOS editor's highest-value actions immediately available, restore safe unlinking, and make transient Tag editing leave focus predictably without adding visual noise.

**Architecture:** Keep the existing SwiftUI shell, WKWebView/BlockNote bridge, CoreFlow store, network client, and Go API. Recompose the formatting bar, carry link direction through the editor presentation model, and coordinate body/Tag focus at the shell boundary. The UI must wait for canonical unlink success before removing a relationship and must preserve existing new-note versus existing-note focus behavior.

**Tech Stack:** SwiftUI, XCTest/XCUITest, Swift Package Manager, WKWebView/BlockNote, CoreFlow, Go/Gin API.

**Status:** Completed on `main` on 2026-07-20. Final evidence: 430/430 CoreFlow tests, 13/13 compact-device XCUITests, fresh ArcNote simulator build, canonical Go link tests, live unlink persistence smoke, and independent Zen/code review approval.

## Global Constraints

- Work directly in `/Users/luffylu/Documents/Chorai/Chorai_IOS_Frontend` on `main`; do not create or switch branches.
- Do not commit unless the user explicitly asks; preserve unrelated outer-repository changes.
- Deployment target remains iOS 16.0 and `TARGETED_DEVICE_FAMILY = 1` (iPhone).
- Fixed toolbar order is `Photo`, `Tag`, divider, then scrollable formatting commands.
- `cardEditorKeyboardDismiss` is removed; interactive scroll, body blur, safe outside taps, and system keyboard actions remain available.
- New notes keep automatic body focus; existing notes do not acquire body focus until the user taps the body.
- Only outgoing links where `sourceCardID == currentCardID` expose unlink.
- Unlink has no confirmation sheet, retains the row until canonical success, and leaves the row retryable after failure.
- A legal non-empty Tag commits when focus leaves; blank, hash-only, duplicate, or over-limit input closes without mutation.
- Tapping another control while Tag input is active completes Tag and performs the target action in the same tap.
- Do not use a full-screen hit-testing overlay or unconditional root tap that steals control/TextField events.
- Interactive targets remain at least 44x44 points, with independent VoiceOver actions and Reduce Motion/Reduce Transparency support.
- Preserve the current Glass surfaces, Zen tokens, spacing rhythm, typography, and progressive disclosure; do not add new modal management UI.

---

### Task 1: Pin Photo and remove the redundant keyboard button

**Files:**
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorFormattingBarZenSourceContractTests.swift`
- Modify: `ArcNote/CardEditor/CardEditorFormattingBar.swift`
- Later integration update: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift`
- Later UI update: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: `BlockNoteCardEditorModel.perform(_:)`, `.canPerform(_:)`, and `.inlineImage`.
- Produces: `CardEditorFormattingCommand.scrollableCommands` and a fixed Photo button with identifier `cardEditorFormatInlineImage`.

- [x] **Step 1: Write the failing source-contract test**

  Assert that the formatting source:
  - contains a fixed `commandButton(.inlineImage)` before `cardEditorAddTag`;
  - defines a scroll-only command collection that excludes `.inlineImage`;
  - iterates the scroll-only collection rather than `allCases`;
  - contains no `cardEditorKeyboardDismiss` or `keyboard.chevron.compact.down`;
  - retains `frame(minWidth: 45, minHeight: 44)`.

- [x] **Step 2: Verify RED**

  Run:

  ```bash
  swift test --package-path Packages/CoreFlow \
    --scratch-path /tmp/chorai-toolbar-red \
    --filter CardEditorFormattingBarZenSourceContractTests
  ```

  Expected: FAIL because Photo is still in `allCases` and the keyboard button still exists.

- [x] **Step 3: Implement the fixed common-action zone**

  Add an explicit scroll command list:

  ```swift
  static let scrollableCommands: [Self] = [
      .paragraph, .heading2, .heading3, .bold, .italic, .underline,
      .strike, .bulletList, .numberedList, .checklist, .inlineLink,
      .undo, .redo,
  ]
  ```

  In `CardEditorFormattingBar.body`, render:

  ```swift
  commandButton(.inlineImage)
  Button(action: onBeginTag) { ... }
  Divider()
  ScrollView(.horizontal, showsIndicators: false) {
      ForEach(CardEditorFormattingCommand.scrollableCommands) { command in
          commandButton(command)
      }
  }
  ```

  Delete only the custom keyboard button; do not remove model blur support.

- [x] **Step 4: Verify GREEN**

  Re-run the Task 1 test and expect PASS.

- [x] **Step 5: Self-review**

  Confirm Photo appears exactly once, stays enabled according to `model.canPerform`, retains the existing SF Symbol and accessibility label, and adds no new visual surface.

---

### Task 2: Restore direction-safe inline unlink

**Files:**
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorUnlinkSourceContractTests.swift`
- Modify: `ArcNote/CardEditor/CardEditorMetadataRows.swift`
- Modify: `ArcNote/CardEditor/CardEditorShell.swift`
- Modify: `ArcNote/NewNoteView.swift`
- Later integration update: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift`
- Later integration update: `Packages/CoreFlow/Tests/CoreFlowTests/NewNoteViewSourceContractTests.swift`
- Later UI update: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: `CardEditingLink.sourceCardID`, `targetCardID`, and `CardEditingStore.deleteLink(_:)`.
- Produces: `CardEditorLinkItem.canRemove`, `CardEditorLinkRow.onRemove`, `CardEditorShell.onRemoveLink`, and session-level `removeOntologyLink(_:)`.

- [x] **Step 1: Write the failing unlink contract**

  Assert that:
  - `CardEditorLinkItem` carries `sourceCardID`, `targetCardID`, and `canRemove`;
  - row identity differentiates direction, preferably `sourceCardID + "->" + targetCardID`;
  - `CardEditorLinkRow` receives `onRemove` and exposes `cardEditorRemoveLink.<id>` only inside `if link.canRemove`;
  - `CardEditorShell` accepts and forwards `onRemoveLink`;
  - `editorLinkItems` maps `canRemove: link.sourceCardID == cardID`;
  - `removeOntologyLink` finds the exact source/target edge and awaits `editingStore.deleteLink(link)`.

- [x] **Step 2: Verify RED**

  ```bash
  swift test --package-path Packages/CoreFlow \
    --scratch-path /tmp/chorai-unlink-red \
    --filter CardEditorUnlinkSourceContractTests
  ```

  Expected: FAIL because the current editor link rows are display-only.

- [x] **Step 3: Restore the presentation model and row action**

  Extend `CardEditorLinkItem` with direction and fail-closed removability. In the expanded link row:
  - keep `CardMetadataRelatedRow` as the content;
  - place a trailing plain `xmark` only for `canRemove`;
  - give the action a 44x44 hit area;
  - keep row content and unlink as separate accessibility elements;
  - label it `Unlink <title>` and hint that neither note is deleted.

- [x] **Step 4: Restore canonical deletion wiring**

  Add `onRemoveLink` through `CardEditorShell` and fixtures. In `CardEditorSessionView`:

  ```swift
  private func removeOntologyLink(_ item: CardEditorLinkItem) {
      guard item.canRemove,
            let link = editingStore.links.first(where: {
                $0.sourceCardID == item.sourceCardID
                    && $0.targetCardID == item.targetCardID
            }) else { return }
      Task {
          let didDelete = await editingStore.deleteLink(link)
          if didDelete {
              saveMessage = nil
              hideSaveFailure()
          } else {
              saveMessage = "Couldn't unlink. Try again."
          }
      }
  }
  ```

  Keep the row present while `editingStore.phase == .linking`; the Store already removes it only after service success. Disable repeat taps while busy and use a small progress indicator in the same trailing slot.

- [x] **Step 5: Verify GREEN and existing canonical semantics**

  ```bash
  swift test --package-path Packages/CoreFlow \
    --scratch-path /tmp/chorai-unlink-green \
    --filter CardEditorUnlinkSourceContractTests

  swift test --package-path Packages/CoreFlow \
    --scratch-path /tmp/chorai-store-unlink \
    --filter CardEditingStoreTests
  ```

  Expected: both commands PASS; Store tests prove failure retention and retry reconciliation.

---

### Task 3: Make Tag completion predictable across non-editing surfaces

**Files:**
- Create: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorTagFocusSourceContractTests.swift`
- Modify: `ArcNote/CardEditor/CardEditorMetadataRows.swift`
- Modify: `ArcNote/CardEditor/CardEditorShell.swift`
- Modify: `ArcNote/NewNoteView.swift`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`

**Interfaces:**
- Consumes: idempotent `onCompleteTag`, `BlockNoteCardEditorModel.dismissKeyboard()`, and existing semantic control callbacks.
- Produces: a shell-owned Tag focus binding and a single `completeTagEntry()` path for Return, focus loss, blank-area tap, body tap, and control transitions.

- [x] **Step 1: Add failing source and UI tests**

  Source contract must reject an unconditional root tap and require a focus binding from Shell to `CardEditorTagInput`.

  UI coverage must prove:
  - tapping the real shell gutter commits a valid Tag and hides the keyboard;
  - tapping the Tag field itself does not close it;
  - tapping Privacy commits the Tag and toggles Privacy in one tap;
  - tapping Links disclosure commits the Tag and expands Links in one tap;
  - blank/hash-only input exits without adding a Tag.

- [x] **Step 2: Verify RED**

  ```bash
  swift test --package-path Packages/CoreFlow \
    --scratch-path /tmp/chorai-tag-focus-red \
    --filter CardEditorTagFocusSourceContractTests
  ```

  Expected: FAIL because focus is private to `CardEditorTagInput` and only the body has a completion tap.

- [x] **Step 3: Lift focus ownership and centralize semantic completion**

  Use a Shell-owned `@FocusState` binding or equivalent explicit focus state. `CardEditorTagInput` consumes the binding rather than owning an isolated private focus state. Keep `completeTagEntry()` idempotent.

  Add a background-only tap surface behind interactive content, and wrap semantic control actions so they call `onCompleteTag()` before their own action when `isAddingTag` is true. Do not place a hit-testing overlay above the content.

- [x] **Step 4: Preserve one-tap focus transfer**

  Body tap: complete Tag, then allow WKWebView to receive the same tap. Privacy, More, leading control, disclosure, remove Tag, inline image, and inline link: complete Tag first and continue the selected action.

- [x] **Step 5: Verify GREEN**

  Re-run the source contract. Run the targeted UI methods after the integration build in Task 4.

---

### Task 4: Update legacy contracts and integration fixtures

**Files:**
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/CardEditorShellSourceContractTests.swift`
- Modify: `Packages/CoreFlow/Tests/CoreFlowTests/NewNoteViewSourceContractTests.swift`
- Modify: `ArcNoteUITests/ArcNoteUITests.swift`
- Modify as needed: `ArcNote/CardEditor/CardEditorShell.swift` DEBUG fixture only

**Interfaces:**
- Consumes: completed Tasks 1–3.
- Produces: fixture states for outgoing removable links, incoming static links, unlink progress/failure, and outside-Tag focus transitions.

- [x] **Step 1: Remove obsolete assertions**

  Delete assertions requiring `cardEditorKeyboardDismiss`, static editor links, absence of `canRemove`, and absence of `onRemoveLink`.

- [x] **Step 2: Add fixture behavior**

  Give at least one fixture relation `canRemove: true` and one `canRemove: false`. Fixture unlink removes only the outgoing relation. Keep blocked/compatibility fixtures non-removable.

- [x] **Step 3: Replace keyboard-button helpers**

  Existing production smoke tests must not type newline to dismiss the keyboard. Add a reusable vertical-drag dismissal helper and replace every `tapButton("cardEditorKeyboardDismiss")` call.

- [x] **Step 4: Run package tests**

  ```bash
  swift test --package-path Packages/CoreFlow \
    --scratch-path /tmp/chorai-editor-coreflow
  ```

  Expected: all CoreFlow tests PASS with no obsolete editor contracts.

- [x] **Step 5: Build the app**

  ```bash
  xcodebuild build \
    -project ArcNote.xcodeproj \
    -scheme ArcNote \
    -destination 'platform=iOS Simulator,id=43E6164C-1F4B-47E4-9B65-D154C7281A56' \
    -derivedDataPath /tmp/chorai-editor-zen-build
  ```

  Expected: `BUILD SUCCEEDED`.

---

### Task 5: Verify behavior from UI through canonical API

**Files:**
- Modify if coverage is missing: `ArcNoteUITests/ArcNoteUITests.swift`
- No production backend changes expected.

**Interfaces:**
- Consumes: editor fixture helpers, production smoke-card helpers, Go `/api/cards/{source}/links/{target}` DELETE endpoint.
- Produces: fresh test evidence for toolbar, focus, unlink UI, and canonical persistence.

- [x] **Step 1: Run targeted fixture UI tests**

  Verify Photo/Tag order, no keyboard icon, scroll dismissal, image source dialog, Tag outside-tap cases, outgoing/incoming unlink visibility, unlink success, and 44-point targets.

- [x] **Step 2: Run the real unlink smoke**

  Create source and target cards, create a link, reopen the source editor, expand Related Notes, tap x, assert the row disappears, fetch canonical links and assert the edge is absent, then reopen the editor and assert it stays absent.

- [x] **Step 3: Run canonical service tests**

  ```bash
  go test ./internal/ontology/handlers \
    -run TestDeleteLinkHandlerReturnsRemovedForCommittedResponseReplay \
    -count=1

  go test ./tests/contract -run 'Test.*Link' -count=1
  ```

  Expected: both Go commands PASS.

- [x] **Step 4: Run the complete relevant UI group**

  Use a unique DerivedData path and `-parallel-testing-enabled NO`. Expected: zero failures.

---

### Task 6: Zen Aesthetic and accessibility acceptance

**Files:**
- Save accepted screenshots under: `/tmp/chorai-editor-zen-audit/`
- No source changes unless the visual comparison finds a concrete defect.

**Interfaces:**
- Consumes: the user-provided before screenshot and current simulator states.
- Produces: accepted after screenshots and a requirement-by-requirement audit.

- [x] **Step 1: Capture stable states**

  Capture and inspect:
  1. body focused with keyboard and formatting bar;
  2. Add Tag active;
  3. Related Notes expanded with outgoing x and incoming static row;
  4. unlink in progress or deterministic fixture state;
  5. Tag completed after outside tap.

- [x] **Step 2: Compare the toolbar against the reference crop**

  Confirm the fixed zone contains exactly Photo and Tag, no redundant keyboard icon, no extra glass layer, correct 44-point rhythm, and more visible formatting commands than before.

- [x] **Step 3: Audit Zen principles**

  Confirm content-first hierarchy, quiet chrome, progressive disclosure, direct manipulation, restrained motion, and no additional modal step.

- [x] **Step 4: Audit accessibility**

  Check VoiceOver labels/order, independent unlink action, Dynamic Type hit targets, Reduce Motion, Reduce Transparency, keyboard focus escape, and error recovery. Do not claim full accessibility compliance from screenshots alone.

- [x] **Step 5: Fix and recapture any visible mismatch**

  Compare the same viewport and state after each adjustment. Reject cropped, loading, or incorrect screenshots.

---

### Task 7: Final completion audit

**Files:**
- Review all task diffs and the plan checklist.

- [x] **Step 1: Run fresh full verification**

  Re-run CoreFlow tests, app build, relevant XCUITests, and Go link tests from clean commands.

- [x] **Step 2: Inspect repository state**

  Confirm the nested iOS repository remains on `main`, list exactly the changed files, and verify no unrelated files were modified.

- [x] **Step 3: Review requirement coverage**

  Map each user requirement to source, automated test, runtime behavior, and screenshot evidence. Any missing evidence keeps the task incomplete.

- [x] **Step 4: Perform broad code review**

  Review focus ordering, async unlink races, fail-closed direction handling, accessibility semantics, animation behavior, and test quality. Fix Critical/Important findings and rerun their covering tests.
