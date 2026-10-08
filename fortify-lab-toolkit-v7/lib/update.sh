#!/usr/bin/env bash
update_check(){ require_pass final-validation; assert_disk_headroom 25; versions_discover; echo 'Installed/locked:'; versions_show; }
update_plan(){
  local c=${1:-all}; require_pass final-validation; echo "Upgrade plan for: $c"; echo '1. Enforce healthy baseline'; echo '2. Require 25 GiB free disk'; echo '3. Create database and configuration backup'; echo '4. Pull and render candidate charts'; echo '5. Upgrade in dependency order'; echo '6. Validate readiness after every component'; echo '7. Stop on first failure and retain rollback checkpoint';
}
validate_upgraded_component(){ local c=$1; case "$c" in lim) wait_named_pod_ready lim-0 900; assert_helm_release lim;; ssc) wait_named_pod_ready ssc-webapp-0 1200; assert_helm_release ssc; ssc_validate;; sast) wait_named_pod_ready scancentral-sast-controller-0 1200; wait_named_pod_ready scancentral-sast-sensor-linux-0 1200; assert_helm_release scancentral-sast;; dast-core) assert_helm_release scancentral-dast-core; wait_pod_ready 'app.kubernetes.io/name=scancentral-dast-core' 3 1800;; dast-scanner) assert_helm_release scancentral-dast-scanner; stage_dast_scanner;; esac; }
update_apply(){
  local c=${1:-all}; ensure_base; require_pass final-validation; assert_no_bad_pods; assert_disk_headroom 25; health_all; confirm "Create backups and upgrade $c using locked versions?" || return 0
  backup_create; database_backup
  local list=(); if [[ "$c" == all ]]; then list=(lim ssc sast dast-core dast-scanner); else list=("$c"); fi
  local x; for x in "${list[@]}"; do log "Upgrade gate: $x"; helm_apply "$x" || die "Upgrade failed at $x. Use Helm history/rollback."; validate_upgraded_component "$x" || die "Post-upgrade validation failed at $x"; done
  assert_no_bad_pods; state_set final-validation NOT_STARTED 'Upgrade completed; full validation required'; workflow_run final-validation
}
rollback_component(){
  local c=${1:-}; local rev=${2:-}; [[ -n "$c" ]] || c=$(choose_component); local rel; rel=$(helm_release "$c"); helm history "$rel" -n "$(ns)"; [[ -n "$rev" ]] || read -rp 'Revision: ' rev; confirm "Rollback $rel to revision $rev?" || return 0; helm rollback "$rel" "$rev" -n "$(ns)" --wait --timeout 60m; validate_upgraded_component "$c"; state_set final-validation NOT_STARTED 'Rollback completed; full validation required'; workflow_run final-validation
}
