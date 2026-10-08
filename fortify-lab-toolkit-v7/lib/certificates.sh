#!/usr/bin/env bash
CERT_DIR="$FORTIFY_HOME/generated/certificates"
certificate_preflight(){
  local fqdn; fqdn=$(config_get EXTERNAL_FQDN)
  [[ -n "$fqdn" ]] || die "External FQDN is not configured"
  command_exists openssl || die "openssl is required"
  command_exists keytool || die "Java keytool is required"
  mkdir -p "$CERT_DIR"; chmod 700 "$CERT_DIR"
}
cert_password_file(){ printf '%s' "$(secret_value SSC_KEYSTORE_PASSWORD)" > "$CERT_DIR/ssc-keystore-password.txt"; chmod 600 "$CERT_DIR/ssc-keystore-password.txt"; }
certificates_generate_self_signed(){
  need_root; certificate_preflight
  local fqdn ip; fqdn=$(config_get EXTERNAL_FQDN); ip=$(config_get EXTERNAL_IP)
  warn "Generating lab/demo self-signed certificates. This is not a production PKI workflow."
  confirm "Generate and replace local certificate artifacts for $fqdn?" || return 0
  local san="DNS:$fqdn,DNS:$(config_get LIM_HOSTNAME),DNS:$(config_get SAST_HOSTNAME),DNS:$(config_get DAST_HOSTNAME),DNS:$(vm_short_hostname),DNS:lim,DNS:lim.$(ns).svc.cluster.local,DNS:scancentral-sast-controller,DNS:scancentral-sast-controller.$(ns).svc.cluster.local"
  [[ -n "$ip" ]] && san="$san,IP:$ip"
  openssl req -newkey rsa:3072 -new -nodes -x509 -days 825 \
    -keyout "$CERT_DIR/platform.key" -out "$CERT_DIR/platform.crt" \
    -subj "/CN=$fqdn/O=Fortify Lab" -addext "subjectAltName=$san"
  openssl pkcs12 -export -name fortify -out "$CERT_DIR/platform.pfx" \
    -inkey "$CERT_DIR/platform.key" -in "$CERT_DIR/platform.crt" \
    -passout "pass:$(secret_value DAST_PFX_PASSWORD)"
  keytool -importkeystore -noprompt \
    -srckeystore "$CERT_DIR/platform.pfx" -srcstoretype PKCS12 \
    -srcstorepass "$(secret_value DAST_PFX_PASSWORD)" \
    -destkeystore "$CERT_DIR/ssc-keystore.p12" -deststoretype PKCS12 \
    -deststorepass "$(secret_value SSC_KEYSTORE_PASSWORD)"
  cert_password_file
  chmod 600 "$CERT_DIR"/*
  certificates_validate
}
certificates_import(){
  need_root; certificate_preflight
  local crt key chain; read -rp "Server certificate PEM path: " crt; read -rp "Private key PEM path: " key; read -rp "Intermediate chain PEM path (optional): " chain
  [[ -r "$crt" && -r "$key" ]] || die "Certificate or key not readable"
  openssl x509 -in "$crt" -noout -subject -issuer -dates
  openssl pkey -in "$key" -check -noout
  local cert_pub key_pub
  cert_pub=$(openssl x509 -in "$crt" -pubkey -noout | openssl pkey -pubin -outform der | sha256sum | awk '{print $1}')
  key_pub=$(openssl pkey -in "$key" -pubout -outform der | sha256sum | awk '{print $1}')
  [[ "$cert_pub" == "$key_pub" ]] || die "Certificate and private key do not match"
  cp "$crt" "$CERT_DIR/platform.crt"; cp "$key" "$CERT_DIR/platform.key"
  if [[ -n "$chain" ]]; then [[ -r "$chain" ]] || die "Chain file not readable"; cat "$crt" "$chain" > "$CERT_DIR/platform-fullchain.crt"; else cp "$crt" "$CERT_DIR/platform-fullchain.crt"; fi
  openssl pkcs12 -export -name fortify -out "$CERT_DIR/platform.pfx" -inkey "$CERT_DIR/platform.key" -in "$CERT_DIR/platform.crt" ${chain:+-certfile "$chain"} -passout "pass:$(secret_value DAST_PFX_PASSWORD)"
  keytool -importkeystore -noprompt -srckeystore "$CERT_DIR/platform.pfx" -srcstoretype PKCS12 -srcstorepass "$(secret_value DAST_PFX_PASSWORD)" -destkeystore "$CERT_DIR/ssc-keystore.p12" -deststoretype PKCS12 -deststorepass "$(secret_value SSC_KEYSTORE_PASSWORD)"
  cert_password_file; chmod 600 "$CERT_DIR"/*; certificates_validate
}
certificates_validate(){
  certificate_preflight
  [[ -r "$CERT_DIR/platform.crt" ]] || die "No platform certificate found"
  openssl x509 -in "$CERT_DIR/platform.crt" -noout -subject -issuer -dates -ext subjectAltName
  keytool -list -keystore "$CERT_DIR/ssc-keystore.p12" -storepass "$(secret_value SSC_KEYSTORE_PASSWORD)" >/dev/null
  openssl pkcs12 -in "$CERT_DIR/platform.pfx" -passin "pass:$(secret_value DAST_PFX_PASSWORD)" -nokeys -clcerts -noout
  ok "Certificate artifacts validated"
}
certificates_sync(){
  need_root; certificates_validate; local n; n=$(ns)
  kubectl_cmd -n "$n" create secret tls lim-server-certificate --cert="$CERT_DIR/platform.crt" --key="$CERT_DIR/platform.key" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  kubectl_cmd -n "$n" create secret generic lim-signing-certificate --from-file=tls.pfx="$CERT_DIR/platform.pfx" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  kubectl_cmd -n "$n" create secret generic lim-signing-certificate-password --from-literal=pfx.password="$(secret_value DAST_PFX_PASSWORD)" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  kubectl_cmd -n "$n" create secret generic ssc-keystore --from-file=certificate-keystore="$CERT_DIR/ssc-keystore.p12" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  kubectl_cmd -n "$n" create secret generic ssc-keystore-password --from-literal=httpCertificateKeystorePassword="$(secret_value SSC_KEYSTORE_PASSWORD)" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  kubectl_cmd -n "$n" create secret generic ssc-key-password --from-literal=httpCertificateKeyPassword="$(secret_value SSC_KEYSTORE_PASSWORD)" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  for name in dast-api-certificate dast-utility-certificate; do kubectl_cmd -n "$n" create secret generic "$name" --from-file=tls.pfx="$CERT_DIR/platform.pfx" --from-literal=password="$(secret_value DAST_PFX_PASSWORD)" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null; done
  ok "Certificate secrets synchronized"
}
certificates_menu(){ while true; do echo '1) Generate self-signed lab certificates 2) Import CA certificates 3) Validate 4) Sync Kubernetes secrets 0) Back'; read -rp 'Select: ' n; case $n in 1) certificates_generate_self_signed;;2) certificates_import;;3) certificates_validate;;4) certificates_sync;;0) return;;esac; done; }
