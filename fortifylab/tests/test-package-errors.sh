#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
MISSING="$TMP/missing/fortifylab"
mkdir -p "$(dirname "$MISSING")"
cp -a "$ROOT" "$MISSING"
# Missing-package check must identify both acceptable names.
if WORK="$TMP/w1" OUT="$TMP/o1" "$MISSING/build-v12.sh" >"$TMP/missing.log" 2>&1; then
  echo 'FAIL: missing packages were accepted' >&2; exit 1
fi
grep -q 'Expected exactly one of: fortify-lab-toolkit-v7.zip or fortify-lab-toolkit-v7.tar.gz' "$TMP/missing.log"
# Duplicate-format check for the first required package.
DUP="$TMP/duplicate/fortifylab"
mkdir -p "$(dirname "$DUP")"
cp -a "$ROOT" "$DUP"
mkdir -p "$TMP/src/fortify-lab-toolkit-v7"
(cd "$TMP/src" && zip -qr "$DUP/fortify-lab-toolkit-v7.zip" fortify-lab-toolkit-v7 && tar -czf "$DUP/fortify-lab-toolkit-v7.tar.gz" fortify-lab-toolkit-v7)
if WORK="$TMP/w2" OUT="$TMP/o2" "$DUP/build-v12.sh" >"$TMP/duplicate.log" 2>&1; then
  echo 'FAIL: duplicate formats were accepted' >&2; exit 1
fi
grep -q 'Duplicate package formats found for fortify-lab-toolkit-v7' "$TMP/duplicate.log"
echo 'PASS: strict missing-package and duplicate-format checks'
