#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"
PACKAGE_DIR="$SCRIPT_DIR"
WORK=${WORK:-$SCRIPT_DIR/v12-build}
OUT=${OUT:-$SCRIPT_DIR/dist}

[[ -d "$SCRIPT_DIR/assets" ]] || { echo "ERROR: Missing assets directory under $SCRIPT_DIR" >&2; exit 1; }
[[ -d "$SCRIPT_DIR/tests" ]] || { echo "ERROR: Missing tests directory under $SCRIPT_DIR" >&2; exit 1; }

echo
echo "Builder directory:"
echo "  $SCRIPT_DIR"
echo
echo "Package directory:"
echo "  $PACKAGE_DIR"
echo
echo "Files detected:"
find "$PACKAGE_DIR" -maxdepth 1 -type f -printf '  %f\n' | sort
echo
ROOT_NAME=fortify-lab-toolkit-v12
ZIP_NAME=fortify-lab-toolkit-v12-foundation.zip
TAR_NAME=fortify-lab-toolkit-v12-foundation.tar.gz

STEMS=(
  fortify-lab-toolkit-v7
  fortify-github-addon-v8
  fortify-recovery-addon-v9
  fortify-validation-addon-v10
  fortify-guided-lifecycle-addon-v11
)

fatal(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

find_package(){
  local stem=$1 zip="$PACKAGE_DIR/$stem.zip" tgz="$PACKAGE_DIR/$stem.tar.gz"
  local have_zip=0 have_tgz=0
  [[ -f "$zip" ]] && have_zip=1
  [[ -f "$tgz" ]] && have_tgz=1
  if (( have_zip && have_tgz )); then
    fatal "Duplicate package formats found for $stem. Keep exactly one of: $stem.zip or $stem.tar.gz"
  elif (( have_zip )); then
    printf '%s\n' "$zip"
  elif (( have_tgz )); then
    printf '%s\n' "$tgz"
  else
    fatal "Missing required package $stem. Expected exactly one of: $stem.zip or $stem.tar.gz in $PACKAGE_DIR"
  fi
}

validate_archive(){
  local archive=$1
  [[ -s "$archive" ]] || fatal "Archive is empty: $archive"
  case "$archive" in
    *.zip) unzip -tq "$archive" >/dev/null || fatal "Invalid ZIP archive: $archive";;
    *.tar.gz) tar -tzf "$archive" >/dev/null || fatal "Invalid TAR.GZ archive: $archive";;
    *) fatal "Unsupported archive format: $archive";;
  esac
}

extract_archive(){
  local archive=$1 destination=$2
  mkdir -p "$destination"
  case "$archive" in
    *.zip) unzip -q "$archive" -d "$destination";;
    *.tar.gz) tar -xzf "$archive" -C "$destination";;
    *) fatal "Unsupported archive format during extraction: $archive";;
  esac
}

validate_expected_root(){
  local archive=$1 destination=$2 expected=$3
  [[ -d "$destination/$expected" ]] || {
    printf 'Archive contents for %s:\n' "$archive" >&2
    find "$destination" -mindepth 1 -maxdepth 2 -printf '  %P\n' >&2 || true
    fatal "Package $archive did not extract expected root directory: $expected"
  }
}

render_template(){
  local template=$1 output=$2 format=$3 archive=$4 command=$5 block=$6
  python3 - "$template" "$output" "$format" "$archive" "$command" "$block" <<'PY'
import pathlib, sys
src, out, fmt, archive, command, block = sys.argv[1:]
text = pathlib.Path(src).read_text()
for key, value in {
    '{{PACKAGE_FORMAT}}': fmt,
    '{{ARCHIVE_NAME}}': archive,
    '{{EXTRACT_COMMAND}}': command,
    '{{EXTRACTION_BLOCK}}': block,
}.items():
    text = text.replace(key, value)
if '{{' in text or '}}' in text:
    raise SystemExit(f'Unresolved template token in {src}')
pathlib.Path(out).write_text(text)
PY
}

scan_wrong_format_references(){
  local tree=$1 forbidden=$2
  local hit
  hit=$(grep -RInF --exclude='*.pdf' --exclude='*.png' --exclude='*.jpg' --exclude='*.zip' --exclude='*.gz' "$forbidden" "$tree" || true)
  [[ -z "$hit" ]] || { printf '%s\n' "$hit" >&2; fatal "Wrong-format archive reference found: $forbidden"; }
}

# Discover exactly one format for every required input.
declare -A PKG
for stem in "${STEMS[@]}"; do
  PKG["$stem"]=$(find_package "$stem")
  validate_archive "${PKG[$stem]}"
done

printf '\nDetected and validated input packages\n=====================================\n'
for stem in "${STEMS[@]}"; do printf '  %-38s %s\n' "$stem" "$(basename "${PKG[$stem]}")"; done
printf '\n'

rm -rf "$WORK"
mkdir -p "$WORK/source" "$OUT"

# Extract each input into an isolated area first, validate its root, then merge.
for stem in "${STEMS[@]}"; do
  stage="$WORK/extracted/$stem"
  extract_archive "${PKG[$stem]}" "$stage"
  validate_expected_root "${PKG[$stem]}" "$stage" "$stem"
  cp -a "$stage/$stem" "$WORK/source/"
done

TARGET="$WORK/source/fortify-lab-toolkit-v7"
"$WORK/source/fortify-github-addon-v8/apply-to-v7.sh" "$TARGET"
"$WORK/source/fortify-recovery-addon-v9/apply-to-v7.sh" "$TARGET"
"$WORK/source/fortify-validation-addon-v10/apply-to-v7.sh" "$TARGET"
"$WORK/source/fortify-guided-lifecycle-addon-v11/apply-to-v7.sh" "$TARGET"
printf '12.0.0-foundation\n' > "$TARGET/VERSION"

[[ -x "$TARGET/tests/run-tests.sh" ]] && (cd "$TARGET" && ./tests/run-tests.sh)
[[ -x "$WORK/source/fortify-recovery-addon-v9/tests/recovery-static-test.sh" ]] && "$WORK/source/fortify-recovery-addon-v9/tests/recovery-static-test.sh" "$TARGET"
[[ -x "$WORK/source/fortify-guided-lifecycle-addon-v11/tests/guided-static-test.sh" ]] && "$WORK/source/fortify-guided-lifecycle-addon-v11/tests/guided-static-test.sh" "$TARGET"

rm -f "$OUT/$ZIP_NAME" "$OUT/$TAR_NAME" "$OUT/SHA256SUMS"

ZIP_TREE="$WORK/output-zip/$ROOT_NAME"
mkdir -p "$(dirname "$ZIP_TREE")"; cp -a "$TARGET" "$ZIP_TREE"
ZIP_BLOCK=$'```bash\nunzip '"$ZIP_NAME"$'\ncd '"$ROOT_NAME"$'\nsudo ./install.sh\n```'
render_template "$SCRIPT_DIR/assets/QUICK_START-template.md" "$ZIP_TREE/QUICK_START.md" ZIP "$ZIP_NAME" "unzip $ZIP_NAME" "$ZIP_BLOCK"
printf 'ZIP\n' > "$ZIP_TREE/PACKAGE_FORMAT"; printf '%s\n' "$ZIP_NAME" > "$ZIP_TREE/SOURCE_ARCHIVE"
scan_wrong_format_references "$ZIP_TREE" "$TAR_NAME"
(cd "$WORK/output-zip" && zip -qr "$OUT/$ZIP_NAME" "$ROOT_NAME")

TAR_TREE="$WORK/output-tar/$ROOT_NAME"
mkdir -p "$(dirname "$TAR_TREE")"; cp -a "$TARGET" "$TAR_TREE"
TAR_BLOCK=$'```bash\ntar -xzf '"$TAR_NAME"$'\ncd '"$ROOT_NAME"$'\nsudo ./install.sh\n```'
render_template "$SCRIPT_DIR/assets/QUICK_START-template.md" "$TAR_TREE/QUICK_START.md" TAR.GZ "$TAR_NAME" "tar -xzf $TAR_NAME" "$TAR_BLOCK"
printf 'TAR.GZ\n' > "$TAR_TREE/PACKAGE_FORMAT"; printf '%s\n' "$TAR_NAME" > "$TAR_TREE/SOURCE_ARCHIVE"
scan_wrong_format_references "$TAR_TREE" "$ZIP_NAME"
(cd "$WORK/output-tar" && tar -czf "$OUT/$TAR_NAME" "$ROOT_NAME")

# End-to-end verification of finished outputs.
unzip -tq "$OUT/$ZIP_NAME" >/dev/null
tar -tzf "$OUT/$TAR_NAME" >/dev/null
unzip -p "$OUT/$ZIP_NAME" "$ROOT_NAME/QUICK_START.md" | grep -Fq "unzip $ZIP_NAME"
! unzip -p "$OUT/$ZIP_NAME" "$ROOT_NAME/QUICK_START.md" | grep -Fq "$TAR_NAME"
tar -xOf "$OUT/$TAR_NAME" "$ROOT_NAME/QUICK_START.md" | grep -Fq "tar -xzf $TAR_NAME"
! tar -xOf "$OUT/$TAR_NAME" "$ROOT_NAME/QUICK_START.md" | grep -Fq "$ZIP_NAME"
[[ "$(unzip -p "$OUT/$ZIP_NAME" "$ROOT_NAME/PACKAGE_FORMAT")" == ZIP ]]
[[ "$(tar -xOf "$OUT/$TAR_NAME" "$ROOT_NAME/PACKAGE_FORMAT")" == TAR.GZ ]]
sha256sum "$OUT/$ZIP_NAME" "$OUT/$TAR_NAME" > "$OUT/SHA256SUMS"
printf 'Build passed. Outputs: %s and %s\n' "$OUT/$ZIP_NAME" "$OUT/$TAR_NAME"
