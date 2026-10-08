#!/usr/bin/env bash
FCLI_INSTALL_DIR=/usr/local/lib/fortify/fcli
FCLI_BIN=/usr/local/bin/fcli
fcli_install_latest(){
  need_root
  local tmp tgz sum expected actual version
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
  tgz="$tmp/fcli-linux.tgz"; sum="$tmp/fcli-linux.tgz.sha256"
  curl -fL https://github.com/fortify/fcli/releases/latest/download/fcli-linux.tgz -o "$tgz"
  if curl -fL https://github.com/fortify/fcli/releases/latest/download/fcli-linux.tgz.sha256 -o "$sum"; then
    expected=$(awk '{print $1}' "$sum"); actual=$(sha256sum "$tgz" | awk '{print $1}')
    [[ "$expected" == "$actual" ]] || die 'fcli SHA-256 verification failed'
  else
    warn 'Published fcli SHA-256 asset was unavailable; refusing unverified installation.'
    return 1
  fi
  mkdir -p "$FCLI_INSTALL_DIR"
  tar -xzf "$tgz" -C "$FCLI_INSTALL_DIR"
  local found; found=$(find "$FCLI_INSTALL_DIR" -type f -name fcli -perm /111 | head -1)
  [[ -n "$found" ]] || die 'fcli executable not found in downloaded archive'
  ln -sfn "$found" "$FCLI_BIN"
  version=$($FCLI_BIN --version)
  ok "Installed $version"
}
fcli_validate(){ command_exists fcli || die 'fcli is not installed'; fcli --version; }
