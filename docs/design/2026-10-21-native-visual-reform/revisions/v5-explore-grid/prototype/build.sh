#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
prototype_root="$(cd "$(dirname "$0")" && pwd)"
prototype_output=/tmp/chorai-native-prototype-v5
prototype_app="$prototype_output/ChoraiPrototype.app"
mkdir -p "$prototype_app"
prototype_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator swiftc -sdk "$prototype_sdk" -target arm64-apple-ios26.0-simulator -parse-as-library -module-name ChoraiPrototype \
  "$prototype_root/Model.swift" "$prototype_root/RichModel.swift" "$prototype_root/Theme.swift" "$prototype_root/RichCardContent.swift" "$prototype_root/ExploreGrid.swift" "$prototype_root/NoteActions.swift" "$prototype_root/ChoraiPrototype.swift" -o "$prototype_app/ChoraiPrototype"
cat > "$prototype_app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.chorai.nativeprototype.v5</string>
<key>CFBundleName</key><string>Chorai Explore V5</string>
<key>CFBundleDisplayName</key><string>Chorai Explore V5</string>
<key>CFBundleExecutable</key><string>ChoraiPrototype</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>MinimumOSVersion</key><string>26.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>LSRequiresIPhoneOS</key><true/>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
<key>UILaunchScreen</key><dict/>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
</dict></plist>
PLIST
if [ -d "$prototype_root/Assets" ]; then
  cp "$prototype_root/Assets/"* "$prototype_app/"
fi
codesign --force --sign - "$prototype_app"
xcrun --sdk macosx swiftc "$prototype_root/Model.swift" "$prototype_root/RichModel.swift" "$prototype_root/ModelTests.swift" -o "$prototype_output/model-tests"
"$prototype_output/model-tests"
plutil -lint "$prototype_app/Info.plist"
printf 'Built %s\n' "$prototype_app"
