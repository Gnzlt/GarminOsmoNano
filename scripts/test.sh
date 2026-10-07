#!/usr/bin/env bash
# Run every (:test) function of bin/OsmoNano-test.prg in the Connect IQ SDK's
# simulator (or with ciq-sim, a headless runner, when it is installed). The
# device is $DEVICE, fenix847mm by default.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE:-fenix847mm}"
cd "$ROOT"
if command -v ciq-sim >/dev/null; then
    exec ciq-sim test bin/OsmoNano-test.prg "$DEVICE"
fi
# Reuse a running simulator: killing and relaunching it made it crash.
if ! pgrep -f "ConnectIQ.app/Contents/MacOS/simulator" >/dev/null; then
    connectiq >/dev/null 2>&1 &
fi
log="$(mktemp)"
for _ in $(seq 1 30); do
    if monkeydo bin/OsmoNano-test.prg "$DEVICE" -t >"$log" 2>&1 && grep -q "^Ran" "$log"; then
        break
    fi
    sleep 2
done
grep -E "ASSERTION|FAIL|ERROR" "$log" || true
tail -1 "$log"
grep -q "^PASSED" "$log"
