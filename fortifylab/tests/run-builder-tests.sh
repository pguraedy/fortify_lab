#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
bash -n "$ROOT/build-v12.sh"
"$ROOT/tests/test-package-errors.sh"
"$ROOT/tests/test-mixed-inputs.sh"
echo 'ALL BUILDER TESTS PASS'
