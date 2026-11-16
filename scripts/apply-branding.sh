#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# apply-branding.sh — turn a stock Ubuntu 24.04 install into DCT OS.
#
# This is the fast iteration loop. Run it on a VM, look at the result, change
# something under payload/, run it again. It is idempotent: running it twice
# produces the same system as running it once.
#
#   sudo ./scripts/apply-branding.sh              # apply to /
#   ./scripts/apply-branding.sh --dry-run         # show what would change
#   sudo ./scripts/apply-branding.sh --root /mnt  # apply into a mounted image
#
# Installed copy (from dct-os-defaults): /usr/share/dct-os/apply-branding.sh
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_DIR="$(cd "$HERE/.." && pwd)"

# Two layouts must work:
#   repo:      scripts/apply-branding.sh     + payload/        (sibling)
#   installed: /usr/share/dct-os/apply-branding.sh + /usr/share/dct-os/payload/
if [ -d "$HERE/payload" ]; then
    PAYLOAD="$HERE/payload"
else
    PAYLOAD="$SELF_DIR/payload"
fi

[ -r "$PAYLOAD/branding/tokens.env" ] || {
    echo "cannot find payload/branding/tokens.env next to $HERE" >&2
    exit 1
}
# shellcheck source=/dev/null
. "$PAYLOAD/branding/tokens.env"

ROOT="/"
DRY=0
DO_GRUB=1
DO_PLYMOUTH=1
DO_INITRAMFS=1
DO_SHIELD=1

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m  xx\033[0m %s\n' "$*" >&2; exit 1; }

run() {
    if [ "$DRY" -eq 1 ]; then printf '     + %s\n' "$*"; else "$@"; fi
}

usage() {
    cat <<'EOF'
usage: apply-branding.sh [options]

  --root DIR      apply into DIR instead of / (for a mounted image/chroot)
  --dry-run       print intended actions, change nothing
  --no-grub       skip GRUB theme + update-grub
  --no-plymouth   skip plymouth theme
  --no-initramfs  skip initramfs rebuild (faster while iterating)
  --no-shield     skip dpkg diversions + apt hook (used by the rebrand hook)
  -h, --help      this text
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --root)        ROOT="${2:?--root needs a value}"; shift 2 ;;
        --dry-run)     DRY=1; shift ;;
        --no-grub)     DO_GRUB=0; shift ;;
        --no-plymouth) DO_PLYMOUTH=0; shift ;;
        --no-initramfs) DO_INITRAMFS=0; shift ;;
        --no-shield)   DO_SHIELD=0; shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             die "unknown argument: $1" ;;
    esac
done

ROOT="${ROOT%/}"
[ -n "$ROOT" ] || ROOT="/"

if [ "$DRY" -eq 0 ] && [ "$ROOT" = "/" ] && [ "$(id -u)" -ne 0 ]; then
    die "run as root (or use --dry-run to preview)"
fi

if [ "$ROOT" != "/" ] && [ ! -d "$ROOT/etc" ]; then
    die "$ROOT does not look like a root filesystem (no $ROOT/etc)"
fi

T="$ROOT"
[ "$ROOT" = "/" ] && T=""    # avoid //etc/... paths when targeting the live root

install_file() {                       # src dst [mode]
    local src="$1" dst="$2" mode="${3:-0644}"
    [ -e "$src" ] || { warn "missing source $src — skipped"; return 0; }
    run install -D -m "$mode" "$src" "$T$dst"
}

# ---------------------------------------------------------------------------
# 0. Update shield
#
# The single biggest risk to a rebranded distro is not the install, it is the
# first `apt upgrade`. Several files we replace are OWNED BY PACKAGES:
#
#   /etc/os-release      base-files
#   /usr/lib/os-release  base-files
#   /etc/lsb-release     base-files
#   /etc/issue(.net)     base-files
#
# dpkg overwrites package-owned files without asking, so a base-files upgrade
# would silently revert the machine to "Ubuntu 24.04 LTS". A diversion fixes
# that at the dpkg layer: base-files keeps upgrading normally, but its copy of
# the file lands at *.dct-orig instead of on top of ours.
#
# Files we create ourselves (themes, wallpapers, schema overrides) are not
# owned by any package, so nothing overwrites them. That is deliberate.
# ---------------------------------------------------------------------------
SHIELDED="/etc/os-release /usr/lib/os-release /etc/lsb-release /etc/issue /etc/issue.net"

branding_update_shield() {
    [ "$DO_SHIELD" -eq 1 ] || { say "update shield (skipped)"; return 0; }
    say "update shield"

    local f
    # --dry-run still shows the dpkg-divert calls, useful on a stock machine.
    if [ "$DRY" -eq 0 ] && ! in_target sh -c 'command -v dpkg-divert >/dev/null 2>&1'; then
        warn "dpkg-divert not found — package upgrades WILL overwrite /etc/os-release"
        return 0
    fi

    for f in $SHIELDED; do
        if [ "$DRY" -eq 1 ]; then
            printf '     + dpkg-divert --package dct-os-defaults --divert %s.dct-orig --add --no-rename %s\n' "$f" "$f"
            continue
        fi
        in_target dpkg-divert --package dct-os-defaults \
            --divert "${f}.dct-orig" --no-rename --add "$f" >/dev/null 2>&1 \
            && ok "diverted $f" \
            || warn "could not divert $f (already diverted?)"
    done

    # Second layer: if a package still manages to clobber a branded file, the
    # apt hook re-applies branding after the transaction finishes.
    if [ -d "$T/etc/apt/apt.conf.d" ] || [ "$DRY" -eq 1 ]; then
        install_file "$PAYLOAD/update/99dct-branding" /etc/apt/apt.conf.d/99dct-branding
        install_file "$PAYLOAD/update/dct-rebrand"    /usr/sbin/dct-rebrand 0755
        ok "apt hook installed (re-applies identity after every apt run)"
    else
        warn "no /etc/apt/apt.conf.d — apt hook not installed"
    fi

    # Self-healing needs the payload on the installed system, not just in the
    # repo. The hook is a no-op if this directory is absent.
    if [ "$DRY" -eq 1 ]; then
        printf '     + cp -a payload/ -> /usr/share/dct-os/payload\n'
        printf '     + cp apply-branding.sh -> /usr/share/dct-os/\n'
    elif [ -d "$T/usr/share/dct-os" ] || [ -d "$T/usr" ]; then
        run install -d -m 0755 "$T/usr/share/dct-os"
        # Do not copy a directory onto itself when re-run from the installed copy.
        src_p="$(readlink -f "$PAYLOAD")"
        dst_p="$(readlink -f "$T/usr/share/dct-os/payload" 2>/dev/null || true)"
        if [ "$src_p" != "$dst_p" ]; then
            run cp -a "$PAYLOAD" "$T/usr/share/dct-os/payload"
        fi
        src_s="$(readlink -f "$HERE/apply-branding.sh")"
        dst_s="$(readlink -f "$T/usr/share/dct-os/apply-branding.sh" 2>/dev/null || true)"
        if [ "$src_s" != "$dst_s" ]; then
            run cp -a "$HERE/apply-branding.sh" "$T/usr/share/dct-os/apply-branding.sh"
        fi
        ok "branding payload staged at /usr/share/dct-os"
    fi
}

# ---------------------------------------------------------------------------
# 1. Identity
# ---------------------------------------------------------------------------
branding_identity() {
    say "identity"
    install_file "$PAYLOAD/identity/os-release"   /etc/os-release
    install_file "$PAYLOAD/identity/lsb-release"  /etc/lsb-release
    install_file "$PAYLOAD/identity/issue"        /etc/issue
    install_file "$PAYLOAD/identity/issue.net"    /etc/issue.net
    install_file "$PAYLOAD/identity/motd"         /etc/motd

    # /usr/lib/os-release is the canonical copy on modern systems; keep both
    # pointing at one file so they cannot drift.
    if [ "$DRY" -eq 0 ]; then
        # relative to /usr/lib, /etc is two levels up: ../../etc/os-release
        ln -sfn ../../etc/os-release "$T/usr/lib/os-release" 2>/dev/null || true
    else
        printf '     + ln -sf ../../etc/os-release /usr/lib/os-release\n'
    fi
    ok "os-release, issue, motd written"
}

# ---------------------------------------------------------------------------
# 2. GRUB theme
# ---------------------------------------------------------------------------
branding_grub() {
    [ "$DO_GRUB" -eq 1 ] || { say "grub (skipped)"; return 0; }
    say "grub"

    run install -d -m 0755 "$T/boot/grub/themes/dct"
    install_file "$PAYLOAD/grub/theme/theme.txt" /boot/grub/themes/dct/theme.txt

    if [ -f "$PAYLOAD/assets/background.png" ]; then
        install_file "$PAYLOAD/assets/background.png" \
                     /boot/grub/themes/dct/background.png
    else
        warn "no payload/assets/background.png — GRUB will use the flat desktop-color"
    fi

    set_grub_key GRUB_DISTRIBUTOR "\"$DCT_NAME\""
    set_grub_key GRUB_THEME       "\"/boot/grub/themes/dct/theme.txt\""

    if [ "$DRY" -eq 0 ]; then
        if in_target command -v update-grub >/dev/null 2>&1; then
            in_target update-grub >/dev/null 2>&1 && ok "grub.cfg regenerated" \
                || warn "update-grub failed (blame: see 'update-grub' output)"
        else
            warn "update-grub not present — skipping (chroot not fully mounted?)"
        fi
    fi
}

set_grub_key() {                       # key value
    local key="$1" val="$2" f="$T/etc/default/grub"
    if [ "$DRY" -eq 1 ]; then
        printf '     + /etc/default/grub: %s=%s\n' "$key" "$val"; return 0
    fi
    [ -f "$f" ] || : > "$f"
    if grep -qE "^[#[:space:]]*${key}=" "$f"; then
        sed -i -E "s|^[#[:space:]]*${key}=.*|${key}=${val}|" "$f"
    else
        printf '%s=%s\n' "$key" "$val" >> "$f"
    fi
}

# ---------------------------------------------------------------------------
# 3. Plymouth splash
# ---------------------------------------------------------------------------
branding_plymouth() {
    [ "$DO_PLYMOUTH" -eq 1 ] || { say "plymouth (skipped)"; return 0; }
    say "plymouth"

    local d="$T/usr/share/plymouth/themes/dct"
    run install -d -m 0755 "$d"
    install_file "$PAYLOAD/plymouth/dct/dct.plymouth" /usr/share/plymouth/themes/dct/dct.plymouth
    install_file "$PAYLOAD/plymouth/dct/dct.script"   /usr/share/plymouth/themes/dct/dct.script

    if [ -f "$PAYLOAD/assets/logo.png" ]; then
        install_file "$PAYLOAD/assets/logo.png" /usr/share/plymouth/themes/dct/logo.png
    else
        warn "no payload/assets/logo.png — splash will show colours only"
    fi

    if [ "$DRY" -eq 1 ]; then
        printf '     + plymouth-set-default-theme dct\n'; return 0
    fi
    if in_target command -v plymouth-set-default-theme >/dev/null 2>&1; then
        if [ "$DO_INITRAMFS" -eq 1 ]; then
            in_target plymouth-set-default-theme dct -R >/dev/null 2>&1 \
                && ok "splash set, initramfs rebuilt" \
                || warn "plymouth-set-default-theme failed"
        else
            in_target plymouth-set-default-theme dct >/dev/null 2>&1 \
                && ok "splash set (initramfs not rebuilt)" \
                || warn "plymouth-set-default-theme failed"
        fi
    elif in_target test -x /usr/bin/update-alternatives; then
        # Ubuntu 24.04 dropped plymouth-set-default-theme. The initramfs
        # plymouth hook reads the default.plymouth ALTERNATIVE, not
        # /etc/plymouth/plymouthd.conf, so this is what puts the DCT splash
        # into the initrd.
        in_target update-alternatives --install \
            /usr/share/plymouth/themes/default.plymouth default.plymouth \
            /usr/share/plymouth/themes/dct/dct.plymouth 200 >/dev/null 2>&1 \
            && ok "splash set via update-alternatives" \
            || warn "could not register the dct plymouth alternative"
    else
        warn "plymouth not installed — skipping"
    fi
}

# ---------------------------------------------------------------------------
# 4. Desktop defaults (GSettings)
# ---------------------------------------------------------------------------
branding_defaults() {
    say "desktop defaults"
    install_file "$PAYLOAD/gschema/99_dct-os.gschema.override" \
                 /usr/share/glib-2.0/schemas/99_dct-os.gschema.override

    fix_theme_fallbacks

    if [ "$DRY" -eq 0 ] && command -v glib-compile-schemas >/dev/null 2>&1; then
        glib-compile-schemas "$T/usr/share/glib-2.0/schemas" && ok "schemas compiled" \
            || warn "glib-compile-schemas failed"
    fi

    # Firefox enterprise policy — homepage + bookmarks for students.
    run install -d -m 0755 "$T/etc/firefox/policies"
    install_file "$PAYLOAD/policies/firefox-policies.json" \
                 /etc/firefox/policies/policies.json
}

# GSettings will happily point at a theme that does not exist, and you get a
# half-branded desktop with no error message. Guard against it explicitly.
fix_theme_fallbacks() {
    local f="$T/usr/share/glib-2.0/schemas/99_dct-os.gschema.override"
    [ -f "$f" ] || return 0

    if [ ! -d "$T/usr/share/themes/dct-gtk" ]; then
        warn "GTK theme 'dct-gtk' not installed — falling back to Adwaita-dark"
        warn "  (theme work is Phase 3; see docs/branding-checklist.md)"
        run sed -i "s/^gtk-theme=.*/gtk-theme='Adwaita-dark'/" "$f"
    fi
    if [ ! -d "$T/usr/share/icons/dct-cursors" ]; then
        warn "cursor theme 'dct-cursors' not installed — falling back to Adwaita"
        run sed -i "s/^cursor-theme=.*/cursor-theme='Adwaita'/" "$f"
    fi
    if [ ! -d "$T/usr/share/sounds/dct" ]; then
        warn "sound theme 'dct' not installed — falling back to freedesktop"
        run sed -i "s/^theme-name=.*/theme-name='freedesktop'/" "$f"
    fi
}

# ---------------------------------------------------------------------------
# 5. Wallpapers and logo
# ---------------------------------------------------------------------------
branding_artwork() {
    say "artwork"
    run install -d -m 0755 "$T/usr/share/backgrounds/dct"

    local n=0 f
    for f in dct-default.png dct-default-dark.png dct-lock.png; do
        if [ -f "$PAYLOAD/assets/$f" ]; then
            install_file "$PAYLOAD/assets/$f" "/usr/share/backgrounds/dct/$f"
            n=$((n + 1))
        fi
    done
    if [ "$n" -eq 0 ]; then
        warn "no wallpapers in payload/assets/ — desktop will use a flat colour"
        warn "  see payload/assets/README.md for the required file list"
    else
        ok "$n wallpaper(s) installed"
    fi

    if [ -f "$PAYLOAD/assets/logo.svg" ]; then
        install_file "$PAYLOAD/assets/logo.svg" /usr/share/pixmaps/dct-logo.svg
    fi
    if [ -f "$PAYLOAD/assets/dct-logo.png" ]; then
        install_file "$PAYLOAD/assets/dct-logo.png" /usr/share/pixmaps/dct-logo.png
    else
        warn "no payload/assets/dct-logo.png — greeter logo will be blank"
    fi
}

# ---------------------------------------------------------------------------
# 6. Calamares installer branding (only if calamares is present)
# ---------------------------------------------------------------------------
branding_calamares() {
    if [ ! -d "$T/etc/calamares" ]; then
        say "calamares (not installed, skipped)"
        return 0
    fi
    say "calamares"
    run install -d -m 0755 "$T/etc/calamares/branding/dct"
    install_file "$PAYLOAD/calamares/branding/dct/branding.desc" \
                 /etc/calamares/branding/dct/branding.desc
    install_file "$PAYLOAD/calamares/branding/dct/stylesheet.qss" \
                 /etc/calamares/branding/dct/stylesheet.qss
    if [ -f "$PAYLOAD/assets/dct-logo.png" ]; then
        install_file "$PAYLOAD/assets/dct-logo.png" \
                     /etc/calamares/branding/dct/logo.png
    fi
    ok "installer branding installed (settings.conf sets branding: dct)"
}

# ---------------------------------------------------------------------------
# 7. Default user skeleton
# ---------------------------------------------------------------------------
branding_skel() {
    say "user skeleton"
    local d="$T/etc/skel/.config/dconf"
    run install -d -m 0755 "$d"
    if [ "$DRY" -eq 0 ]; then
        cat > "$d/dct-user" <<'EOF'
# Placeholder marker. Real defaults come from the system-wide GSettings
# overrides in /usr/share/glib-2.0/schemas/99_dct-os.gschema.override, which
# apply to every new user without per-user dconf state. Keep this file to make
# the intent obvious to whoever maintains this next.
EOF
        ok "skel prepared"
    fi
}

# ---------------------------------------------------------------------------
# helper: run a command inside $ROOT, or directly if ROOT is /
# ---------------------------------------------------------------------------
in_target() {
    if [ "$ROOT" = "/" ]; then
        "$@"
    else
        chroot "$ROOT" "$@"
    fi
}

# ---------------------------------------------------------------------------
main() {
    say "DCT OS $DCT_VERSION — applying branding to ${ROOT}"
    [ "$DRY" -eq 1 ] && warn "DRY RUN — nothing will be written"

    branding_update_shield
    branding_identity
    branding_artwork
    branding_defaults
    branding_grub
    branding_plymouth
    branding_calamares
    branding_skel

    say "done"
    if [ "$DRY" -eq 0 ]; then
        cat <<EOF

  Check it:
    cat /etc/os-release
    gsettings get org.gnome.desktop.background picture-uri
    ./scripts/verify-branding.sh

  Then bake a bootable image:  sudo ./scripts/build-live-iso.sh --fast
EOF
    fi
}

main "$@"
