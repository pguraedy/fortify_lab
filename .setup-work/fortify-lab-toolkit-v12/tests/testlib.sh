#!/usr/bin/env bash
set -Eeuo pipefail
PASS=0 FAIL=0 SKIP=0
RESULT_DIR=${RESULT_DIR:-/tmp/fortify-tests}
mkdir -p "$RESULT_DIR"
pass(){ echo "PASS: $*"; PASS=$((PASS+1)); }
fail(){ echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }
skip(){ echo "SKIP: $*"; SKIP=$((SKIP+1)); }
assert_file(){ [[ -f "$1" ]] && pass "file exists: $1" || fail "file missing: $1"; }
assert_exec(){ [[ -x "$1" ]] && pass "executable: $1" || fail "not executable: $1"; }
assert_contains(){ grep -qE "$2" "$1" && pass "$1 contains $2" || fail "$1 missing $2"; }
assert_eq(){ [[ "$1" == "$2" ]] && pass "$3" || fail "$3: expected '$2', got '$1'"; }
summary(){ echo "RESULT: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"; (( FAIL == 0 )); }
