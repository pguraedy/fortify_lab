#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/tests/testlib.sh"
[[ ${RUN_PLATFORM_TESTS:-0} == 1 ]] || { skip 'platform tests disabled; set RUN_PLATFORM_TESTS=1'; summary; exit; }
[[ $EUID -eq 0 ]] || { fail 'run platform tests with sudo'; summary; exit 1; }
export FORTIFY_HOME=${FORTIFY_HOME:-/opt/fortify-deploy}
source "$FORTIFY_HOME/lib/common.sh"
source "$FORTIFY_HOME/lib/config.sh"
source "$FORTIFY_HOME/lib/hosts.sh"
source "$FORTIFY_HOME/lib/health.sh"
source "$FORTIFY_HOME/lib/stages.sh"
for s in preflight prerequisites configuration hostname-resolution secrets versions infrastructure license-file certificates database lim licensing ssc sast dast-core dast-scanner final-validation; do
  [[ "$(state_get "$s")" == PASS ]] && pass "stage $s" || fail "stage $s is $(state_get "$s")"
done
if assert_no_bad_pods; then pass 'no known unhealthy pods'; else fail 'unhealthy pods found'; fi
if hosts_verify; then pass 'all local hostnames resolve'; else fail 'hostname verification'; fi
summary
