#!/usr/bin/env bash
# Conservative, dependency-ordered K3s/OpenEBS recovery.
RECOVERY_LOG="$FORTIFY_HOME/logs/recovery.log"
RECOVERY_STATE="$FORTIFY_HOME/state/recovery-state.tsv"
RECOVERY_STALE_SECONDS=${RECOVERY_STALE_SECONDS:-600}

recovery_note(){ printf '%s\t%s\t%s\n' "$(date -Is)" "$1" "$2" >> "$RECOVERY_STATE"; log "RECOVERY $1: $2"; }
wait_systemd_active(){ local unit=$1 timeout=${2:-180}; local end=$((SECONDS+timeout)); until systemctl is-active --quiet "$unit"; do (( SECONDS >= end )) && die "$unit did not become active within ${timeout}s"; sleep 5; done; ok "$unit active"; }
wait_k3s_ready(){ local timeout=${1:-300}; local end=$((SECONDS+timeout)); until kubectl_cmd get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{ok=1} END{exit !ok}'; do (( SECONDS >= end )) && die 'K3s node did not become Ready'; sleep 5; done; ok 'K3s node Ready'; }
wait_openebs_ready(){
  local timeout=${1:-600} end=$((SECONDS+timeout))
  kubectl_cmd get namespace openebs >/dev/null 2>&1 || die 'OpenEBS namespace is missing'
  until kubectl_cmd -n openebs get pods --no-headers 2>/dev/null | awk 'BEGIN{bad=0;n=0} {n++; split($2,a,"/"); if($3!="Running" || a[1]!=a[2]) bad=1} END{exit !(n>0 && bad==0)}'; do
    (( SECONDS >= end )) && { kubectl_cmd -n openebs get pods -o wide || true; die 'OpenEBS pods did not become Ready'; }
    sleep 10
  done
  kubectl_cmd get storageclass "$(config_get STORAGE_CLASS)" >/dev/null || die "StorageClass missing: $(config_get STORAGE_CLASS)"
  ok 'OpenEBS and configured StorageClass Ready'
}
wait_pvcs_bound(){
  local timeout=${1:-600} end=$((SECONDS+timeout)) unbound
  until true; do
    unbound=$(kubectl_cmd -n "$(ns)" get pvc --no-headers 2>/dev/null | awk '$2!="Bound"{print $1":"$2}')
    [[ -z "$unbound" ]] && { ok 'All Fortify PVCs Bound'; return; }
    (( SECONDS >= end )) && die "PVCs not Bound: $unbound"
    sleep 10
  done
}
pod_age_seconds(){ local pod=$1 started now; started=$(kubectl_cmd -n "$(ns)" get pod "$pod" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null) || return 1; now=$(date +%s); echo $((now-$(date -d "$started" +%s))); }
conservative_recreate_stale_pods(){
  local pod status age reason deleted=0
  while read -r pod status; do
    [[ -n "$pod" ]] || continue
    age=$(pod_age_seconds "$pod" || echo 0)
    reason=''
    case "$status" in
      ContainerStatusUnknown|CreateContainerError|CreateContainerConfigError|ImageInspectError) reason=$status;;
      Terminating|ContainerCreating|PodInitializing) (( age >= RECOVERY_STALE_SECONDS )) && reason="$status for ${age}s";;
    esac
    [[ -n "$reason" ]] || continue
    warn "Stale pod candidate: $pod ($reason)"
    recovery_note STALE "$pod $reason"
    kubectl_cmd -n "$(ns)" delete pod "$pod" --grace-period=30 --wait=false
    deleted=$((deleted+1))
  done < <(kubectl_cmd -n "$(ns)" get pods --no-headers 2>/dev/null | awk '{print $1,$3}')
  (( deleted == 0 )) && ok 'No stale pods required recreation' || warn "Requested recreation of $deleted stale pod(s)"
}
wait_component_pods(){
  local pattern=$1 timeout=${2:-1200} expected=${3:-1}; local end=$((SECONDS+timeout)) count
  until true; do
    count=$(kubectl_cmd -n "$(ns)" get pods --no-headers 2>/dev/null | awk -v p="$pattern" '$1~p{split($2,a,"/"); if($3=="Running" && a[1]==a[2])n++} END{print n+0}')
    (( count >= expected )) && { ok "$pattern Ready ($count pod(s))"; return; }
    (( SECONDS >= end )) && { kubectl_cmd -n "$(ns)" get pods -o wide || true; die "$pattern did not become Ready"; }
    sleep 10
  done
}
recovery_storage_gate(){ wait_openebs_ready 600; wait_pvcs_bound 600; }
recover_all(){
  need_root; mkdir -p "$FORTIFY_HOME/logs" "$FORTIFY_HOME/state"; touch "$RECOVERY_LOG" "$RECOVERY_STATE"; chmod 600 "$RECOVERY_LOG" "$RECOVERY_STATE"
  exec 8>"$FORTIFY_HOME/state/recovery.lock"; flock -n 8 || die 'Another recovery is running'
  recovery_note START 'Conservative attended recovery'
  assert_disk_headroom 10
  systemctl start docker; wait_systemd_active docker 180
  systemctl start k3s; wait_systemd_active k3s 180; wait_k3s_ready 300
  recovery_storage_gate
  install_database; database_wait || die 'SQL Server unavailable after boot'
  conservative_recreate_stale_pods
  wait_component_pods '^lim-' 900 1
  wait_component_pods '^ssc-' 1200 1
  wait_component_pods 'scancentral-sast-controller' 1200 1
  wait_component_pods 'scancentral-sast-sensor' 1200 1
  wait_component_pods 'dast-core.*(api|globalservice|utilityservice)|scancentral-dast-core' 1800 3
  wait_component_pods 'dast-scanner|scancentral-dast-scanner' 2400 1
  assert_no_bad_pods
  health_all
  recovery_note PASS 'All storage and application gates passed'
}

boot_health_check(){
  # Read-only except for starting already-enabled systemd services. Never deletes pods or runs Helm.
  need_root; mkdir -p "$FORTIFY_HOME/logs" "$FORTIFY_HOME/state"; touch "$RECOVERY_LOG"; chmod 600 "$RECOVERY_LOG"
  local failures=0
  systemctl is-active --quiet docker || { warn 'Docker inactive'; failures=$((failures+1)); }
  systemctl is-active --quiet k3s || { warn 'K3s inactive'; failures=$((failures+1)); }
  if (( failures == 0 )); then
    wait_k3s_ready 180 || failures=$((failures+1))
    wait_openebs_ready 300 || failures=$((failures+1))
    wait_pvcs_bound 300 || failures=$((failures+1))
    database_wait || { warn 'SQL Server unavailable'; failures=$((failures+1)); }
    assert_no_bad_pods || failures=$((failures+1))
  fi
  kubectl_cmd -n "$(ns)" get pods -o wide >> "$RECOVERY_LOG" 2>&1 || true
  if (( failures == 0 )); then recovery_note BOOT_PASS 'Read-only boot health check passed'; return 0; fi
  recovery_note BOOT_WARN "$failures check(s) failed; run sudo fortify-lab recover"
  return 0
}
