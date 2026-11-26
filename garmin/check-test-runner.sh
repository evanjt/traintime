#!/bin/bash
# Fails with a plain message before the Connect IQ test runner outgrows the
# 253 instance members a class may have on CIQ 3 devices.
#
# Usage: ./check-test-runner.sh <output dir of a monkeyc -t build>
#
# monkeyc writes the runner it generates to <output dir>/gen/*/source/UnitTests.mcgen,
# even when the build then fails on the member limit. The runner lists each
# (:test) function once for every source file compiled after the one that
# holds it, so tests kept in source/ multiply with every app file added. They
# live in test/, which the jungle compiles last.

set -u

LIMIT=253
# Headroom so the ceiling is hit in review, well before the compiler error.
CEILING=$((LIMIT - 30))

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:?usage: check-test-runner.sh <output dir of a monkeyc -t build>}"

misplaced="$(grep -lE '^\s*\(:test\)' "$SCRIPT_DIR"/TrainTime/source/*.mc 2> /dev/null)"
if [ -n "$misplaced" ]; then
    echo "Error: (:test) code belongs in TrainTime/test/, not source/:"
    echo "$misplaced" | sed 's|.*/TrainTime/|  |'
    exit 1
fi

# A test/ declaration without (:test) compiles into the app build, where it
# costs memory a 128 KB watch needs. Helpers go in a (:test) module.
leaked="$(awk '/^(function|class|module|const|var) / && prev !~ /^\(:test/ { print FILENAME ": " $0 }
    NF { prev = $0 }' "$SCRIPT_DIR"/TrainTime/test/*.mc | sed 's|.*/TrainTime/|  |')"
if [ -n "$leaked" ]; then
    echo "Error: test/ declarations without (:test) end up in the app build:"
    echo "$leaked"
    exit 1
fi

runners=("$OUT_DIR"/gen/*/source/UnitTests.mcgen)
if [ ! -f "${runners[0]}" ]; then
    echo "Error: no generated test runner under $OUT_DIR/gen. Build with monkeyc -t first."
    exit 1
fi

status=0
for runner in "${runners[@]}"; do
    members=$(grep -cE '^    ((private|public|protected|hidden) )?(function|var) ' "$runner")
    entries=$(grep -cE '^        idToName\[[0-9]+\] = ' "$runner")
    if [ "$members" -gt "$CEILING" ]; then
        echo "Error: the test runner has $members members ($entries test entries), past the ceiling of $CEILING."
        echo "CIQ 3 refuses more than $LIMIT. Merge (:test) functions that check one rule, or test files."
        status=1
    else
        echo "Test runner: $members of $CEILING members ($entries test entries)"
    fi
done
exit $status
