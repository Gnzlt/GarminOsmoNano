#!/usr/bin/env bash
# Run every (:test) function of bin/OsmoNano-test.prg in a fresh simulator, on
# $DEVICE (fenix847mm by default). Here (Linux, headless) that is ciq-sim,
# which restarts the simulator itself. On a Mac it is the SDK's simulator,
# restarted too: one that still holds the app's BLE profiles from an earlier
# run can crash in registerProfile or hang monkeydo.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE:-fenix847mm}"
cd "$ROOT"
if command -v ciq-sim >/dev/null; then
    exec ciq-sim test bin/OsmoNano-test.prg "$DEVICE"
fi
pkill -f "ConnectIQ.app/Contents/MacOS/simulator" 2>/dev/null || true
sleep 2
connectiq >/dev/null 2>&1 &
# monkeydo fails with "Unable to connect" until the simulator listens.
log="$(mktemp)"
for _ in $(seq 1 30); do
    if monkeydo bin/OsmoNano-test.prg "$DEVICE" -t >"$log" 2>&1 && grep -q "^Ran" "$log"; then
        break
    fi
    grep -q "^Ran" "$log" && break
    sleep 2
done
grep -E "^(Executing|ERROR|FAIL)|ASSERTION|at .*Test\.mc" "$log" | grep -B1 -A3 -E "ERROR|FAIL|ASSERTION" || true
tail -1 "$log"
grep -q "^PASSED" "$log"
