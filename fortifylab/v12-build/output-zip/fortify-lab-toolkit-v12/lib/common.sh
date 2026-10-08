#!/usr/bin/env bash
COLOR=${COLOR:-1}
if [[ -t 1 && "$COLOR" == 1 ]]; then RED='\033[31m'; GRN='\033[32m'; YLW='\033[33m'; BLU='\033[34m'; RST='\033[0m'; else RED=;GRN=;YLW=;BLU=;RST=; fi
log(){ printf '%b[%s] %s%b\n' "$BLU" "$(date '+%F %T')" "$*" "$RST" | tee -a "$FORTIFY_HOME/logs/fortify-lab.log"; }
ok(){ printf '%b[PASS]%b %s\n' "$GRN" "$RST" "$*"; }
warn(){ printf '%b[WARN]%b %s\n' "$YLW" "$RST" "$*" >&2; }
die(){ printf '%b[FAIL]%b %s\n' "$RED" "$RST" "$*" >&2; exit 1; }
need_root(){ [[ $EUID -eq 0 ]] || die "Run with sudo/root."; }
command_exists(){ command -v "$1" >/dev/null 2>&1; }
pause(){ read -rp "Press Enter to continue..." _; }
confirm(){ local p=${1:-Proceed?}; read -rp "$p [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }
choose_component(){
  local opts=(infrastructure database lim ssc sast dast-core dast-scanner)
  printf 'Components:\n' >&2; local i=1; for x in "${opts[@]}"; do printf '%d) %s\n' "$i" "$x" >&2; ((i++)); done
  read -rp "Select component: " n
  [[ "$n" =~ ^[1-7]$ ]] || die "Invalid component"
  echo "${opts[$((n-1))]}"
}
run(){ log "+ $*"; "$@"; }
kubectl_cmd(){ if command_exists kubectl; then kubectl "$@"; elif command_exists k3s; then k3s kubectl "$@"; else die "kubectl unavailable"; fi; }
helm_release(){ case "$1" in lim) echo lim;; ssc) echo ssc;; sast) echo scancentral-sast;; dast-core) echo scancentral-dast-core;; dast-scanner) echo scancentral-dast-scanner;; *) echo "$1";; esac; }
component_chart(){ case "$1" in lim) echo helm-lim;; ssc) echo helm-ssc;; sast) echo helm-scancentral-sast;; dast-core) echo helm-scancentral-dast-core;; dast-scanner) echo helm-scancentral-dast-scanner;; esac; }
