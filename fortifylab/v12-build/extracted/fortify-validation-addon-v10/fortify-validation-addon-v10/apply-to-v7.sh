#!/usr/bin/env bash
set -Eeuo pipefail
TARGET=${1:-.}; [[ -f "$TARGET/lib/prerequisites.sh" ]] || { echo 'Target must be an extracted toolkit.' >&2; exit 1; }
cp "$(dirname "$0")/lib/fcli.sh" "$TARGET/lib/fcli.sh"
cp "$(dirname "$0")/tests/"*.sh "$TARGET/tests/"
python3 - "$TARGET" <<'PY'
import pathlib,sys
r=pathlib.Path(sys.argv[1])
p=r/'bin/fortify-lab'; s=p.read_text(); s=s.replace('source "$ROOT/lib/common.sh"','source "$ROOT/lib/common.sh"\nsource "$ROOT/lib/fcli.sh"'); p.write_text(s)
p=r/'lib/prerequisites.sh'; s=p.read_text()
s=s.replace('for c in curl jq openssl', 'for c in curl jq openssl fcli')
s=s.replace("ok 'Prerequisites installed", "fcli_install_latest\n  fcli_validate\n  ok 'Prerequisites installed")
p.write_text(s)
PY
cat >> "$TARGET/TEST_PLAN.md" <<'DOC'

## Storage-gate failure injection

Run only on a disposable/snapshotted configured VM with no active deployment operation:

```bash
sudo RUN_STORAGE_FAILURE_TESTS=1 /opt/fortify-deploy/tests/30-pvc-pending-injection.sh
sudo RUN_STORAGE_FAILURE_TESTS=1 /opt/fortify-deploy/tests/31-disk-headroom-injection.sh
```

### PVC Pending cleanup
The test creates only `fortify-test-pending-pvc`, with a nonexistent StorageClass. A trap deletes this PVC on success, failure, Ctrl+C, or termination. Safe manual cleanup:

```bash
kubectl -n fortify delete pvc fortify-test-pending-pvc --ignore-not-found --wait=true
kubectl -n fortify get pvc
```

Never delete real Fortify PVCs during this test.

### DiskPressure cleanup
The safe test injects failure by setting the required free-space threshold one GiB above current free space. It does not allocate storage, create a fill file, or alter kubelet eviction settings, so no filesystem cleanup is required. The test reruns the gate with a one-GiB threshold to verify recovery. Do not use `fallocate`, `dd`, or manual containerd snapshot deletion on the Fortify VM.
DOC
for f in "$TARGET"/bin/fortify-lab "$TARGET"/lib/*.sh "$TARGET"/tests/*.sh; do bash -n "$f"; done
echo 'fcli and storage failure-injection tests applied.'
