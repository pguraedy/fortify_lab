#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/tests/testlib.sh"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
export FORTIFY_HOME="$WORK"
mkdir -p "$WORK/config" "$WORK/logs" "$WORK/state"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/config.sh"
source "$ROOT/lib/stages.sh"
state_init
state_set preflight PASS 'test pass'
state_set prerequisites INTERRUPTED 'test interruption'
assert_eq "$(state_get preflight)" PASS 'state writes PASS'
assert_eq "$(state_get prerequisites)" INTERRUPTED 'state writes INTERRUPTED'
assert_eq "$(workflow_next_stage)" prerequisites 'resume selects interrupted stage'
state_set prerequisites PASS 'resumed'
assert_eq "$(workflow_next_stage)" configuration 'resume advances after pass'
summary
