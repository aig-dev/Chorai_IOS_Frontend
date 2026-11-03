# Chorai native visual prototype · V3 color study

An independent SwiftUI review app with four paired light/dark palettes and a larger Explore card. This is **not a production UI migration**. Earlier V1/V2 artifacts remain available; V3 lives entirely in `revisions/v3-color-study/` and installs alongside V2.

## Build and launch

Run `./build.sh` from this folder. It uses `/Applications/Xcode.app` and its simulator SDK to compile a separate arm64 iOS 26+ review app without fetching dependencies.

- Output: `/tmp/chorai-native-prototype-v3/ChoraiPrototype.app`
- Bundle: `com.chorai.nativeprototype.v3`
- Home Screen name: **Chorai Colors V3**
- Launcher: `../Open-Prototype.command`

The build also runs the existing 37 model checks. An isolated installed-app UI harness lives in `UITests/`. The build script does not operate the Simulator; binaries, model executables and signing output stay outside the repository.

## Review controls

- `--screen explore|home|editor` selects the initial screen.
- `--appearance light|dark` pins appearance. Omit it to follow the system.
- `--palette green-gold|purple|blue|clay` selects a palette; the default is `green-gold`.
- The tab menu offers Color study → Palette and Prototype appearance → Appearance. These are prototype review controls, not approved product settings.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch --terminate-running-process 92DE3535-B261-49B5-844F-9BD9B8C241B4 com.chorai.nativeprototype.v3 --screen explore --appearance dark --palette purple
```

## V3 changes

- Explore uses a compact inline page header, 14 pt outer gutters instead of 24 pt, and a card whose minimum height responds to the viewport. The body preview allows 12 lines instead of seven; tapping still opens the full note.
- The large permanent Skip / Collect button row is removed. Directional hints appear on the first card, with SKIP / COLLECT feedback during a drag. More → Skip note and More → Collect sample / Remove from collection remain available; VoiceOver custom actions also remain.
- More → Collect sample changes collection membership and stays on the current card, matching the previous menu behavior. Right swipe collects and advances. More → Skip note advances.
- Previous and Continue exploring remain visible in the compact row below the card.
- Four semantic palettes cover Explore, Home, reader and editor: College Green & Gold, Twilight Violet, Deep Sea Blue, and Clay & Paper. Full tokens and design rationale are in `../PALETTES.md`.

## Preserved interactions

- Native TabView: Explore, Home, Chat, each with its own NavigationStack.
- Explore: left swipe skips; right swipe collects and advances. Repeated collection is idempotent. Previous revisits cards without changing collection; Continue exploring returns to the unread frontier, or the completed state after all cards have been explored.
- Newly added collection has a separate 10-second Undo. It removes only that addition and leaves navigation in place. Previous is not an undo; manual collection changes dismiss the pending undo.
- Opening the full reader and returning preserves the card. Author, Spark, independent likes and comments entry remain.
- Search queries only on keyboard submission. Search mode retains its result paging, directional navigation, clear and cancel behavior.
- Home retains Notes / Collect, tag filtering, submitted search, owned editing, collected read-only notes and new private sample creation.
- Editor remains one native TextEditor body. Dirty Save updates the local sample and stays; after saving the leading control becomes Back. Discard requires confirmation; untouched new drafts are removed on exit.
- Chat remains an honest empty state with an explanatory sheet.

## Scope and verification

All content, collection membership and editor saves are in-memory samples that reset on relaunch. There is no networking, authentication, publication, AI generation or cloud persistence. The editor is a **plain native text-input probe**, not a replacement for production BlockNote, rich-text blocks, revision acceptance, autosave or conflict recovery.

V3 built successfully and all 37 model checks passed. All nine native UI behaviors have passing evidence across the initial run and affected-path reruns. A too-short flick threshold was corrected. One intermittent menu presentation miss was observed; a diagnostic rerun and three subsequent repetitions passed, so it remains documented rather than claimed fixed. See `../REVIEW.md` for exact run boundaries and evidence.

Theme.swift also passed a standalone simulator-SDK typecheck. Forty opaque-token contrast comparisons meet ≥4.5:1, with a minimum of 4.78:1. These calculations do not certify composited glass, system secondary labels, or the whole interface.

Uses real system TabView, NavigationStack, toolbar, Menu, sheet, Picker, TextEditor, SF Symbols, `.glassEffect`, `.glass` and `.glassProminent`. The separate prototype requires iOS 26+; the production app's iOS 16 minimum is unchanged. Chora remains outside this color/layout study.
