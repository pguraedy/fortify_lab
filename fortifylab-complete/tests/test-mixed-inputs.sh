#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PKG="$TMP/packages"; mkdir -p "$PKG"

make_tree(){
  local stem=$1
  mkdir -p "$TMP/src/$stem"
  case "$stem" in
    fortify-lab-toolkit-v7)
      mkdir -p "$TMP/src/$stem/tests" "$TMP/src/$stem/lib" "$TMP/src/$stem/bin"
      cat > "$TMP/src/$stem/tests/run-tests.sh" <<'SH'
#!/usr/bin/env bash
set -e
echo safe-tests-pass
SH
      chmod +x "$TMP/src/$stem/tests/run-tests.sh"
      cat > "$TMP/src/$stem/install.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
      chmod +x "$TMP/src/$stem/install.sh"
      ;;
    *)
      cat > "$TMP/src/$stem/apply-to-v7.sh" <<'SH'
#!/usr/bin/env bash
set -e
TARGET=$1
printf '%s\n' "$(basename "$(dirname "$0")")" >> "$TARGET/applied-addons.txt"
SH
      chmod +x "$TMP/src/$stem/apply-to-v7.sh"
      if [[ "$stem" == fortify-recovery-addon-v9 || "$stem" == fortify-guided-lifecycle-addon-v11 ]]; then
        mkdir -p "$TMP/src/$stem/tests"
        name=recovery-static-test.sh; [[ "$stem" == fortify-guided-lifecycle-addon-v11 ]] && name=guided-static-test.sh
        cat > "$TMP/src/$stem/tests/$name" <<'SH'
#!/usr/bin/env bash
set -e
[[ -d "$1" ]]
SH
        chmod +x "$TMP/src/$stem/tests/$name"
      fi
      ;;
  esac
}
pack_zip(){ local stem=$1; (cd "$TMP/src" && zip -qr "$PKG/$stem.zip" "$stem"); }
pack_tgz(){ local stem=$1; (cd "$TMP/src" && tar -czf "$PKG/$stem.tar.gz" "$stem"); }

stems=(fortify-lab-toolkit-v7 fortify-github-addon-v8 fortify-recovery-addon-v9 fortify-validation-addon-v10 fortify-guided-lifecycle-addon-v11)
for s in "${stems[@]}"; do make_tree "$s"; done
# Intentionally mixed formats.
pack_tgz fortify-lab-toolkit-v7
pack_zip fortify-github-addon-v8
pack_tgz fortify-recovery-addon-v9
pack_zip fortify-validation-addon-v10
pack_tgz fortify-guided-lifecycle-addon-v11

BUILDER="$TMP/fortifylab"
cp -a "$ROOT" "$BUILDER"
cp "$PKG"/* "$BUILDER/"
WORK="$TMP/work" OUT="$TMP/out" "$BUILDER/build-v12.sh"
[[ -s "$TMP/out/fortify-lab-toolkit-v12-foundation.zip" ]]
[[ -s "$TMP/out/fortify-lab-toolkit-v12-foundation.tar.gz" ]]
unzip -p "$TMP/out/fortify-lab-toolkit-v12-foundation.zip" fortify-lab-toolkit-v12/applied-addons.txt | grep -q fortify-github-addon-v8
tar -xOf "$TMP/out/fortify-lab-toolkit-v12-foundation.tar.gz" fortify-lab-toolkit-v12/applied-addons.txt | grep -q fortify-guided-lifecycle-addon-v11
echo 'PASS: mixed ZIP/TAR.GZ end-to-end build'
