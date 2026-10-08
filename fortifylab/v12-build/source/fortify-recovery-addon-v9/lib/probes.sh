#!/usr/bin/env bash
# Persist startup probes through Helm values when the selected chart supports the relevant keys.
probe_values_file(){ echo "$FORTIFY_HOME/generated/$1-probes.yaml"; }
probe_schema_check(){
  local component=$1 defaults=$2
  [[ -s "$defaults" ]] || die "Default chart values missing: $defaults"
  case "$component" in
    lim) grep -qiE 'startupProbe|livenessProbe' "$defaults" || die 'LIM chart does not expose probe configuration; manual chart mapping required';;
    sast) grep -qiE 'startupProbe|livenessProbe' "$defaults" || die 'SAST chart does not expose probe configuration; manual chart mapping required';;
  esac
}
generate_probe_values(){
  local component=$1 out; out=$(probe_values_file "$component")
  case "$component" in
    lim) cat > "$out" <<'YAML'
livenessProbe:
  initialDelaySeconds: 300
  timeoutSeconds: 5
  periodSeconds: 10
  failureThreshold: 6
readinessProbe:
  initialDelaySeconds: 120
  timeoutSeconds: 5
  periodSeconds: 10
  failureThreshold: 12
startupProbe:
  httpGet:
    path: /
    port: https
    scheme: HTTPS
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 30
YAML
;;
    sast) cat > "$out" <<'YAML'
controller:
  livenessProbe:
    initialDelaySeconds: 300
    timeoutSeconds: 5
    periodSeconds: 10
    failureThreshold: 6
  readinessProbe:
    initialDelaySeconds: 120
    timeoutSeconds: 5
    periodSeconds: 10
    failureThreshold: 12
  startupProbe:
    httpGet:
      path: /scancentral-ctrl/
      port: https
      scheme: HTTPS
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 30
YAML
;;
    *) return 0;;
  esac
  chmod 600 "$out"
}
verify_live_startup_probe(){
  local component=$1 json
  case "$component" in lim) json=$(kubectl_cmd -n "$(ns)" get statefulset lim -o jsonpath='{.spec.template.spec.containers[0].startupProbe}' 2>/dev/null);; sast) json=$(kubectl_cmd -n "$(ns)" get statefulset scancentral-sast-controller -o jsonpath='{.spec.template.spec.containers[0].startupProbe}' 2>/dev/null);; esac
  [[ -n "$json" ]] || die "$component startupProbe not present in live StatefulSet"
  ok "$component startupProbe verified"
}
