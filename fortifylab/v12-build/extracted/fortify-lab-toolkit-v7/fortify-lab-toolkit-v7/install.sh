#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
    -h|--help)
        cat <<'EOF'

Fortify Lab Toolkit

Usage:
  sudo ./install.sh

After installation:
  sudo fortify-lab menu

Commands:
  --help     Show this help

EOF
        exit 0
        ;;
esac

[[ $EUID -eq 0 ]] || {
    echo "Run with sudo"
    exit 1
}

SRC=$(cd "$(dirname "$0")" && pwd)
DEST=/opt/fortify-deploy
mkdir -p "$DEST"
cp -a "$SRC"/. "$DEST"/
chmod -R go-rwx "$DEST/config" 2>/dev/null || true
chmod +x "$DEST/bin/fortify-lab"
ln -sf "$DEST/bin/fortify-lab" /usr/local/bin/fortify-lab
install -d -m 700 /etc/fortify-deploy
cat >/etc/systemd/system/fortify-lab-recovery.service <<UNIT
[Unit]
Description=Fortify Lab post-boot health and recovery
After=network-online.target docker.service k3s.service
Wants=network-online.target
ConditionPathExists=$DEST/config/deployment.env

[Service]
Type=oneshot
ExecStart=$DEST/bin/fortify-lab health
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable fortify-lab-recovery.service >/dev/null
printf 'Installed. Run: sudo fortify-lab menu\n'
