#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${RUN_STORAGE_FAILURE_TESTS:-0} == 1 ]] || { echo 'SKIP: set RUN_STORAGE_FAILURE_TESTS=1'; exit 0; }
[[ $EUID -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
export FORTIFY_HOME=${FORTIFY_HOME:-/opt/fortify-deploy}
source "$FORTIFY_HOME/lib/common.sh"
source "$FORTIFY_HOME/lib/config.sh"
source "$FORTIFY_HOME/lib/lifecycle.sh"
source "$FORTIFY_HOME/lib/recovery-hardened.sh"
NS=$(ns); PVC=fortify-test-pending-pvc; SC=fortify-test-missing-storageclass
cleanup(){ kubectl_cmd -n "$NS" delete pvc "$PVC" --ignore-not-found --wait=true >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
cleanup
cat <<YAML | kubectl_cmd -n "$NS" apply -f - >/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC
  labels: {fortify-test: storage-gate}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 1Mi}}
  storageClassName: $SC
YAML
sleep 3
phase=$(kubectl_cmd -n "$NS" get pvc "$PVC" -o jsonpath='{.status.phase}')
[[ "$phase" == Pending ]] || { echo "FAIL: expected Pending, got $phase"; exit 1; }
if wait_pvcs_bound 15; then echo 'FAIL: PVC gate accepted a Pending PVC'; exit 1; else echo 'PASS: PVC gate rejected Pending PVC'; fi
cleanup
kubectl_cmd -n "$NS" get pvc "$PVC" >/dev/null 2>&1 && { echo 'FAIL: cleanup did not delete PVC'; exit 1; } || echo 'PASS: PVC cleanup complete'
