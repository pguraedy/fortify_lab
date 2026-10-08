#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
status=0
for t in "$ROOT"/30-pvc-pending-injection.sh "$ROOT"/31-disk-headroom-injection.sh; do echo "===== $(basename "$t") ====="; sudo RUN_STORAGE_FAILURE_TESTS=1 FORTIFY_HOME=${FORTIFY_HOME:-/opt/fortify-deploy} "$t" || status=1; done
exit "$status"
