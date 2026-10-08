# Ubuntu Validation Test Plan

## Safe tests

Run before copying the toolkit to a target VM:

```bash
./tests/run-tests.sh
```

This performs Bash syntax checks, command-dispatch smoke tests, sandboxed namespace hostname and `/etc/hosts` conflict tests, and durable resume-state tests. It does not install or modify Ubuntu services.

## Ubuntu integration tests

After installing and configuring the toolkit on a disposable Ubuntu VM:

```bash
sudo RUN_DESTRUCTIVE_TESTS=1 /opt/fortify-deploy/tests/10-ubuntu-integration.sh
```

This verifies Ubuntu, Docker, K3s, Helm, `/etc/hosts`, hostname resolution, and node readiness. It reads the live configuration.

## Platform certification

After the complete attended deployment reaches final validation:

```bash
sudo RUN_PLATFORM_TESTS=1 /opt/fortify-deploy/tests/20-platform-validation.sh
```

This verifies every durable workflow stage is `PASS`, checks for known unhealthy pod states, and validates local hostname resolution.

## Failure-injection tests

Perform on a disposable VM or after taking a VM snapshot:

1. Add a conflicting `ssc.<namespace>.com` entry and verify `fortify-lab hosts precheck` fails.
2. Add a duplicate hostname entry and verify the precheck fails.
3. Stop the workflow during a component stage and verify that the state becomes `INTERRUPTED` and resume selects that stage.
4. Temporarily remove the license file and verify the `license-file` gate stops.
5. Use a mismatched certificate and key and verify certificate import stops.
6. Stop SQL Server and verify the database gate stops.
7. Leave LIM licensing incomplete and verify SSC/DAST do not advance past `MANUAL_PENDING`.
8. Create a pod in `CrashLoopBackOff` and verify final validation fails.
9. Reduce free disk below the configured threshold and verify preflight or upgrade stops.
10. Reboot the VM after full deployment and run `fortify-lab recover`, then platform validation.

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
