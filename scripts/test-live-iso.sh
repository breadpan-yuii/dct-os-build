#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test-live-iso.sh — prove a built ISO is bootable BEFORE it goes on a stick.
#
#   ./scripts/test-live-iso.sh                  # structure + both boot tests
#   ./scripts/test-live-iso.sh --structure      # no QEMU, fast
#   ./scripts/test-live-iso.sh --serial         # kernel-direct serial boot
#   ./scripts/test-live-iso.sh --firmware       # full UEFI/GRUB boot + screenshots
#   ./scripts/test-live-iso.sh path/to.iso
#
# Three independent questions:
#
#   1. structure  is this a hybrid BIOS+UEFI image with a branded squashfs?
#   2. serial     does the live system reach userspace? (definitive, text mode)
#   3. firmware   does GRUB render and does the desktop come up? (screenshots)
#
# (2) is the one that matters. It boots the ISO's own kernel and initrd, so
# casper's medium detection and the layer chain are exercised for real. (3)
# additionally exercises the El Torito/UEFI boot path that a stick uses.
#
# Requires: qemu-system-x86_64, edk2-ovmf, xorriso, squashfs-tools,
#           imagemagick (screenshots only). Uses KVM when /dev/kvm is
#           accessible, otherwise falls back to slow TCG emulation.
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
TMP_BASE="${TMPDIR:-$REPO/.iso-work}"
mkdir -p "$TMP_BASE"
TMP="$TMP_BASE/dct-iso-test.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

DO_STRUCT=0; DO_SERIAL=0; DO_FIRMWARE=0
ISO=""
SERIAL_TIMEOUT=480

while [ $# -gt 0 ]; do
    case "$1" in
        --structure) DO_STRUCT=1 ;;
        --serial)    DO_SERIAL=1 ;;
        --firmware)  DO_FIRMWARE=1 ;;
        --all)       DO_STRUCT=1; DO_SERIAL=1; DO_FIRMWARE=1 ;;
        -h|--help)   sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)          echo "unknown option: $1" >&2; exit 2 ;;
        *)           ISO="$1" ;;
    esac
    shift
done

if [ "$DO_STRUCT$DO_SERIAL$DO_FIRMWARE" = "000" ]; then
    DO_STRUCT=1; DO_SERIAL=1; DO_FIRMWARE=1
fi

if [ -z "$ISO" ]; then
    ISO="$(ls -t "$REPO"/dist/*.iso 2>/dev/null | head -1 || true)"
fi
[ -n "$ISO" ] && [ -f "$ISO" ] || { echo "no ISO found (build one, or pass a path)" >&2; exit 2; }
ISO="$(cd "$(dirname "$ISO")" && pwd)/$(basename "$ISO")"

# Hardware acceleration. Without KVM a full live desktop session under TCG can
# take 20+ minutes and may never settle, so prefer KVM whenever it is usable.
QEMU_ACCEL=()
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    QEMU_ACCEL=(-enable-kvm -cpu host)
    ACCEL_NOTE="KVM"
    BOOT_SCALE=1
else
    ACCEL_NOTE="TCG (software, slow)"
    SERIAL_TIMEOUT=900
    BOOT_SCALE=4
fi

PASS=0; FAIL=0; WARN=0
p() { printf '\033[1;32m PASS\033[0m %s\n' "$*"; PASS=$((PASS + 1)); }
f() { printf '\033[1;31m FAIL\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }
w() { printf '\033[1;33m WARN\033[0m %s\n' "$*"; WARN=$((WARN + 1)); }
h() { printf '\n\033[1;34m==\033[0m %s\n' "$*"; }

h "image"
printf '  %s\n  %s\n  accel: %s\n' "$ISO" "$(du -h "$ISO" | cut -f1)" "$ACCEL_NOTE"

# ---------------------------------------------------------------------------
# 1. Structure
# ---------------------------------------------------------------------------
if [ "$DO_STRUCT" -eq 1 ]; then
    h "structure"

    if xorriso -indev "$ISO" -report_el_torito plain 2>/dev/null | grep -qi 'El Torito'; then
        p "El Torito boot record"
    else
        f "no El Torito record — not bootable"
    fi

    torito="$(xorriso -indev "$ISO" -report_el_torito plain 2>/dev/null || true)"
    printf '%s\n' "$torito" | grep -qi 'BIOS' && p "BIOS/legacy boot entry" \
        || w "no BIOS boot entry (UEFI-only image)"
    printf '%s\n' "$torito" | grep -qi 'UEFI' && p "UEFI boot entry" \
        || f "no UEFI boot entry — Secure Boot machines will refuse it"

    if xorriso -indev "$ISO" -ls /EFI/BOOT/BOOTX64.EFI >/dev/null 2>&1; then
        p "EFI/BOOT/BOOTX64.EFI present (Canonical's signed shim)"
    else
        f "EFI/BOOT/BOOTX64.EFI missing"
    fi

    for f_ in /casper/vmlinuz /casper/initrd; do
        if xorriso -indev "$ISO" -ls "$f_" >/dev/null 2>&1; then
            p "$f_ present"
        else
            f "$f_ missing"
        fi
    done

    casper_list="$(xorriso -indev "$ISO" -find /casper -maxdepth 1 2>/dev/null \
                   | tr -d "'" | sed 's|^/casper/||' || true)"
    base=""
    for cand in filesystem.squashfs minimal.squashfs; do
        printf '%s\n' "$casper_list" | grep -qx "$cand" && { base="$cand"; break; }
    done
    if [ -n "$base" ]; then
        p "base layer: $base"
    else
        f "no known base layer in /casper"
    fi

    stray="$(printf '%s\n' "$casper_list" | grep '\.squashfs$' | grep -vxF -e "${base:-none}" \
             -e 'minimal.standard.squashfs' -e 'minimal.standard.live.squashfs' || true)"
    [ -z "$stray" ] && p "no stray language layers" \
        || w "extra layers present: $(echo "$stray" | tr '\n' ' ')"

    if [ -n "$base" ]; then
        printf '  reading branding out of %s ...\n' "$base"
        if xorriso -osirrox on -indev "$ISO" \
                -extract "/casper/$base" "$TMP/base.squashfs" 2>/dev/null; then
            if unsquashfs -q -cat "$TMP/base.squashfs" etc/os-release 2>/dev/null \
                    | grep -q '^ID=dctos'; then
                p "squashfs declares ID=dctos"
            else
                f "squashfs does not declare ID=dctos"
            fi
            if unsquashfs -q -cat "$TMP/base.squashfs" etc/dct-os-release 2>/dev/null \
                    | grep -q 'BUILD_KIND='; then
                p "build stamp present (proves which image booted)"
            else
                w "no /etc/dct-os-release in the squashfs"
            fi
            if unsquashfs -ll "$TMP/base.squashfs" >"$TMP/base.list" 2>/dev/null \
                    && grep -Fq 'etc/systemd/user/ubuntu-desktop-installer.service -> /dev/null' \
                        "$TMP/base.list"; then
                p "Ubuntu installer does not auto-open over the DCT live desktop"
            else
                f "Ubuntu installer auto-start mask missing from the live system"
            fi
            if unsquashfs -q -cat "$TMP/base.squashfs" etc/lightdm/slick-greeter.conf 2>/dev/null \
                    | grep -q '^background=/usr/share/backgrounds/dct/dct-greeter.png'; then
                p "greeter policy points at the purple/gray backdrop"
            else
                f "greeter policy missing or not pointing at dct-greeter.png"
            fi
            # Large listing: grep -q can SIGPIPE unsquashfs, so relax pipefail
            # around this one (same reason as the content checks in the build).
            if ( set +o pipefail
                 unsquashfs -q -ll "$TMP/base.squashfs" 2>/dev/null \
                     | grep -q 'usr/share/themes/Yaru-purple-dark/' ); then
                p "Yaru-purple-dark GTK theme present"
            else
                f "Yaru-purple-dark theme missing — desktop falls back to Adwaita"
            fi
            rm -f "$TMP/base.squashfs"
        else
            f "could not extract the base layer"
        fi
    fi

    if xorriso -osirrox on -indev "$ISO" \
            -extract /boot/grub/grub.cfg "$TMP/grub.cfg" 2>/dev/null; then
        grep -q 'ignore_uuid' "$TMP/grub.cfg" \
            && p "grub.cfg carries ignore_uuid" \
            || w "grub.cfg has no ignore_uuid"
        grep -q 'Dominican OS' "$TMP/grub.cfg" \
            && p "grub.cfg shows the Dominican OS label" \
            || w "grub.cfg still shows the upstream label"
    else
        w "no /boot/grub/grub.cfg"
    fi
fi

# ---------------------------------------------------------------------------
# 2. Serial boot — the definitive test
# ---------------------------------------------------------------------------
if [ "$DO_SERIAL" -eq 1 ]; then
    h "serial boot (kernel-direct, text mode)"

    if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
        w "qemu-system-x86_64 not installed — skipping"
    else
        for f_ in vmlinuz initrd; do
            xorriso -osirrox on -indev "$ISO" -extract "/casper/$f_" "$TMP/$f_" 2>/dev/null \
                || f "could not extract /casper/$f_"
        done

        if [ -s "$TMP/vmlinuz" ] && [ -s "$TMP/initrd" ]; then
            # No `ignore_uuid` here on purpose: this exercises casper's real
            # medium detection, including the /.disk UUID handshake.
            qemu-system-x86_64 \
                -m 3072 -smp 2 "${QEMU_ACCEL[@]}" \
                -cdrom "$ISO" \
                -kernel "$TMP/vmlinuz" -initrd "$TMP/initrd" \
                -append "console=ttyS0,115200 text nopersistent" \
                -display none -monitor none \
                -serial "file:$TMP/serial.log" \
                -no-reboot >/dev/null 2>&1 &
            qpid=$!

            found=""
            for _ in $(seq 1 $((SERIAL_TIMEOUT / 2))); do
                if grep -qE 'login:|Reached target Multi-User System|Started Getty' \
                        "$TMP/serial.log" 2>/dev/null; then
                    found="userspace"
                    break
                fi
                if grep -qE 'Unable to find a medium|Kernel panic|not syncing' \
                        "$TMP/serial.log" 2>/dev/null; then
                    found="panic"
                    break
                fi
                kill -0 "$qpid" 2>/dev/null || break
                sleep 2
            done

            kill "$qpid" 2>/dev/null || true
            wait "$qpid" 2>/dev/null || true

            case "$found" in
                userspace)
                    p "reached userspace (live system booted)" ;;
                panic)
                    f "kernel panic or medium not found — see the log tail below" ;;
                *)
                    f "no userspace marker within ${SERIAL_TIMEOUT}s" ;;
            esac

            if grep -q 'casper' "$TMP/serial.log" 2>/dev/null; then
                p "casper ran (medium detection reached)"
            else
                w "no casper output on the console"
            fi
            # Ubuntu 24.04's casper does not print the squashfs filenames to
            # the console, so grepping for them can never succeed — it produced
            # a permanent warning that looked like a failure. casper-bottom is
            # the step that actually assembles the overlay, and reaching
            # userspace from that overlay is the proof it worked.
            if grep -qi 'casper-bottom' "$TMP/serial.log" 2>/dev/null; then
                p "casper assembled the layer chain (casper-bottom ran)"
            else
                w "no casper-bottom message on the console"
            fi

            if [ "$found" != "userspace" ]; then
                printf '\n  --- serial log tail ---\n'
                tail -30 "$TMP/serial.log" 2>/dev/null | sed 's/^/  /'
                cp "$TMP/serial.log" "$REPO/.iso-work/serial-failure.log" 2>/dev/null || true
                [ -f "$REPO/.iso-work/serial-failure.log" ] \
                    && printf '  saved: %s\n' "$REPO/.iso-work/serial-failure.log"
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 3. Firmware boot — GRUB and the desktop, via screenshots
# ---------------------------------------------------------------------------
if [ "$DO_FIRMWARE" -eq 1 ]; then
    h "firmware boot (UEFI + GRUB + desktop)"

    OVMF_CODE=""
    for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd \
             /usr/share/edk2/x64/OVMF_CODE.fd \
             /usr/share/ovmf/x64/OVMF_CODE.fd; do
        [ -f "$c" ] && { OVMF_CODE="$c"; break; }
    done
    OVMF_VARS=""
    for v in /usr/share/edk2/x64/OVMF_VARS.4m.fd \
             /usr/share/edk2/x64/OVMF_VARS.fd \
             /usr/share/ovmf/x64/OVMF_VARS.fd; do
        [ -f "$v" ] && { OVMF_VARS="$v"; break; }
    done

    if [ -z "$OVMF_CODE" ] || [ -z "$OVMF_VARS" ]; then
        w "no OVMF firmware — install edk2-ovmf, skipping"
    elif ! command -v convert >/dev/null 2>&1; then
        w "imagemagick not installed — skipping screenshot analysis"
    else
        cp "$OVMF_VARS" "$TMP/VARS.fd"
        SOCK="$TMP/monitor.sock"

        qemu-system-x86_64 \
            -machine q35 -m 3072 -smp 2 "${QEMU_ACCEL[@]}" \
            -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
            -drive if=pflash,format=raw,file="$TMP/VARS.fd" \
            -cdrom "$ISO" -boot d \
            -display none -serial "file:$TMP/fw-serial.log" \
            -monitor "unix:$SOCK,server=on,wait=off" \
            -no-reboot >/dev/null 2>&1 &
        qpid=$!

        # GRUB waits `timeout=30`, so 45 s is the menu, 150 s is past the
        # splash and into the live session.
        python3 - "$SOCK" "$TMP" "$BOOT_SCALE" <<'PY' &
import socket, sys, time
sock, out, scale = sys.argv[1], sys.argv[2], float(sys.argv[3])
for _ in range(60):
    try:
        s = socket.socket(socket.AF_UNIX); s.connect(sock); break
    except OSError:
        time.sleep(1)
else:
    sys.exit(1)
s.settimeout(10)
def cmd(c):
    s.sendall((c + "\n").encode()); time.sleep(0.5)
time.sleep(20 * scale)
cmd("screendump %s/grub.ppm" % out)
time.sleep(110 * scale)
cmd("screendump %s/desktop.ppm" % out)
cmd("quit")
PY
        mon=$!

        # Hard ceiling in case the monitor helper dies.
        ( sleep $((300 * BOOT_SCALE)); kill "$qpid" 2>/dev/null ) &
        watchdog=$!

        wait "$mon" 2>/dev/null || true
        kill "$qpid" 2>/dev/null || true
        wait "$qpid" 2>/dev/null || true
        kill "$watchdog" 2>/dev/null || true

        for shot in grub desktop; do
            if [ -s "$TMP/$shot.ppm" ]; then
                read -r mean colors < <(
                    convert "$TMP/$shot.ppm" -format '%[fx:mean] %k' info: 2>/dev/null
                ) || true
                mean="${mean:-0}"; colors="${colors:-0}"
                printf '  %-8s mean=%.4f colours=%s\n' "$shot" "$mean" "$colors"
                if awk -v m="$mean" 'BEGIN{exit !(m > 0.005)}'; then
                    p "$shot rendered something (not a black screen)"
                else
                    f "$shot is black — the guest did not draw anything"
                fi
                if [ "$shot" = "desktop" ] && [ "${colors:-0}" -gt 200 ]; then
                    p "desktop has ${colors} distinct colours (wallpaper, not text mode)"
                fi
                cp "$TMP/$shot.ppm" "$REPO/.iso-work/$shot.ppm" 2>/dev/null || true
            else
                f "no $shot screenshot captured"
            fi
        done
        printf '  screenshots kept in %s/.iso-work/*.ppm (convert to png to view)\n' "$REPO"
    fi
fi

# ---------------------------------------------------------------------------
h "result"
printf '  %d passed, %d failed, %d warnings\n' "$PASS" "$FAIL" "$WARN"
[ "$FAIL" -eq 0 ] || exit 1
