#!/bin/bash
# Runs the daemon without root - real sensors, SMC and pmset writes replaced by log lines - and
# drives it through fancurvectl over its socket.
#   swift build && ./scripts/smoke-dry-run.sh
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=.build/debug
ROOT=$(mktemp -d /tmp/fc-smoke.XXXXXX)
SOCK="$ROOT/fancurve.sock"
LOG="$ROOT/daemon.log"

"$BIN/fancurved" --dry-run --root "$ROOT" 2> "$LOG" &
PID=$!
cleanup() {
  kill "$PID" 2>/dev/null
  wait "$PID" 2>/dev/null
  rm -rf "$ROOT"
}
trap cleanup EXIT

for _ in $(seq 50); do [ -S "$SOCK" ] && break; sleep 0.1; done
[ -S "$SOCK" ] || { echo "FAIL: no socket at $SOCK"; cat "$LOG"; exit 1; }
sleep 2  # a few ticks

ctl() { "$BIN/fancurvectl" --socket "$SOCK" "$@"; }
FAILS=0
check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then echo "ok   $name"; else echo "FAIL $name"; FAILS=$((FAILS + 1)); fi
}

STATUS=$(ctl status)
echo "$STATUS"
check "status: mode active" grep -q "^mode: active" <<< "$STATUS"
check "status: the cpu reads" grep -Eq "^cpu [0-9]" <<< "$STATUS"
check "status --json is JSON" python3 -c "import json, sys; json.load(sys.stdin)" <<< "$(ctl status --json)"
check "history: header and rows" test "$(ctl history 5 | wc -l)" -ge 2
check "config get: the hotspot curve" grep -q '"hotspot"' <<< "$(ctl config get)"
check "disable: mode disabled" grep -q "^mode: disabled" <<< "$(ctl disable)"
check "enable: control resumes" grep -Eq "^mode: (starting|active)" <<< "$(ctl enable)"
check "gpu on" grep -q "auto-graphics on" <<< "$(ctl gpu on)"
check "gpu off" grep -q "auto-graphics off" <<< "$(ctl gpu off)"
check "heartbeat file" test -f "$ROOT/run/heartbeat"
check "take only logged" grep -q "dry-run: take" "$LOG"
check "pmset only logged" grep -q "dry-run: pmset gpuswitch ac 1 battery 2" "$LOG"
kill -TERM "$PID"
wait "$PID" 2>/dev/null
check "SIGTERM hands the fans back" grep -q "shutting down, fans handed back to macOS" "$LOG"

echo "---- daemon log"
cat "$LOG"
[ "$FAILS" -eq 0 ] && { echo "PASS"; exit 0; }
echo "FAILED: $FAILS"
exit 1
