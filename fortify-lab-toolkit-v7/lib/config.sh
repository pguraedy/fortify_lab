#!/usr/bin/env bash
CONFIG="$FORTIFY_HOME/config/deployment.env"
config_get(){ local k=$1; [[ -f "$CONFIG" ]] && awk -F= -v k="$k" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$CONFIG"; }
config_set(){ local k=$1 v=$2; mkdir -p "$(dirname "$CONFIG")"; touch "$CONFIG"; if grep -q "^${k}=" "$CONFIG"; then sed -i "s|^${k}=.*|${k}=${v//|/\\|}|" "$CONFIG"; else printf '%s=%s\n' "$k" "$v" >> "$CONFIG"; fi; chmod 600 "$CONFIG"; }
prompt_default(){ local label=$1 key=$2 def=${3:-}; local cur; cur=$(config_get "$key"); [[ -n "$cur" ]] && def=$cur; read -rp "$label [$def]: " value; config_set "$key" "${value:-$def}"; }
configure_interactive(){
  need_root
  mkdir -p "$FORTIFY_HOME"/{config,generated,logs,state,charts,backups}
  prompt_default "Deployment name" DEPLOYMENT_NAME "$(hostname -s | tr '[:upper:]' '[:lower:]')"
  prompt_default "VM hostname" VM_HOSTNAME "$(hostname -s | tr '[:upper:]' '[:lower:]')"
  prompt_default "Kubernetes namespace" NAMESPACE fortify
  prompt_default "Local domain suffix (without leading dot)" DOMAIN_SUFFIX com
  local namespace suffix base
  namespace=$(config_get NAMESPACE); suffix=$(config_get DOMAIN_SUFFIX); suffix=${suffix#.}; config_set DOMAIN_SUFFIX "$suffix"; base="$namespace.$suffix"
  config_set EXTERNAL_FQDN "ssc.$base"
  config_set LIM_HOSTNAME "lim.$base"
  config_set SAST_HOSTNAME "sast.$base"
  config_set DAST_HOSTNAME "dast.$base"
  prompt_default "VM IP address" EXTERNAL_IP "$(hostname -I | awk '{print $1}')"
  prompt_default "SSC NodePort" SSC_NODEPORT 30291
  prompt_default "DAST API NodePort" DAST_NODEPORT 32085
  prompt_default "Storage class" STORAGE_CLASS openebs-hostpath
  prompt_default "SQL Server image" MSSQL_IMAGE mcr.microsoft.com/mssql/server:2022-latest
  prompt_default "Database host/IP" DATABASE_HOST "$(config_get EXTERNAL_IP)"
  prompt_default "Fortify license file path" FORTIFY_LICENSE_PATH /opt/fortify-deploy/config/license/fortify.license
  prompt_default "Certificate mode (self-signed/import)" CERTIFICATE_MODE self-signed
  prompt_default "Fortify release policy (validated/latest-compatible/locked)" VERSION_POLICY validated
  ok "Namespace-based hostnames: ssc.$base, lim.$base, sast.$base, dast.$base"
  ok "Configuration saved in $CONFIG"
}
