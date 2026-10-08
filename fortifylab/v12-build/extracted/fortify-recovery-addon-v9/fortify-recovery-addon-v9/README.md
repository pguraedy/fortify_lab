# Fortify Toolkit Reboot-Recovery Hardening Add-on

Apply to an extracted v7 toolkit:

```bash
./fortify-recovery-addon-v9/apply-to-v7.sh ./fortify-lab-toolkit
cd fortify-lab-toolkit
./tests/run-tests.sh
../fortify-recovery-addon-v9/tests/recovery-static-test.sh .
```

## Added behavior

- Docker and K3s service gates
- K3s node Ready gate
- OpenEBS pod and StorageClass gate
- all-PVCs-Bound gate
- SQL Server readiness gate
- conservative stale-pod recreation only for known runtime failures or states older than 600 seconds
- strict application recovery order
- persisted LIM and ScanCentral SAST startup probes through Helm values
- live StatefulSet startup-probe verification
- boot-time read-only health service that never deletes pods or runs Helm

The boot service records warnings and instructs the operator to run `sudo fortify-lab recover`. It returns success so a lab VM can finish booting even when Fortify needs attended repair.
