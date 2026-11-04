#!/bin/bash
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
chorai_design_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chorai_prototype_app=/tmp/chorai-native-prototype-v4/ChoraiPrototype.app
chorai_simulator=92DE3535-B261-49B5-844F-9BD9B8C241B4

if [ ! -d "$chorai_prototype_app" ]; then
  /bin/bash "$chorai_design_dir/prototype/build.sh"
fi

xcrun simctl boot "$chorai_simulator" 2>/dev/null || true
xcrun simctl bootstatus "$chorai_simulator" -b
xcrun simctl install "$chorai_simulator" "$chorai_prototype_app"
open -a /Applications/Xcode.app/Contents/Applications/DeviceHub.app
xcrun simctl launch --terminate-running-process "$chorai_simulator" com.chorai.nativeprototype.v4 "$@"
