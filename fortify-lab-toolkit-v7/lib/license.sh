#!/usr/bin/env bash
LICENSE_DIR="$FORTIFY_HOME/config/license"
LICENSE_FILE="$LICENSE_DIR/fortify.license"
LICENSE_META="$FORTIFY_HOME/state/license-file.env"

license_import(){
  need_root
  mkdir -p "$LICENSE_DIR" "$FORTIFY_HOME/state"
  chmod 700 "$LICENSE_DIR"
  local src=${1:-}
  if [[ -z "$src" ]]; then
    echo "Copy the Fortify license onto this VM, then enter its local path."
    echo "Example: /home/$SUDO_USER/fortify.license"
    read -r -e -p "Local path to fortify.license: " src
  fi
  [[ -f "$src" && -r "$src" ]] || die "License file is not readable: $src"
  [[ -s "$src" ]] || die "License file is empty: $src"
  local size
  size=$(stat -c %s "$src")
  (( size >= 100 )) || die "License file is unexpectedly small (${size} bytes)"
  install -o root -g root -m 600 "$src" "$LICENSE_FILE"
  config_set FORTIFY_LICENSE_PATH "$LICENSE_FILE"
  license_validate
  ok "Fortify license imported into $LICENSE_FILE"
}

license_validate(){
  local f=${1:-$(config_get FORTIFY_LICENSE_PATH)}
  [[ -n "$f" ]] || f="$LICENSE_FILE"
  [[ -f "$f" && -r "$f" && -s "$f" ]] || die "Fortify license is missing, unreadable, or empty: $f"
  local size sha mime modified
  size=$(stat -c %s "$f")
  (( size >= 100 )) || die "Fortify license is unexpectedly small (${size} bytes)"
  sha=$(sha256sum "$f" | awk '{print $1}')
  mime=$(file -b --mime-type "$f" 2>/dev/null || echo unknown)
  modified=$(stat -c %y "$f")
  case "$mime" in
    text/*|application/octet-stream|application/xml) ;;
    *) warn "Unexpected license MIME type: $mime";;
  esac
  cat > "$LICENSE_META" <<META
LICENSE_PATH=$f
LICENSE_SHA256=$sha
LICENSE_SIZE=$size
LICENSE_MIME=$mime
LICENSE_MODIFIED=$modified
VALIDATED_AT=$(date -Is)
META
  chmod 600 "$LICENSE_META"
  ok "License file structurally validated: size=${size} bytes sha256=${sha}"
  warn "This validates file presence, readability, size, and checksum. Product entitlement is confirmed only when SSC/SAST accept the license during deployment."
}

license_sync(){
  need_root
  license_validate
  local f n
  f=$(config_get FORTIFY_LICENSE_PATH); n=$(ns)
  kubectl_cmd create namespace "$n" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  kubectl_cmd -n "$n" create secret generic ssc-license \
    --from-file=fortify.license="$f" --dry-run=client -o yaml | kubectl_cmd apply -f - >/dev/null
  kubectl_cmd -n "$n" get secret ssc-license -o jsonpath='{.data.fortify\.license}' | base64 -d | sha256sum | awk '{print $1}' > "$FORTIFY_HOME/state/license-secret.sha256"
  local expected actual
  expected=$(sha256sum "$f" | awk '{print $1}')
  actual=$(cat "$FORTIFY_HOME/state/license-secret.sha256")
  [[ "$expected" == "$actual" ]] || die "Kubernetes license Secret checksum does not match the local license"
  ok "License synchronized to Kubernetes and checksum verified"
}

license_status(){
  if [[ -s "$LICENSE_META" ]]; then cat "$LICENSE_META"; else warn "No validated license metadata found"; fi
  if command_exists kubectl && [[ -n "$(config_get NAMESPACE)" ]]; then
    kubectl_cmd -n "$(ns)" get secret ssc-license >/dev/null 2>&1 && ok "ssc-license Secret exists" || warn "ssc-license Secret not found"
  fi
}

license_menu(){
  while true; do
    echo '1) Import fortify.license from local VM path'
    echo '2) Validate local license file'
    echo '3) Sync and checksum Kubernetes Secret'
    echo '4) Show license status'
    echo '0) Back'
    read -rp 'Select: ' n
    case "$n" in 1) license_import;; 2) license_validate;; 3) license_sync;; 4) license_status;; 0) return;; *) warn 'Invalid selection';; esac
  done
}
