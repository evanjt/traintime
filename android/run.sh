#!/usr/bin/env bash
# One-command run, the `npx expo run:android` equivalent: boot an emulator if
# none is connected, build + install, launch, and drop a Swiss location in so
# the app actually shows departures. Override the location: ./run.sh <lat> <lon>
set -euo pipefail

LAT="${1:-46.2306}"   # Place de la Planta, Sion
LON="${2:-7.3576}"
AVD="${TT_AVD:-Pixel_5_API_35}"
SDK="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$SDK/platform-tools/adb"
EMULATOR="$SDK/emulator/emulator"

cd "$(dirname "$0")"

# Boot an emulator only if nothing is attached. -gpu host avoids the slow
# software-renderer black screen on first paint.
if ! "$ADB" get-state >/dev/null 2>&1; then
    echo "No device — booting $AVD…"
    "$EMULATOR" -avd "$AVD" -gpu host -no-boot-anim >/dev/null 2>&1 &
    "$ADB" wait-for-device
fi
"$ADB" shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done'

# 3-button nav so there's a visible Home/Back bar (the emulator defaults to
# gesture nav, which is fiddly to drive in the emulator window).
"$ADB" shell cmd overlay enable com.android.internal.systemui.navbar.threebutton >/dev/null 2>&1 || true

./gradlew installDebug
"$ADB" shell am start -n com.evanjt.traintime/.MainActivity >/dev/null

# Feed a location the fused provider will actually read (adb emu geo fix is
# unreliable for it). Harmless if it's already set up.
"$ADB" shell appops set com.android.shell android:mock_location allow >/dev/null 2>&1 || true
for p in gps network; do
    "$ADB" shell cmd location providers add-test-provider "$p" --supportsBearing --supportsSpeed >/dev/null 2>&1 || true
    "$ADB" shell cmd location providers set-test-provider-enabled "$p" true >/dev/null 2>&1 || true
    "$ADB" shell cmd location providers set-test-provider-location "$p" --location "$LAT,$LON" --accuracy 8 >/dev/null 2>&1 || true
done

echo "Running at $LAT,$LON. Re-run anytime to rebuild + reinstall."
