#!/bin/bash
# Fails when the app's code and data outgrow the budget that leaves a 128 KB
# watch room to parse its replies.
#
# Usage: ./check-memory.sh
#
# fenix 6 and 6S give a watch app 128 KB, code and data included. A 5 KB
# nearby reply needs about 25 KB free to parse, and the view and the system
# hold about 10 KB beyond code and data. At the ceiling the app idles near
# 96 KB of 124 in the simulator. The build is the debug one the simulator
# runs. The store build strips about 7 KB of debug data from it.

set -u

DEVICE=fenix6s
CEILING=85000

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Debug data holds every source path, so the build runs from a path of fixed
# length to read the same on every machine.
OUT="$(mktemp -d /tmp/ttmem.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT
cp -r "$SCRIPT_DIR/TrainTime" "$OUT/app"

cd "$OUT/app" || exit 1
stats="$(monkeyc -d "$DEVICE" -f monkey.jungle -o "$OUT/app.prg" -y "$HOME/.Garmin/developer_key.der" --build-stats 0 2>&1)"
if ! echo "$stats" | grep -q 'BUILD SUCCESSFUL'; then
    echo "$stats"
    echo "Error: $DEVICE build failed"
    exit 1
fi

# SDK 8 lists Data and Code each with a Foreground line under it. SDK 9 lists
# Foreground with Code and Data lines under it.
read -r code data < <(echo "$stats" | awk '
    /^ *(Data|Code|Foreground):$/ { section = $1 }
    /^ *Foreground: [0-9]/ { if (section == "Code:") c = $2; if (section == "Data:") d = $2 }
    /^ *Code: [0-9]/ { if (section == "Foreground:") c = $2 }
    /^ *Data: [0-9]/ { if (section == "Foreground:") d = $2 }
    END { print c + 0, d + 0 }')
total=$((data + code))
if [ "$code" -eq 0 ] || [ "$total" -gt "$CEILING" ]; then
    echo "Error: $DEVICE code $code + data $data = $total bytes, past the ceiling of $CEILING."
    echo "Leave code these watches never run out of their build in monkey.jungle, or cut resident data."
    exit 1
fi
echo "Memory: $DEVICE code $code + data $data = $total of $CEILING bytes"
