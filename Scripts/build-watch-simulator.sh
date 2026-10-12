#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "Run this script on your Mac with Xcode selected."
    exit 1
fi

if [[ "$#" -gt 1 ]]; then
    echo "Usage: Scripts/build-watch-simulator.sh [Watch-simulator-UUID]"
    exit 1
fi

check_watch_plist() {
    local plist="$1"
    local watch_only
    watch_only="$(/usr/libexec/PlistBuddy -c 'Print :WKWatchOnly' "$plist" 2>/dev/null || true)"
    if [[ "$watch_only" != "true" ]]; then
        echo "Expected WKWatchOnly=true in: $plist"
        return 1
    fi
    if /usr/libexec/PlistBuddy -c 'Print :WKRunsIndependentlyOfCompanionApp' "$plist" >/dev/null 2>&1; then
        echo "Conflicting WKRunsIndependentlyOfCompanionApp key found in: $plist"
        echo "Remove that key entirely, keeping WKWatchOnly."
        return 1
    fi
}

echo "Building project: $PWD/PickleMyBallsWatch.xcodeproj"
if [[ -d .git || -f .git ]]; then
    git log -1 --oneline
fi
check_watch_plist WatchApp/Info.plist

# Keep this build separate from Xcode's cached products. Retain the log and app for diagnosis.
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/PickleMyBallsBuild.XXXXXX")"
echo "Fresh build directory: $build_dir"
if ! xcodebuild \
    -project PickleMyBallsWatch.xcodeproj \
    -scheme "PickleMyBalls Watch" \
    -configuration Debug \
    -sdk watchsimulator \
    -destination 'generic/platform=watchOS Simulator' \
    -derivedDataPath "$build_dir" \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$build_dir/build.log"; then
    echo "Build failed. Log: $build_dir/build.log"
    exit 1
fi

app="$build_dir/Build/Products/Debug-watchsimulator/PickleMyBalls Watch.app"
if [[ ! -f "$app/Info.plist" ]]; then
    echo "Expected app was not produced: $app"
    exit 1
fi
check_watch_plist "$app/Info.plist"
echo "Verified built app metadata: WKWatchOnly=true; no conflicting independence key."
echo "Built app: $app"

# An explicit simulator UUID avoids installing into an unrelated booted iPhone simulator.
if [[ -n "${1:-}" ]]; then
    xcrun simctl bootstatus "$1" -b
    xcrun simctl install "$1" "$app"
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
    xcrun simctl launch "$1" "$bundle_id"
fi
