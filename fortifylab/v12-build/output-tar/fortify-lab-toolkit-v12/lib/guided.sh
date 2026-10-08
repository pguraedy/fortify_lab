#!/usr/bin/env bash
# Guided Lab Lifecycle menu. Uses existing toolkit functions and remains attended.
GUIDED_LOG="$FORTIFY_HOME/logs/guided-lifecycle.log"

guided_run(){ local label=$1; shift; echo; echo "===== $label =====" | tee -a "$GUIDED_LOG"; "$@" 2>&1 | tee -a "$GUIDED_LOG"; }
guided_require_snapshot(){
  cat <<'TXT'
Recommended checkpoint
----------------------
Create a VM snapshot before initial deployment, upgrades, recovery testing,
or failure-injection testing. The toolkit cannot create a hypervisor snapshot.
TXT
  confirm 'Confirm that a snapshot exists, or explicitly continue without one?' || return 1
}
guided_check_no_active_scans(){
  echo 'Confirm there are no active SAST or DAST scans before disruptive testing.'
  confirm 'No active scans are running?' || return 1
}

guided_build_lab(){
  need_root; mkdir -p "$(dirname "$GUIDED_LOG")"; touch "$GUIDED_LOG"; chmod 600 "$GUIDED_LOG"
  guided_require_snapshot || return 0
  guided_run 'Strict host preflight' strict_preflight
  guided_run 'Install prerequisites' prerequisites_install
  guided_run 'Validate Git' git --version
  guided_run 'Validate GitHub CLI' gh --version
  guided_run 'Validate fcli' fcli_validate
  echo
  if confirm 'Configure optional GitHub repository integration now?'; then repo_menu; fi
  guided_run 'Configure deployment' configure_interactive
  guided_run 'Precheck and apply local hosts' hosts_apply
  guided_run 'Initialize or edit encrypted secrets' secrets_init
  guided_run 'Discover compatible versions' versions_discover
  versions_lock_interactive
  guided_run 'Import and validate fortify.license' license_import
  case "$(config_get CERTIFICATE_MODE)" in
    self-signed) guided_run 'Generate lab certificates' certificates_generate_self_signed;;
    import) guided_run 'Import certificates' certificates_import;;
    *) die 'CERTIFICATE_MODE must be self-signed or import';;
  esac
  echo
  echo 'Starting the durable strict workflow. Completed stages are skipped.'
  workflow_resume
  echo
  workflow_status
}

guided_validate_lab(){
  need_root
  guided_run 'Workflow state' workflow_status
  guided_run 'Hosts resolution' hosts_verify
  guided_run 'Platform health' health_all
  if [[ -x "$FORTIFY_HOME/tests/20-platform-validation.sh" ]]; then
    guided_run 'Platform certification tests' env RUN_PLATFORM_TESTS=1 FORTIFY_HOME="$FORTIFY_HOME" "$FORTIFY_HOME/tests/20-platform-validation.sh"
  else warn 'Platform validation script is not installed'; fi
}

guided_recover_lab(){
  need_root
  echo 'The boot health check is conservative and does not delete pods or run Helm.'
  guided_run 'Boot health check' boot_health_check
  if confirm 'Run attended dependency-ordered recovery now?'; then
    guided_run 'Attended recovery' recover_all
    guided_validate_lab
  fi
}

guided_resiliency_menu(){
  need_root
  while true; do
    cat <<'MENU'
Resiliency Testing
------------------
1) Run all safe, non-destructive tests
2) PVC Pending storage-gate test
3) Safe DiskPressure/headroom test
4) Run both storage-gate tests
5) Platform certification
6) Show safe cleanup commands
0) Back
MENU
    read -rp 'Select: ' n
    case "$n" in
      1) guided_run 'Safe test suite' "$FORTIFY_HOME/tests/run-tests.sh";;
      2) guided_require_snapshot && guided_check_no_active_scans && guided_run 'PVC Pending test' env RUN_STORAGE_FAILURE_TESTS=1 FORTIFY_HOME="$FORTIFY_HOME" "$FORTIFY_HOME/tests/30-pvc-pending-injection.sh";;
      3) guided_check_no_active_scans && guided_run 'Disk headroom test' env RUN_STORAGE_FAILURE_TESTS=1 FORTIFY_HOME="$FORTIFY_HOME" "$FORTIFY_HOME/tests/31-disk-headroom-injection.sh";;
      4) guided_require_snapshot && guided_check_no_active_scans && guided_run 'Storage failure tests' env RUN_STORAGE_FAILURE_TESTS=1 FORTIFY_HOME="$FORTIFY_HOME" "$FORTIFY_HOME/tests/run-storage-failure-tests.sh";;
      5) guided_validate_lab;;
      6) cat <<'CLEAN'
PVC test cleanup:
  kubectl -n fortify delete pvc fortify-test-pending-pvc --ignore-not-found --wait=true
  kubectl -n fortify get pvc

Disk headroom test cleanup:
  None. The safe test creates no fill file and changes no persistent settings.

Never delete actual Fortify PVCs or containerd snapshot directories.
CLEAN
;;
      0) return;;
      *) warn 'Invalid selection';;
    esac
    pause
  done
}

guided_update_lab(){
  need_root; require_pass final-validation; guided_require_snapshot || return 0
  guided_run 'Repository status' repo_status || true
  if confirm 'Check the toolkit repository for a validated update?'; then repo_update; fi
  guided_run 'Check Fortify component versions' update_check
  update_plan all
  confirm 'Apply the planned Fortify platform update?' && update_apply all
}

guided_backup_lab(){ need_root; guided_run 'Configuration checkpoint' backup_create; guided_run 'Database backup' database_backup; }

guided_admin_menu(){
  while true; do
    cat <<'MENU'
Administration Tools
--------------------
1) Workflow state and resume
2) Hosts management
3) Secrets management
4) License-file management
5) Certificates and PKI
6) LIM licensing
7) SQL Server/database
8) Repository management
9) Component repair
10) Show logs and state locations
0) Back
MENU
    read -rp 'Select: ' n
    case "$n" in
      1) workflow_status; confirm 'Resume workflow?' && workflow_resume;;
      2) hosts_menu;; 3) secrets_menu;; 4) license_menu;; 5) certificates_menu;;
      6) licensing_menu;; 7) database_validate; confirm 'Create a database backup?' && database_backup;;
      8) repo_menu;; 9) c=$(choose_component); repair_component "$c";;
      10) printf '%s\n' "$FORTIFY_HOME/logs" "$FORTIFY_HOME/state" "$FORTIFY_HOME/backups";;
      0) return;; *) warn 'Invalid selection';;
    esac
    pause
  done
}

guided_menu(){
  while true; do
    clear || true
    cat <<'MENU'
Fortify Guided Lab Lifecycle
============================
1) Build a new lab
2) Validate an existing lab
3) Recover lab after VM reboot
4) Test lab resiliency
5) Update toolkit and Fortify platform
6) Back up lab configuration and databases
7) Administration tools
8) Show durable workflow status
0) Exit
MENU
    read -rp 'Select: ' n
    case "$n" in
      1) guided_build_lab;; 2) guided_validate_lab;; 3) guided_recover_lab;;
      4) guided_resiliency_menu;; 5) guided_update_lab;; 6) guided_backup_lab;;
      7) guided_admin_menu;; 8) workflow_status;; 0) return;; *) warn 'Invalid selection';;
    esac
    pause
  done
}
