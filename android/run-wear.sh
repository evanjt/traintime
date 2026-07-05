#!/usr/bin/env bash
# Wear OS twin of run.sh: boot the watch AVD (with a window), build + install
# :wear, launch, fix up the emulator's missing wifi, and drop a Swiss location
# in. Override the location: ./run-wear.sh <lat> <lon>
set -euo pipefail

LAT="${1:-46.2306}"   # Place de la Planta, Sion
LON="${2:-7.3576}"
AVD="${TT_WEAR_AVD:-tt_wear}"
SDK="${ANDROID_HOME:-$HOME/Android/Sdk}"
ADB="$SDK/platform-tools/adb"
EMULATOR="$SDK/emulator/emulator"

cd "$(dirname "$0")"

# Find an already-running instance of this AVD, else boot one.
serial_of_avd() {
    for s in $("$ADB" devices | awk '/emulator-/{print $1}'); do
        if [ "$("$ADB" -s "$s" emu avd name 2>/dev/null | head -1 | tr -d '\r')" = "$AVD" ]; then
            echo "$s"; return
        fi
    done
}
SERIAL="$(serial_of_avd || true)"
if [ -z "${SERIAL:-}" ]; then
    echo "Booting $AVD…"
    # No display (ssh/agent shell) → headless, else the emulator aborts.
    WINDOW_FLAG=""
    [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && WINDOW_FLAG="-no-window"
    "$EMULATOR" -avd "$AVD" -gpu swiftshader_indirect -no-boot-anim $WINDOW_FLAG >/dev/null 2>&1 &
    sleep 5
    for _ in $(seq 1 24); do
        SERIAL="$(serial_of_avd || true)"; [ -n "$SERIAL" ] && break; sleep 5
    done
fi
[ -n "${SERIAL:-}" ] || { echo "Could not find $AVD on adb"; exit 1; }
echo "Watch is $SERIAL"
"$ADB" -s "$SERIAL" shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 1; done'

# A standalone Wear AVD boots with no network — associate the virtual wifi.
# Needs root for the wifi command; drop back to shell after (mock location
# fails under root).
"$ADB" -s "$SERIAL" root >/dev/null 2>&1 || true
sleep 2
"$ADB" -s "$SERIAL" shell cmd wifi connect-network AndroidWifi open >/dev/null 2>&1 || true
"$ADB" -s "$SERIAL" unroot >/dev/null 2>&1 || true
# adb flaps offline briefly around root/unroot; wait for a real "device" state.
for _ in $(seq 1 30); do
    [ "$("$ADB" -s "$SERIAL" get-state 2>/dev/null || true)" = "device" ] && break
    sleep 2
done

# Install just the wear APK on just this device (gradlew installDebug would
# hit every connected emulator, including a phone one).
./gradlew :wear:assembleDebug
"$ADB" -s "$SERIAL" install -r wear/build/outputs/apk/debug/wear-debug.apk

# Mock the fused provider. --accuracy is required: without it the fix is
# silently dropped. GMS can still be stubborn; if the app insists you're not
# in Switzerland, run:  $ADB -s $SERIAL shell cmd location set-location-enabled false
# and relaunch — the app then runs off its cached coordinate.
"$ADB" -s "$SERIAL" shell appops set com.android.shell android:mock_location allow >/dev/null 2>&1 || true
for p in fused gps network; do
    "$ADB" -s "$SERIAL" shell cmd location providers add-test-provider "$p" >/dev/null 2>&1 || true
    "$ADB" -s "$SERIAL" shell cmd location providers set-test-provider-enabled "$p" true >/dev/null 2>&1 || true
    "$ADB" -s "$SERIAL" shell cmd location providers set-test-provider-location "$p" --location "$LAT,$LON" --accuracy 5 >/dev/null 2>&1 || true
done

"$ADB" -s "$SERIAL" shell am start -n com.evanjt.traintime/com.evanjt.traintime.wear.MainActivity >/dev/null
echo "Running at $LAT,$LON on $SERIAL. Re-run anytime to rebuild + reinstall."
