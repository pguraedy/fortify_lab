#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/tests/testlib.sh"
for f in "$ROOT/bin/fortify-lab" "$ROOT/install.sh" "$ROOT"/lib/*.sh; do
  if bash -n "$f"; then pass "bash syntax: ${f#$ROOT/}"; else fail "bash syntax: ${f#$ROOT/}"; fi
done
assert_exec "$ROOT/bin/fortify-lab"
assert_exec "$ROOT/install.sh"
assert_contains "$ROOT/lib/stages.sh" 'hostname-resolution'
assert_contains "$ROOT/lib/stages.sh" 'license-file'
assert_contains "$ROOT/lib/stages.sh" 'MANUAL_PENDING'
assert_contains "$ROOT/lib/hosts.sh" 'hosts_precheck'
assert_contains "$ROOT/lib/hosts.sh" 'Duplicate definitions'
assert_contains "$ROOT/lib/license.sh" 'license-secret.sha256'
assert_contains "$ROOT/lib/certificates.sh" 'LIM_HOSTNAME'
assert_contains "$ROOT/lib/certificates.sh" 'SAST_HOSTNAME'
assert_contains "$ROOT/lib/certificates.sh" 'DAST_HOSTNAME'
assert_contains "$ROOT/config/deployment.env.example" '^NAMESPACE=fortify$'
assert_contains "$ROOT/config/deployment.env.example" '^DOMAIN_SUFFIX=com$'
assert_contains "$ROOT/config/deployment.env.example" '^EXTERNAL_FQDN=ssc\.fortify\.com$'
summary
