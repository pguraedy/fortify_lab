#!/usr/bin/env bash
HOSTS_FILE=/etc/hosts
HOSTS_BEGIN='# BEGIN FORTIFY-LAB MANAGED HOSTS'
HOSTS_END='# END FORTIFY-LAB MANAGED HOSTS'
HOSTS_EXPORT="$FORTIFY_HOME/generated/hosts-file.txt"

vm_short_hostname(){ hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9.-]/-/g'; }
namespace_name(){ local n; n=$(config_get NAMESPACE); [[ -n "$n" ]] || n=fortify; printf '%s' "$n"; }
domain_suffix(){ local s; s=$(config_get DOMAIN_SUFFIX); [[ -n "$s" ]] || s=com; s=${s#.}; printf '%s' "$s"; }
base_domain(){ printf '%s.%s' "$(namespace_name)" "$(domain_suffix)"; }
lab_ip(){ local ip; ip=$(config_get EXTERNAL_IP); [[ -n "$ip" ]] || ip=$(hostname -I | awk '{print $1}'); printf '%s' "$ip"; }
component_hostnames(){ local d; d=$(base_domain); printf '%s\n' "ssc.$d" "lim.$d" "sast.$d" "dast.$d"; }

validate_namespace_domain(){
  local n s
  n=$(namespace_name); s=$(domain_suffix)
  [[ "$n" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "Namespace must be lowercase DNS-label compatible: $n"
  (( ${#n} <= 63 )) || die "Namespace exceeds 63 characters"
  [[ "$s" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || die "Domain suffix is not DNS-safe: $s"
  [[ "$s" != .* && "$s" != *. ]] || die "Domain suffix must not begin or end with a dot"
}

hosts_render_block(){
  local ip short names
  validate_namespace_domain
  ip=$(lab_ip); short=$(vm_short_hostname); names=$(component_hostnames | tr '\n' ' ')
  cat <<BLOCK
$HOSTS_BEGIN
$ip $short $short.local $names
$HOSTS_END
BLOCK
}

host_occurrences(){
  local name=$1
  awk -v name="$name" -v b="$HOSTS_BEGIN" -v e="$HOSTS_END" '
    $0==b {managed=1; next}
    $0==e {managed=0; next}
    managed=="" {managed=0}
    /^[[:space:]]*#/ || NF<2 {next}
    {
      for (i=2;i<=NF;i++) if ($i==name) print $1 "\t" managed "\t" NR "\t" $0
    }
  ' "$HOSTS_FILE"
}

hosts_precheck(){
  validate_namespace_domain
  local expected name matches total external iplist
  expected=$(lab_ip)
  [[ "$expected" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "Invalid VM IPv4 address: $expected"
  while read -r name; do
    matches=$(host_occurrences "$name" || true)
    [[ -z "$matches" ]] && { ok "$name does not already exist"; continue; }
    total=$(wc -l <<< "$matches" | tr -d ' ')
    external=$(awk -F '\t' '$2==0{n++} END{print n+0}' <<< "$matches")
    iplist=$(awk -F '\t' '{print $1}' <<< "$matches" | sort -u | tr '\n' ' ')
    if (( external > 0 )); then
      warn "Existing unmanaged /etc/hosts entry found for $name:"
      awk -F '\t' '$2==0{print "  line "$3": "$4}' <<< "$matches"
      if awk -F '\t' -v expected="$expected" '$1!=expected{bad=1} END{exit !bad}' <<< "$matches"; then
        die "Conflicting unmanaged entry for $name. Expected $expected; found IP(s): $iplist. Resolve manually before deployment."
      fi
      if (( total > 1 )); then die "Duplicate definitions exist for $name. Remove duplicates before deployment."; fi
      ok "Existing unmanaged entry for $name already matches $expected; it will be preserved"
    else
      if (( total > 1 )); then die "Duplicate managed definitions exist for $name"; fi
      local found_ip; found_ip=$(awk -F '\t' 'NR==1{print $1}' <<< "$matches")
      [[ "$found_ip" == "$expected" ]] || warn "Managed entry for $name will be updated from $found_ip to $expected"
    fi
  done < <(component_hostnames)
}

hosts_apply(){
  need_root
  hosts_precheck
  local ip; ip=$(lab_ip)
  cp -a "$HOSTS_FILE" "$HOSTS_FILE.fortify-backup.$(date +%Y%m%d-%H%M%S)"
  local tmp; tmp=$(mktemp)
  awk -v b="$HOSTS_BEGIN" -v e="$HOSTS_END" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "$HOSTS_FILE" > "$tmp"
  printf '\n' >> "$tmp"; hosts_render_block >> "$tmp"
  install -o root -g root -m 644 "$tmp" "$HOSTS_FILE"; rm -f "$tmp"
  mkdir -p "$(dirname "$HOSTS_EXPORT")"
  printf '%s ' "$ip" > "$HOSTS_EXPORT"; component_hostnames | tr '\n' ' ' >> "$HOSTS_EXPORT"; printf '\n' >> "$HOSTS_EXPORT"
  chmod 644 "$HOSTS_EXPORT"
  hosts_verify
  ok "Managed Fortify entries written to $HOSTS_FILE"
  echo "Client workstation entries: $HOSTS_EXPORT"
}

hosts_verify(){
  validate_namespace_domain
  local ip name resolved matches count
  ip=$(lab_ip)
  grep -Fxq "$HOSTS_BEGIN" "$HOSTS_FILE" || die "Managed hosts block is missing"
  grep -Fxq "$HOSTS_END" "$HOSTS_FILE" || die "Managed hosts block terminator is missing"
  while read -r name; do
    matches=$(host_occurrences "$name" || true)
    count=$(wc -l <<< "$matches" | tr -d ' ')
    (( count == 1 )) || die "Expected exactly one /etc/hosts definition for $name; found $count"
    [[ "$(awk -F '\t' 'NR==1{print $1}' <<< "$matches")" == "$ip" ]] || die "$name is not mapped to $ip in /etc/hosts"
    resolved=$(getent ahostsv4 "$name" | awk 'NR==1{print $1}')
    [[ "$resolved" == "$ip" ]] || die "Hostname $name resolves to '${resolved:-nothing}', expected $ip"
    ok "$name resolves to $resolved"
  done < <(component_hostnames)
  resolved=$(getent ahostsv4 "$(vm_short_hostname)" | awk 'NR==1{print $1}')
  [[ "$resolved" == "$ip" ]] || die "VM short hostname $(vm_short_hostname) resolves to '${resolved:-nothing}', expected $ip"
  ok "VM hostname $(vm_short_hostname) resolves to $resolved"
}

hosts_show(){ echo "VM short hostname: $(vm_short_hostname)"; echo "VM IP: $(lab_ip)"; echo "Kubernetes namespace: $(namespace_name)"; echo "Domain suffix: .$(domain_suffix)"; echo "Base domain: $(base_domain)"; hosts_render_block; }
hosts_remove(){ need_root; local tmp; tmp=$(mktemp); awk -v b="$HOSTS_BEGIN" -v e="$HOSTS_END" '$0==b{skip=1;next}$0==e{skip=0;next}!skip{print}' "$HOSTS_FILE" > "$tmp"; install -o root -g root -m 644 "$tmp" "$HOSTS_FILE"; rm -f "$tmp"; ok 'Managed Fortify hosts block removed'; }
hosts_menu(){ while true; do echo '1) Show proposed entries 2) Precheck existing entries 3) Apply /etc/hosts entries 4) Verify resolution 5) Remove managed entries 0) Back'; read -rp 'Select: ' n; case $n in 1) hosts_show;;2) hosts_precheck;;3) hosts_apply;;4) hosts_verify;;5) hosts_remove;;0) return;;*) warn 'Invalid selection';;esac; done; }
