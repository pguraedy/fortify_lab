#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/tests/testlib.sh"
[[ ${RUN_DESTRUCTIVE_TESTS:-0} == 1 ]] || { skip 'destructive Ubuntu integration tests disabled; set RUN_DESTRUCTIVE_TESTS=1'; summary; exit; }
[[ $EUID -eq 0 ]] || { fail 'run destructive integration test with sudo'; summary; exit 1; }
source /etc/os-release
assert_eq "$ID" ubuntu 'Ubuntu operating system'
source "$ROOT/lib/common.sh"
source "$ROOT/lib/config.sh"
source "$ROOT/lib/hosts.sh"
if command -v docker >/dev/null; then pass 'Docker installed'; else fail 'Docker missing'; fi
if command -v k3s >/dev/null; then pass 'K3s installed'; else fail 'K3s missing'; fi
if command -v helm >/dev/null; then pass 'Helm installed'; else fail 'Helm missing'; fi
if hosts_precheck; then pass '/etc/hosts precheck'; else fail '/etc/hosts precheck'; fi
if hosts_verify; then pass 'hostname resolution'; else fail 'hostname resolution'; fi
if k3s kubectl get nodes --no-headers | awk '$2=="Ready"{ok=1} END{exit !ok}'; then pass 'K3s node Ready'; else fail 'K3s node not Ready'; fi
summary
