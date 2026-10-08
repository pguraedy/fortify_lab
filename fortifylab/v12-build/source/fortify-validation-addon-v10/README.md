# fcli and Storage Failure-Testing Add-on

- Adds latest stable `fcli` installation to prerequisites using the official GitHub `latest` Linux archive and published SHA-256 file.
- Adds a PVC Pending failure-injection test with automatic trap cleanup.
- Adds a safe DiskPressure/headroom test that allocates no disk space.

Apply after the recovery hardening add-on because the PVC test uses `wait_pvcs_bound` from `recovery-hardened.sh`.
