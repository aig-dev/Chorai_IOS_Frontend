#!/bin/zsh

readonly DEFAULT_IOS_DEVICE="iPhone 17 Pro"
readonly DEFAULT_IOS_DERIVED_DATA="/tmp/chorai-ios-local"
readonly IOS_SCHEME_NAME="ArcNote"
readonly IOS_CONFIGURATION_NAME="Debug"
readonly IOS_PRODUCT_NAME="ArcNote.app"
readonly IOS_BUNDLE_IDENTIFIER="com.michen.arcnote"

choose_ios_device() {
    local device_list="${1:-}"
    local explicit_device="${IOS_DEVICE:-}"

    if [[ -n "${explicit_device//[[:space:]]/}" ]]; then
        print -r -- "$explicit_device"
        return 0
    fi

    local booted_device_id
    if ! booted_device_id=$(
        /usr/bin/osascript -l JavaScript -e '
            function run(argv) {
                const root = JSON.parse(argv[0]);
                const runtimes = root.devices || {};
                const iphoneTypePrefix =
                    "com.apple.CoreSimulator.SimDeviceType.iPhone-";

                for (const runtimeIdentifier of Object.keys(runtimes)) {
                    if (!runtimeIdentifier.includes(".SimRuntime.iOS-")) {
                        continue;
                    }
                    const devices = runtimes[runtimeIdentifier];
                    if (!Array.isArray(devices)) {
                        continue;
                    }
                    for (const device of devices) {
                        if (
                            device.state === "Booted"
                            && device.isAvailable !== false
                            && typeof device.deviceTypeIdentifier === "string"
                            && device.deviceTypeIdentifier.startsWith(
                                iphoneTypePrefix
                            )
                            && typeof device.udid === "string"
                        ) {
                            return device.udid;
                        }
                    }
                }
                return "";
            }
        ' "$device_list"
    ); then
        print -u2 -- "[ios-run] Unable to parse Simulator device list"
        return 1
    fi

    if [[ -n "$booted_device_id" ]]; then
        print -r -- "$booted_device_id"
    else
        print -r -- "$DEFAULT_IOS_DEVICE"
    fi
}

require_command() {
    local command_name="$1"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        print -u2 -- "[ios-run] Missing required command: $command_name"
        return 1
    fi
}

main() {
    setopt localoptions errexit nounset pipefail

    require_command xcrun
    require_command xcodebuild
    require_command open
    require_command /usr/bin/osascript

    local script_path="${(%):-%x}"
    local repository_root="${script_path:A:h:h}"
    local derived_data="${IOS_DERIVED_DATA:-$DEFAULT_IOS_DERIVED_DATA}"
    local device_list
    local device
    local destination
    local app_path

    device_list="$(xcrun simctl list devices available --json)"
    device="$(choose_ios_device "$device_list")"
    if [[ "$device" =~ '^[0-9A-Fa-f-]{36}$' ]]; then
        destination="platform=iOS Simulator,id=$device"
    else
        destination="platform=iOS Simulator,name=$device"
    fi
    app_path="$derived_data/Build/Products/Debug-iphonesimulator/$IOS_PRODUCT_NAME"

    print -r -- "[ios-run] Simulator: $device"
    local boot_output=""
    local boot_status=0
    if boot_output="$(xcrun simctl boot "$device" 2>&1)"; then
        boot_status=0
    else
        boot_status=$?
    fi

    if xcrun simctl bootstatus "$device" -b; then
        :
    else
        local bootstatus_status=$?
        if (( boot_status != 0 )); then
            print -u2 -- \
                "[ios-run] Simulator boot request failed (status $boot_status):"
            if [[ -n "$boot_output" ]]; then
                print -u2 -r -- "$boot_output"
            fi
        fi
        print -u2 -- "[ios-run] Unable to boot Simulator: $device"
        return "$bootstatus_status"
    fi
    open -a Simulator

    print -r -- "[ios-run] Building latest Local ArcNote app..."
    xcodebuild build -quiet \
        -project "$repository_root/ArcNote.xcodeproj" \
        -scheme "$IOS_SCHEME_NAME" \
        -configuration "$IOS_CONFIGURATION_NAME" \
        -destination "$destination" \
        -derivedDataPath "$derived_data" \
        CODE_SIGNING_ALLOWED=NO

    if [[ ! -d "$app_path" ]]; then
        print -u2 -- "[ios-run] Built app not found: $app_path"
        return 1
    fi

    print -r -- "[ios-run] Installing and launching $IOS_BUNDLE_IDENTIFIER..."
    xcrun simctl install "$device" "$app_path"
    xcrun simctl launch --terminate-running-process \
        "$device" \
        "$IOS_BUNDLE_IDENTIFIER"
    print -r -- "[ios-run] ArcNote is running on $device"
}

if [[ "${ZSH_EVAL_CONTEXT:-}" == "toplevel" ]]; then
    main "$@"
fi
