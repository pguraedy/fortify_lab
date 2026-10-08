#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)
RESULT_DIR=${RESULT_DIR:-$ROOT/test-results/$STAMP}
mkdir -p "$RESULT_DIR"
status=0
for t in "$ROOT"/tests/[0-9][0-9]-*.sh; do
  echo "===== $(basename "$t") =====" | tee "$RESULT_DIR/$(basename "$t").log"
  RESULT_DIR="$RESULT_DIR" bash "$t" 2>&1 | tee -a "$RESULT_DIR/$(basename  "$t").log" || status=1
  echo
 done
printf 'Test logs: %s\n' "$RESULT_DIR"
exit "$status"
