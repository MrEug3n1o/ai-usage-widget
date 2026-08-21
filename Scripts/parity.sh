#!/bin/bash
# Diff this app's collection against cli/usage_monitor.py, the reference
# implementation of the Provider/Meter contract. Keys are sorted and volatile
# fields blanked, so what remains is real divergence.
#
# Usage: Scripts/parity.sh [path-to-usage_monitor.py]
set -uo pipefail

PY="${1:-$(cd "$(dirname "$0")/../../ai-usage-monitor" && pwd)/cli/usage_monitor.py}"
APP="/Applications/AI Usage.app/Contents/MacOS/AI Usage"

[ -f "$PY" ] || { echo "reference not found: $PY" >&2; exit 2; }
[ -x "$APP" ] || { echo "app not installed: $APP (build the AIUsage scheme first)" >&2; exit 2; }

# reset_at moves between the two runs and percentages drift as quota is spent;
# both are compared for presence and shape, not value.
normalize() {
    python3 -c '
import json, sys
def scrub(p):
    for m in p.get("meters", []):
        if m.get("reset_at"): m["reset_at"] = "<timestamp>"
        if m.get("percent") is not None: m["percent"] = round(float(m["percent"]), 0)
    return p
print(json.dumps([scrub(p) for p in json.load(sys.stdin)], indent=2, sort_keys=True))
'
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
python3 "$PY" once --json | normalize > "$TMP/python.json" || { echo "reference run failed" >&2; exit 2; }
"$APP" --probe            | normalize > "$TMP/swift.json"  || { echo "app run failed" >&2; exit 2; }

if diff -u "$TMP/python.json" "$TMP/swift.json"; then
    echo "PARITY OK"
else
    echo
    echo "^ divergence: - is Python (reference), + is Swift"
    exit 1
fi
