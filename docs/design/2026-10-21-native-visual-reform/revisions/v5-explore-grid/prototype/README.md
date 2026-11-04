# Chorai native rich-card prototype · V4

An independent SwiftUI review app with eight content formats, five paired light/dark palettes, and the existing enlarged Explore card. V1/V2/V3 and earlier offline packages remain separate. This is a design sample, not a production UI migration.

## Build and launch

Run `./build.sh`. It uses `/Applications/Xcode.app` and the simulator SDK without fetching dependencies.

- Output: `/tmp/chorai-native-prototype-v4/ChoraiPrototype.app`
- Bundle: `com.chorai.nativeprototype.v4`
- Home Screen name: **Chorai Cards V4**
- Launcher: `../Open-Prototype.command`
- Model checks: 54 assertions, including 17 rich-content checks.
- UI harness: `UITests/ChoraiPrototypeUITests.xcodeproj`.

The build does not launch a simulator. Build outputs stay outside the repository.

## Review controls

- `--screen explore|home|editor` selects the initial screen.
- `--appearance light|dark` pins appearance; omit to follow the system.
- `--palette original|green-gold|purple|blue|clay` chooses a palette; default `original`.
- `--card photo|essay|quote|checklist|code|reference|comparison|short` starts Explore at a specific sample.
- The menu includes palette and appearance review controls. These are not proposed product settings.

## Content and preserved flow

Eight external-author samples: photo, long essay, original quote, read-only checklist, Swift code, fictional source excerpt, comparison table, and short thought. The two owned notes remain unchanged. Structured content participates in local submitted search. `RichCardContent` renders both previews and the complete reader; photo content loads from the app bundle. Provenance and the exact image-generation prompt are in `../ASSET-CREDITS.md`.

Left swipe skips; right swipe collects and advances. Previous revisits without changing collection; Continue exploring returns to the unread frontier. Newly added collection has a separate Undo. Menu collection stays on the current card; the full reader returns to the same position. Short or vertical drags do not trigger a swipe action or open the reader.

Home, owned-note editing, private sample creation, save-and-stay, and the native tab/navigation structure are inherited from V3. The editor is a native text-input sample, not a production rich-text replacement.

All content and edits are in-memory fixtures that reset on relaunch. No real authentication, AI, publication, cloud sync or backend is connected. Checklist state and source metadata are displayed content, not new task or external-link features.

## Verification

On 2026-10-21, Xcode 27.1 (27A9275), iPhone 17 Pro / iOS 26.5:

- Native build and all 54 model assertions passed.
- Five targeted UI tests passed, zero failures: all eight rich formats opening and returning; palette/appearance state preservation; short/vertical drag safeguards; collect/undo/history; skip/history/resume.
- The targeted UI run preceded a final auxiliary-text color and image-alt-text polish. The final build and all 54 model assertions passed again; gesture/navigation code was unchanged by that polish.
- Build log: `/tmp/chorai-v4-build.log`; UI log: `/tmp/chorai-v4-rich-ui.log`; result: `/tmp/chorai-v4-rich-ui.xcresult`.

Uses native SwiftUI Text, Image, Grid, SF Symbols, TabView, NavigationStack, Menu, sheets, TextEditor and Liquid Glass APIs. Requires iOS 26+ for this isolated prototype; production deployment settings are unchanged.

`capture-cards.py` captures all 80 palette/content/appearance variants from the isolated bundle on the designated simulator and restores its temporary status-bar overrides afterward.
