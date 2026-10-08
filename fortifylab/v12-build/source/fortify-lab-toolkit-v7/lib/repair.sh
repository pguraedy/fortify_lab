#!/usr/bin/env bash
repair_pods(){
  local n; n=$(ns)
  kubectl_cmd -n "$n" get pods --no-headers 2>/dev/null | awk '$3 ~ /ContainerStatusUnknown|ImageInspectError/ {print $1}' | while read -r p; do warn "Recreating stale pod $p"; kubectl_cmd -n "$n" delete pod "$p" --grace-period=0 --force; done
}
repair_component(){
  local c=${1:-all}; ensure_base; backup_create
  if [[ "$c" == all ]]; then repair_pods; state_set final-validation NOT_STARTED "Repair initiated"; workflow_resume; else case "$c" in infrastructure) prerequisites_install;; database) install_database;; *) helm_apply "$c";; esac; fi
  health_all
}
recover_all(){
  need_root; systemctl restart docker || true; systemctl restart k3s || true; sleep 5
  repair_pods
  for target in lim-0 ssc-webapp-0 scancentral-sast-controller-0; do kubectl_cmd -n "$(ns)" get pod "$target" >/dev/null 2>&1 || continue; done
  repair_component all
}
backup_create(){
  need_root; local d="$FORTIFY_HOME/backups/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$d"/{helm,kubernetes,database}; cp -a "$CONFIG" "$LOCK" "$SECRETS_ENC" "$d/" 2>/dev/null || true
  for r in lim ssc scancentral-sast scancentral-dast-core scancentral-dast-scanner; do helm get values "$r" -n "$(ns)" -a > "$d/helm/$r-values.yaml" 2>/dev/null || true; helm history "$r" -n "$(ns)" > "$d/helm/$r-history.txt" 2>/dev/null || true; done
  kubectl_cmd get all,pvc -n "$(ns)" -o yaml > "$d/kubernetes/resources.yaml" 2>/dev/null || true
  if docker inspect mssql >/dev/null 2>&1; then docker exec mssql mkdir -p /var/opt/mssql/backup >/dev/null 2>&1 || true; fi
  (cd "$d" && find . -type f -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
  ok "Backup created: $d"
}
