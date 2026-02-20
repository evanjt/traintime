#!/bin/bash

APP_NAME="TrainTime"

# Check if monkeyc exists
if ! command -v monkeyc &> /dev/null; then
    echo "Error: monkeyc not found. Please run ./setup.sh and install the SDK first."
    exit 1
fi

cd $APP_NAME

if [ "$1" = "release" ]; then
    echo "Building $APP_NAME release package for all devices..."
    monkeyc -e -f monkey.jungle -o ../$APP_NAME.iq -y ~/.Garmin/developer_key.der -r

    if [ $? -eq 0 ]; then
        echo "Release build successful! Output: $APP_NAME.iq"
        echo ""
        echo "Upload $APP_NAME.iq to the Garmin Connect IQ Store."
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
