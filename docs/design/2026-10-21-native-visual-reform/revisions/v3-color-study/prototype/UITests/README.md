# Isolated native UI checks

This project contains only an XCTest UI runner. It targets the already installed standalone app `com.chorai.nativeprototype.v3`; it does not reference or change the production ArcNote project.

Build the raw prototype with `../build.sh`, install that `.app` on the chosen simulator, then run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ChoraiPrototypeUITests.xcodeproj \
  -scheme ChoraiPrototypeUITests \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/chorai-native-prototype-v3-ui \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
```

Run from this `UITests` directory, replacing the simulator ID. Coordinate Simulator ownership before executing, because the tests launch and operate the prototype.

Seven cases cover:

1. Real Explore/Home tabs; Notes/Collect distinction; owned-body editing; Save stays in editor, becomes Back, and the saved local text survives a Home round trip.
2. Explore query typing remains idle until keyboard Search submission; result shown; Cancel restores Explore.
3. Floating New note is hittable above native Tab Bar; opens empty body; local save stays in editor; Back returns to the new sample row.
4. A real left drag skips a card; repeated Previous revisits history without collecting; Continue exploring returns to the unread position.
5. A real right drag collects and advances; Undo collection does not navigate; later revisiting preserves a newly added collection.
6. Right-dragging an already collected card keeps it collected without offering an undo that could remove the prior collection; reading and returning preserves the current history position.

The swipe cases use accessibility identifiers for controls and perform horizontal drags across the real body button. Their checks use the visible card index and collection/history state, rather than internal model inspection. The sample assumptions are first card uncollected, second card already collected, and at least three cards. Position assertions do not fix the deck's total count.

7. Short horizontal rebound and vertical scrolling on the note body must not open the reader, advance the card, or collect it.

Tests reset their sample state by relaunching the standalone app. They do not authenticate, contact a backend, or alter production app data.


V3 has nine UI cases, including menu collection fallback and palette/appearance changes preserving browsing state. Final verification evidence and the intermittent menu observation are documented in `../../REVIEW.md`.
