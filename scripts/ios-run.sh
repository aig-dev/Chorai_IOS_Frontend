#!/bin/zsh

set -euo pipefail

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
    booted_device_id=$(
        print -r -- "$device_list" \
            | awk '
                /^-- iOS / { in_ios = 1; next }
                /^-- / { in_ios = 0 }
                in_ios && /\(Booted\)/ && $0 !~ /^[[:space:]]*iPad/ {
                    print
                    exit
                }
            ' \
            | sed -nE \
                's/.*\(([0-9A-Fa-f-]{36})\) \(Booted\)[[:space:]]*$/\1/p'
    )

    if [[ -n "$booted_device_id" ]]; then
        print -r -- "$booted_device_id"
    else
        print -r -- "$DEFAULT_IOS_DEVICE"
    fi
}

is_ios_device_booted() {
    local device="$1"
    local device_list="$2"

    print -r -- "$device_list" | awk -v device="$device" '
        /^-- iOS / { in_ios = 1; next }
        /^-- / { in_ios = 0 }
        !in_ios || !/\(Booted\)[[:space:]]*$/ { next }
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            if (index(line, "(" device ") (Booted)") > 0) {
                found = 1
                exit
            }

            name = line
            sub(/[[:space:]]+\([0-9A-Fa-f-]+\) \(Booted\)[[:space:]]*$/, "", name)
            if (name == device) {
                found = 1
                exit
            }
        }
        END { exit found ? 0 : 1 }
    '
}

require_command() {
    local command_name="$1"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        print -u2 -- "[ios-run] Missing required command: $command_name"
        return 1
    fi
}

main() {
    require_command xcrun
    require_command xcodebuild
    require_command open

    local script_path="${(%):-%x}"
    local repository_root="${script_path:A:h:h}"
    local derived_data="${IOS_DERIVED_DATA:-$DEFAULT_IOS_DERIVED_DATA}"
    local device_list
    local device
    local destination
    local app_path

    device_list="$(xcrun simctl list devices available)"
    device="$(choose_ios_device "$device_list")"
    if [[ "$device" =~ '^[0-9A-Fa-f-]{36}$' ]]; then
        destination="platform=iOS Simulator,id=$device"
    else
        destination="platform=iOS Simulator,name=$device"
    fi
    app_path="$derived_data/Build/Products/Debug-iphonesimulator/$IOS_PRODUCT_NAME"

    print -r -- "[ios-run] Simulator: $device"
    if is_ios_device_booted "$device" "$device_list"; then
        print -r -- "[ios-run] Simulator is already booted: $device"
    elif ! xcrun simctl boot "$device"; then
        print -u2 -- "[ios-run] Unable to boot Simulator: $device"
        return 1
    fi
    if ! xcrun simctl bootstatus "$device" -b; then
        print -u2 -- "[ios-run] Unable to boot Simulator: $device"
        return 1
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
