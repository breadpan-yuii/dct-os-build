#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# audit-secureboot.sh — READ-ONLY firmware / Secure Boot baseline.
#
# Changes nothing. Safe to run on every lab PC.
#
#   ./scripts/audit-secureboot.sh                  # print report
#   sudo ./scripts/audit-secureboot.sh             # fuller report (MOK details)
#   ./scripts/audit-secureboot.sh report.txt       # also save to file
#
# Why this exists: "Secure Boot is disabled on the lab PCs" is a claim, not a
# measurement. Zorin OS ships Canonical's signed boot chain (shim-signed +
# grub-efi-amd64-signed), so most machines are probably still *enabled*. You
# cannot design the image until you know which state each machine is in.
# ---------------------------------------------------------------------------
set -uo pipefail

OUT="${1:-}"

# Colour only when stdout is a terminal, so redirected reports stay clean.
if [ -t 1 ]; then
    SBC=$'\033[1;36m'; RST=$'\033[0m'
    YEL=$'\033[1;33m'; RED=$'\033[1;31m'; GRN=$'\033[1;32m'
else
    SBC=; RST=; YEL=; RED=; GRN=
fi

have() { command -v "$1" >/dev/null 2>&1; }
sec()  { printf '\n%s-- %s %s\n' "$SBC" "$*" "$RST"; }
kv()   { printf '%-22s %s\n' "$1:" "${2:-<unset>}"; }

read_dmi() {
    local f="/sys/class/dmi/id/$1"
    [ -r "$f" ] && cat "$f" 2>/dev/null || echo "?"
}

# Read a numeric EFI variable: skip 4 attribute bytes, take 1 value byte.
efivar_val() {
    local f="/sys/firmware/efi/efivars/$1-8be4df61-93ca-11d2-aa0d-00e098032b8c"
    [ -r "$f" ] || { echo "absent"; return; }
    od -An -tu1 -j4 -N1 "$f" 2>/dev/null | tr -d ' \n'
}

report() {
    sec "machine"
    kv hostname  "$(hostnamectl --static 2>/dev/null || hostname)"
    kv date      "$(date -Is)"
    kv vendor    "$(read_dmi sys_vendor)"
    kv product   "$(read_dmi product_name)"
    kv board     "$(read_dmi board_name)"
    kv bios      "$(read_dmi bios_version) ($(read_dmi bios_date))"

    sec "boot mode"
    local UEFI=0
    if [ -d /sys/firmware/efi ]; then
        UEFI=1; kv boot_mode "UEFI"
        kv efi_runtime "$([ -d /sys/firmware/efi/efivars ] && echo present || echo MISSING)"
    else
        kv boot_mode "LEGACY / CSM"
        printf '  %sNOTE%s: in legacy mode Secure Boot does not apply at all.\n' \
               "$YEL" "$RST"
    fi

    local SB="n/a" SETUP="n/a"
    if [ "$UEFI" -eq 1 ]; then
        SB="$(efivar_val SecureBoot)"
        SETUP="$(efivar_val SetupMode)"
        kv secureboot_efivar "$SB"
        kv setup_mode "$SETUP"
    fi

    sec "secure boot state"
    if have mokutil; then
        kv "mokutil --sb-state" "$(mokutil --sb-state 2>&1 | tr '\n' ' ')"
    else
        printf '  mokutil not installed (apt install mokutil)\n'
    fi

    sec "boot chain packages"
    if have dpkg-query; then
        local pkglist="shim-signed grub-efi-amd64-signed grub-efi-amd64-bin sbsigntool mokutil linux-generic-hwe-24.04"
        for p in $pkglist; do
            local st
            st="$(dpkg-query -W -f='${Status} ${Version}' "$p" 2>/dev/null)"
            [ -n "$st" ] && kv "$p" "$st" || kv "$p" "not installed"
        done
    elif have pacman; then
        # Arch-family: package names differ, so report the tools that matter.
        for p in shim-signed sbctl sbsigntools mokutil grub efibootmgr; do
            if pacman -Q "$p" >/dev/null 2>&1; then
                kv "$p" "$(pacman -Q "$p" | awk '{print $2}')"
            else
                kv "$p" "not installed"
            fi
        done
        printf '  (Debian names like shim-signed/grub-efi-amd64-signed do not apply here.)\n'
    else
        printf '  neither dpkg-query nor pacman available\n'
    fi

    sec "signatures on disk"
    if have sbverify; then
        local f
        for f in $(find /boot/efi/EFI -maxdepth 2 -iname 'shimx64.efi' \
                                             -o -iname 'grubx64.efi' 2>/dev/null); do
            printf '%s\n' "$f"
            sbverify --list "$f" 2>&1 | sed -n '2,3p' | sed 's/^/    /'
        done
        local k
        for k in /boot/vmlinuz-*; do
            [ -e "$k" ] || continue
            printf '%s\n' "$k"
            sbverify --list "$k" 2>&1 | sed -n '2,3p' | sed 's/^/    /'
        done
    else
        printf '  sbsigntool not installed — cannot inspect signatures\n'
    fi

    sec "enrolled Machine Owner Keys (MOK)"
    if have mokutil; then
        local n
        n="$(mokutil --list-enrolled 2>/dev/null | grep -c '^\[key' || true)"
        kv "mok_count" "$n"
        printf '  (MOK is normal — NVIDIA / DKMS drivers enrol here. Not tampering.)\n'
        if [ "${n:-0}" -gt 0 ]; then
            mokutil --list-enrolled 2>/dev/null | grep -E '^\[key' | head -5 | sed 's/^/    /'
        fi
        kv "pending_enrolments" "$(mokutil --list-new 2>/dev/null | grep -c '^\[key' || echo 0)"
    else
        printf '  mokutil not installed — install it (apt install mokutil / pacman -S mokutil)\n'
    fi

    sec "firmware boot entries"
    if have efibootmgr; then
        efibootmgr -v 2>/dev/null \
            | grep -E '^(BootCurrent|BootOrder|Boot[0-9A-Fa-f]{4})' \
            | sed 's/\t.*//' \
            | head -12 | sed 's/^/  /'
    else
        printf '  efibootmgr not installed\n'
    fi

    sec "other OS / encryption"
    if have lsblk; then
        lsblk -o NAME,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null | grep -Ei 'bitlocker|ntfs|veracrypt' \
            | sed 's/^/  /' || printf '  none detected\n'
    fi

    # ---- verdict ----------------------------------------------------------
    # SetupMode=1 is its own case and worth shouting about: it means no
    # Platform Key is enrolled, so the firmware trust store has no owner.
    # Turning Secure Boot "off" in a menu leaves SetupMode at 0 and keeps PK.
    local verdict why
    if [ "$UEFI" -eq 0 ]; then
        verdict="LEGACY"
        why="booted via CSM; Secure Boot bypassed by boot mode"
    elif [ "$SB" = "1" ]; then
        verdict="ENABLED"
        why="Secure Boot enforcing"
    elif [ "$SB" = "0" ] && [ "$SETUP" = "1" ]; then
        verdict="DISABLED+SETUPMODE"
        why="Secure Boot off AND no Platform Key enrolled — trust store has no owner"
    elif [ "$SB" = "0" ]; then
        verdict="DISABLED"
        why="UEFI boot, Secure Boot switched off in firmware (reversible)"
    else
        verdict="UNKNOWN"
        why="could not read SecureBoot efivar"
    fi

    case "$verdict" in
        ENABLED)  printf '\n%s VERDICT: %s%s  (%s)\n' "$GRN" "$verdict" "$RST" "$why" ;;
        DISABLED) printf '\n%s VERDICT: %s%s  (%s)\n' "$YEL" "$verdict" "$RST" "$why" ;;
        *)        printf '\n%s VERDICT: %s%s  (%s)\n' "$RED" "$verdict" "$RST" "$why" ;;
    esac

    case "$verdict" in
        ENABLED)
            printf '  %s\n' "Nothing to fix. A Dominican OS image with the signed chain boots here unchanged." ;;
        DISABLED)
            printf '  %s\n' "A Dominican OS image with the signed chain boots here unchanged. No firmware change needed." ;;
        DISABLED+SETUPMODE)
            printf '  %s\n' "The signed chain still boots here, but re-enrolling keys later needs the" \
                            "  original vendor keys. Back up PK/KEK/db before changing anything." ;;
        LEGACY)
            printf '  %s\n' "A UEFI-only Dominican OS image will NOT boot in this mode. Record it and" \
                            "  plan a firmware switch during deployment." ;;
        *)
            printf '  %s\n' "Inconclusive — re-run as root, or check firmware settings manually." ;;
    esac

    printf 'MACHINE|%s|%s|%s|%s|%s\n' \
        "$(hostnamectl --static 2>/dev/null || hostname)" \
        "$verdict" "$SB" "$(read_dmi bios_version)" "$(image_hint)"
}

# Which OS is currently booted — useful when auditing the existing fleet.
image_hint() {
    local id="unknown"
    [ -r /etc/os-release ] && id="$(. /etc/os-release; echo "${ID:-unknown} ${VERSION_ID:-}")"
    echo "$id" | tr ' ' '-'
}

main() {
    if [ -n "$OUT" ]; then
        # Create the destination directory so `... > docs/baseline/x.txt` style
        # calls and `audit-secureboot.sh docs/baseline/x.txt` both just work.
        local dir
        dir="$(dirname "$OUT")"
        [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || true
        report 2>&1 | tee "$OUT"
        printf '\nSaved: %s\n' "$OUT" >&2
    else
        report
    fi
}

main "$@"
