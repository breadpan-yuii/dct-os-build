#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build-live-iso.sh — turn the official Ubuntu 24.04 ISO into a DCT OS live ISO.
#
# A REMASTER, not a from-scratch build:
#
#   Ubuntu live ISO -> extract the casper layers
#                   -> overlay-mount them exactly like casper does
#                   -> materialise the union
#                   -> apply-branding.sh --root <tree>
#                   -> mksquashfs -> xorriso re-inject -> new ISO
#
# Ubuntu 24.04.5 no longer ships one filesystem.squashfs. It ships a layered
# image and the live initrd selects a chain via
#   /etc/casper.conf: LAYERFS_PATH=minimal.standard.live.squashfs
# casper mounts minimal -> minimal.standard -> minimal.standard.live as an
# overlay. We reproduce that union, brand it, then write the whole branded
# system into the BASE layer and leave the upper layers empty but valid. That
# keeps the live boot and the installer both working, and means a rebuilt
# initrd (which loses LAYERFS_PATH) still resolves to the same filesystem.
#
# Why remaster at all:
#   * works without Docker and without an Ubuntu host
#   * Canonical's signed shim -> GRUB -> kernel chain is untouched, so the
#     image still boots with Secure Boot ON
#   * the result boots to a live desktop; nothing is written to the target
#     disk unless Install is clicked
#
#   sudo ./scripts/build-live-iso.sh            # full build (xz)
#   sudo ./scripts/build-live-iso.sh --fast     # zstd squashfs, ~3x faster
#   sudo ./scripts/build-live-iso.sh --check-updates
#   sudo ./scripts/build-live-iso.sh --no-extras   # skip the extra apt packages
#   ./scripts/build-live-iso.sh --dry-run       # preflight only
#
# Requires: xorriso, squashfs-tools  (pacman -S xorriso squashfs-tools)
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
. "$REPO/payload/branding/tokens.env"

ISO_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04.5.1-desktop-amd64.iso"
ISO_SHA256="4da4a0c9035da8e68a59a838674f403f0a54472c78a83b4fb7f78d03588f85a7"
ISO_BYTES=6250332160          # 5.82 GiB, disk-space estimate only
VOLID="DCT OS 1.0"

WORK="$REPO/.iso-work"
OUT="$REPO/dist"
BASE="$WORK/base.iso"
ROOTFS="$WORK/rootfs"
NEWSQ="$WORK/new-base.squashfs"
EXTRAS="$WORK/extras"
LOGDIR="$WORK/logs"
MNT="$WORK/mnt"

FAST=0; KEEP_TREE=0; DRY=0; SKIP_VERIFY=0; DO_INITRAMFS=1; CHECK_UPDATES=0
EXTRAS_PKGS=1
INITRD_REBUILT=0
JOBS="$(nproc)"

die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
say()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }
step() { printf '\033[1;36m  ..\033[0m %s\n' "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --fast)          FAST=1 ;;
        --keep-tree)     KEEP_TREE=1 ;;
        --dry-run)       DRY=1 ;;
        --no-verify)     SKIP_VERIFY=1 ;;
        --no-initramfs)  DO_INITRAMFS=0 ;;
        --no-extras)     EXTRAS_PKGS=0 ;;
        --check-updates) CHECK_UPDATES=1 ;;
        --jobs)          JOBS="${2:?--jobs needs a number}"; shift ;;
        -h|--help)       sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)               die "unknown option: $1  (try --help)" ;;
    esac
    shift
done

[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] \
    || die "run with sudo (unsquashfs must preserve ownership and caps)"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
say "preflight"

missing=()
for t in xorriso unsquashfs mksquashfs mount rsync curl sha256sum; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
done
if [ ${#missing[@]} -gt 0 ]; then
    printf '\n  missing: %s\n\n' "${missing[*]}"
    printf '  Install them, then re-run:\n\n    sudo pacman -S --needed xorriso squashfs-tools rsync\n\n'
    exit 1
fi
ok "tooling present"

[ "$(id -u)" -eq 0 ] && ok "running as root — ownership and capabilities preserved" \
                     || warn "not root: capability xattrs will be lost"

# A damaged /dev means a previous run followed a bind mount into the host. Stop
# before it gets worse.
[ -c /dev/null ] && [ -c /dev/zero ] && [ -c /dev/tty ] \
    || die "/dev is missing core device nodes — reboot the host before building"

case "$ROOTFS" in
    "$WORK"/*) ;;
    *) die "internal error: ROOTFS=$ROOTFS is not under $WORK" ;;
esac

# A prior run can leave the materialised tree and packed lower layer behind.
# They are reproducible, and count against the peak-space requirement. Remove
# only these known generated paths, and refuse if any mount remains underneath.
if [ "$DRY" -eq 0 ]; then
    for stale in "$ROOTFS" "$NEWSQ"; do
        case "$stale" in
            "$WORK"/*) ;;
            *) die "refusing to clean path outside WORK: $stale" ;;
        esac
        if [ -e "$stale" ] || [ -L "$stale" ]; then
            mounted="$(awk -v p="$stale" '$2 == p || index($2, p "/") == 1 {print $2}' /proc/mounts)"
            [ -z "$mounted" ] || die "refusing to clean $stale; mount(s) remain: $mounted"
            if [ -d "$stale" ] && [ ! -L "$stale" ]; then
                rm -rf --one-file-system -- "$stale"
            else
                rm -f -- "$stale"
            fi
        fi
    done
fi

# Peak: base ISO + materialised tree + new squashfs. The extracted layer
# files are deleted as soon as they are mounted (the mount holds the inode),
# so they never overlap with the tree.
free_kb=$(df -Pk "$REPO" | awk 'NR==2{print $4}')
need_kb=$(( 22*1024*1024 ))
printf '  free: %s GB   need: ~%s GB\n' \
    "$((free_kb/1024/1024))" "$((need_kb/1024/1024))"
[ "$free_kb" -ge "$need_kb" ] || die "not enough disk space under $REPO (need ~22 GB)"

total_mb=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)
printf '  ram: %s MB   cpus: %s   squashfs jobs: %s\n' "$total_mb" "$JOBS" "$JOBS"
if [ "$total_mb" -lt 6000 ] && [ "$JOBS" -gt 4 ]; then
    warn "under 6 GB RAM — capping squashfs jobs at 4 to avoid the OOM killer"
    JOBS=4
fi

mkdir -p "$WORK" "$OUT" "$EXTRAS" "$LOGDIR" "$MNT"
[ "$DRY" -eq 1 ] && { ok "dry run — stopping before download"; exit 0; }

# ---------------------------------------------------------------------------
# mount helpers
# ---------------------------------------------------------------------------
LAYER_MOUNTS=()
UNION_MOUNTED=0

umount_all() {
    [ "$UNION_MOUNTED" -eq 1 ] && { umount "$MNT/union" 2>/dev/null || true; UNION_MOUNTED=0; }
    local m
    for m in "${LAYER_MOUNTS[@]}"; do umount "$m" 2>/dev/null || true; done
    LAYER_MOUNTS=()
}
trap umount_all EXIT INT TERM

# ---------------------------------------------------------------------------
# chroot helpers
# ---------------------------------------------------------------------------
CHROOT_MOUNTS=()
chroot_enter() {
    local d t
    for d in dev dev/pts proc sys; do
        t="$ROOTFS/$d"
        # Never follow a symlink out of the tree.
        [ -L "$t" ] && rm -f "$t"
        # A previous run may have left a bind mount behind. Peel it before
        # mounting again, or we stack devtmpfs on devtmpfs — which is how a
        # stale mount once ended up on the host's /dev.
        while mountpoint -q "$t" 2>/dev/null; do
            umount -R "$t" 2>/dev/null \
                || die "stale mount at $t cannot be unmounted (run: sudo umount -R $t)"
        done
        mkdir -p "$t"
        if mount --bind "/$d" "$t" 2>/dev/null; then
            CHROOT_MOUNTS+=("$t")
        else
            warn "could not bind-mount /$d"
        fi
    done
    [ -f /etc/resolv.conf ] && cp -f /etc/resolv.conf "$ROOTFS/etc/resolv.conf" 2>/dev/null || true

    # initramfs-tools unpacks through /var/tmp. Give it a real, disposable
    # scratch dir: it keeps ~300 MB of extraction out of the squashfs and
    # guarantees the space unmkinitramfs needs.
    local vt="$ROOTFS/var/tmp"
    [ -L "$vt" ] && rm -f "$vt"
    while mountpoint -q "$vt" 2>/dev/null; do
        umount -R "$vt" 2>/dev/null || die "stale mount at $vt cannot be unmounted"
    done
    mkdir -p "$vt"
    if mount -t tmpfs -o size=2G,mode=1777 tmpfs "$vt" 2>/dev/null; then
        CHROOT_MOUNTS+=("$vt")
    else
        warn "could not mount tmpfs on /var/tmp"
    fi
}
chroot_leave() {
    local i m
    # Reverse order: children must be unmounted before their parent. The old
    # forward loop tried $ROOTFS/dev first, got EBUSY because $ROOTFS/dev/pts
    # was still mounted, ignored the failure, and left the host's /dev bound
    # into the tree.
    for (( i=${#CHROOT_MOUNTS[@]}-1; i>=0; i-- )); do
        m="${CHROOT_MOUNTS[$i]}"
        umount -R "$m" 2>/dev/null || umount "$m" 2>/dev/null || true
    done
    CHROOT_MOUNTS=()
}
trap 'chroot_leave; umount_all' EXIT INT TERM

# Every mount target at or below $1, from /proc/mounts.
mounts_under() {
    awk -v p="$1" '{
        t = $2; gsub(/\\040/, " ", t)
        if (t == p || index(t, p "/") == 1) print t
    }' /proc/mounts
}

# Delete a directory tree without ever crossing a mount point.
#
# `rm -rf "$ROOTFS"` while $ROOTFS/dev is a bind mount of the host's /dev
# follows the mount and deletes the HOST's device nodes. --one-file-system
# makes that impossible; the unmount pass clears anything still mounted.
safe_rm_tree() {
    local t="$1" m
    while read -r m; do
        [ -n "$m" ] || continue
        umount -R "$m" 2>/dev/null || umount "$m" 2>/dev/null || true
    done < <(mounts_under "$t" | sort -r)

    if [ -n "$(mounts_under "$t")" ]; then
        mounts_under "$t" | sed 's/^/    still mounted: /' >&2
        die "refusing to delete $t — mounts still active (run: sudo umount -R $t)"
    fi
    rm -rf --one-file-system "$t"
}

# ---------------------------------------------------------------------------
# 1. Base ISO
# ---------------------------------------------------------------------------
say "base image"
if [ -f "$BASE" ]; then
    ok "using cached $(basename "$BASE")"
else
    printf '  downloading %s\n' "$(basename "$ISO_URL")"
    curl -L -C - --retry 3 --retry-delay 5 --progress-bar -o "$BASE" "$ISO_URL"
fi

actual="$(stat -c %s "$BASE")"
[ "$actual" -eq "$ISO_BYTES" ] \
    || warn "unexpected size $actual (expected $ISO_BYTES) — the checksum decides"
ok "base image: $(du -h "$BASE" | cut -f1)"

if [ "$SKIP_VERIFY" -eq 0 ]; then
    printf '  sha256 ... '
    got="$(sha256sum "$BASE" | cut -d' ' -f1)"
    [ "$got" = "$ISO_SHA256" ] && ok "matches Canonical's published sum" \
        || die "checksum mismatch: $got — re-download"
fi

# ---------------------------------------------------------------------------
# 2. Work out the layer chain, exactly as casper does
# ---------------------------------------------------------------------------
say "detecting layout"

casper_list="$(xorriso -indev "$BASE" -find /casper -maxdepth 1 2>/dev/null \
               | tr -d "'" | sed 's|^/casper/||')"

if printf '%s\n' "$casper_list" | grep -qx 'filesystem.squashfs'; then
    LIVE_LAYER="filesystem.squashfs"
elif printf '%s\n' "$casper_list" | grep -qx 'minimal.standard.live.squashfs'; then
    LIVE_LAYER="minimal.standard.live.squashfs"
elif printf '%s\n' "$casper_list" | grep -qx 'minimal.squashfs'; then
    LIVE_LAYER="minimal.squashfs"
else
    printf '%s\n' "$casper_list" | sed 's/^/    /' >&2
    die "no known casper squashfs layout in this ISO"
fi

# casper walks LAYERFS_PATH by stripping one dot-component at a time:
#   minimal.standard.live.squashfs
#     -> minimal.standard.squashfs
#       -> minimal.squashfs
CHAIN=()
name="${LIVE_LAYER%.squashfs}"
while :; do
    CHAIN=("$name.squashfs" "${CHAIN[@]}")
    parent="${name%.*}"
    [ "$parent" = "$name" ] && break
    name="$parent"
done
BASE_LAYER="${CHAIN[0]}"

ok "live layer: $LIVE_LAYER"
ok "layer chain: ${CHAIN[*]}"
ok "branded content goes into: $BASE_LAYER"

for l in "${CHAIN[@]}"; do
    printf '%s\n' "$casper_list" | grep -qx "$l" || die "layer $l missing from the ISO"
done

# ---------------------------------------------------------------------------
# 3. Extract and union the layers
# ---------------------------------------------------------------------------
say "extracting ${#CHAIN[@]} layer(s)"
idx=0
for l in "${CHAIN[@]}"; do
    f="$WORK/layer$idx.squashfs"
    if [ ! -f "$f" ]; then
        xorriso -osirrox on -indev "$BASE" -extract "/casper/$l" "$f" 2>"$LOGDIR/extract-$idx.log"
    fi
    printf '  %-34s %s\n' "$l" "$(du -h "$f" | cut -f1)"
    idx=$((idx + 1))
done

say "overlay-mounting the union"
mkdir -p "$MNT/upper" "$MNT/work" "$MNT/union"
idx=0
for l in "${CHAIN[@]}"; do
    mkdir -p "$MNT/l$idx"
    mount -t squashfs -o loop,ro "$WORK/layer$idx.squashfs" "$MNT/l$idx" \
        || die "could not mount $l"
    LAYER_MOUNTS+=("$MNT/l$idx")
    # The mount keeps the inode alive; deleting the file now reclaims the
    # space before the 12 GB tree is written.
    rm -f "$WORK/layer$idx.squashfs"
    idx=$((idx + 1))
done

# Highest-priority layer first, mirroring casper's rofsstring order.
lower=""
for ((i = ${#CHAIN[@]} - 1; i >= 0; i--)); do
    lower="${lower:+$lower:}$MNT/l$i"
done
mount -t overlay overlay -o "lowerdir=$lower" "$MNT/union" \
    || die "overlay mount failed"
UNION_MOUNTED=1
ok "union mounted ($lower)"

say "materialising the union into $ROOTFS"
mkdir -p "$ROOTFS"
# -a keeps modes/owners/devices, -H hardlinks, -A ACLs, -X xattrs.
# No --info=progress2: it writes a carriage-return progress stream that makes
# the build log unreadable.
rsync -aHAX --numeric-ids "$MNT/union/" "$ROOTFS/" \
    || die "rsync of the union failed"
ok "tree: $(du -sh "$ROOTFS" | cut -f1)"

umount_all
rm -f "$WORK"/layer*.squashfs 2>/dev/null || true
ok "unmounted the layers"

# ---------------------------------------------------------------------------
# 3b. Desktop extras the stock live layer does not carry
#
# The gschema override asks for Papirus-Dark and Inter. Without the packages
# GNOME silently falls back to Adwaita, which reads as "half-branded".
# ---------------------------------------------------------------------------
if [ "$EXTRAS_PKGS" -eq 1 ]; then
    say "installing desktop extras"
    chroot_enter
    if chroot "$ROOTFS" env DEBIAN_FRONTEND=noninteractive \
            apt-get update -qq >"$LOGDIR/apt-extras-update.log" 2>&1; then
        if chroot "$ROOTFS" env DEBIAN_FRONTEND=noninteractive \
                apt-get install -y --no-install-recommends \
                papirus-icon-theme fonts-inter fonts-jetbrains-mono \
                >"$LOGDIR/apt-extras.log" 2>&1; then
            ok "papirus icons + Inter / JetBrains Mono installed"
        else
            warn "extras install failed — desktop falls back to Adwaita (see $LOGDIR/apt-extras.log)"
        fi
        rm -rf "$ROOTFS/var/lib/apt/lists/"* "$ROOTFS/var/cache/apt/archives/"*.deb 2>/dev/null || true
    else
        warn "apt-get update failed — skipping extras (offline?)"
    fi
    chroot_leave
fi

# ISO-side config we patch and map back in.
say "extracting boot config"
for f in boot/grub/grub.cfg boot/grub/loopback.cfg casper/install-sources.yaml .disk/info; do
    mkdir -p "$EXTRAS/$(dirname "$f")"
    xorriso -osirrox on -indev "$BASE" -extract "/$f" "$EXTRAS/$f" 2>/dev/null \
        && ok "$f" || warn "$f not in image"
done

# casper derives the live username and hostname from the first word of
# /.disk/info (lowercased). Leaving "Ubuntu ..." here produces a live session
# user and host called "ubuntu" even when everything else is branded.
if [ -f "$EXTRAS/.disk/info" ]; then
    printf '%s\n' "$DCT_PRETTY_NAME ($DCT_CODENAME) - Release amd64" \
        > "$EXTRAS/.disk/info"
    ok ".disk/info -> $(cat "$EXTRAS/.disk/info")"
fi

INITRD_PATH=""
for p in casper/initrd casper/initrd.gz; do
    if [ -e "$ROOTFS/$p" ]; then INITRD_PATH="$p"; break; fi
done
# The initrd lives outside the squashfs on this layout; extract it for reference.
if [ -z "$INITRD_PATH" ] && printf '%s\n' "$casper_list" | grep -qx 'initrd'; then
    mkdir -p "$EXTRAS/casper"
    rm -f "$EXTRAS/casper/initrd"
    xorriso -osirrox on -indev "$BASE" -extract /casper/initrd "$EXTRAS/casper/initrd" 2>/dev/null \
        && INITRD_PATH="casper/initrd" && ok "initrd extracted for reference"
fi

# ---------------------------------------------------------------------------
# 4. Brand the live filesystem
# ---------------------------------------------------------------------------
say "applying DCT branding"
# --no-grub: the ISO boots from its own grub.cfg, not /etc/default/grub.
"$REPO/scripts/apply-branding.sh" --root "$ROOTFS" --no-initramfs --no-grub \
    || die "apply-branding failed"

# Ubuntu's live layer automatically opens ubuntu-desktop-bootstrap in the
# graphical session ("Welcome to Ubuntu" / "Preparing Ubuntu..."). This is a
# try-only demo image: mask the auto-start so the session lands on the DCT
# desktop, but keep the installer reachable from the app grid under a DCT name
# and icon. Its artwork is overlaid on the snap at boot by
# dct-installer-brand.service, which apply-branding installs.
mkdir -p "$ROOTFS/etc/systemd/user"
ln -sfn /dev/null "$ROOTFS/etc/systemd/user/ubuntu-desktop-installer.service"
installer_desktop="$ROOTFS/var/lib/snapd/desktop/applications/ubuntu-desktop-bootstrap_ubuntu-desktop-bootstrap.desktop"
if [ -f "$installer_desktop" ]; then
    sed -i -e '/^NoDisplay=/d' \
           -e 's/^Name=.*/Name=Install DCT OS/' \
           -e 's/^Icon=.*/Icon=dct-os/' "$installer_desktop"
    # snapd owns the file above and may rewrite it; a copy in
    # /usr/share/applications takes precedence and cannot be clobbered.
    install -D -m 0644 "$installer_desktop" \
        "$ROOTFS/usr/share/applications/$(basename "$installer_desktop")"
    ok "installer launcher -> Install DCT OS (icon dct-os)"
else
    warn "no installer desktop entry found — launcher keeps the Ubuntu name"
fi
ok "Ubuntu installer auto-launch masked; live session is try-only"

mkdir -p "$ROOTFS/etc/plymouth"
cat > "$ROOTFS/etc/plymouth/plymouthd.conf" <<'EOF'
[Daemon]
Theme=dct
ShowDelay=0
DeviceTimeout=8
EOF
ok "plymouth default -> dct"

mkdir -p "$ROOTFS/etc"
cat > "$ROOTFS/etc/dct-os-release" <<EOF
DCT_NAME="$DCT_NAME"
DCT_VERSION="$DCT_VERSION"
DCT_CODENAME="$DCT_CODENAME"
BUILD_KIND="live-remaster"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BASE_IMAGE="$(basename "$ISO_URL")"
BASE_SHA256="$ISO_SHA256"
LAYER_CHAIN="${CHAIN[*]}"
EOF
ok "build stamp -> /etc/dct-os-release"

# ---------------------------------------------------------------------------
# 4b. Prove the branding survives an upgrade (optional)
# ---------------------------------------------------------------------------
if [ "$CHECK_UPDATES" -eq 1 ]; then
    say "update-resilience test — reinstalling base-files in the chroot"
    BRANDING_FAIL=0
    before="$(sha256sum "$ROOTFS/etc/os-release" | cut -d' ' -f1)"
    chroot_enter

    if chroot "$ROOTFS" apt-get update -qq >"$LOGDIR/apt-update.log" 2>&1; then
        ok "chroot reached the Ubuntu archive"
    else
        warn "apt-get update failed — skipping (see $LOGDIR/apt-update.log)"
    fi

    if chroot "$ROOTFS" env DEBIAN_FRONTEND=noninteractive \
            apt-get install -y --reinstall --no-install-recommends base-files \
            >"$LOGDIR/apt-reinstall.log" 2>&1; then
        after="$(sha256sum "$ROOTFS/etc/os-release" | cut -d' ' -f1)"

        if chroot "$ROOTFS" grep -q '^ID=dctos' /etc/os-release; then
            ok "/etc/os-release still says ID=dctos after base-files reinstall"
        else
            warn "/etc/os-release was reverted by the upgrade"; BRANDING_FAIL=1
        fi
        [ "$before" = "$after" ] && ok "identity file byte-identical (diversion held)" \
            || warn "identity file changed — check the diversion"

        # base-files ships /etc/os-release as a symlink and /usr/lib/os-release
        # as a regular file, so prefer the regular file: the /etc copy is a
        # symlink and may be dangling depending on what it points at.
        orig=""
        for p in /usr/lib/os-release.dct-orig /etc/os-release.dct-orig; do
            if [ -f "$ROOTFS$p" ]; then orig="$p"; break; fi
        done
        if [ -z "$orig" ]; then
            for p in /etc/os-release.dct-orig /usr/lib/os-release.dct-orig; do
                if [ -L "$ROOTFS$p" ]; then orig="$p"; break; fi
            done
        fi
        if [ -n "$orig" ]; then
            ok "base-files wrote its copy to $orig, as intended"
        else
            warn "no .dct-orig file — dumping diversions for diagnosis"
            chroot "$ROOTFS" dpkg-divert --list >"$LOGDIR/diversions.log" 2>&1 || true
            ls -la "$ROOTFS/etc/"*.dct-orig "$ROOTFS/usr/lib/"*.dct-orig \
                >>"$LOGDIR/diversions.log" 2>&1 || true
        fi

        # Layer 2: clobber on purpose, then let the hook repair it.
        if [ -n "$orig" ]; then
            if cp "$ROOTFS$orig" "$ROOTFS/etc/os-release" 2>>"$LOGDIR/diversions.log"; then
                if chroot "$ROOTFS" /usr/sbin/dct-rebrand --quiet; then
                    if chroot "$ROOTFS" grep -q '^ID=dctos' /etc/os-release; then
                        ok "apt hook repaired a deliberately clobbered identity"
                    else
                        warn "apt hook did not repair the identity"
                    fi
                else
                    warn "dct-rebrand failed"
                fi
            else
                warn "could not copy $orig over /etc/os-release — hook test skipped"
            fi
        fi

        rm -rf "$ROOTFS/var/lib/apt/lists/"* "$ROOTFS/var/cache/apt/archives/"*.deb 2>/dev/null || true
    else
        warn "base-files reinstall failed — skipping assertions"
    fi
    chroot_leave
fi

# ---------------------------------------------------------------------------
# 5. Rebuild the initrd so the early splash is DCT, not Ubuntu
# ---------------------------------------------------------------------------
if [ "$DO_INITRAMFS" -eq 1 ]; then
    say "rebuilding initrd"
    KVER="$(ls -1 "$ROOTFS/lib/modules" 2>/dev/null | sort -V | tail -1)"
    if [ -z "$KVER" ]; then
        warn "no kernel in the tree — keeping Ubuntu's initrd"
    else
        step "kernel: $KVER"

        # casper reads the layer chain from /etc/casper.conf inside the initrd.
        # Ubuntu bakes this in when it builds its own initrd; a rebuild from
        # this tree would lose it, so write it before running the hook.
        if [ -f "$ROOTFS/etc/casper.conf" ] \
           && ! grep -q '^export LAYERFS_PATH=' "$ROOTFS/etc/casper.conf"; then
            printf '\nexport LAYERFS_PATH="%s"\n' "$LIVE_LAYER" \
                >> "$ROOTFS/etc/casper.conf"
            ok "casper layer path -> $LIVE_LAYER"
        fi

        chroot_enter
        # Absolute paths: the host's PATH does not necessarily contain
        # /usr/sbin, so a bare `update-initramfs` can fail with "No such file".
        if chroot "$ROOTFS" env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
                /usr/sbin/update-initramfs -u -k "$KVER" >"$LOGDIR/initramfs.log" 2>&1; then
            new="$ROOTFS/boot/initrd.img-$KVER"
            # lsinitramfs unpacks through unmkinitramfs, which needs a writable
            # scratch dir — /var/tmp. Keep its stderr: without it a failure
            # looks identical to an initrd that genuinely lacks casper.
            chroot "$ROOTFS" env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
                TMPDIR=/var/tmp /usr/bin/lsinitramfs "/boot/initrd.img-$KVER" \
                >"$LOGDIR/initrd-contents.txt" 2>"$LOGDIR/lsinitramfs.log" || true
            listing="$(cat "$LOGDIR/initrd-contents.txt" 2>/dev/null)"
            if [ ! -s "$new" ]; then
                warn "rebuilt initrd is empty — keeping Ubuntu's"
            elif [ -z "$listing" ]; then
                warn "could not list the rebuilt initrd — keeping Ubuntu's (see $LOGDIR/lsinitramfs.log)"
            elif ! printf '%s\n' "$listing" | grep -q 'scripts/casper'; then
                # Without casper in the initrd the image cannot boot at all.
                warn "rebuilt initrd has no casper hooks — keeping Ubuntu's"
            elif ! printf '%s\n' "$listing" | grep -q 'conf/conf.d/default-boot-to-casper.conf'; then
                # The casper initramfs hook generates this file (and uuid.conf)
                # only when CASPER_GENERATE_UUID is set. Without it the live
                # session never hands over to casper.
                warn "rebuilt initrd lost the casper boot config — keeping Ubuntu's"
            elif ! printf '%s\n' "$listing" | grep -q 'plymouth/themes/dct'; then
                warn "rebuilt initrd lacks the dct splash — keeping Ubuntu's"
            else
                # A rebuilt initrd gets a NEW random UUID: casperize.conf sets
                # CASPER_GENERATE_UUID=1 and the casper hook runs `uuidgen -r`.
                # casper finds its medium by comparing the initrd's
                # conf/uuid.conf with the ISO's /.disk/casper-uuid-generic, so
                # the two must be kept in step or the image cannot boot.
                NEWUUID="$(chroot "$ROOTFS" env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin sh -c "
                    rm -rf /tmp/.dct-ir
                    unmkinitramfs /boot/initrd.img-$KVER /tmp/.dct-ir >/dev/null 2>&1 || exit 0
                    cat /tmp/.dct-ir/main/conf/uuid.conf 2>/dev/null ||
                        cat /tmp/.dct-ir/conf/uuid.conf 2>/dev/null
                    rm -rf /tmp/.dct-ir
                " 2>/dev/null | tr -d '[:space:]')"
                if [ -z "$NEWUUID" ]; then
                    # Shipping a rebuilt initrd with an unknown UUID is worse
                    # than shipping Ubuntu's: keep the original, which still
                    # matches the ISO.
                    warn "could not read the new initrd UUID — keeping Ubuntu's"
                else
                    mkdir -p "$EXTRAS/$(dirname "$INITRD_PATH")" "$EXTRAS/.disk"
                    cp -f "$new" "$EXTRAS/$INITRD_PATH"
                    printf '%s\n' "$NEWUUID" > "$EXTRAS/.disk/casper-uuid-generic"
                    INITRD_REBUILT=1
                    ok "medium UUID re-synced with the new initrd: $NEWUUID"
                    ok "initrd rebuilt ($(du -h "$new" | cut -f1)) with casper + dct splash"
                fi
            fi
        else
            warn "update-initramfs failed — keeping Ubuntu's (see $LOGDIR/initramfs.log)"
        fi
        chroot_leave
    fi
fi

# ---------------------------------------------------------------------------
# 6. Verify the tree before it is packed
# ---------------------------------------------------------------------------
say "verifying the branded tree"
if "$REPO/scripts/verify-branding.sh" --root "$ROOTFS" >"$LOGDIR/verify.log" 2>&1; then
    ok "verify-branding: pass"
else
    warn "verify-branding reported problems:"
    sed -n '/FAIL/p' "$LOGDIR/verify.log" | sed 's/^/     /' | head -10
fi

# ---------------------------------------------------------------------------
# 7. Patch the ISO-side menus and installer source list
# ---------------------------------------------------------------------------
say "patching boot menus"
menus=()
for f in boot/grub/grub.cfg boot/grub/loopback.cfg; do
    [ -f "$EXTRAS/$f" ] && menus+=("$EXTRAS/$f")
done
[ ${#menus[@]} -gt 0 ] || die "no grub menus extracted — refusing to build an unbootable image"

for p in "${menus[@]}"; do
    # Medium lookups: uuid/label -> a file test. Neither uuid nor label is
    # guaranteed to survive a repack, and this is what turns "boots on my PC"
    # into "GRUB prompt on theirs".
    perl -i -pe '
        if (/\bsearch\b/) {
            s/--fs-uuid\s+\S+/--file \/casper\/vmlinuz/g;
            s/--label\s+(?:"[^"]*"|\S+)/--file \/casper\/vmlinuz/g;
        }
    ' "$p"

    # User-visible strings, inside menu entries only.
    perl -i -pe '
        if (/^\s*(menuentry|menu label|menu title|text|label)\b/) {
            s/Ubuntu 24\.04(\.\d+)? LTS/DCT OS 1.0/g;
            s/\bUbuntu\b/DCT OS/g;
            s/Try or Install DCT OS/Try DCT OS/g;
        }
    ' "$p"

    # Second layer of defence for medium detection: casper normally matches the
    # initrd UUID against /.disk/casper-uuid-generic. `ignore_uuid` removes that
    # check entirely, so a repack that changes either one still boots.
    perl -i -pe 's/^(\s*linux(?:efi)?\s+\S+\s+)/${1}ignore_uuid /' "$p"

    # GRUB theme, if we are shipping one.
    if [ "$(basename "$p")" = "grub.cfg" ] && [ -f "$REPO/payload/grub/theme/theme.txt" ]; then
        perl -i -pe '
            if (/^\s*terminal_output\s+gfxterm/ && !$done) {
                $_ .= "set theme=\/boot\/grub\/themes\/dct\/theme.txt\n";
                $done = 1;
            }
        ' "$p"
    fi
    ok "patched ${p#$EXTRAS/}"
done

grep -hE '^\s*(menuentry|menu label)' "$EXTRAS/boot/grub/grub.cfg" 2>/dev/null \
    | sed -E 's/^[[:space:]]*(menuentry|menu label)[[:space:]]*"?//; s/".*//' \
    | head -6 | sed 's/^/     · /'

# Uncompressed size of the branded system: casper and the installer both want
# a number here, and a stale one produces a bogus "not enough disk space".
UNCOMPRESSED_KB="$(du -sk "$ROOTFS" | cut -f1)"
UNCOMPRESSED_BYTES=$((UNCOMPRESSED_KB * 1024))
printf '%s\n' "$UNCOMPRESSED_BYTES" > "$WORK/filesystem.size"
ok "uncompressed size: $((UNCOMPRESSED_BYTES/1024/1024/1024)) GB"

# Installer source list.
#
# The installer resolves a fsimage-layered path by walking the layer chain from
# the filename it is given (minimal.standard.squashfs -> minimal.squashfs). All
# of our branding now lives in the base layer, so both entries point at it —
# pointing the second at an intentionally-empty upper layer would install a
# blank system.
if [ -f "$EXTRAS/casper/install-sources.yaml" ]; then
    cat > "$EXTRAS/casper/install-sources.yaml" <<EOF
- default: true
  description:
    en: The Dominican College of Tarlac desktop, ready to use.
  id: ubuntu-desktop-minimal
  locale_support: langpack
  name:
    en: $DCT_NAME
  path: $BASE_LAYER
  preinstalled_langs:
  - en
  size: $UNCOMPRESSED_BYTES
  type: fsimage-layered
  variant: desktop
- default: false
  description:
    en: The Dominican College of Tarlac desktop, ready to use.
  id: ubuntu-desktop
  locale_support: langpack
  name:
    en: $DCT_NAME
  path: $BASE_LAYER
  preinstalled_langs:
  - en
  size: $UNCOMPRESSED_BYTES
  type: fsimage-layered
  variant: desktop
EOF
    ok "install-sources.yaml rewritten (both entries -> $BASE_LAYER)"
fi

# ---------------------------------------------------------------------------
# 8. Pack
# ---------------------------------------------------------------------------
say "packing the filesystem (the slow part)"
if [ "$FAST" -eq 1 ]; then
    warn "--fast: zstd — boots on 24.04+, bigger image"
    COMP=(-comp zstd -Xcompression-level 3)
else
    # Upstream uses xz with a 128K block. Match it.
    COMP=(-comp xz -b 128K)
fi

rm -f "$NEWSQ"
mksquashfs "$ROOTFS" "$NEWSQ" -noappend -all-root -no-progress \
    -processors "$JOBS" -mem-percent 60 "${COMP[@]}" \
    || die "mksquashfs failed (try --jobs 4)"
ok "branded layer: $(du -h "$NEWSQ" | cut -f1)"

# Empty but valid upper layers, so the LAYERFS_PATH chain still resolves.
mkdir -p "$WORK/empty"
rm -f "$WORK/empty.squashfs"
mksquashfs "$WORK/empty" "$WORK/empty.squashfs" -noappend -all-root -no-progress \
    -comp xz >/dev/null || die "could not create the empty layer"
ok "empty upper layer: $(du -h "$WORK/empty.squashfs" | cut -f1)"

if [ "$KEEP_TREE" -eq 1 ]; then
    warn "--keep-tree: leaving $ROOTFS ($(du -sh "$ROOTFS" | cut -f1))"
else
    chroot_leave
    safe_rm_tree "$ROOTFS"
fi

# ---------------------------------------------------------------------------
# 9. Assemble the ISO, preserving the boot equipment
# ---------------------------------------------------------------------------
say "assembling ISO"
OUTISO="$OUT/DCT-OS-${DCT_VERSION}-live-amd64.iso"
rm -f "$OUTISO"

MAP=( -map "$NEWSQ" "/casper/$BASE_LAYER"
      -map "$WORK/filesystem.size" /casper/filesystem.size )

# The remaining chain layers become empty.
for ((i = 1; i < ${#CHAIN[@]}; i++)); do
    MAP+=( -map "$WORK/empty.squashfs" "/casper/${CHAIN[$i]}" )
done

for f in boot/grub/grub.cfg boot/grub/loopback.cfg casper/install-sources.yaml .disk/info; do
    [ -f "$EXTRAS/$f" ] && MAP+=( -map "$EXTRAS/$f" "/$f" )
done

# Keep the ISO-side medium UUID in step with the rebuilt initrd.
if [ -f "$EXTRAS/.disk/casper-uuid-generic" ]; then
    MAP+=( -map "$EXTRAS/.disk/casper-uuid-generic" /.disk/casper-uuid-generic )
    ok "medium UUID mapped into the image"
fi
if [ "${INITRD_REBUILT:-0}" -eq 1 ] && [ -s "$EXTRAS/$INITRD_PATH" ]; then
    MAP+=( -map "$EXTRAS/$INITRD_PATH" "/$INITRD_PATH" )
    ok "rebuilt initrd mapped into the image"
fi

if [ -f "$REPO/payload/grub/theme/theme.txt" ] \
   && grep -q 'themes/dct' "$EXTRAS/boot/grub/grub.cfg" 2>/dev/null; then
    MAP+=( -map "$REPO/payload/grub/theme/theme.txt" /boot/grub/themes/dct/theme.txt )
    [ -f "$REPO/payload/assets/background.png" ] \
        && MAP+=( -map "$REPO/payload/assets/background.png" /boot/grub/themes/dct/background.png )
    ok "GRUB theme mapped into the image"
fi

# Drop every layer we are not shipping. If the initrd is ever rebuilt and
# LAYERFS_PATH disappears, casper falls back to mounting every *.squashfs it
# finds — and a stray language layer would then shadow our branding.
RM=()
for l in $casper_list; do
    case "$l" in
        *.squashfs) ;;
        *) continue ;;
    esac
    keep=0
    for c in "${CHAIN[@]}"; do [ "$l" = "$c" ] && keep=1; done
    [ "$keep" -eq 1 ] || RM+=( "/casper/$l" )
done
# Stale checksums and a signature that can no longer be valid.
for f in SHA256SUMS SHA256SUMS.gpg; do
    printf '%s\n' "$casper_list" | grep -qx "$f" && RM+=( "/casper/$f" )
done
[ ${#RM[@]} -gt 0 ] && ok "removing ${#RM[@]} stale casper file(s)"
RM_ARGS=()
[ ${#RM[@]} -gt 0 ] && RM_ARGS=( -rm "${RM[@]}" )

set +e
xorriso -indev "$BASE" -outdev "$OUTISO" \
    -boot_image any replay \
    "${MAP[@]}" \
    -volid "$VOLID" \
    -changes_pending yes \
    "${RM_ARGS[@]}" \
    >"$LOGDIR/xorriso.log" 2>&1
xor_rc=$?
set -e

if [ "$xor_rc" -ne 0 ]; then
    tail -25 "$LOGDIR/xorriso.log" >&2
    die "xorriso failed (rc=$xor_rc) — full log: $LOGDIR/xorriso.log"
fi
[ -s "$OUTISO" ] || die "xorriso produced no image"
ok "wrote $OUTISO ($(du -h "$OUTISO" | cut -f1))"

# ---------------------------------------------------------------------------
# 10. Verify — the checks that decide "bootable on another PC"
# ---------------------------------------------------------------------------
say "verifying"
fail=${BRANDING_FAIL:-0}

if xorriso -indev "$OUTISO" -report_el_torito plain 2>/dev/null | grep -qi 'El Torito'; then
    ok "El Torito boot record present (BIOS + UEFI)"
else
    warn "no El Torito record — this image will NOT boot"; fail=1
fi

if xorriso -indev "$OUTISO" -report_el_torito plain 2>/dev/null | grep -qi 'UEFI'; then
    ok "UEFI boot entry present"
else
    warn "no UEFI boot entry — Secure Boot machines will refuse it"; fail=1
fi

have_efi=0
for p in /efi/boot/bootx64.efi /EFI/BOOT/BOOTX64.EFI; do
    xorriso -indev "$OUTISO" -ls "$p" >/dev/null 2>&1 && { have_efi=1; break; }
done
if [ "$have_efi" -eq 1 ]; then
    ok "EFI/BOOT/BOOTX64.EFI in place (Canonical's signed shim, untouched)"
else
    warn "BOOTX64.EFI not found"; fail=1
fi

got_volid="$(xorriso -indev "$OUTISO" -pvd_info 2>/dev/null \
             | sed -n 's/^Volume [Ii]d *: *//p' | head -1)"
[ "$got_volid" = "$VOLID" ] && ok "volume id: $got_volid" \
    || warn "volume id is '$got_volid', expected '$VOLID'"

# Boot menus, read back from the image that will be written to the stick.
mkdir -p "$WORK/tmp"
if xorriso -osirrox on -indev "$OUTISO" \
        -extract /boot/grub/grub.cfg "$WORK/tmp/grub.cfg" 2>/dev/null; then
    grep -q 'ignore_uuid' "$WORK/tmp/grub.cfg" \
        && ok "grub.cfg carries ignore_uuid (medium detection cannot fail on UUID)" \
        || warn "grub.cfg has no ignore_uuid"
    grep -q 'DCT OS' "$WORK/tmp/grub.cfg" \
        && ok "grub.cfg shows the DCT OS menu label" \
        || warn "grub.cfg still shows the upstream label"
    grep -qE -- '--fs-uuid|--label' "$WORK/tmp/grub.cfg" \
        && warn "grub.cfg still looks up the medium by uuid/label" || true
fi

# The medium UUID on the ISO must equal the one baked into the initrd.
if [ "${INITRD_REBUILT:-0}" -eq 1 ] && [ -f "$EXTRAS/.disk/casper-uuid-generic" ]; then
    rm -f "$WORK/tmp/uuid.iso"
    xorriso -osirrox on -indev "$OUTISO" \
        -extract /.disk/casper-uuid-generic "$WORK/tmp/uuid.iso" 2>/dev/null || true
    iso_uuid="$(tr -d '[:space:]' < "$WORK/tmp/uuid.iso" 2>/dev/null || true)"
    want_uuid="$(tr -d '[:space:]' < "$EXTRAS/.disk/casper-uuid-generic")"
    if [ "$iso_uuid" = "$want_uuid" ]; then
        ok "medium UUID matches the rebuilt initrd"
    else
        warn "medium UUID mismatch (iso='$iso_uuid' initrd='$want_uuid')"; fail=1
    fi
fi

new_list="$(xorriso -indev "$OUTISO" -find /casper -maxdepth 1 2>/dev/null \
            | tr -d "'" | sed 's|^/casper/||')"
for c in "${CHAIN[@]}"; do
    printf '%s\n' "$new_list" | grep -qx "$c" \
        && ok "layer present: $c" || { warn "layer missing: $c"; fail=1; }
done
stray="$(printf '%s\n' "$new_list" | grep '\.squashfs$' | grep -vxF "$(printf '%s\n' "${CHAIN[@]}")" || true)"
[ -z "$stray" ] && ok "no stray layers" || warn "stray layers still present: $stray"

# Read the branding back out of the squashfs that is actually on the ISO.
if xorriso -osirrox on -indev "$OUTISO" \
        -extract "/casper/$BASE_LAYER" "$WORK/verify.squashfs" 2>/dev/null; then
    if unsquashfs -q -cat "$WORK/verify.squashfs" etc/os-release 2>/dev/null | grep -q '^ID=dctos'; then
        ok "squashfs on the ISO declares ID=dctos"
    else
        warn "squashfs on the ISO does not declare ID=dctos"; fail=1
    fi
    if unsquashfs -q -cat "$WORK/verify.squashfs" etc/dct-os-release 2>/dev/null \
            | grep -q 'BUILD_KIND="live-remaster"'; then
        ok "build stamp present (testers can prove which image booted)"
    else
        warn "build stamp missing from squashfs"
    fi
    rm -f "$WORK/verify.squashfs"
else
    warn "could not extract squashfs for inspection"
fi

sha256sum "$OUTISO" | tee "$OUTISO.sha256"
[ -s "$OUTISO.sha256" ] || die "could not write checksum"

say "done"
cat <<EOF

  $OUTISO
  $(du -h "$OUTISO" | cut -f1)

  Write it to a USB stick (8 GB+). Replace /dev/sdX with the STICK, not a disk
  you care about — 'lsblk' first, and check the size:

    sudo dd if=$OUTISO of=/dev/sdX bs=4M status=progress oflag=sync
    sync

  Boot the target PC from it and pick "Try DCT OS".
  This is a try-only demo image. It does not install or modify the target disk.

  Prove which image booted, on the live desktop:

    cat /etc/dct-os-release
    head -3 /etc/os-release

EOF

if [ "$fail" -ne 0 ]; then
    printf '\033[1;31m  verification reported problems above\033[0m\n'
    exit 2
fi

if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    chown "$SUDO_USER": "$OUTISO" "$OUTISO.sha256" 2>/dev/null || true
fi
