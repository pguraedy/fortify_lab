#!/usr/bin/env bash
LOCK="$FORTIFY_HOME/config/versions.lock.env"
components=(lim ssc sast dast-core dast-scanner)
repo_for(){ echo "fortifydocker/$(component_chart "$1")"; }
dockerhub_token(){
  local u p; u=$(secret_value DOCKERHUB_USER); p=$(secret_value DOCKERHUB_TOKEN)
  curl -fsS -H 'Content-Type: application/json' -X POST -d "$(jq -n --arg u "$u" --arg p "$p" '{username:$u,password:$p}')" https://hub.docker.com/v2/users/login/ | jq -r .token
}
list_tags(){ local repo=$1 token=$2; curl -fsS -H "Authorization: JWT $token" "https://hub.docker.com/v2/repositories/$repo/tags/?page_size=100" | jq -r '.results[].name'; }
version_family(){ grep -oE '^[0-9]+\.[0-9]+' <<< "$1" || true; }
version_sort(){ sort -V; }
versions_discover(){
  ensure_age; [[ -s "$SECRETS_ENC" ]] || die 'Initialize secrets first for Docker Hub access.'
  local tok; tok=$(dockerhub_token); local tmp; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
  for c in "${components[@]}"; do list_tags "$(repo_for "$c")" "$tok" | grep -E '^[0-9]+\.[0-9]+' | version_sort > "$tmp/$c"; done
  comm -12 <(for c in "${components[@]}"; do awk '{match($0,/^[0-9]+\.[0-9]+/);print substr($0,RSTART,RLENGTH)}' "$tmp/$c" | sort -u; done | sort | uniq -c | awk -v n=${#components[@]} '$1==n{print $2}' | sort -V) <(for c in "${components[@]}"; do awk '{match($0,/^[0-9]+\.[0-9]+/);print substr($0,RSTART,RLENGTH)}' "$tmp/$c" | sort -u; done | sort -u) > "$FORTIFY_HOME/state/common-families"
  echo 'Complete release families:'; cat "$FORTIFY_HOME/state/common-families"
  for c in "${components[@]}"; do cp "$tmp/$c" "$FORTIFY_HOME/state/tags-$c"; done
}
versions_lock(){
  local fam=${1:-}; [[ -n "$fam" ]] || fam=$(tail -1 "$FORTIFY_HOME/state/common-families" 2>/dev/null); [[ -n "$fam" ]] || die 'Run versions discover first.'
  : > "$LOCK"; printf 'RELEASE_FAMILY=%q\n' "$fam" >> "$LOCK"
  for c in "${components[@]}"; do local v; v=$(grep -E "^${fam//./\.}([.-]|$)" "$FORTIFY_HOME/state/tags-$c" | tail -1); [[ -n "$v" ]] || die "No $c version for $fam"; printf '%s=%q\n' "VERSION_${c^^}" "$v" | tr '-' '_' >> "$LOCK"; done
  chmod 600 "$LOCK"; versions_show
}
versions_lock_interactive(){ local d; d=$(tail -1 "$FORTIFY_HOME/state/common-families" 2>/dev/null); read -rp "Release family [$d]: " f; versions_lock "${f:-$d}"; }
versions_show(){ [[ -s "$LOCK" ]] && cat "$LOCK" || warn 'No versions locked'; }
locked_version(){ local c=${1^^}; c=${c//-/_}; [[ -s "$LOCK" ]] && bash -c 'source "$1"; eval "printf %s \"\${VERSION_'"$c"':-}\""' bash "$LOCK"; }
