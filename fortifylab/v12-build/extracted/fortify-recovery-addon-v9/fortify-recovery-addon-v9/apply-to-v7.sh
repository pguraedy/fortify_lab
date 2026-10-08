#!/usr/bin/env bash
set -Eeuo pipefail
TARGET=${1:-.}
[[ -f "$TARGET/lib/lifecycle.sh" && -f "$TARGET/bin/fortify-lab" ]] || { echo 'Target must be an extracted Fortify toolkit v7 directory.' >&2; exit 1; }
cp "$(dirname "$0")/lib/recovery.sh" "$TARGET/lib/recovery-hardened.sh"
cp "$(dirname "$0")/lib/probes.sh" "$TARGET/lib/probes.sh"
mkdir -p "$TARGET/systemd"
cp "$(dirname "$0")/systemd/fortify-lab-boot-health.service" "$TARGET/systemd/"
python3 - "$TARGET" <<'PY'
import pathlib,sys
r=pathlib.Path(sys.argv[1])
# Dispatcher
p=r/'bin/fortify-lab'; s=p.read_text()
s=s.replace('source "$ROOT/lib/repair.sh"','source "$ROOT/lib/probes.sh"\nsource "$ROOT/lib/recovery-hardened.sh"\nsource "$ROOT/lib/repair.sh"')
s=s.replace('  recover                           Dependency-aware post-reboot recovery','  recover                           Strict dependency-ordered reboot recovery\n  boot-health                       Conservative read-only boot health check')
s=s.replace('  recover) recover_all;;','  recover) recover_all;;\n  boot-health) boot_health_check;;')
p.write_text(s)
# Lifecycle probe injection after chart defaults are available.
p=r/'lib/lifecycle.sh'; s=p.read_text()
needle='helm show chart "$(chart_ref "$c")" --version "$v" > "$FORTIFY_HOME/charts/$c-$v-Chart.yaml"'
replacement=needle+'\n  local probe_extra=()\n  if [[ "$c" == lim || "$c" == sast ]]; then\n    probe_schema_check "$c" "$FORTIFY_HOME/charts/$c-$v-default-values.yaml"\n    generate_probe_values "$c"\n    probe_extra+=(-f "$(probe_values_file "$c")")\n  fi'
s=s.replace(needle,replacement)
s=s.replace('-n "$(ns)" -f "$f" "${extra[@]}" > "$FORTIFY_HOME/generated/$c-rendered.yaml"','-n "$(ns)" -f "$f" "${probe_extra[@]}" "${extra[@]}" > "$FORTIFY_HOME/generated/$c-rendered.yaml"')
s=s.replace('-n "$(ns)" -f "$f" "${extra[@]}" --wait','-n "$(ns)" -f "$f" "${probe_extra[@]}" "${extra[@]}" --wait')
p.write_text(s)
# Stage verification of live probes and storage.
p=r/'lib/stages.sh'; s=p.read_text()
s=s.replace('stage_lim(){\n  helm_apply lim;', 'stage_lim(){\n  helm_apply lim; verify_live_startup_probe lim;')
s=s.replace('stage_sast(){ require_pass license-file; helm_apply sast;', 'stage_sast(){ require_pass license-file; helm_apply sast; verify_live_startup_probe sast;')
s=s.replace('stage_infrastructure(){', 'stage_infrastructure(){')
s=s.replace('secrets_sync; assert_disk_headroom 25','secrets_sync; assert_disk_headroom 25\n  wait_openebs_ready 600\n  wait_pvcs_bound 600')
p.write_text(s)
# Install systemd health-only service.
p=r/'install.sh'; s=p.read_text()
insert='''\ncp "$DEST/systemd/fortify-lab-boot-health.service" /etc/systemd/system/fortify-lab-boot-health.service\nsystemctl daemon-reload\nsystemctl enable fortify-lab-boot-health.service >/dev/null\n'''
s=s.replace('systemctl daemon-reload\nsystemctl enable fortify-lab-recovery.service >/dev/null', 'systemctl daemon-reload\nsystemctl enable fortify-lab-recovery.service >/dev/null'+insert)
p.write_text(s)
PY
for f in "$TARGET"/bin/fortify-lab "$TARGET"/lib/*.sh "$TARGET"/install.sh; do bash -n "$f"; done
echo 'Recovery hardening applied. Run ./tests/run-tests.sh before installation.'
