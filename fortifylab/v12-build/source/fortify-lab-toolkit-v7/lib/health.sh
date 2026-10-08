#!/usr/bin/env bash
health_component(){
  local c=$1 n; n=$(ns); case "$c" in
  infrastructure) systemctl is-active --quiet k3s && ok K3s || warn K3s; systemctl is-active --quiet docker && ok Docker || warn Docker;;
  database) docker inspect -f '{{.State.Running}}' mssql 2>/dev/null | grep -q true && ok MSSQL || warn MSSQL;;
  lim) kubectl_cmd -n "$n" get pod lim-0 --no-headers 2>/dev/null | grep -q '1/1.*Running' && ok LIM || warn LIM;;
  ssc) kubectl_cmd -n "$n" get pod ssc-webapp-0 --no-headers 2>/dev/null | grep -q '1/1.*Running' && ok SSC || warn SSC;;
  sast) kubectl_cmd -n "$n" get pods --no-headers 2>/dev/null | grep -q 'scancentral-sast-controller-0.*1/1.*Running' && ok 'SAST Controller' || warn 'SAST Controller';;
  dast-core) kubectl_cmd -n "$n" get pods --no-headers 2>/dev/null | grep -q 'dast-core-.*api.*1/1.*Running\|scancentral-dast-core-api.*1/1.*Running' && ok 'DAST Core' || warn 'DAST Core';;
  dast-scanner) kubectl_cmd -n "$n" get pods --no-headers 2>/dev/null | grep -q 'dast-scanner.*4/4.*Running' && ok 'DAST Scanner' || warn 'DAST Scanner';;
  esac
}
health_all(){ for c in infrastructure database lim ssc sast dast-core dast-scanner; do health_component "$c"; done; df -h /; kubectl_cmd -n "$(ns)" get pods 2>/dev/null || true; }
