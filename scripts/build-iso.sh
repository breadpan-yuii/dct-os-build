#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build-iso.sh — assemble the bootable ISO with live-build.
#
# Expects `make pkgs` to have produced dist/*.deb first; the live-build hook
# installs them into the chroot.
#
# live-build needs root, mount and chroot, so it runs in a privileged
# container. If your podman/docker cannot do that, run live-build directly on
# an Ubuntu 24.04 host instead (see docs/architecture.md#native-path).
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO"

CTR=""
command -v podman >/dev/null 2>&1 && CTR=podman
[ -z "$CTR" ] && command -v docker >/dev/null 2>&1 && CTR=docker
[ -n "$CTR" ] || { echo "need podman or docker" >&2; exit 1; }

ls dist/*.deb >/dev/null 2>&1 || {
    echo "no debs in dist/ — run 'make pkgs' first" >&2; exit 1
}

echo "==> building ISO (this takes 25-60 min)"
"$CTR" run --rm -it \
    --privileged \
    -v "$REPO":/src:z \
    -w /src/live-build \
    ubuntu:24.04 bash -euc '
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends \
            live-build debootstrap squashfs-tools xorriso \
            mtools dosfstools grub-pc-bin grub-efi-amd64-bin >/dev/null
        ./auto/config
        # Copy debs AFTER lb config, because config/ is regenerated.
        install -d config/includes.chroot/var/tmp/dct-debs
        cp -a /src/dist/*.deb config/includes.chroot/var/tmp/dct-debs/
        # Calamares sequence is build-time config, not on-system branding.
        install -d config/includes.chroot/etc/calamares
        cp -a /src/installer/calamares/settings.conf \
              config/includes.chroot/etc/calamares/settings.conf
        lb build
    '

echo
echo "==> done"
ls -lh live-build/*.iso 2>/dev/null || {
    echo "no ISO produced — read the log above." >&2
    echo "Most common causes: see docs/architecture.md#first-build-failures" >&2
    exit 1
}
