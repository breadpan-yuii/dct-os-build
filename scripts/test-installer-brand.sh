#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test-installer-brand.sh — exercise payload/installer/dct-installer-brand
# without root and without the installer snap.
#
# Builds a fake snap tree with placeholder artwork, runs the real script in a
# user namespace (so the mounts are allowed), then checks that the six artwork
# files were replaced, that everything else in the snap survived, and that the
# launcher was rewritten.
#
#   ./scripts/test-installer-brand.sh
#
# Needs `unshare` with user namespaces (default on Ubuntu 24.04). Nothing
# outside $TMPDIR is touched.
# ---------------------------------------------------------------------------
set -euo pipefail

# The mounts only exist inside one mount namespace, so re-exec the whole test
# (setup, run, assertions) inside it.
if [ "${DCT_TEST_IN_NS:-0}" != 1 ]; then
    exec unshare -rm env DCT_TEST_IN_NS=1 bash "$0" "$@"
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SCRIPT="$REPO/payload/installer/dct-installer-brand"
ART="$REPO/payload/installer"

TMP="${TMPDIR:-/tmp}/dct-installer-test.$$"
SNAP="$TMP/snap/ubuntu-desktop-bootstrap/680"
ASSETS="$SNAP/bin/data/flutter_assets/packages/ubuntu_provision/assets"
DESKTOP_DIR="$TMP/snapd/desktop/applications"

cleanup() {
    # Lazy-unmount what the script mounted, or rm trips over the busy paths.
    umount -l "$TMP/run/merged" 2>/dev/null || true
    umount -l "$SNAP" 2>/dev/null || true
    umount -l "$TMP/run/lower" 2>/dev/null || true
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT

fail=0
pass() { printf '\033[1;32m PASS\033[0m %s\n' "$*"; }
bad()  { printf '\033[1;31m FAIL\033[0m %s\n' "$*"; fail=1; }

# --- fake snap ------------------------------------------------------------
mkdir -p "$ASSETS/images" "$ASSETS/theme" "$DESKTOP_DIR" "$TMP/run"
ln -s 680 "$TMP/snap/ubuntu-desktop-bootstrap/current"
for f in logo-light.svg logo-dark.svg mascot.svg mascot_no_background.svg; do
    echo 'ubuntu-original' > "$ASSETS/images/$f"
done
for f in light-theme.png dark-theme.png; do
    echo 'ubuntu-original' > "$ASSETS/theme/$f"
done
# Files that must survive the overlay untouched.
echo 'whitelabel' > "$ASSETS/whitelabel.yml"
echo 'binary' > "$SNAP/bin/ubuntu_bootstrap"

cat > "$DESKTOP_DIR/ubuntu-desktop-bootstrap_ubuntu-desktop-bootstrap.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Install RELEASE
Exec=ubuntu-desktop-bootstrap
Icon=ubiquity
NoDisplay=true
EOF

# --- run the real script in a private mount namespace ---------------------
echo "running $SCRIPT in a user namespace"
env \
    DCT_SNAP_ROOT="$TMP/snap" \
    DCT_INSTALLER_ASSETS="$ART" \
    DCT_INSTALLER_RUN="$TMP/run" \
    DCT_INSTALLER_DESKTOP_DIR="$DESKTOP_DIR" \
    sh "$SCRIPT"

# --- assertions -----------------------------------------------------------
for f in logo-light.svg logo-dark.svg mascot.svg mascot_no_background.svg; do
    cmp -s "$ART/$f" "$ASSETS/images/$f" \
        && pass "images/$f replaced" \
        || bad "images/$f not replaced"
done
for f in light-theme.png dark-theme.png; do
    cmp -s "$ART/$f" "$ASSETS/theme/$f" \
        && pass "theme/$f replaced" \
        || bad "theme/$f not replaced"
done

[ "$(cat "$ASSETS/whitelabel.yml")" = whitelabel ] \
    && pass "whitelabel.yml untouched" || bad "whitelabel.yml was damaged"
[ "$(cat "$SNAP/bin/ubuntu_bootstrap")" = binary ] \
    && pass "rest of the snap untouched" || bad "rest of the snap was damaged"

grep -q '^Name=Install DCT OS$' "$DESKTOP_DIR/ubuntu-desktop-bootstrap_ubuntu-desktop-bootstrap.desktop" \
    && pass "launcher renamed" || bad "launcher name not changed"
grep -q '^Icon=dct-os$' "$DESKTOP_DIR/ubuntu-desktop-bootstrap_ubuntu-desktop-bootstrap.desktop" \
    && pass "launcher icon set" || bad "launcher icon not changed"
grep -q '^NoDisplay=' "$DESKTOP_DIR/ubuntu-desktop-bootstrap_ubuntu-desktop-bootstrap.desktop" \
    && bad "launcher still hidden" || pass "launcher visible"

# Upper layer must stay small: only the six files are copied up.
upper_kb=$(du -sk "$TMP/run/upper" | cut -f1)
[ "$upper_kb" -lt 512 ] \
    && pass "upper layer is small (${upper_kb}K)" \
    || bad "upper layer is ${upper_kb}K — too much was copied up"

echo
if [ "$fail" -eq 0 ]; then
    echo "all installer-brand checks passed"
else
    echo "installer-brand checks FAILED" >&2
fi
exit "$fail"
