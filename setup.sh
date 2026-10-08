#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILDER_DIR="$ROOT/fortifylab"
BUILD_SCRIPT="$BUILDER_DIR/build-v12.sh"
DIST_DIR="$BUILDER_DIR/dist"
WORK_DIR="$ROOT/.setup-work"
TAR_ARTIFACT="$DIST_DIR/fortify-lab-toolkit-v12-foundation.tar.gz"
ZIP_ARTIFACT="$DIST_DIR/fortify-lab-toolkit-v12-foundation.zip"
TOOLKIT_ROOT=fortify-lab-toolkit-v12

STEMS=(
  fortify-lab-toolkit-v7
  fortify-github-addon-v8
  fortify-recovery-addon-v9
  fortify-validation-addon-v10
  fortify-guided-lifecycle-addon-v11
)

fatal() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '\n==> %s\n' "$*"
}

pause() {
  read -r -p "Press Enter to continue..." _
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fatal "Required command not found: $1"
}

validate_repository() {
  [[ -d "$BUILDER_DIR" ]] || fatal "Builder directory not found: $BUILDER_DIR"
  [[ -f "$BUILD_SCRIPT" ]] || fatal "Build script not found: $BUILD_SCRIPT"
  [[ -d "$BUILDER_DIR/assets" ]] || fatal "Builder assets directory not found"
  [[ -d "$BUILDER_DIR/tests" ]] || fatal "Builder tests directory not found"

  require_command bash
  require_command tar
  require_command unzip
  require_command zip
  require_command python3
  require_command sha256sum
}

find_input_archive() {
  local stem=$1
  local candidates=()
  local directory extension candidate

  for directory in \
    "$BUILDER_DIR" \
    "$ROOT" \
    "$ROOT/fortifylab-complete"
  do
    for extension in .tar.gz .zip; do
      candidate="$directory/$stem$extension"
      [[ -f "$candidate" ]] && candidates+=("$candidate")
    done
  done

  if (( ${#candidates[@]} == 0 )); then
    fatal "Missing build input $stem. Expected one .tar.gz or .zip archive under the repository root, fortifylab/, or fortifylab-complete/."
  fi

  # Prefer an archive already located in the builder directory. Otherwise,
  # require exactly one source candidate to avoid silently choosing stale data.
  for candidate in "${candidates[@]}"; do
    if [[ $(dirname "$candidate") == "$BUILDER_DIR" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if (( ${#candidates[@]} > 1 )); then
    printf 'Multiple candidates found for %s:\n' "$stem" >&2
    printf '  %s\n' "${candidates[@]}" >&2
    fatal "Remove stale duplicates or place the intended archive in $BUILDER_DIR"
  fi

  printf '%s\n' "${candidates[0]}"
}

prepare_build_inputs() {
  local stem source target

  info "Preparing build inputs"

  for stem in "${STEMS[@]}"; do
    source=$(find_input_archive "$stem")
    target="$BUILDER_DIR/$(basename "$source")"

    if [[ "$source" != "$target" ]]; then
      cp -f "$source" "$target"
      printf 'Copied %s -> fortifylab/%s\n' "$(basename "$source")" "$(basename "$target")"
    else
      printf 'Found  %s\n' "$(basename "$source")"
    fi
  done
}

verify_inputs() {
  validate_repository
  prepare_build_inputs
  info "Verifying package archives"
  (cd "$BUILDER_DIR" && bash ./build-v12.sh --verify)
}

run_builder_tests() {
  validate_repository
  info "Running builder tests"
  (cd "$BUILDER_DIR" && bash ./tests/run-builder-tests.sh)
}

build_toolkit() {
  validate_repository
  prepare_build_inputs
  info "Building Fortify Lab Toolkit v12"
  (cd "$BUILDER_DIR" && bash ./build-v12.sh)

  [[ -s "$TAR_ARTIFACT" ]] || fatal "Expected TAR.GZ output was not created: $TAR_ARTIFACT"
  [[ -s "$ZIP_ARTIFACT" ]] || fatal "Expected ZIP output was not created: $ZIP_ARTIFACT"

  printf '\nBuild outputs:\n  %s\n  %s\n' "$TAR_ARTIFACT" "$ZIP_ARTIFACT"
}

extract_built_toolkit() {
  [[ -s "$TAR_ARTIFACT" ]] || build_toolkit

  rm -rf "$WORK_DIR"
  mkdir -p "$WORK_DIR"
  tar -xzf "$TAR_ARTIFACT" -C "$WORK_DIR"

  [[ -f "$WORK_DIR/$TOOLKIT_ROOT/install.sh" ]] || \
    fatal "Built package did not contain $TOOLKIT_ROOT/install.sh"

  # Protect against executable bits lost when content originated on Windows.
  find "$WORK_DIR/$TOOLKIT_ROOT" -type f -name '*.sh' -exec chmod +x {} +
  [[ -f "$WORK_DIR/$TOOLKIT_ROOT/bin/fortify-lab" ]] && \
    chmod +x "$WORK_DIR/$TOOLKIT_ROOT/bin/fortify-lab"
}

install_toolkit() {
  validate_repository
  extract_built_toolkit

  info "Installing Fortify Lab Toolkit"
  sudo bash "$WORK_DIR/$TOOLKIT_ROOT/install.sh"

  command -v fortify-lab >/dev/null 2>&1 || \
    fatal "Installation completed but fortify-lab was not found in PATH"

  printf '\nInstallation complete. Launch with: sudo fortify-lab menu\n'
}

launch_toolkit_menu() {
  command -v fortify-lab >/dev/null 2>&1 || \
    fatal "fortify-lab is not installed. Choose Build and install first."

  info "Launching Fortify Lab menu"
  sudo fortify-lab menu
}

build_install_launch() {
  build_toolkit
  install_toolkit
  launch_toolkit_menu
}

show_status() {
  echo
  echo "Repository : $ROOT"
  echo "Builder    : $BUILDER_DIR"
  echo "TAR output : $TAR_ARTIFACT"
  echo "ZIP output : $ZIP_ARTIFACT"
  echo

  if command -v fortify-lab >/dev/null 2>&1; then
    echo "Installed  : yes ($(command -v fortify-lab))"
  else
    echo "Installed  : no"
  fi

  [[ -s "$TAR_ARTIFACT" ]] && echo "TAR built  : yes" || echo "TAR built  : no"
  [[ -s "$ZIP_ARTIFACT" ]] && echo "ZIP built  : yes" || echo "ZIP built  : no"
}

clean_generated() {
  info "Removing generated build and setup work directories"
  rm -rf "$BUILDER_DIR/v12-build" "$WORK_DIR"
  echo "Kept release files under $DIST_DIR."
}

print_menu() {
  clear 2>/dev/null || true
  cat <<'MENU'
============================================================
 Fortify Lab Setup
============================================================

1) Build, install, and launch the Fortify Lab menu
2) Verify embedded build-input archives
3) Run builder tests
4) Build v12 foundation packages only
5) Install the latest locally built v12 package
6) Launch the installed Fortify Lab menu
7) Show setup status
8) Clean temporary build files
0) Exit

Recommended first-time path: option 1
MENU
}

main_menu() {
  while true; do
    print_menu
    read -r -p "Select an option: " choice

    case "$choice" in
      1) build_install_launch; pause ;;
      2) verify_inputs; pause ;;
      3) run_builder_tests; pause ;;
      4) build_toolkit; pause ;;
      5) install_toolkit; pause ;;
      6) launch_toolkit_menu; pause ;;
      7) show_status; pause ;;
      8) clean_generated; pause ;;
      0) echo "Exiting."; exit 0 ;;
      *) echo "Invalid selection: $choice"; pause ;;
    esac
  done
}

case "${1:-}" in
  --help|-h)
    cat <<'HELP'
Fortify Lab repository setup wizard

Usage:
  ./setup.sh                 Open the interactive setup menu
  ./setup.sh --all           Build, install, and launch the toolkit menu
  ./setup.sh --verify        Verify required component archives
  ./setup.sh --test          Run builder tests
  ./setup.sh --build         Build v12 packages only
  ./setup.sh --install       Install the latest locally built package
  ./setup.sh --menu          Launch the installed Fortify Lab menu
  ./setup.sh --status        Show local build/install status
  ./setup.sh --clean         Remove temporary build files
  ./setup.sh --help          Show this help

Run setup.sh as a normal user. The script requests sudo only for installation
and for launching the installed Fortify Lab administration menu.
HELP
    ;;
  --all) build_install_launch ;;
  --verify) verify_inputs ;;
  --test) run_builder_tests ;;
  --build) build_toolkit ;;
  --install) install_toolkit ;;
  --menu) launch_toolkit_menu ;;
  --status) show_status ;;
  --clean) clean_generated ;;
  '') main_menu ;;
  *) fatal "Unknown option: ${1:-}" ;;
esac
