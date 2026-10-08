#!/usr/bin/env bash
SSC_DIR="$FORTIFY_HOME/generated/ssc"
ssc_guard(){ [[ -r "$(config_get FORTIFY_LICENSE_PATH)" ]] || die "Configure a readable FORTIFY_LICENSE_PATH"; [[ -r "$CERT_DIR/ssc-keystore.p12" ]] || die "Prepare certificates first"; database_validate; }
ssc_generate_autoconfig(){
  need_root; mkdir -p "$SSC_DIR"; chmod 700 "$SSC_DIR"; local host user pwd fqdn; host=$(config_get DATABASE_HOST); [[ -n "$host" ]] || host=$(config_get EXTERNAL_IP); user=$(secret_value SSC_DB_USER); pwd=$(secret_value SSC_DB_PASSWORD); fqdn=$(config_get EXTERNAL_FQDN)
  cat > "$SSC_DIR/ssc.autoconfig" <<YAML
appProperties:
  host.url: 'https://$fqdn:$(config_get SSC_NODEPORT)'
  host.validation: false
datasourceProperties:
  jdbc.url: 'jdbc:sqlserver://$host:1433;databaseName=SSC;sendStringParametersAsUnicode=false;encrypt=true;trustServerCertificate=true'
  jdbc.username: '$user'
  jdbc.password: '$pwd'
  db.url: 'jdbc:sqlserver://$host:1433;databaseName=SSC;sendStringParametersAsUnicode=false;encrypt=true;trustServerCertificate=true'
  db.username: '$user'
  db.password: '$pwd'
dbMigrationProperties:
  migration.enabled: true
YAML
  chmod 600 "$SSC_DIR/ssc.autoconfig"; ok "SSC autoconfig generated"
}
ssc_sync_secrets(){
  need_root; ssc_guard; ssc_generate_autoconfig; local n; n=$(ns)
  kubectl_cmd -n "$n" create secret generic ssc-license --from-file=fortify.license="$(config_get FORTIFY_LICENSE_PATH)" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  kubectl_cmd -n "$n" create secret generic ssc-autoconfig --from-file=ssc.autoconfig="$SSC_DIR/ssc.autoconfig" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  certificates_sync
  ok "SSC license, autoconfig, and certificate secrets synchronized"
}
ssc_validate(){
  local n; n=$(ns); kubectl_cmd -n "$n" get secret ssc-license ssc-autoconfig ssc-keystore ssc-keystore-password ssc-key-password >/dev/null
  if kubectl_cmd -n "$n" get pod ssc-webapp-0 >/dev/null 2>&1; then kubectl_cmd -n "$n" wait --for=condition=Ready pod/ssc-webapp-0 --timeout=900s; fi
  local fqdn; fqdn=$(config_get EXTERNAL_FQDN); curl -skI --max-time 15 "https://$fqdn:$(config_get SSC_NODEPORT)/" | head -1 || true
}
