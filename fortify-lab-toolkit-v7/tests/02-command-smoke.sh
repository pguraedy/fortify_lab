#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/tests/testlib.sh"
export FORTIFY_HOME="$ROOT"
if "$ROOT/bin/fortify-lab" --help > "$RESULT_DIR/help.txt"; then pass 'help command'; else fail 'help command'; fi
if "$ROOT/bin/fortify-lab" workflow status > "$RESULT_DIR/workflow-status.txt"; then pass 'workflow status'; else fail 'workflow status'; fi
assert_contains "$RESULT_DIR/help.txt" 'workflow run\|resume\|status'
assert_contains "$RESULT_DIR/help.txt" 'hosts precheck\|apply\|verify'
assert_contains "$RESULT_DIR/help.txt" 'license import\|validate\|sync'
assert_contains "$RESULT_DIR/workflow-status.txt" 'hostname-resolution'
assert_contains "$RESULT_DIR/workflow-status.txt" 'license-file'
assert_contains "$RESULT_DIR/workflow-status.txt" 'final-validation'
summary
