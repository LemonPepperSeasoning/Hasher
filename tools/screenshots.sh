#!/bin/bash
# Takes the App Store screenshots on the 6.9" iPhone and 13" iPad simulators, plus a 6.3" set
# resized from the 6.9" one. Usage: tools/screenshots.sh [output directory]
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(cd "$(mkdir -p "${1:-screenshots}" && echo "${1:-screenshots}")" && pwd)

for device in "iPhone 17 Pro Max" "iPad Pro 13-inch (M5)"; do
    id=$(xcrun simctl list devices available | grep -F "$device (" | head -1 | grep -oE '[0-9A-F-]{36}')
    # A fresh boot drops the "◀ <app>" back button another app leaves in the status bar.
    xcrun simctl shutdown "$id" 2>/dev/null || true
    xcrun simctl boot "$id"
    xcrun simctl bootstatus "$id" >/dev/null
    xcrun simctl status_bar "$id" override --time 9:41 --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3
    xcrun simctl uninstall "$id" com.takahiro.Hasher 2>/dev/null || true
    TEST_RUNNER_SHOTS_DIR="$out" xcodebuild test -project Hasher.xcodeproj -scheme Hasher \
        -destination "id=$id" -only-testing:HasherUITests/ScreenshotTests -quiet
done

mkdir -p "$out/6.3"
for f in "$out"/iPhone*.png; do
    sips -z 2622 1206 "$f" --out "$out/6.3/$(basename "$f")" >/dev/null
done
echo "Screenshots in $out"
