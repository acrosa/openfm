#!/bin/sh
# Installs the built app on a simulator, launches it and saves a screenshot.
#   Tools/shot.sh "simulator name" out.png [launch args...]
# With `-openfm.landscape 1` the app lays itself out sideways and the
# screenshot is turned upright afterwards.
cd "$(dirname "$0")/.." || exit 1
DEVICE="$1"; OUT="$2"; shift 2
xcrun simctl boot "$DEVICE" 2>/dev/null
xcrun simctl bootstatus "$DEVICE" >/dev/null 2>&1
xcrun simctl install "$DEVICE" build/Build/Products/Debug-iphonesimulator/OpenFM.app
xcrun simctl terminate "$DEVICE" org.openfm.OpenFM 2>/dev/null
xcrun simctl launch "$DEVICE" org.openfm.OpenFM "$@" >/dev/null
sleep 3
xcrun simctl io "$DEVICE" screenshot "$OUT" >/dev/null 2>&1
case "$*" in *openfm.landscape*) sips -r 270 "$OUT" >/dev/null ;; esac
echo "$OUT"
