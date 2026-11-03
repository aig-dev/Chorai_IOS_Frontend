# Chorai native visual prototype

Independent SwiftUI review app for the approved native-reading direction. This is **not a production UI migration**. Native app source, BlockNote, routes, backend contracts, permissions and credentials are unchanged.

## Build

Run `./build.sh` from this folder, or run its absolute path. Requires the installed Xcode at `/Applications/Xcode.app` and its simulator SDK. It compiles a separate arm64 iOS 26+ simulator app without creating an Xcode project or fetching dependencies.

Output: `/tmp/chorai-native-prototype/ChoraiPrototype.app`  
Bundle: `com.chorai.nativeprototype`  
Home Screen name: `Chorai Prototype`

The build also runs 37 model checks: 13 original checks and 24 Explore swipe/history checks. An isolated native UI harness lives in `UITests/`; see its README for installed-app navigation and editing checks. Source and image resources stay in this folder; binaries, test executables and signing output stay outside the repository.

## Review controls

- `--screen explore`, `--screen home`, `--screen editor` select the initial review screen.
- `--appearance light` or `--appearance dark` pins appearance for six comparable captures.
- With no appearance argument, the app follows the system.
- The menu on each tab contains the prototype-only Follow System / Light / Dark picker.

Example after installing this separate app in the Simulator:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch --terminate-running-process 92DE3535-B261-49B5-844F-9BD9B8C241B4 com.chorai.nativeprototype --screen explore --appearance light
```

Installation, launches and screenshots are performed separately by the review owner. The build script does not operate the Simulator.

## Real interactions available

- Native TabView: Explore, Home, Chat, in that order; each has its own NavigationStack.
- Explore V2: a compact seven-line preview (full original body on tap), native draggable card stack, left swipe to skip and right swipe to collect then advance. Matching Skip / Collect buttons remain available. Collection is idempotent: swiping an already-collected note right keeps it collected.
- Explore history: Previous can revisit earlier cards repeatedly without changing collection membership. Continue exploring returns directly to the unread frontier; after all cards are explored it returns to the completed state. Opening a full note and returning preserves the current card.
- Collection undo: a separate 10-second Undo affordance removes only the most recent newly added collection and leaves navigation in place. Previous does not undo; previously collected notes do not offer a destructive undo. A separate manual collection change dismisses the pending undo.
- Explore still includes author sheets, the full note reader, a local collection toggle, independent likes, and the Spark entry explaining the unconnected service. Six foreign-author samples are provided: Mira starts uncollected and only Leo starts collected, so both right-swipe states can be tried.
- Explore search: explicit search mode, native keyboard Search submission, one-result-at-a-time browsing, previous/next, directional swipe, cancel/clear. Typing does not query.
- Home: Notes / Collect, tag filter, scoped submitted search, owned note editing, collected author note reading, new private sample note.
- Editor: a single native TextEditor body, system text selection/copy/paste/keyboard/undo, staged privacy, tags/details sheet, More menu. Dirty leading Save updates the sample and stays in the editor; after saving, the leading control becomes Back. Discard uses a confirmation dialog. An untouched new draft is removed on exit.
- Chat: clickable honest empty state with an explanatory sheet; no pretend messages or sends.

The editor is a **plain native text-input probe**, not a replacement for production BlockNote. It demonstrates input and appearance; it does not emulate production rich-text blocks, revision/hash acceptance, autosave, conflict recovery or AI generation.

All content, profile, collection membership and editor saves are sample state in memory. Save feedback explicitly says local sample. Data resets on relaunch. There is no networking, authentication, credential storage, publication, background task or cloud persistence.

## V2 verification status

All 37 model behavior checks passed after an observed failing swipe-advance test. Logs: `/tmp/chorai-swipe-model-red.log` and `/tmp/chorai-swipe-model-green.log`. All seven native UI cases passed on iPhone 17 Pro / iOS 26.5, covering real directional drags, collection undo, history and resume, idempotent collection, reading and returning, short rebound/vertical scroll discrimination, search, creation and editing. Evidence: `/tmp/chorai-swipe-ui-verified.log` and `/tmp/chorai-swipe-ui-verified.xcresult`. The separate app was rebuilt successfully; production app verification remains outside this prototype revision.

## Visual implementation

Uses actual system TabView, NavigationStack, toolbars, menus, sheets, segmented Picker, TextEditor, SF Symbols, `.glassEffect`, `.buttonStyle(.glass)` and `.buttonStyle(.glassProminent)`. Content remains on stable warm surfaces. Light references #FAF9F6 / #153B37; dark references #242329 with adaptive semantic text and muted green. Chora is reserved for a later review using the complete approved character visual; this prototype does not display or implement it.

This standalone iOS 26 prototype does not change the production app’s iOS 16 minimum. Prototype controls such as the appearance picker are review tools, not an approved product feature.
