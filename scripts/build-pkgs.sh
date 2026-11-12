#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build-pkgs.sh — build the two DCT OS .deb packages into dist/
#
# Runs dpkg-buildpackage inside a throwaway ubuntu:24.04 container so you do
# not need an Ubuntu host and cannot pollute your system with build-deps.
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
cd "$REPO"

CTR=""
command -v podman >/dev/null 2>&1 && CTR=podman
[ -z "$CTR" ] && command -v docker >/dev/null 2>&1 && CTR=docker
[ -n "$CTR" ] || { echo "need podman or docker" >&2; exit 1; }

PKGS=(dct-os-desktop dct-os-defaults)
IMG=ubuntu:24.04

echo "==> staging payload into packages"
for p in "${PKGS[@]}"; do
    rm -rf "packages/$p/stage"
done
mkdir -p packages/dct-os-defaults/stage
cp -a payload                        packages/dct-os-defaults/stage/
cp -a scripts/apply-branding.sh      packages/dct-os-defaults/stage/
chmod 0755 packages/dct-os-defaults/stage/apply-branding.sh
echo "    ok"

mkdir -p dist

for p in "${PKGS[@]}"; do
    echo "==> building $p"
    "$CTR" run --rm \
        -v "$REPO":/src:z \
        -w "/src/packages/$p" \
        "$IMG" bash -euc '
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq --no-install-recommends \
                build-essential debhelper fakeroot dpkg-dev >/dev/null
            dpkg-buildpackage -us -uc -b -rfakeroot
            mv ../*.deb /src/dist/
        '
done

echo
echo "==> artefacts in dist/"
ls -1 dist/*.deb
echo
echo "Install on a test VM with:  sudo apt install ./dist/*.deb"
