#!/usr/bin/env bash
set -Eeuo pipefail
TARGET=${1:-.}; [[ -f "$TARGET/lib/prerequisites.sh" && -f "$TARGET/bin/fortify-lab" ]] || { echo 'Run against an extracted v7 toolkit directory.' >&2; exit 1; }
cp "$(dirname "$0")/lib/repository.sh" "$TARGET/lib/repository.sh"
cp "$(dirname "$0")/setup-github-desktop-ubuntu.sh" "$TARGET/setup-github-desktop-ubuntu.sh"
chmod +x "$TARGET/setup-github-desktop-ubuntu.sh"
python3 - "$TARGET" <<'PY'
import sys, pathlib
r=pathlib.Path(sys.argv[1])
p=r/'lib/prerequisites.sh'; s=p.read_text()
s=s.replace('for c in curl jq openssl docker', 'for c in curl jq openssl git gh docker')
needle='apt-get install -y curl wget git vim jq unzip tree ca-certificates gnupg lsb-release net-tools openssl openjdk-17-jdk age dialog apache2-utils'
repl=needle+'\n  install -m 0755 -d /etc/apt/keyrings\n  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg\n  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg\n  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list\n  apt-get update\n  apt-get install -y gh'
s=s.replace(needle,repl); p.write_text(s)
p=r/'bin/fortify-lab'; s=p.read_text(); s=s.replace('source "$ROOT/lib/hosts.sh"','source "$ROOT/lib/repository.sh"\nsource "$ROOT/lib/hosts.sh"')
s=s.replace('  hosts precheck|apply|verify|show|remove','  repo auth|clone|status|update|validate Optional repository workflow\n  hosts precheck|apply|verify|show|remove')
insert='''  repo)\n    sub="${1:-status}"; shift || true\n    case "$sub" in auth) repo_auth;; clone) repo_clone "${1:-}" "${2:-}";; status) repo_status;; update) repo_update;; validate) repo_validate "${1:-}";; menu) repo_menu;; *) usage;; esac;;\n'''
s=s.replace('  hosts)',insert+'  hosts)'); p.write_text(s)
PY
for f in "$TARGET"/bin/fortify-lab "$TARGET"/lib/*.sh "$TARGET"/setup-github-desktop-ubuntu.sh; do bash -n "$f"; done
echo 'Git/GitHub add-on applied. Run the toolkit safe tests next.'
