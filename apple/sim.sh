#!/bin/bash
# Build and run TrainTime on a simulator
#
# Usage:
#   ./sim.sh              Build & run phone app (default)
#   ./sim.sh phone        Build & run phone app on an iPhone
#   ./sim.sh duo          Build & run phone app on the iPhone Duo
#   ./sim.sh watch        Build & run watch app
#
# The simulator is SIM_UDID when set, else the one simpick.py picks from the installed runtimes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/TrainTimeWatch.xcodeproj"
TARGET="${1:-phone}"

if [ "$TARGET" = "--help" ] || [ "$TARGET" = "-h" ]; then
    echo "Usage: [SIM_UDID=<udid>] ./sim.sh [phone|duo|watch]"
    echo ""
    echo "  phone (default)     Build & run the phone app on the newest installed iPhone:"
    echo "                      a standard iPhone, else the iPhone Duo, else an iPad"
    echo "  duo                 Build & run the phone app on the iPhone Duo"
    echo "  watch               Build & run the watch app on the first Apple Watch of the"
    echo "                      newest installed watchOS runtime"
    echo ""
    echo "  SIM_UDID=<udid>     Run on this simulator instead of the picked one"
    exit 0
fi

case "$TARGET" in
    phone|duo)
        SCHEME="TrainTimePhone"
        PLATFORM="iOS Simulator"
        APP_NAME="TrainTimePhone.app"
        APP_SUBDIR="Debug-iphonesimulator"
        BUNDLE_ID="com.evanjt.traintime"
        ;;
    watch)
        SCHEME="TrainTimeWatch"
        PLATFORM="watchOS Simulator"
        APP_NAME="TrainTimeWatch.app"
        APP_SUBDIR="Debug-watchsimulator"
        BUNDLE_ID="com.evanjt.traintime.watchkitapp"
        ;;
    *)
        echo "Unknown target: $TARGET (use 'phone', 'duo' or 'watch')"
        exit 1
        ;;
esac

# Every later step addresses the simulator by this udid
if ! PICKED=$(xcrun simctl list devices available -j | python3 "$SCRIPT_DIR/simpick.py" "$TARGET" 2>&1); then
    echo "No simulator: $PICKED"
    exit 1
fi
IFS=$'\t' read -r UDID DEVICE <<< "$PICKED"

DESTINATION="platform=$PLATFORM,id=$UDID"

# Ensure Secrets.swift exists (gitignored, copy from example if missing)
SECRETS="$SCRIPT_DIR/TrainTimeWatch/Secrets.swift"
if [ ! -f "$SECRETS" ]; then
    cp "$SECRETS.example" "$SECRETS"
    echo "Created Secrets.swift from example (update with real API key if needed)"
fi

echo "Building $SCHEME for $DEVICE ($UDID)..."

# Build for simulator
if ! xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$SCRIPT_DIR/.build" \
    build \
    2>&1 | tail -5; then
    echo "Build failed!"
    exit 1
fi

echo "Build successful!"

# Find the built .app
APP_PATH=$(find "$SCRIPT_DIR/.build" -name "$APP_NAME" -path "*/$APP_SUBDIR/*" | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find built $APP_NAME"
    exit 1
fi

# Boot the simulator if needed. The steps after it wait for its services themselves.
if ! xcrun simctl list devices booted | grep "$UDID" > /dev/null; then
    echo "Booting $DEVICE..."
    xcrun simctl boot "$UDID"
fi

# Show the simulator in the selected Xcode's DeviceHub, where that Xcode ships one
DEVICE_HUB="$(xcode-select -p)/../Applications/DeviceHub.app"
if [ -d "$DEVICE_HUB" ]; then
    open "$DEVICE_HUB" || true
fi

# Set location to Place de la Planta, Sion
echo "Setting location to Place de la Planta, Sion..."
xcrun simctl location "$UDID" set "46.2306,7.3576"

# Install and launch
echo "Installing and launching..."
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo "Running on $DEVICE!"
