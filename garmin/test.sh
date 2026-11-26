#!/bin/bash
# Runs the Connect IQ unit tests (:test) in the simulator under Xvfb and
# exits 0 only on PASSED with failed=0 and errors=0.
#
# Usage: ./test.sh [device]    (default fenix6pro)

set -u

APP_NAME="TrainTime"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVICE="${1:-fenix6pro}"

for tool in monkeyc monkeydo simulator xvfb-run; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: $tool not found. Put the Connect IQ SDK bin/ and xvfb-run on PATH."
        exit 1
    fi
done

if [ ! -f "$SCRIPT_DIR/$APP_NAME/source/Secrets.mc" ]; then
    echo "Error: $APP_NAME/source/Secrets.mc not found. Copy it from the main checkout."
    exit 1
fi

# The simulator always listens on 127.0.0.1:1234, Xvfb displays live in the
# shared /tmp and the simulator keys SysV shared memory to a fixed id, so two
# runs on one machine collide. Private network, mount and IPC namespaces give
# each run its own of each. The outer namespace maps to root to set them up,
# and the inner one maps back to the real user for the SDK.
if [ -z "${TT_TEST_INNER:-}" ] && unshare -rnmi true 2> /dev/null; then
    exec env TT_TEST_INNER=1 unshare -rnmi bash -c '
        ip link set lo up && mount -t tmpfs tmpfs /tmp &&
        exec unshare -U --map-user="$1" --map-group="$2" bash "$0" "${@:3}"' \
        "$0" "$(id -u)" "$(id -g)" "$@"
fi

# The desktop display is out of reach in the namespace.
if [ -n "${TT_TEST_INNER:-}" ]; then
    unset DISPLAY
    export JAVA_TOOL_OPTIONS="-Djava.awt.headless=true${JAVA_TOOL_OPTIONS:+ $JAVA_TOOL_OPTIONS}"
fi
REAL_HOME="$HOME"

SCRATCH="$(mktemp -d)"
SIM_PID=""
cleanup() {
    if [ -n "$SIM_PID" ]; then
        kill -TERM -- "-$SIM_PID" 2> /dev/null
        wait "$SIM_PID" 2> /dev/null
    fi
    rm -rf "$SCRATCH"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

# The SDK links against the library versions of its release. When the system
# has moved on (libjxl.so.0.11 against 0.12), point the missing soname at the
# installed one.
SIM="$(command -v simulator)"
mkdir -p "$SCRATCH/lib"
for missing in $(ldd "$SIM" | awk '/not found/ { print $1 }'); do
    base="${missing%%.so*}.so"
    found="$(ldconfig -p | awk -v b="$base" '$1 ~ "^" b "\\." { print $NF; exit }')"
    if [ -z "$found" ]; then
        echo "Error: simulator needs $missing and no $base.* is installed."
        exit 1
    fi
    echo "Shim: $missing -> $found"
    ln -s "$found" "$SCRATCH/lib/$missing"
done
export LD_LIBRARY_PATH="$SCRATCH/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Newer freetype crashes inside the simulator's bundled TrueType bytecode
# interpreter while hinting. Turning hinting off skips that path.
cat > "$SCRATCH/fonts.conf" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
  <match target="font">
    <edit name="hinting" mode="assign"><bool>false</bool></edit>
    <edit name="autohint" mode="assign"><bool>false</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintnone</const></edit>
  </match>
</fontconfig>
EOF
export FONTCONFIG_FILE="$SCRATCH/fonts.conf"

cd "$SCRIPT_DIR/$APP_NAME" || exit 1
echo "Building tests for $DEVICE..."
monkeyc -f monkey.jungle -d "$DEVICE" -o "$SCRATCH/app.prg" -y "$REAL_HOME/.Garmin/developer_key.der" -t
built=$?
# Also run on a failed build, so the member limit reads as a plain message.
"$SCRIPT_DIR/check-test-runner.sh" "$SCRATCH" || exit 1
if [ "$built" -ne 0 ]; then
    echo "Test build failed!"
    exit 1
fi
"$SCRIPT_DIR/check-memory.sh" || exit 1

# The simulator keeps a PID lock in $HOME/Sim-root, device storage under
# $TMPDIR and rewrites ~/.Garmin/ConnectIQ/simulator.ini on exit. A run gets
# its own of all three, linked to the real SDK, devices and fonts.
CIQ="$REAL_HOME/.Garmin/ConnectIQ"
mkdir -p "$SCRATCH/home/.Garmin/ConnectIQ" "$SCRATCH/tmp"
for entry in "$CIQ"/*; do
    case "$(basename "$entry")" in
        simulator.ini) cp "$entry" "$SCRATCH/home/.Garmin/ConnectIQ/" ;;
        *) ln -s "$entry" "$SCRATCH/home/.Garmin/ConnectIQ/" ;;
    esac
done

# Its own session, so one signal to the group stops xvfb-run, Xvfb and the
# simulator together.
HOME="$SCRATCH/home" TMPDIR="$SCRATCH/tmp" \
    setsid xvfb-run -a -s "-screen 0 1280x1024x24" simulator > "$SCRATCH/sim.log" 2>&1 &
SIM_PID=$!

# A push sent before the window is laid out is lost, so wait for that as
# well as the listening socket.
simulator_ready() {
    grep -q 'SetLayout' "$SCRATCH/sim.log" &&
        awk '$2 ~ /:04D2$/ && $4 == "0A" { found = 1 } END { exit !found }' /proc/net/tcp /proc/net/tcp6
}
ready=0
for i in $(seq 1 60); do
    if simulator_ready; then ready=1; break; fi
    sleep 1
done
if [ "$ready" -ne 1 ]; then
    echo "Error: simulator not ready after 60s"
    cat "$SCRATCH/sim.log"
    exit 1
fi
echo "Simulator ready after ${i}s"

# monkeydo exits 1 even on success, so judge by the summary line.
timeout 120 monkeydo "$SCRATCH/app.prg" "$DEVICE" -t | tee "$SCRATCH/result.txt"
if ! grep -Eq '^PASSED \(passed=[0-9]+, failed=0, errors=0\)' "$SCRATCH/result.txt"; then
    echo "Garmin unit tests did not pass"
    tail -20 "$SCRATCH/sim.log"
    exit 1
fi
echo "Garmin unit tests passed"
