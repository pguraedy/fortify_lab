#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${RUN_STORAGE_FAILURE_TESTS:-0} == 1 ]] || { echo 'SKIP: set RUN_STORAGE_FAILURE_TESTS=1'; exit 0; }
export FORTIFY_HOME=${FORTIFY_HOME:-/opt/fortify-deploy}
source "$FORTIFY_HOME/lib/common.sh"
source "$FORTIFY_HOME/lib/config.sh"
source "$FORTIFY_HOME/lib/stages.sh"
free=$(df -BG / | awk 'NR==2{gsub("G","");print $4}')
threshold=$((free+1))
echo "Injecting a safe logical DiskPressure condition: free=${free}GiB required=${threshold}GiB"
if (assert_disk_headroom "$threshold"); then echo 'FAIL: disk headroom gate accepted insufficient capacity'; exit 1; else echo 'PASS: disk headroom gate rejected insufficient capacity'; fi
assert_disk_headroom 1
echo 'PASS: disk gate recovered after restoring normal threshold'
echo 'CLEANUP: none required; this test does not allocate disk space or create files.'
