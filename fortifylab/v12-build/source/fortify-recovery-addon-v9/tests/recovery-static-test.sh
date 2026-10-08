#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=${1:-.}
grep -q 'wait_openebs_ready' "$ROOT/lib/recovery-hardened.sh"
grep -q 'wait_pvcs_bound' "$ROOT/lib/recovery-hardened.sh"
grep -q 'ContainerStatusUnknown' "$ROOT/lib/recovery-hardened.sh"
grep -q 'startupProbe' "$ROOT/lib/probes.sh"
grep -q 'boot_health_check' "$ROOT/lib/recovery-hardened.sh"
echo 'Recovery hardening static checks passed.'
