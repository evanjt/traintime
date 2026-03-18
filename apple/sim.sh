#!/bin/bash
# Build and run TrainTime in the iOS/watchOS Simulator
#
# Usage:
#   ./sim.sh              Build & run phone app (default)
#   ./sim.sh phone        Build & run phone app
#   ./sim.sh watch        Build & run watch app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/TrainTimeWatch.xcodeproj"
TARGET="${1:-phone}"

if [ "$TARGET" = "--help" ] || [ "$TARGET" = "-h" ]; then
    echo "Usage: ./sim.sh [phone|watch]"
    echo ""
    echo "  phone (default)     Build & run on iPhone 17 Pro Max"
    echo "  watch               Build & run on Apple Watch Ultra 2"
    exit 0
fi

case "$TARGET" in
    phone)
        SCHEME="TrainTimePhone"
        DEVICE="iPhone 17 Pro Max"
        PLATFORM="iOS Simulator"
        APP_NAME="TrainTimePhone.app"
        APP_SUBDIR="Debug-iphonesimulator"
        BUNDLE_ID="com.evanjt.traintime"
        ;;
    watch)
        SCHEME="TrainTimeWatch"
        DEVICE="Apple Watch Ultra 3 (49mm)"
        PLATFORM="watchOS Simulator"
        APP_NAME="TrainTimeWatch.app"
        APP_SUBDIR="Debug-watchsimulator"
        BUNDLE_ID="com.evanjt.traintime.watchkitapp"
        ;;
    *)
        echo "Unknown target: $TARGET (use 'phone' or 'watch')"
        exit 1
        ;;
esac

DESTINATION="platform=$PLATFORM,name=$DEVICE"

echo "Building $SCHEME for $DEVICE..."

# Build for simulator
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$SCRIPT_DIR/.build" \
    build \
    2>&1 | tail -5

if [ ${PIPESTATUS[0]} -ne 0 ]; then
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

# Boot simulator if needed
BOOTED=$(xcrun simctl list devices booted | grep "$DEVICE" || true)
if [ -z "$BOOTED" ]; then
    echo "Booting $DEVICE..."
    xcrun simctl boot "$DEVICE" 2>/dev/null || true
    sleep 2
fi

# Open Simulator.app
open -a Simulator

# Set location to Sion old town, Switzerland
echo "Setting location to Sion, Switzerland..."
xcrun simctl location "$DEVICE" set "46.2325,7.3597"

# Install and launch
echo "Installing and launching..."
xcrun simctl install "$DEVICE" "$APP_PATH"
xcrun simctl launch "$DEVICE" "$BUNDLE_ID"

echo "Running on $DEVICE!"
