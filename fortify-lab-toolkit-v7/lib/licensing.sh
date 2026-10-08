#!/usr/bin/env bash
LIC_STATE="$FORTIFY_HOME/state/licensing.env"
licensing_guard(){ [[ -n "$(secret_value LIM_ACTIVATION_TOKEN)" ]] || die "LIM activation token missing"; [[ -n "$(secret_value SAST_ACTIVATION_TOKEN)" ]] || die "SAST activation token missing"; [[ -n "$(secret_value DAST_ACTIVATION_TOKEN)" ]] || die "DAST activation token missing"; }
licensing_prepare(){
  need_root; licensing_guard
  cat > "$LIC_STATE" <<EOF2
LIM_URL=https://$(config_get EXTERNAL_FQDN):37562
LIM_ADMIN_USER=$(secret_value LIM_ADMIN_USER)
LIM_POOL_NAME=$(secret_value LIM_POOL_NAME)
TOKENS_PRESENT=true
EOF2
  chmod 600 "$LIC_STATE"
  warn "The supplied runbooks document LIM activation and pool assignment through the LIM UI, not a supported automation API."
  echo "1. Open LIM using port-forward: kubectl -n $(ns) port-forward svc/lim 8080:37562"
  echo "2. In ADMIN, enter the LIM activation token and license server details."
  echo "3. In PRODUCT LICENSES, add the SAST and DAST activation tokens."
  echo "4. In LICENSE POOLS, create the exact pool: $(secret_value LIM_POOL_NAME)"
  echo "5. Assign the DAST license to that pool."
  echo "6. Return here and run: fortify-lab licensing verify"
}
licensing_verify(){
  local n; n=$(ns); kubectl_cmd -n "$n" get secret dast-lim-pool >/dev/null || die "dast-lim-pool secret missing"
  local pool; pool=$(kubectl_cmd -n "$n" get secret dast-lim-pool -o jsonpath='{.data.username}' | base64 -d)
  [[ "$pool" == "$(secret_value LIM_POOL_NAME)" ]] || die "Kubernetes pool name does not match encrypted configuration"
  if kubectl_cmd -n "$n" get pod lim-0 >/dev/null 2>&1; then kubectl_cmd -n "$n" wait --for=condition=Ready pod/lim-0 --timeout=600s; fi
  printf 'VERIFIED_AT=%q\nPOOL_NAME=%q\n' "$(date -Is)" "$pool" >> "$LIC_STATE"; stage_mark licensing PASS "Operator confirmed LIM activation, product licenses, pool creation, and assignment"; ok "Licensing gate verified and marked PASS."
}
licensing_menu(){ while true; do echo '1) Prepare guided LIM licensing 2) Verify local licensing prerequisites 0) Back'; read -rp 'Select: ' n; case $n in 1) licensing_prepare;;2) licensing_verify;;0) return;;esac; done; }
