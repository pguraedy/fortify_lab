#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=${1:-.}
grep -q 'guided_menu' "$ROOT/lib/guided.sh"
grep -q 'guided_build_lab' "$ROOT/lib/guided.sh"
grep -q 'guided_recover_lab' "$ROOT/lib/guided.sh"
grep -q 'RUN_STORAGE_FAILURE_TESTS=1' "$ROOT/lib/guided.sh"
grep -q 'guided) guided_menu' "$ROOT/bin/fortify-lab"
bash -n "$ROOT/lib/guided.sh"
echo 'Guided lifecycle static checks passed.'
