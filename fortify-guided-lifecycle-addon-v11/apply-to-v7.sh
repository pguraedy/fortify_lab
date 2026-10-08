#!/usr/bin/env bash
set -Eeuo pipefail
TARGET=${1:-.}
[[ -f "$TARGET/bin/fortify-lab" && -f "$TARGET/lib/stages.sh" ]] || { echo 'Target must be an extracted, add-on-patched Fortify toolkit.' >&2; exit 1; }
# Verify prerequisite add-ons are present.
for f in lib/repository.sh lib/recovery-hardened.sh lib/fcli.sh tests/30-pvc-pending-injection.sh; do
  [[ -f "$TARGET/$f" ]] || { echo "Missing $f. Apply GitHub v8, recovery v9, and validation v10 add-ons first." >&2; exit 1; }
done
cp "$(dirname "$0")/lib/guided.sh" "$TARGET/lib/guided.sh"
python3 - "$TARGET" <<'PY'
import pathlib,sys
r=pathlib.Path(sys.argv[1]); p=r/'bin/fortify-lab'; s=p.read_text()
if 'source "$ROOT/lib/guided.sh"' not in s:
    s=s.replace('source "$ROOT/lib/stages.sh"','source "$ROOT/lib/stages.sh"\nsource "$ROOT/lib/guided.sh"')
s=s.replace('Usage: fortify-lab [command] [subcommand] [component]', 'Usage: fortify-lab [command] [subcommand] [component]\n\nPrimary attended experience: fortify-lab guided')
if '  guided                            Guided Lab Lifecycle menu' not in s:
    s=s.replace('Commands:', 'Commands:\n  guided                            Guided Lab Lifecycle menu')
if '  guided) guided_menu;;' not in s:
    s=s.replace('case "$cmd" in', 'case "$cmd" in\n  guided) guided_menu;;')
p.write_text(s)
PY
cat >> "$TARGET/README.md" <<'DOC'

## Guided Lab Lifecycle

Run the attended lifecycle interface:

```bash
sudo fortify-lab guided
```

The guided menu orchestrates first-time build, validation, reboot recovery, resiliency testing, repository/platform updates, backups, and administration tools. It uses the existing durable stage state, hard gates, cleanup traps, and manual licensing checkpoints rather than bypassing them.
DOC
for f in "$TARGET"/bin/fortify-lab "$TARGET"/lib/*.sh; do bash -n "$f"; done
echo 'Guided Lab Lifecycle menu applied.'
