# Fortify Lab Lifecycle Manager

Self-contained, menu-driven lifecycle toolkit for a single Ubuntu VM running Docker-hosted SQL Server, K3s, Helm, OpenEBS, LIM, SSC, ScanCentral SAST, and ScanCentral DAST.

## Install

```bash
sudo ./install.sh
sudo fortify-lab menu
```

## Recommended first-run order

```bash
sudo fortify-lab preflight
sudo fortify-lab prerequisites install
sudo fortify-lab configure
sudo fortify-lab secrets init
sudo fortify-lab versions discover
sudo fortify-lab versions lock 26.2
sudo fortify-lab install all
```

## Lifecycle commands

```bash
sudo fortify-lab health
sudo fortify-lab repair all
sudo fortify-lab repair ssc
sudo fortify-lab update check
sudo fortify-lab update plan all
sudo fortify-lab update apply all
sudo fortify-lab rollback ssc 2
sudo fortify-lab recover
sudo fortify-lab backup
```

## Security

Secrets are encrypted locally with `age`. The identity is stored at `/etc/fortify-deploy/age.key` with root-only permissions. Encrypted data is stored at `/opt/fortify-deploy/config/secrets.env.age`. Plaintext secret work files use `/dev/shm` and are removed after use.

## Important scope

This is a single-node lab/demo framework, not a production HA design. The generated values are intentionally minimal and must be compared with the exact `values.yaml` and `values.schema.json` of each selected Fortify chart. The version lock and chart cache make repair reproducible.

## Current implementation status

Implemented: menu, local config, encrypted secrets, prerequisite installation, Docker Hub version discovery, common release-family locking, component install/repair/update/rollback orchestration, health checks, post-reboot recovery, and local backups.

Environment-specific certificate generation, complete SSC autoconfig generation, SQL database/user creation, and every chart-version schema mapping remain guarded extension points. Review generated values before deployment.

## Guarded workflows

```bash
sudo fortify-lab certificates generate
sudo fortify-lab certificates import
sudo fortify-lab certificates validate
sudo fortify-lab certificates sync

sudo fortify-lab database init
sudo fortify-lab database validate
sudo fortify-lab database backup

sudo fortify-lab ssc prepare
sudo fortify-lab ssc validate

sudo fortify-lab licensing prepare
sudo fortify-lab licensing verify
```

The database workflow creates or repairs SSC and DAST databases and principals without dropping existing application tables. Certificate workflows verify certificate/key matching and required secret keys. SSC preparation generates the dual `jdbc.*` and `db.*` autoconfig properties, then creates license, autoconfig, and certificate secrets. LIM licensing remains intentionally guided because the supplied runbooks document activation, product-license entry, pool creation, and assignment through the LIM UI rather than a supported automation API.

## Strict stage-gated deployment and resume

The full installation now uses durable stage state in:

```text
/opt/fortify-deploy/state/deployment-state.tsv
```

Run or resume safely:

```bash
sudo fortify-lab workflow run
sudo fortify-lab workflow resume
sudo fortify-lab workflow status
sudo fortify-lab workflow reset certificates
sudo fortify-lab workflow verify database
```

Stages advance only after verification: strict host preflight, prerequisites, configuration, encrypted secrets, version lock, infrastructure, certificates, SQL Server/databases, LIM, manual licensing, SSC, SAST, DAST Core, DAST Scanner, and final validation. Interruptions are marked `INTERRUPTED`; successful stages are skipped on resume. LIM licensing is a mandatory `MANUAL_PENDING` gate until `sudo fortify-lab licensing verify` marks it passed.

## Fortify license attended gate

Before certificates, SSC, or ScanCentral SAST deployment, the workflow pauses if a local `fortify.license` has not been imported. Copy the license file onto the VM using SCP, SFTP, VMware shared folders, or another attended method, then select **Import/validate fortify.license** or run:

```bash
sudo fortify-lab license import /local/path/fortify.license
sudo fortify-lab license validate
sudo fortify-lab license sync
sudo fortify-lab workflow resume
```

The toolkit stores the file locally as `/opt/fortify-deploy/config/license/fortify.license` with root-only permissions, saves a SHA-256 checksum, creates the `ssc-license` Kubernetes Secret, and verifies that the Secret content checksum matches the local file. SSC receives the license Secret. ScanCentral SAST receives the same local license with the chart's documented `secrets.fortifyLicense` set-file value. The SSC and SAST stages also hard-stop if startup logs report common invalid, expired, missing, or unreadable license errors.

## Automatic local hostname and /etc/hosts management

The configuration wizard defaults the deployment name and VM hostname from `hostname -s`, lowercases the value, and derives local lab names such as:

```text
ssc.scancentral.lab
lim.scancentral.lab
sast.scancentral.lab
dast.scancentral.lab
```

The strict workflow includes a `hostname-resolution` gate. It can update the Ubuntu hostname through `hostnamectl`, adds an idempotent managed block to `/etc/hosts`, and verifies every name using `getent ahostsv4` before continuing. Existing `/etc/hosts` is backed up before modification.

```bash
sudo fortify-lab hosts show
sudo fortify-lab hosts apply
sudo fortify-lab hosts verify
sudo fortify-lab hosts remove
```

The toolkit also writes `/opt/fortify-deploy/generated/hosts-file.txt` for copying to the workstation hosts file. The VM's `/etc/hosts` affects only the Ubuntu VM; browsers on a separate Windows, macOS, or Linux workstation need equivalent local hosts entries.

## Namespace-based local hostnames

The attended configuration prompts for:

```text
Kubernetes namespace [fortify]:
Local domain suffix [com]:
```

The defaults produce:

```text
ssc.fortify.com
lim.fortify.com
sast.fortify.com
dast.fortify.com
```

Before editing `/etc/hosts`, the toolkit scans the entire file. A missing name is added. A single existing entry with the expected VM IP is preserved. Conflicting IPs or duplicate hostname definitions are hard failures and must be corrected before deployment. The same four hostnames are included in generated certificate SANs and checked again by the strict hostname-resolution gate.

## Test scripts

```bash
./tests/run-tests.sh
sudo RUN_DESTRUCTIVE_TESTS=1 /opt/fortify-deploy/tests/10-ubuntu-integration.sh
sudo RUN_PLATFORM_TESTS=1 /opt/fortify-deploy/tests/20-platform-validation.sh
```

See `TEST_PLAN.md` for safe, integration, platform-certification, and failure-injection tests. Test logs are written under `test-results/<timestamp>/`.
