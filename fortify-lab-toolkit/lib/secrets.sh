#!/usr/bin/env bash
AGE_KEY=/etc/fortify-deploy/age.key
SECRETS_ENC="$FORTIFY_HOME/config/secrets.env.age"
secret_fields=(DOCKERHUB_USER DOCKERHUB_TOKEN MSSQL_SA_PASSWORD SSC_DB_USER SSC_DB_PASSWORD LIM_ADMIN_USER LIM_ADMIN_PASSWORD LIM_POOL_NAME LIM_POOL_PASSWORD SSC_KEYSTORE_PASSWORD SAST_SSC_USER SAST_SSC_PASSWORD DAST_SSC_USER DAST_SSC_PASSWORD DAST_SERVICE_TOKEN DAST_PFX_PASSWORD DAST_DB_USER DAST_DB_PASSWORD LIM_ACTIVATION_TOKEN SAST_ACTIVATION_TOKEN DAST_ACTIVATION_TOKEN)
ensure_age(){ command_exists age && command_exists age-keygen || die "age is required. Run prerequisites install."; }
secrets_decrypt(){ ensure_age; [[ -s "$SECRETS_ENC" ]] || die "Secrets not initialized"; age -d -i "$AGE_KEY" "$SECRETS_ENC"; }
secrets_encrypt_file(){ local f=$1 pub; pub=$(age-keygen -y "$AGE_KEY"); age -r "$pub" -o "$SECRETS_ENC.tmp" "$f"; mv "$SECRETS_ENC.tmp" "$SECRETS_ENC"; chmod 600 "$SECRETS_ENC"; }
secrets_init(){
  need_root; ensure_age; install -d -m 700 /etc/fortify-deploy "$FORTIFY_HOME/config"
  [[ -s "$AGE_KEY" ]] || age-keygen -o "$AGE_KEY" >/dev/null
  chmod 600 "$AGE_KEY"
  local tmp; tmp=$(mktemp /dev/shm/fortify-secrets.XXXXXX); trap 'rm -f "$tmp"' RETURN
  for k in "${secret_fields[@]}"; do
    case "$k" in LIM_ADMIN_USER) d=lim_admin;; LIM_POOL_NAME) d=Default;; SSC_DB_USER) d=fortify;; SAST_SSC_USER|DAST_SSC_USER) d=admin;; DAST_DB_USER) d=dastuser;; *) d=;; esac
    if [[ "$k" == *_USER || "$k" == *_NAME ]]; then read -rp "$k [$d]: " v; v=${v:-$d}; else read -rsp "$k: " v; echo; [[ -n "$v" ]] || { v=$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9@#%+=' | head -c 28); echo "Generated $k"; }; fi
    printf '%s=%q\n' "$k" "$v" >> "$tmp"
  done
  secrets_encrypt_file "$tmp"; ok "Encrypted secrets saved locally."
}
secrets_list(){ local data; data=$(secrets_decrypt); while IFS='=' read -r k v; do [[ -n "$k" ]] && printf '%-28s %s\n' "$k" '********'; done <<< "$data"; }
secrets_edit(){
  need_root; local tmp; tmp=$(mktemp /dev/shm/fortify-secrets.XXXXXX); trap 'rm -f "$tmp"' RETURN
  secrets_decrypt > "$tmp"; chmod 600 "$tmp"; "${EDITOR:-nano}" "$tmp"; secrets_encrypt_file "$tmp"; ok "Secrets updated. Run secrets sync to update Kubernetes."
}
secret_value(){ local k=$1; secrets_decrypt | bash -c 'set -a; source /dev/stdin; printf "%s" "${!1-}"' bash "$k"; }
apply_secret_basic(){ local name=$1 user_key=$2 pass_key=$3 ns; ns=$(config_get NAMESPACE); kubectl_cmd -n "$ns" create secret generic "$name" --type=kubernetes.io/basic-auth --from-literal=username="$(secret_value "$user_key")" --from-literal=password="$(secret_value "$pass_key")" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null; }
secrets_sync(){
  need_root; local ns; ns=$(config_get NAMESPACE); [[ -n "$ns" ]] || ns=fortify
  kubectl_cmd create namespace "$ns" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  kubectl_cmd -n "$ns" create secret docker-registry fortify-dockerhub --docker-server=https://index.docker.io/v1/ --docker-username="$(secret_value DOCKERHUB_USER)" --docker-password="$(secret_value DOCKERHUB_TOKEN)" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  apply_secret_basic lim-admin-credentials LIM_ADMIN_USER LIM_ADMIN_PASSWORD
  apply_secret_basic dast-lim-pool LIM_POOL_NAME LIM_POOL_PASSWORD
  apply_secret_basic sc-sast-ssc-svc-account-secret SAST_SSC_USER SAST_SSC_PASSWORD
  apply_secret_basic dast-ssc-account DAST_SSC_USER DAST_SSC_PASSWORD
  apply_secret_basic dast-dbo-secret DAST_DB_USER DAST_DB_PASSWORD
  apply_secret_basic dast-standard-secret DAST_DB_USER DAST_DB_PASSWORD
  kubectl_cmd -n "$ns" create secret generic dast-service-token --from-literal=servicetoken="$(secret_value DAST_SERVICE_TOKEN)" --from-literal=token="$(secret_value DAST_SERVICE_TOKEN)" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  ok "Kubernetes secrets synchronized."
}
secrets_menu(){ while true; do echo '1) Initialize 2) List 3) Edit 4) Sync to Kubernetes 0) Back'; read -rp 'Select: ' n; case $n in 1) secrets_init;;2) secrets_list;;3) secrets_edit;;4) secrets_sync;;0) return;;esac; done; }
