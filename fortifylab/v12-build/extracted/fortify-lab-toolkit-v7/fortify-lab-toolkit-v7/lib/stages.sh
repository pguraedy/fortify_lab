#!/usr/bin/env bash
# Strict, durable, resumable deployment workflow.
STATE_FILE="$FORTIFY_HOME/state/deployment-state.tsv"
STATE_LOCK="$FORTIFY_HOME/state/deployment-state.lock"
RUN_LOG="$FORTIFY_HOME/logs/staged-deployment.log"
MANUAL_EXIT=20
STAGES=(
  preflight prerequisites configuration hostname-resolution secrets versions infrastructure
  license-file certificates database lim licensing ssc sast dast-core dast-scanner final-validation
)

epoch(){ date +%s; }
state_init(){
  mkdir -p "$FORTIFY_HOME/state" "$FORTIFY_HOME/logs"
  touch "$STATE_FILE" "$STATE_LOCK" "$RUN_LOG"
  chmod 600 "$STATE_FILE" "$STATE_LOCK" "$RUN_LOG"
}
state_get(){ local stage=$1 field=${2:-status}; local col=2; [[ "$field" == updated ]] && col=3; [[ "$field" == detail ]] && col=4; awk -F '\t' -v s="$stage" -v c="$col" '$1==s{v=$c} END{print v}' "$STATE_FILE"; }
state_set(){
  local stage=$1 status=$2 detail=${3:-}; state_init
  detail=${detail//$'\t'/ }; detail=${detail//$'\n'/ }
  local tmp; tmp=$(mktemp "$FORTIFY_HOME/state/.state.XXXXXX")
  awk -F '\t' -v s="$stage" '$1!=s' "$STATE_FILE" > "$tmp"
  printf '%s\t%s\t%s\t%s\n' "$stage" "$status" "$(date -Is)" "$detail" >> "$tmp"
  sort -t $'\t' -k1,1 "$tmp" > "$STATE_FILE"
  rm -f "$tmp"; chmod 600 "$STATE_FILE"
}
stage_mark(){ state_set "$1" "$2" "${3:-}"; }
workflow_status(){
  state_init
  printf '%-20s %-16s %-25s %s\n' STAGE STATUS UPDATED DETAIL
  printf '%-20s %-16s %-25s %s\n' '--------------------' '----------------' '-------------------------' '------'
  local s st up de
  for s in "${STAGES[@]}"; do st=$(state_get "$s"); up=$(state_get "$s" updated); de=$(state_get "$s" detail); printf '%-20s %-16s %-25s %s\n' "$s" "${st:-NOT_STARTED}" "${up:--}" "$de"; done
}
workflow_reset(){
  need_root; local from=${1:-all}; state_init
  if [[ "$from" == all ]]; then confirm 'Reset all durable deployment state? This does not uninstall workloads.' || return 0; : > "$STATE_FILE"; ok 'All workflow state reset'; return; fi
  local found=0 s
  for s in "${STAGES[@]}"; do [[ "$s" == "$from" ]] && found=1; (( found )) && state_set "$s" NOT_STARTED 'Reset by operator'; done
  (( found )) || die "Unknown stage: $from"
  ok "State reset from stage: $from"
}
workflow_next_stage(){ local s; for s in "${STAGES[@]}"; do [[ "$(state_get "$s")" == PASS ]] || { echo "$s"; return; }; done; }
require_pass(){ local s=$1; [[ "$(state_get "$s")" == PASS ]] || die "Required stage '$s' has not passed. Run: fortify-lab workflow resume"; }
require_files(){ local f; for f in "$@"; do [[ -s "$f" ]] || die "Required file missing or empty: $f"; done; }
require_cmds(){ local c; for c in "$@"; do command_exists "$c" || die "Required command missing: $c"; done; }
wait_pod_ready(){ local selector=$1 expected=${2:-1} timeout=${3:-900}; kubectl_cmd -n "$(ns)" wait --for=condition=Ready pod -l "$selector" --timeout="${timeout}s"; local ready; ready=$(kubectl_cmd -n "$(ns)" get pods -l "$selector" --no-headers 2>/dev/null | awk '$2==$3 && $4=="Running"{n++} END{print n+0}'); (( ready >= expected )) || die "Ready pod count for '$selector' is $ready; expected at least $expected"; }
wait_named_pod_ready(){ local pod=$1 timeout=${2:-900}; kubectl_cmd -n "$(ns)" wait --for=condition=Ready "pod/$pod" --timeout="${timeout}s"; }
assert_no_bad_pods(){ local bad; bad=$(kubectl_cmd -n "$(ns)" get pods --no-headers 2>/dev/null | awk '$3 ~ /CrashLoopBackOff|Error|ImagePullBackOff|ErrImagePull|ContainerStatusUnknown|CreateContainerConfigError/ {print $1":"$3}'); [[ -z "$bad" ]] || die "Unhealthy pods detected: $bad"; }
assert_disk_headroom(){ local min=${1:-20} free; free=$(df -BG / | awk 'NR==2{gsub("G","");print $4}'); (( free >= min )) || die "Only ${free} GiB free on /. Hard requirement is ${min} GiB."; }
assert_helm_release(){ local rel=$1; helm status "$rel" -n "$(ns)" >/dev/null; local status; status=$(helm status "$rel" -n "$(ns)" -o json | jq -r '.info.status'); [[ "$status" == deployed ]] || die "Helm release $rel status is $status, expected deployed"; }

strict_preflight(){
  source /etc/os-release || true
  [[ "${ID:-}" == ubuntu ]] || die "Ubuntu is required; found ${ID:-unknown}"
  [[ "$(uname -m)" == x86_64 ]] || die "amd64/x86_64 is required"
  local cpu mem disk free
  cpu=$(nproc); mem=$(awk '/MemTotal/{printf "%.0f",$2/1024/1024}' /proc/meminfo); disk=$(df -BG / | awk 'NR==2{gsub("G","");print $2}'); free=$(df -BG / | awk 'NR==2{gsub("G","");print $4}')
  (( cpu >= 8 )) || die "At least 8 CPU cores are required; found $cpu"
  (( mem >= 30 )) || die "At least 30 GiB RAM is required; found ${mem} GiB"
  (( disk >= 100 )) || die "At least 100 GiB root disk is required; found ${disk} GiB"
  (( free >= 30 )) || die "At least 30 GiB free disk is required for initial deployment; found ${free} GiB"
  [[ "$(hostname)" =~ ^[a-z0-9.-]+$ ]] || die "Hostname must be lowercase and DNS-safe: $(hostname)"
  getent hosts registry-1.docker.io >/dev/null || die "Cannot resolve Docker Hub registry"
  curl -fsSI --max-time 15 https://registry-1.docker.io/v2/ >/dev/null || [[ $? -eq 22 ]] || die "Cannot reach Docker Hub registry"
  ok 'Strict host preflight passed'
}

stage_preflight(){ strict_preflight; }
stage_prerequisites(){ prerequisites_install; require_cmds curl jq openssl docker k3s kubectl helm age age-keygen java keytool; systemctl is-active --quiet docker || die 'Docker is not active'; systemctl is-active --quiet k3s || die 'K3s is not active'; kubectl_cmd get nodes | grep -q ' Ready ' || die 'Kubernetes node is not Ready'; kubectl_cmd get storageclass | grep -q openebs-hostpath || die 'openebs-hostpath StorageClass is unavailable'; }
stage_configuration(){
  [[ -s "$CONFIG" ]] || configure_interactive
  local k n suffix base
  for k in NAMESPACE DOMAIN_SUFFIX EXTERNAL_FQDN LIM_HOSTNAME SAST_HOSTNAME DAST_HOSTNAME EXTERNAL_IP SSC_NODEPORT DAST_NODEPORT STORAGE_CLASS MSSQL_IMAGE DATABASE_HOST CERTIFICATE_MODE; do [[ -n "$(config_get "$k")" ]] || die "Configuration key missing: $k"; done
  n=$(config_get NAMESPACE); suffix=$(config_get DOMAIN_SUFFIX); suffix=${suffix#.}; base="$n.$suffix"
  [[ "$n" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "Invalid Kubernetes namespace: $n"
  [[ "$suffix" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || die "Invalid domain suffix: $suffix"
  [[ "$(config_get EXTERNAL_FQDN)" == "ssc.$base" ]] || die "SSC hostname must be ssc.$base"
  [[ "$(config_get LIM_HOSTNAME)" == "lim.$base" ]] || die "LIM hostname must be lim.$base"
  [[ "$(config_get SAST_HOSTNAME)" == "sast.$base" ]] || die "SAST hostname must be sast.$base"
  [[ "$(config_get DAST_HOSTNAME)" == "dast.$base" ]] || die "DAST hostname must be dast.$base"
}
stage_hostname_resolution(){
  local desired current
  desired=$(config_get VM_HOSTNAME); current=$(vm_short_hostname)
  [[ -n "$desired" ]] || desired="$current"
  desired=$(printf '%s' "$desired" | tr '[:upper:]' '[:lower:]')
  [[ "$desired" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || die "Configured VM hostname is not DNS-safe: $desired"
  if [[ "$current" != "$desired" ]]; then
    warn "Current hostname '$current' differs from configured VM hostname '$desired'."
    confirm "Change the Ubuntu hostname to '$desired' now?" || die 'Hostname must match configuration before deployment'
    hostnamectl set-hostname "$desired"
    config_set VM_HOSTNAME "$desired"
  fi
  hosts_precheck
  hosts_apply
  hosts_verify
}
stage_secrets(){ [[ -s "$SECRETS_ENC" ]] || secrets_init; [[ -s "$AGE_KEY" ]] || die 'age identity is missing'; chmod 600 "$AGE_KEY" "$SECRETS_ENC"; local k; for k in DOCKERHUB_USER DOCKERHUB_TOKEN MSSQL_SA_PASSWORD SSC_DB_USER SSC_DB_PASSWORD DAST_DB_USER DAST_DB_PASSWORD LIM_ADMIN_PASSWORD LIM_POOL_NAME LIM_POOL_PASSWORD SSC_KEYSTORE_PASSWORD DAST_PFX_PASSWORD DAST_SERVICE_TOKEN; do [[ -n "$(secret_value "$k")" ]] || die "Secret is empty: $k"; done; }
stage_versions(){ [[ -s "$LOCK" ]] || { versions_discover; versions_lock_interactive; }; local c; for c in lim ssc sast dast-core dast-scanner; do [[ -n "$(locked_version "$c")" ]] || die "No locked version for $c"; done; versions_show; }
stage_infrastructure(){
  systemctl is-active --quiet docker || die 'Docker inactive'; systemctl is-active --quiet k3s || die 'K3s inactive'; kubectl_cmd get nodes --no-headers | awk '$2=="Ready"{ok=1} END{exit !ok}' || die 'No Ready Kubernetes node'
  kubectl_cmd get storageclass "$(config_get STORAGE_CLASS)" >/dev/null || die "StorageClass unavailable: $(config_get STORAGE_CLASS)"
  kubectl_cmd create namespace "$(ns)" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  secrets_sync; assert_disk_headroom 25
}
stage_license_file(){
  local f; f=$(config_get FORTIFY_LICENSE_PATH)
  if [[ -z "$f" || ! -r "$f" ]]; then
    license_import
  else
    license_validate "$f"
  fi
  license_sync
}
stage_certificates(){
  if [[ ! -s "$CERT_DIR/platform.crt" ]]; then case "$(config_get CERTIFICATE_MODE)" in self-signed) certificates_generate_self_signed;; import) certificates_import;; *) die 'CERTIFICATE_MODE must be self-signed or import';; esac; fi
  certificates_validate; certificates_sync
  local n; n=$(ns); for s in lim-server-certificate lim-signing-certificate lim-signing-certificate-password ssc-keystore ssc-keystore-password ssc-key-password dast-api-certificate dast-utility-certificate; do kubectl_cmd -n "$n" get secret "$s" >/dev/null || die "Certificate secret missing: $s"; done
}
stage_database(){ install_database; database_initialize; database_validate; database_backup; }
stage_lim(){
  helm_apply lim; assert_helm_release lim; wait_named_pod_ready lim-0 900
  local logs; logs=$(kubectl_cmd -n "$(ns)" logs lim-0 --tail=100 2>/dev/null || true); grep -q 'LIM DBProvider' <<< "$logs" || warn 'LIM startup marker not present in last 100 log lines';
}
stage_licensing(){
  if grep -q '^VERIFIED_AT=' "$LIC_STATE" 2>/dev/null; then licensing_verify; return; fi
  licensing_prepare
  stage_mark licensing MANUAL_PENDING 'Complete LIM activation, add SAST/DAST licenses, create pool, assign DAST license, then run licensing verify'
  warn 'Deployment paused at mandatory manual licensing gate.'
  return "$MANUAL_EXIT"
}
stage_ssc(){ require_pass license-file; ssc_sync_secrets; helm_apply ssc; assert_helm_release ssc; wait_named_pod_ready ssc-webapp-0 1200; ssc_validate;
  local ssc_bad; ssc_bad=$(kubectl_cmd -n "$(ns)" logs ssc-webapp-0 --tail=500 2>/dev/null | grep -iE 'license.*(invalid|expired|missing|not found|error)|invalid.*license' || true); [[ -z "$ssc_bad" ]] || die "SSC reported a license error: $ssc_bad"; local code; code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 20 "https://$(config_get EXTERNAL_FQDN):$(config_get SSC_NODEPORT)/" || true); [[ "$code" =~ ^(200|301|302|401|403)$ ]] || die "SSC endpoint returned HTTP $code"; }
stage_sast(){ require_pass license-file; helm_apply sast; assert_helm_release scancentral-sast; wait_named_pod_ready scancentral-sast-controller-0 1200; wait_named_pod_ready scancentral-sast-sensor-linux-0 1200;
  local sast_bad; sast_bad=$(kubectl_cmd -n "$(ns)" logs scancentral-sast-controller-0 --tail=500 2>/dev/null | grep -iE 'license.*(invalid|expired|missing|not found|error)|invalid.*license' || true); [[ -z "$sast_bad" ]] || die "ScanCentral SAST reported a license error: $sast_bad";
}
stage_dast_core(){ require_pass licensing; helm_apply dast-core; assert_helm_release scancentral-dast-core; wait_pod_ready 'app.kubernetes.io/name=scancentral-dast-core' 3 1800; local utility; utility=$(kubectl_cmd -n "$(ns)" get pods --no-headers | awk '/utilityservice/{print $2" "$3" "$1}'); grep -q '^3/3 Running ' <<< "$utility" || die "DAST Utility Service not 3/3 Running: $utility"; }
stage_dast_scanner(){ helm_apply dast-scanner; assert_helm_release scancentral-dast-scanner; local pod; pod=$(kubectl_cmd -n "$(ns)" get pods --no-headers | awk '/dast-scanner/{print $1;exit}'); [[ -n "$pod" ]] || die 'DAST scanner pod not found'; wait_named_pod_ready "$pod" 2400; local state; state=$(kubectl_cmd -n "$(ns)" get pod "$pod" --no-headers); grep -q '4/4.*Running' <<< "$state" || die "DAST scanner not 4/4 Running: $state"; }
stage_final_validation(){ assert_no_bad_pods; health_all; for s in preflight prerequisites configuration hostname-resolution secrets versions infrastructure license-file certificates database lim licensing ssc sast dast-core dast-scanner; do require_pass "$s"; done; ok 'All strict deployment gates passed'; }

run_stage(){
  local stage=$1 fn="stage_${stage//-/_}" current; current=$(state_get "$stage")
  [[ "$current" == PASS ]] && { ok "Skipping completed stage: $stage"; return 0; }
  declare -F "$fn" >/dev/null || die "No implementation for stage: $stage"
  stage_set_context="$stage"; state_set "$stage" RUNNING "PID $$"
  log "===== STAGE START: $stage =====" | tee -a "$RUN_LOG"
  set +e; "$fn" 2>&1 | tee -a "$RUN_LOG"; local rc=${PIPESTATUS[0]}; set -e
  if (( rc == 0 )); then state_set "$stage" PASS 'Verification passed'; ok "Stage passed: $stage"; return 0; fi
  if (( rc == MANUAL_EXIT )); then return "$MANUAL_EXIT"; fi
  state_set "$stage" FAIL "Exit code $rc; inspect $RUN_LOG"; die "Stage failed: $stage. Resume after correction with: fortify-lab workflow resume"
}
workflow_run(){
  need_root; state_init
  exec 9>"$STATE_LOCK"; flock -n 9 || die 'Another Fortify workflow is already running'
  trap 'rc=$?; if [[ -n "${stage_set_context:-}" && $rc -ne 0 && "$(state_get "$stage_set_context")" == RUNNING ]]; then state_set "$stage_set_context" INTERRUPTED "Signal/exit $rc; resume is safe"; fi' EXIT INT TERM
  local from=${1:-}; local begin=0 s
  [[ -z "$from" ]] && from=$(workflow_next_stage)
  [[ -z "$from" ]] && { ok 'All deployment stages already passed'; workflow_status; return 0; }
  for s in "${STAGES[@]}"; do [[ "$s" == "$from" ]] && begin=1; (( begin )) || continue; run_stage "$s" || { local rc=$?; (( rc == MANUAL_EXIT )) && return 0; return "$rc"; }; done
  workflow_status
}
workflow_resume(){ local next; next=$(workflow_next_stage); [[ -n "$next" ]] || { ok 'Workflow already complete'; return; }; workflow_run "$next"; }
workflow_verify_stage(){ local s=$1 fn="stage_${s//-/_}"; declare -F "$fn" >/dev/null || die "Unknown stage: $s"; "$fn"; state_set "$s" PASS 'Explicit verification passed'; }
