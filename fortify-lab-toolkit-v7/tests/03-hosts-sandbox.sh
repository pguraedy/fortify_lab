#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/tests/testlib.sh"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
export FORTIFY_HOME="$WORK/fortify"
mkdir -p "$FORTIFY_HOME/config" "$FORTIFY_HOME/generated" "$FORTIFY_HOME/logs"
cat > "$FORTIFY_HOME/config/deployment.env" <<CFG
NAMESPACE=fortify
DOMAIN_SUFFIX=com
EXTERNAL_IP=192.0.2.10
CFG
source "$ROOT/lib/common.sh"
source "$ROOT/lib/config.sh"
source "$ROOT/lib/hosts.sh"
HOSTS_FILE="$WORK/hosts"
printf '127.0.0.1 localhost\n' > "$HOSTS_FILE"
out=$(hosts_render_block)
grep -q 'ssc.fortify.com' <<< "$out" && pass 'namespace SSC hostname generated' || fail 'namespace SSC hostname'
grep -q 'lim.fortify.com' <<< "$out" && pass 'namespace LIM hostname generated' || fail 'namespace LIM hostname'
grep -q 'sast.fortify.com' <<< "$out" && pass 'namespace SAST hostname generated' || fail 'namespace SAST hostname'
grep -q 'dast.fortify.com' <<< "$out" && pass 'namespace DAST hostname generated' || fail 'namespace DAST hostname'
# Correct existing unmanaged entry is detected without conflict.
printf '192.0.2.10 ssc.fortify.com\n' >> "$HOSTS_FILE"
if hosts_precheck >/dev/null 2>&1; then pass 'correct existing entry accepted'; else fail 'correct existing entry rejected'; fi
# Conflicting entry must be rejected.
printf '198.51.100.8 lim.fortify.com\n' >> "$HOSTS_FILE"
if (hosts_precheck >/dev/null 2>&1); then fail 'conflicting entry accepted'; else pass 'conflicting entry rejected'; fi
# Duplicate entry must be rejected.
grep -v '198.51.100.8' "$HOSTS_FILE" > "$WORK/clean"; mv "$WORK/clean" "$HOSTS_FILE"
printf '192.0.2.10 ssc.fortify.com\n' >> "$HOSTS_FILE"
if (hosts_precheck >/dev/null 2>&1); then fail 'duplicate entry accepted'; else pass 'duplicate entry rejected'; fi
summary
