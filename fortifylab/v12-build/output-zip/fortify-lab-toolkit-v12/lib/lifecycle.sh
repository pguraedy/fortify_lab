#!/usr/bin/env bash
ns(){ config_get NAMESPACE; }
ensure_base(){ need_root; [[ -s "$CONFIG" ]] || die 'Run configure first'; [[ -s "$LOCK" ]] || die 'Lock versions first'; [[ -s "$SECRETS_ENC" ]] || die 'Initialize secrets first'; kubectl_cmd create namespace "$(ns)" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null; secrets_sync; }
install_database(){
  local image; image=$(config_get MSSQL_IMAGE); [[ -n "$image" ]] || image=mcr.microsoft.com/mssql/server:2022-latest
  docker inspect mssql >/dev/null 2>&1 && { ok 'MSSQL container exists'; return; }
  docker run -d --name mssql -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD="$(secret_value MSSQL_SA_PASSWORD)" -p 1433:1433 --restart unless-stopped "$image" >/dev/null
  ok 'MSSQL container started';
}
chart_ref(){ echo "oci://registry-1.docker.io/fortifydocker/$(component_chart "$1")"; }
values_file(){ echo "$FORTIFY_HOME/generated/$1-values.yaml"; }
generate_values(){
  local c=$1 f; f=$(values_file "$c"); local fqdn storage; fqdn=$(config_get EXTERNAL_FQDN); storage=$(config_get STORAGE_CLASS)
  case "$c" in
    lim) cat > "$f" <<YAML
imagePullSecrets:
  - name: fortify-dockerhub
defaultAdministrator:
  credentialsSecretName: lim-admin-credentials
dataPersistence:
  storageClassName: $storage
  size: 5Gi
YAML
;;
    ssc) cat > "$f" <<YAML
imagePullSecrets:
  - name: fortify-dockerhub
sscLicenseSecret: ssc-license
sscLicenseKey: fortify.license
sscAutoconfigSecret: ssc-autoconfig
sscAutoconfigKey: ssc.autoconfig
httpCertificateKeystoreSecret: ssc-keystore
httpCertificateKeystoreKey: certificate-keystore
httpCertificateKeystorePasswordSecret: ssc-keystore-password
httpCertificateKeystorePasswordKey: httpCertificateKeystorePassword
httpCertificateKeyPasswordSecret: ssc-key-password
httpCertificateKeyPasswordKey: httpCertificateKeyPassword
urlHost: $fqdn
urlPrefix: /
ingress:
  enabled: false
persistence:
  storageClassName: $storage
  size: 20Gi
resources:
  requests: {cpu: 2, memory: 8Gi}
  limits: {cpu: 8, memory: 28Gi}
YAML
;;
    sast) cat > "$f" <<YAML
imagePullSecrets:
  - name: fortify-dockerhub
controller:
  sscUrl: https://$fqdn:$(config_get SSC_NODEPORT)
  sscSvcAccount:
    enabled: true
    secret: sc-sast-ssc-svc-account-secret
persistence:
  storageClassName: $storage
  size: 10Gi
sensor:
  replicas: 1
  resources:
    requests: {cpu: '2', memory: 8Gi}
    limits: {cpu: '4', memory: 16Gi}
YAML
;;
    dast-core) cat > "$f" <<YAML
imagePullSecrets:
  - name: fortify-dockerhub
serviceTokenSecretName: dast-service-token
sscServiceAccountSecretName: dast-ssc-account
limDefaultPoolSecretName: dast-lim-pool
database:
  standardAccountCredentialsSecret: dast-standard-secret
  dboLevelAccountCredentialsSecret: dast-dbo-secret
api:
  tls:
    enabled: true
    serverCertificate:
      secretName: dast-api-certificate
      pathSecretKey: tls.pfx
      passwordSecretName: dast-api-certificate
      passwordSecretKey: password
appsettings:
  sSCSettings:
    sSCRootUrl: 'https://$fqdn:$(config_get SSC_NODEPORT)/'
  lIMSettings:
    limUrl: 'https://lim:37562'
    useLimRestApi: true
YAML
;;
    dast-scanner) cat > "$f" <<YAML
imagePullSecrets:
  - name: fortify-dockerhub
dastApiServiceURL: 'https://scancentral-dast-core-api:34785'
serviceTokenSecretName: dast-service-token
resources:
  requests: {cpu: 500m, memory: 4Gi}
  limits: {memory: 8Gi}
YAML
;;
  esac
  chmod 600 "$f"
}
helm_apply(){
  local c=$1 rel v f; rel=$(helm_release "$c"); v=$(locked_version "$c"); [[ -n "$v" ]] || die "No locked version for $c"; generate_values "$c"; f=$(values_file "$c")
  helm pull "$(chart_ref "$c")" --version "$v" --destination "$FORTIFY_HOME/charts" >/dev/null
  helm show values "$(chart_ref "$c")" --version "$v" > "$FORTIFY_HOME/charts/$c-$v-default-values.yaml"
  helm show chart "$(chart_ref "$c")" --version "$v" > "$FORTIFY_HOME/charts/$c-$v-Chart.yaml"
  local probe_extra=()
  if [[ "$c" == lim || "$c" == sast ]]; then
    probe_schema_check "$c" "$FORTIFY_HOME/charts/$c-$v-default-values.yaml"
    generate_probe_values "$c"
    probe_extra+=(-f "$(probe_values_file "$c")")
  fi
  local extra=()
  if [[ "$c" == sast ]]; then
    license_validate
    grep -q 'fortifyLicense' "$FORTIFY_HOME/charts/$c-$v-default-values.yaml" || die "Selected SAST chart does not expose the expected fortifyLicense value; review chart schema before continuing"
    extra+=(--set-file "secrets.fortifyLicense=$(config_get FORTIFY_LICENSE_PATH)")
  fi
  helm template "$rel" "$(chart_ref "$c")" --version "$v" -n "$(ns)" -f "$f" "${probe_extra[@]}" "${extra[@]}" > "$FORTIFY_HOME/generated/$c-rendered.yaml"
  helm upgrade --install "$rel" "$(chart_ref "$c")" --version "$v" -n "$(ns)" -f "$f" "${probe_extra[@]}" "${extra[@]}" --wait --timeout 60m
}
install_component(){
  local c=${1:-all}; ensure_base
  if [[ "$c" == all ]]; then install_database; database_initialize; certificates_sync; ssc_sync_secrets; for x in lim ssc sast dast-core dast-scanner; do helm_apply "$x"; done; else case "$c" in infrastructure) prerequisites_install;; database) install_database; database_initialize;; *) helm_apply "$c";; esac; fi
  health_all
}
