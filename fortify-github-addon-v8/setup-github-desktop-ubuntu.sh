#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
source /etc/os-release; [[ ${ID:-} == ubuntu ]] || { echo 'Ubuntu required.' >&2; exit 1; }
[[ $(uname -m) == x86_64 ]] || { echo 'amd64/x86_64 required.' >&2; exit 1; }
[[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} || -d /usr/share/xsessions ]] || { echo 'Graphical Ubuntu desktop not detected.' >&2; exit 1; }
echo 'GitHub does not publish an official Linux build of GitHub Desktop.'
echo 'This installs the community-maintained Shiftkey Linux fork.'
read -rp 'Continue? [y/N] ' a; [[ $a =~ ^[Yy]$ ]] || exit 0
apt-get update; apt-get install -y ca-certificates curl jq git gdebi-core
j=$(curl -fsSL https://api.github.com/repos/shiftkey/desktop/releases/latest)
u=$(jq -r '.assets[]|select(.name|test("(amd64|x86_64).*\\.deb$";"i"))|.browser_download_url' <<<"$j"|head -1)
v=$(jq -r .tag_name <<<"$j"); [[ -n "$u" && "$u" != null ]] || { echo 'No amd64 .deb found.' >&2; exit 1; }
t=$(mktemp --suffix=.deb); trap 'rm -f "$t"' EXIT; curl -fL "$u" -o "$t"; dpkg-deb --info "$t" >/dev/null; gdebi -n "$t"; command -v github-desktop >/dev/null; echo "Installed $v"
