#!/bin/bash
# check-app-warnings.sh — Fail if the app target's own sources produced any
# compiler warning.
#
# The VocaMac target builds with complete concurrency checking
# (StrictConcurrency in Package.swift), so a data race the compiler can see
# shows up as a warning. Dependencies' warnings are ignored.
#
# Usage: swift build 2>&1 | tee build.log; ./scripts/check-app-warnings.sh build.log

set -euo pipefail

LOG="${1:?usage: check-app-warnings.sh <build log>}"

WARNINGS="$(sed -E 's/\x1b\[[0-9;]*m//g' "$LOG" \
    | grep -E '/Sources/(VocaMac|VocaMacObjC)/[^:]+:[0-9]+:[0-9]+: warning:' \
    | sort -u || true)"

if [ -n "$WARNINGS" ]; then
    COUNT="$(printf '%s\n' "$WARNINGS" | wc -l | tr -d ' ')"
    echo "❌ $COUNT compiler warning(s) in app sources:"
    printf '%s\n' "$WARNINGS"
    exit 1
fi
echo "✅ No compiler warnings in app sources"
