#!/bin/bash

APP_NAME="TrainTime"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check if monkeyc exists
if ! command -v monkeyc &> /dev/null; then
    echo "Error: monkeyc not found. Please run ./setup.sh and install the SDK first."
    exit 1
fi

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: ./build.sh [command]"
    echo ""
    echo "Commands:"
    echo "  (none)              Build for fenix6pro (default device)"
    echo "  <device>            Build for a specific device (e.g. fenix7pro)"
    echo "  release <version>   Build .iq package for all devices and set version"
    echo "                      Version is written to manifest.xml (e.g. 0.2.0)"
    echo ""
    echo "Examples:"
    echo "  ./build.sh                  Build debug .prg for fenix6pro"
    echo "  ./build.sh epix2pro47mm     Build debug .prg for epix2pro47mm"
    echo "  ./build.sh release 0.2.0    Build release .iq with version 0.2.0"
    exit 0
fi

cd "$SCRIPT_DIR/$APP_NAME"

if [ "$1" = "release" ]; then
    VERSION="$2"
    if [ -z "$VERSION" ]; then
        CURRENT=$(grep -oP 'version="\K[^"]+' manifest.xml | head -1)
        echo "Error: version required. Usage: ./build.sh release <version>"
        echo "Current version: $CURRENT"
        exit 1
    fi

    # Update version in manifest.xml
    sed -i "s/version=\"[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\"/version=\"$VERSION\"/" manifest.xml
    echo "Version set to $VERSION"

    echo "Building $APP_NAME release package for all devices..."
    monkeyc -e -f monkey.jungle -o ../$APP_NAME.iq -y ~/.Garmin/developer_key.der -r

    if [ $? -eq 0 ]; then
        echo "Release build successful! Output: $APP_NAME.iq"
        echo ""
        echo "Upload $APP_NAME.iq to the Garmin Connect IQ Store."
        echo "App Version: $VERSION"
    else
        echo "Release build failed!"
        exit 1
    fi
else
    DEVICE="${1:-fenix6pro}"
    echo "Building $APP_NAME for $DEVICE..."
    monkeyc -d $DEVICE -f monkey.jungle -o ../$APP_NAME.prg -y ~/.Garmin/developer_key.der

    if [ $? -eq 0 ]; then
        echo "Build successful! Output: $APP_NAME.prg"
    else
        echo "Build failed!"
        exit 1
    fi
fi
