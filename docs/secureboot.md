# Secure Boot on the DCT fleet

**Read this before changing any firmware setting on a lab PC.**

## "The PCs' Secure Boot is already tampered"

Probably not. Get the terminology straight first, because the word matters when
you write it in a proposal.

Zorin OS 18.1 Core ships Canonical's *signed* boot chain. That is verifiable from
[Zorin's own published package list](https://zorin.com/os/details):

```
shim-signed
grub-efi-amd64-signed
sbsigntool
mokutil
linux-image-6.17.0-20-generic
```

`shim-signed` is the piece Microsoft signs. It in turn trusts Canonical's
certificate, which signs `grubx64.efi`, which verifies the Canonical-signed
kernel. **So a machine running Zorin OS is normally still booting with Secure
Boot enforced.** Installing a different Linux distribution does not remove or
alter the firmware trust store.

## The three states you will actually find

| State | What happened | Is it "tampering"? | Reversible? |
|---|---|---|---|
| **ENABLED** | Nothing. Zorin used the signed chain. | No | n/a |
| **DISABLED** | Someone switched Secure Boot off in firmware — commonly while installing NVIDIA drivers, a Broadcom Wi-Fi card, or an older Zorin release. | No, it's a *configuration change* | Yes, one firmware toggle |
| **LEGACY / CSM** | Machine boots in BIOS-compatibility mode, so Secure Boot never runs. | No | Yes, but may break an existing Windows install |
| **Keys modified** | `PK`/`KEK`/`db` deleted or replaced with custom keys. | **Yes, this is a real change** | Only with the original keys backed up |
| **MOK enrolled** | A Machine Owner Key was added for a DKMS driver. | No — this is the intended mechanism | Yes, `mokutil --delete` |

Only the fourth row is genuinely "tampered with", and it is rare. Do not put
"Secure Boot has been tampered with" in a proposal without a measurement to back
it up — it is the kind of claim an IT reviewer will push back on.

## Measure it, don't assume it

```bash
make baseline                    # -> docs/baseline/<hostname>.txt
# or, naming the file after the asset tag:
./scripts/audit-secureboot.sh docs/baseline/lab1-pc01.txt
```

Read-only. Changes nothing. Run it on every PC during Phase 1 and keep the
outputs in `docs/baseline/`. Each report ends with a machine-readable line:

```
MACHINE|lab1-pc01|ENABLED|1|1.14.0|zorin-17
```

Collect those into a CSV and you have a firmware baseline for the whole lab —
which is itself a deliverable worth listing in the proposal.

## The design decision that makes this a non-problem

**Keep the signed boot chain. Do not replace it.**

A Dominican OS image that carries `shim-signed` + `grub-efi-amd64-signed` +
Canonical-signed kernels will boot on *every* machine, in *every* state:

- Secure Boot **enabled** → the signed chain validates, boots normally.
- Secure Boot **disabled** → the same chain boots anyway; nothing is enforced.

So you do not need to touch firmware on any machine. You do not need to disable
Secure Boot lab-wide. You inherit a chain that is already trusted, and the fleet
becomes homogeneous regardless of what state it is in today.

This is also why building on Ubuntu 24.04 LTS is the right call: the signed chain
comes for free, exactly as it does for Zorin.

## What you must not do

- Do not delete `PK`, `KEK`, or `db`. That bricks Secure Boot permanently on
  some firmware.
- Do not ship an unsigned GRUB or an unsigned kernel and expect it to boot.
- Do not enrol a custom Secure Boot key unless you have a documented plan to
  distribute it to 40 machines.
- Do not "re-sign" Canonical's shim. It is signed by Microsoft; you cannot.

## Branding that still works with Secure Boot enabled

| Target | Works with SB on? |
|---|---|
| GRUB menu theme (`/boot/grub/themes/`) | **Yes** — loaded from disk by signed GRUB |
| Plymouth splash | **Yes** — runs after the kernel is verified |
| GDM login screen, wallpapers, icons, fonts | **Yes** |
| Calamares installer branding | **Yes** |
| **Firmware boot logo** (`splash.bmp` in the EFI binary) | **No** — compiled into the signed GRUB. Leave it. |

That is the entire branding scope minus one logo. Do not promise a custom UEFI
boot logo in the proposal.

## Related trap: BitLocker

If any lab PC dual-boots Windows with BitLocker, changing Secure Boot state
triggers a recovery-key prompt on next Windows boot. The audit script flags NTFS
and BitLocker partitions — check that section before you touch anything.

## Phase 1 deliverable

1. `audit-secureboot.sh` run on all classroom PCs.
2. Reports archived in `docs/baseline/`.
3. A one-row-per-machine summary table in the proposal appendix.
4. Decision recorded: *keep the signed chain, change no firmware.*
