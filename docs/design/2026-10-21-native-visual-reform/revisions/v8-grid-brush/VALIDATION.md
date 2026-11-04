# V8 validation · 2026-10-26

Independent visual prototype, bundle `com.chorai.nativeprototype.v8`. No production source migration, backend, account, AI, rating write, or growth mutation was tested or introduced.

## Native build and interaction

- Xcode **27.1 (27A9275)**, project-scoped `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- iPhone 17 Pro simulator, iOS 26.5, device `92DE3535-B261-49B5-844F-9BD9B8C241B4`.
- `prototype/build.sh`: passed; app generated at `/tmp/chorai-native-prototype-v8/ChoraiPrototype.app`. All **54** existing model checks passed (13 original, 24 swipe, 17 rich content), bundle validation passed, app installed and launched successfully.
- `CardLevelJourneyTests`: **4 tests, 0 failures**, 90.099 seconds. Scope: six-level guide and unchanged sample content; Grid to matching reader and back without implicit collection; explicit detail collection reflected in Grid and shared count; growth stage kept separate from six growth dimensions.
- Only this XCTest class was run. Older copied UI test classes target earlier revisions and are not counted as V8 verification.
- Raw test result: `/tmp/chorai-v8-ui.xcresult`; build/test logs are copied into `qa/` for reference.
- Xcode emitted a host OS build parsing warning (`invalidDigitCount`); it did not prevent compilation or the successful test result.

## Visual checks and the contained fix

Captured **30 new native screenshots**, 15 states in both light and dark: Grid top/bottom, six matching readers, six full-card specimens, and the level placement in Merge. Guide, growth, and unknown states retain V7 screenshots; older functional chapters retain V6 screenshots. These retained screens are not new V8 captures.

Inspected Grid and detail examples: all six colors retain the original brush mask; Grid has no character or reserved character gap; detail restores the corresponding static character. Significant retains its left-edge character and safe grade spacing. Exceptional retains the green-gold character. Decorative layers do not intercept touches.

During visual verification, the Basic reader's photo expanded its container horizontally. The V8-only image block now uses a fixed-height flexible surface with a bounded image overlay. A fresh build and screenshot confirmed normal side gutters; image content, caption and alt text remain. This fix is not applied to earlier revisions or the production app.

## Browser gallery and offline export

- Gallery data validation: **8 journeys, 53 states, 149 valid action edges, 87 referenced images**, no missing files or invalid hotspot indexes.
- Localhost browser checked by actual clicks: Basic Grid → matching Basic reader → original Grid; light/dark switch; lower Grid → Exceptional reader → lower Grid. Saved browser screenshots: `qa/browser-grid-light.png` and `qa/browser-detail-dark.png`.
- The browser gallery is an annotated native screenshot guide. It does not execute SwiftUI controls or persist a real account's collection. Native interaction was checked separately above.
- Single-file export: `Chorai-Grid-Brush-V8-offline.html`, **20,752,981 bytes (19.79 MiB)**. All 87 images are embedded; CSS and JavaScript are inline. Script syntax, state edges and absence of external resource tags passed static validation (`qa/offline-validation.json`).
- Opening the export as a local `file:` URL was blocked by the browser tool's URL policy. No workaround was used; actual double-click/offline browser execution is **not verified**. Localhost gallery interaction and export static validation are distinct results.

## Preservation and limits

- Full before/after hashes of all **60 V7 files** match, including its previous manifest, offline file and original screenshots (`qa/v7-preservation.json`). No earlier revision was edited.
- Native and web `git diff --check` passed. Their pre-existing tracked changes remain; this task added V8 design files and appended the design version index.
- No formal app build, backend readiness, account authentication, real AI, deployment, push or merge is claimed from these prototype checks.

## Reproduce

Build with `prototype/build.sh`; launch with `Open-Prototype.command --journey levels --step grid --appearance light`. Gallery validation and offline packaging scripts are in `tools/`.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project prototype/UITests/ChoraiPrototypeUITests.xcodeproj \
  -scheme ChoraiPrototypeUITests \
  -destination 'platform=iOS Simulator,id=92DE3535-B261-49B5-844F-9BD9B8C241B4' \
  -derivedDataPath /tmp/chorai-v8-ui-derived \
  -resultBundlePath /tmp/chorai-v8-ui.xcresult \
  -only-testing:ChoraiPrototypeUITests/CardLevelJourneyTests \
  CODE_SIGNING_ALLOWED=NO
```

Use a fresh result bundle path for a repeat test run.
