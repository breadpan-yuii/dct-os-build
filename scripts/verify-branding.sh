#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# verify-branding.sh — catch the things that silently stay wrong.
#
# Run after apply-branding.sh and before every ISO build. Exit code 1 means
# "do not ship this yet".
#
#   ./scripts/verify-branding.sh              # check this machine
#   ./scripts/verify-branding.sh --root /mnt  # check a mounted image
# ---------------------------------------------------------------------------
set -uo pipefail

ROOT="/"
while [ $# -gt 0 ]; do
    case "$1" in
        --root) ROOT="${2:?}"; shift 2 ;;
        -h|--help) echo "usage: $0 [--root DIR]"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
ROOT="${ROOT%/}"; [ -n "$ROOT" ] || ROOT="/"
T="$ROOT"
[ "$ROOT" = "/" ] && T=""    # avoid //etc/... paths when targeting the live root

PASS=0; FAIL=0; WARN=0
p() { printf '\033[1;32m PASS\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
f() { printf '\033[1;31m FAIL\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
w() { printf '\033[1;33m WARN\033[0m %s\n' "$*"; WARN=$((WARN+1)); }

exists() { [ -e "$T$1" ]; }

# A live remaster has no /etc/default/grub theme: the ISO carries its own
# grub.cfg and theme, patched at assembly time. Detect that and skip the
# checks that only make sense on an installed system.
LIVE=0
if [ -r "$T/etc/dct-os-release" ] && grep -q 'BUILD_KIND="live-remaster"' "$T/etc/dct-os-release"; then
    LIVE=1
fi

# Check that a theme named in the GSettings override actually exists on disk.
# GSettings silently accepts a missing theme and you get a half-branded desktop.
check_theme() {                                   # key dir
    local key="$1" dir="$2" val
    val="$(sed -n "s/^${key}='\(.*\)'/\1/p" "$OVR" 2>/dev/null | head -1)"
    [ -n "$val" ] || return 0
    if [ -d "$T$dir/$val" ]; then
        p "$key '$val' exists"
    else
        f "$key '$val' missing at $dir/$val — desktop will look unbranded"
    fi
}

echo "== identity =="
if [ -r "$T/etc/os-release" ] && grep -q '^ID=dctos' "$T/etc/os-release"; then
    p "/etc/os-release declares ID=dctos"
else
    f "/etc/os-release does not declare ID=dctos"
fi

if [ -r "$T/etc/os-release" ] && grep -q '^UBUNTU_CODENAME=noble' "$T/etc/os-release"; then
    p "UBUNTU_CODENAME preserved (apt/snapd will still work)"
else
    f "UBUNTU_CODENAME missing — apt, snapd and third-party repos will break"
fi

# /usr/lib/os-release must actually resolve: it is a symlink to /etc/os-release,
# and tools that read the canonical path break if the relative target is wrong.
if [ -r "$T/usr/lib/os-release" ] && grep -q '^ID=dctos' "$T/usr/lib/os-release"; then
    p "/usr/lib/os-release resolves to the branded identity"
else
    f "/usr/lib/os-release is missing or dangling — check the symlink target"
fi

# The whole point: no upstream distributor marks left behind.
UPSTREAM_MARKS="/etc/os-release /etc/lsb-release /etc/issue /etc/issue.net /etc/motd"
leak=0
for m in $UPSTREAM_MARKS; do
    if [ -r "$T$m" ] && grep -qi 'zorin' "$T$m"; then
        f "upstream mark 'Zorin' still in $m"
        leak=1
    fi
done
[ "$leak" -eq 0 ] && p "no 'Zorin' strings in identity files"

echo "== boot =="
if [ "$LIVE" -eq 1 ]; then
    w "GRUB theme checks skipped (live remaster — the ISO supplies its own grub.cfg)"
else
    if exists /boot/grub/themes/dct/theme.txt; then
        p "GRUB theme present"
    else
        f "GRUB theme missing at /boot/grub/themes/dct/theme.txt"
    fi

    if [ -r "$T/etc/default/grub" ] && grep -q '^GRUB_THEME="/boot/grub/themes/dct/theme.txt"' "$T/etc/default/grub"; then
        p "GRUB_THEME points at the DCT theme"
    else
        f "GRUB_THEME not set in /etc/default/grub"
    fi
fi

if [ -r "$T/etc/default/grub" ] && grep -qE '^GRUB_DISTRIBUTOR="DCT OS"' "$T/etc/default/grub"; then
    p "GRUB_DISTRIBUTOR set"
else
    w "GRUB_DISTRIBUTOR not set to DCT OS"
fi

plymouth_ok=0
if [ -r "$T/etc/plymouth/plymouthd.conf" ] && grep -q '^Theme=dct' "$T/etc/plymouth/plymouthd.conf"; then
    plymouth_ok=1
fi
if [ -r "$T/etc/alternatives/default.plymouth" ] || \
   [ -L "$T/etc/alternatives/default.plymouth" ]; then
    target="$(readlink -f "$T/etc/alternatives/default.plymouth" 2>/dev/null)"
    case "$target" in
        *themes/dct/*) plymouth_ok=1 ;;
    esac
    if [ "$plymouth_ok" -eq 0 ]; then
        f "plymouth still using: ${target##*/}"
    fi
elif [ "$plymouth_ok" -eq 0 ]; then
    w "no plymouth theme configured — splash not applied yet"
fi
[ "$plymouth_ok" -eq 1 ] && p "plymouth theme is dct"

echo "== desktop =="
OVR="$T/usr/share/glib-2.0/schemas/99_dct-os.gschema.override"
if [ -r "$OVR" ]; then
    p "GSettings override installed"

    check_theme gtk-theme    /usr/share/themes
    check_theme cursor-theme /usr/share/icons
    check_theme icon-theme   /usr/share/icons

    wallpaper="$(sed -n "s/^picture-uri='file:\/\/\(.*\)'/\1/p" "$OVR" | head -1)"
    if [ -n "$wallpaper" ]; then
        if exists "$wallpaper"; then
            p "wallpaper $wallpaper present"
        else
            f "wallpaper $wallpaper is referenced but missing"
        fi
    fi

    logo="$(sed -n "s/^logo='\(.*\)'/\1/p" "$OVR" | head -1)"
    if [ -n "$logo" ]; then
        exists "$logo" && p "greeter logo present" || f "greeter logo $logo missing"
    fi
else
    f "no GSettings override at /usr/share/glib-2.0/schemas/99_dct-os.gschema.override"
fi

if exists "/usr/share/pixmaps/dct-logo.png"; then
    h=$(file -b "$T/usr/share/pixmaps/dct-logo.png" 2>/dev/null)
    case "$h" in
        *image*) p "greeter logo is a real image ($h)" ;;
        *)       f "greeter logo is not a valid image: $h" ;;
    esac
else
    w "no /usr/share/pixmaps/dct-logo.png"
fi

echo "== upgrade resilience =="
if exists "/etc/apt/apt.conf.d/99dct-branding"; then
    p "apt hook installed (re-applies branding after upgrades)"
else
    w "no apt hook — a base-files upgrade could revert the identity"
fi

if exists "/usr/sbin/dct-rebrand"; then
    [ -x "$T/usr/sbin/dct-rebrand" ] && p "dct-rebrand executable" \
        || f "/usr/sbin/dct-rebrand is not executable"
else
    w "no /usr/sbin/dct-rebrand"
fi

if [ "$ROOT" = "/" ] && command -v dpkg-divert >/dev/null 2>&1; then
    if dpkg-divert --list /etc/os-release 2>/dev/null | grep -q dct; then
        p "/etc/os-release diverted away from base-files"
    else
        f "/etc/os-release is NOT diverted — base-files will overwrite it"
    fi
elif [ "$ROOT" != "/" ] && [ -f "$T/var/lib/dpkg/diversions" ]; then
    if grep -q '/etc/os-release' "$T/var/lib/dpkg/diversions" 2>/dev/null; then
        p "/etc/os-release diverted away from base-files"
    else
        f "/etc/os-release is NOT diverted — base-files will overwrite it"
    fi
else
    w "cannot inspect diversions here (no dpkg database)"
fi

echo "== package layer =="
if command -v dpkg-query >/dev/null 2>&1 && [ "$ROOT" = "/" ]; then
    for pkg in dct-os-defaults dct-os-desktop; do
        if dpkg-query -W "$pkg" >/dev/null 2>&1; then
            p "$pkg installed"
        else
            w "$pkg not installed (expected on a plain apply-branding run)"
        fi
    done
fi

echo
printf 'result: %d passed, %d failed, %d warnings\n' "$PASS" "$FAIL" "$WARN"
[ "$FAIL" -eq 0 ] || exit 1
