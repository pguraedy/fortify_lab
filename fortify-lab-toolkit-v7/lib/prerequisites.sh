#!/usr/bin/env bash
preflight(){
  echo 'Fortify Lab Preflight'; echo '====================='
  source /etc/os-release || true
  [[ "${ID:-}" == ubuntu ]] && ok "Ubuntu ${VERSION_ID:-unknown}" || warn "Expected Ubuntu; found ${ID:-unknown}"
  [[ $(uname -m) == x86_64 ]] && ok 'Architecture amd64' || warn "Architecture $(uname -m)"
  local cpu mem disk free
  cpu=$(nproc); mem=$(awk '/MemTotal/{printf "%.0f",$2/1024/1024}' /proc/meminfo); disk=$(df -BG / | awk 'NR==2{gsub("G","");print $2}'); free=$(df -BG / | awk 'NR==2{gsub("G","");print $4}')
  (( cpu >= 8 )) && ok "CPU $cpu cores" || warn "CPU $cpu cores; full stack needs substantial capacity"
  (( mem >= 30 )) && ok "Memory ${mem} GiB" || warn "Memory ${mem} GiB; recommend at least 32 GiB for lab"
  (( disk >= 100 )) && ok "Disk ${disk} GiB" || warn "Disk ${disk} GiB; recommend 100 GiB minimum, 120-300 GiB preferred"
  (( free >= 20 )) && ok "Free disk ${free} GiB" || warn "Only ${free} GiB free"
  [[ "$(hostname)" =~ ^[a-z0-9.-]+$ ]] && ok "Hostname $(hostname)" || warn 'Hostname should be lowercase DNS-safe'
  for c in curl jq openssl docker k3s kubectl helm age age-keygen java keytool; do command_exists "$c" && ok "$c installed" || warn "$c missing"; done
}
apt_repair_if_needed() {
    if ! sudo apt-get update >/dev/null 2>&1; then
        echo "Attempting apt repair..."

        sudo rm -f /var/lib/apt/lists/lock
        sudo rm -f /var/cache/apt/archives/lock
        sudo rm -f /var/lib/dpkg/lock
        sudo rm -f /var/lib/dpkg/lock-frontend

        sudo dpkg --configure -a
    fi
}

prerequisites_install(){
  need_root
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y curl wget git vim jq unzip tree ca-certificates gnupg lsb-release net-tools openssl openjdk-17-jdk age dialog apache2-utils
  if ! command_exists docker; then curl -fsSL https://get.docker.com | sh; fi
  systemctl enable --now docker
  if ! command_exists k3s; then curl -sfL https://get.k3s.io | sh -; fi
  if ! command_exists kubectl; then ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl; fi
  if ! command_exists helm; then curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; fi
  helm repo add openebs https://openebs.github.io/charts --force-update
  helm repo update
  helm upgrade -i openebs openebs/openebs --namespace openebs --create-namespace --wait --timeout 20m
  ok 'Prerequisites installed.'
}
