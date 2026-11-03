# V5 native UI checks

Standalone XCTest UI harness for `com.chorai.nativeprototype.v5`. Build and install `../build.sh` output before running. DerivedData and result bundles belong outside the source checkout.

The targeted V5 run checks mode/history preservation, shared collection, reader and mode-return scroll position, ownership-sensitive actions, appearance changes, swipe cancellation/undo, and offline Report/Link/Share entry. `testDesignScreensLightAndDark` and `testOfflineActionFormsAndDesignCaptures` attach native screenshots named `design-*`.

Run with Xcode selected per command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ChoraiPrototypeUITests.xcodeproj -scheme ChoraiPrototypeUITests \
  -destination 'platform=iOS Simulator,id=92DE3535-B261-49B5-844F-9BD9B8C241B4' \
  -derivedDataPath /tmp/chorai-native-prototype-v5-ui \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

Do not interact with this simulator while checks are running. No backend request is required or allowed for the local design fixtures. UI test screenshots are actual iOS renderings, not web-based phone mockups.
