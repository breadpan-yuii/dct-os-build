# Demo runbook

**Goal:** something defensible to show a panel, this week, without waiting on
Docker access, live-build debugging, or the design office.

There are three tiers. Each is honest on its own. Pick the highest tier you can
reach in the time you have, and **say which tier you are showing.** Getting
caught presenting a render as a live system is the only way this demo fails.

| Tier | Artefact | Needs | Time | Claim you can make |
|---|---|---|---|---|
| **0** | Design renders in `demo/mockups/` | nothing — already generated | done | "Design direction for the branded system." |
| **1** | A real Ubuntu VM with branding applied | any VM software | ~1 hour | "The branding layer, running." |
| **2** | A bootable Dominican OS ISO | Tier 1 + `penguins-eggs` | ~half a day | "A Dominican OS image that boots." |

Tier 1 is the sweet spot. Tier 2 is the one that ends the conversation.

---

## Tier 0 — the renders (already done)

```bash
./scripts/make-demo-mockups.sh     # regenerate
ls demo/mockups/
```

| File | Screen |
|---|---|
| `grub.png` | boot menu |
| `plymouth.png` | boot splash |
| `installer.png` | Calamares welcome page |
| `login.png` | greeter |
| `desktop.png` | desktop with the institutional portal open |

**Label them "design render".** Every slide, every caption. They are SVG drawn
from `payload/branding/tokens.env`, not photographs of a running machine. If a
panel member asks "is that the actual system?", the answer is "that's the design
render — the running version is on the laptop, let me show you."

Why they exist: they define the target so the real build has something to be
measured against, and they are what you put on the slide *behind* you while you
talk.

> Regenerate after changing colours: edit `payload/branding/tokens.env`, re-run
> both demo scripts. Never hand-edit the PNGs.

---

## Tier 1 — branding on a real VM

This is the strongest thing you can produce today, because it is the actual
branding code running on an actual system — the same script that will run on
every classroom PC.

### Prepare the VM

1. Download **Ubuntu 24.04 LTS Desktop** (`ubuntu-24.04.*-desktop-amd64.iso`) —
   *not* Zorin. See `docs/licensing.md` for why that is not negotiable.
2. Create a VM: 4 GB RAM, 40 GB disk, UEFI firmware if your hypervisor offers it.
3. Install with a user named `student`, locale `English (Philippines)`,
   timezone `Asia/Manila`. These match the classroom default.

### Apply the branding

```bash
# inside the VM
sudo apt update
sudo apt install -y git rsync

# copy the repo in (or clone it, if you have pushed it somewhere)
rsync -a /media/sf_share/dct-os-build/ ~/dct-os-build/
cd ~/dct-os-build

sudo ./scripts/apply-branding.sh        # ~15 seconds, idempotent
./scripts/verify-branding.sh            # must print zero failures
```

Then reboot. You will see the branded GRUB menu (if it appears at all), the
branded splash, the greeter with the DCT mark, and the wallpaper.

### Optional: install the app set, so the desktop looks real

```bash
sudo apt install -y fonts-inter fonts-jetbrains-mono papirus-icon-theme \
                    libreoffice-writer libreoffice-calc libreoffice-impress \
                    firefox timeshift
```

OnlyOffice is a separate apt repo — add it from `onlyoffice.com/download-desktop`
if you want it on screen. If you skip it, do not talk about it as installed.

### What to capture while it is running

- [ ] Boot splash (record video — a still does not prove it animates)
- [ ] Greeter
- [ ] Desktop with the wallpaper
- [ ] `cat /etc/os-release` — shows *Dominican OS 1.0 (tarlac)*
- [ ] `verify-branding.sh` output — zero failures, on screen

Those five take ten minutes and replace every mockup in your deck with the real
thing. **If you only do one thing from this document, do this one.**

### If something looks wrong

`apply-branding.sh` is idempotent — fix `payload/`, re-run it, reboot. No
reinstall. That is the entire reason the dev loop is built this way; say that
out loud during the demo, it is a better answer than any screenshot.

---

## Tier 2 — a bootable live ISO

This is the one that ends the conversation: a USB stick you hand to a panel
member, who boots it on a machine that has never seen this project.

It is a **remaster** of the official Ubuntu 24.04 ISO, not a from-scratch build:

```
official Ubuntu 24.04 ISO (checksum-verified)
  -> detect the casper layer chain
  -> extract minimal / minimal.standard / minimal.standard.live
  -> overlay-mount the union (live on top)
  -> rsync it out with ownership, ACLs, xattrs, capabilities
  -> apply-branding.sh --root <tree>
  -> rebuild initrd, re-sync the medium UUID
  -> write the branded system into the base layer
  -> mksquashfs the layers, xorriso reassemble with the signed boot chain
  -> dist/Dominican-OS-1.0-live-amd64.iso
```

Ubuntu 24.04.5.1 does not ship a single `filesystem.squashfs` any more; it ships
a layered casper filesystem. The script handles that layout, which is why the
steps above look different from older remaster recipes.

Why this and not penguins-eggs: it does not need a running branded machine, it
does not need Docker, it works from this Arch host, and it leaves the signed
shim/GRUB/kernel chain untouched — so the image still boots with **Secure Boot
on**, on a PC that has never been configured.

### Build it

```bash
sudo pacman -S --needed xorriso squashfs-tools     # Arch host
sudo ./scripts/build-live-iso.sh --check-updates   # ~40 min
# or, to iterate faster (zstd, bigger image, ~3x quicker):
sudo ./scripts/build-live-iso.sh --fast --check-updates
```

`--check-updates` is worth the ten minutes it adds: it reinstalls `base-files`
inside the extracted system and proves the branding survives an Ubuntu upgrade.
See `docs/updates.md`.

### Prove it boots before you touch a USB stick

```bash
./scripts/test-live-iso.sh              # structure + two QEMU boots, ~3 min with KVM
./scripts/test-live-iso.sh --structure  # 30 s, no QEMU
```

The serial boot is the one that counts: it boots the ISO's own kernel and initrd
in text mode and waits for a login prompt. If that passes, casper found the
medium, the layer chain resolved, and userspace came up. The firmware boot adds
GRUB/UEFI coverage and keeps screenshots in `.iso-work/*.ppm`.

Do not skip this because the build said "ok". A build can pass every structural
check and still fail on a real PC.

### Put it on a stick

```bash
lsblk                                     # find the stick, CHECK THE SIZE
sudo dd if=dist/Dominican-OS-1.0-live-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
sync
```

`/dev/sdX` is the whole stick, not a partition. Getting this wrong destroys a
disk. Ventoy also works and is safer if you are nervous.

### Boot it

1. Insert the stick in the target PC, power on, open the boot menu (usually
   F12 or F10), pick the USB device.
2. On a Secure Boot machine, choose the UEFI entry. It boots — the shim is
   Canonical's, unmodified.
3. Pick **Try Dominican OS**. The DCT-branded live desktop appears. The Ubuntu
   desktop-bootstrap installer is deliberately not auto-launched in this
   try-only demo image. **Nothing has been
   written to that PC's disk.**

Success criteria — all five, or it is not a demo:

- [ ] reaches the Dominican OS boot menu
- [ ] splash appears with the DCT mark
- [ ] reaches a live desktop, wallpaper and all
- [ ] `cat /etc/dct-os-release` prints `BUILD_KIND="live-remaster"` and today's date
- [ ] `head -3 /etc/os-release` says *Dominican OS 1.0 (tarlac)*

That fourth check is the one to memorise: it proves the machine booted *this*
build and not some leftover image.

### If it does not boot

| Symptom | Cause |
|---|---|
| Firmware ignores the stick | written to a partition instead of the device; or BIOS/UEFI boot mode mismatch |
| GRUB prompt, no menu | boot menu still looking for the old volume label — check the build log's "medium UUID" and "patched boot menus" lines |
| "Unable to find a medium containing a live file system" | the initrd's `conf/uuid.conf` and the ISO's `/.disk/casper-uuid-generic` disagree — rebuild; do not hand-edit |
| Kernel panic, `/casper` not found | squashfs or `filesystem.size` mismatch; rebuild, do not patch by hand |
| Boots to Ubuntu branding | stale USB cache — check `/etc/dct-os-release` first |

### Legal guardrail

The base image must be the **official Ubuntu 24.04 ISO**, checksum-verified by
the build script against Canonical's published sum. Never remaster a Zorin ISO,
a Windows image, or a PC's installed system: the output would carry artwork and
packages that `docs/licensing.md` says you cannot redistribute.

---

## What you may and may not claim

Say this:

> "The branding layer is implemented and tested. Here it is running on Ubuntu
> 24.04 LTS, and here it is booting from a USB stick on a machine that was never
> touched. The reproducible package-based pipeline is written but has not been
> executed yet — that is Phase 1 of the plan."


Do not say:

| ❌ Don't | Why |
|---|---|
| "It's a finished distro" | It is a branding layer plus a live image; it has never been rolled out |
| "It includes Microsoft Office" | It supports installing *licensed* Office. Nothing is bundled |
| "It's based on Zorin" | It is based on Ubuntu 24.04 LTS. Zorin is only the thing being replaced |
| "It's production ready" | It has never been deployed to a classroom |
| "Here's the ISO" (pointing at a mockup) | Instant credibility loss |
| "It gets updates from Zorin" | It does not. It gets updates from Ubuntu — see `docs/updates.md` |

The reframe is not a weakness. "We built on Ubuntu 24.04 because Zorin's terms
forbid rebranding and Canonical permits internal modification" is a *better*
answer than a clone would have been, because it shows you read the licences.

---

## Pre-demo checklist

**Two days before**

- [ ] Tier 1 completed; screenshots and one boot video captured
- [ ] `verify-branding.sh` passing on the demo VM
- [ ] Deck slide captions say "design render" where applicable
- [ ] `docs/proposal.md` `[[TODO]]` markers that affect your *spoken* claims filled in

**The morning of**

- [ ] VM boots, branding intact (snapshot taken, in case you break it live)
- [ ] ISO on a USB stick, **tested to the desktop** on a machine that is not your workstation
- [ ] Booted once with Secure Boot ON, so nobody can say "it only works in legacy mode"
- [ ] Laptop charged, HDMI adapter packed, files also on the stick
- [ ] One sentence ready for "why not just keep Zorin?" — see `docs/licensing.md`

**If the live demo dies**

Fall back to Tier 0 without apologising. The renders exist for exactly this.
"The build machine is in the lab, so here are the renders and the boot video" is
a normal, unremarkable sentence.

---

## Regenerating everything

```bash
./scripts/make-demo-assets.sh      # -> payload/assets/*.png
./scripts/make-demo-mockups.sh     # -> demo/mockups/*.png
```

Both read `payload/branding/tokens.env`. Change a colour there, re-run, and every
asset and render follows. `payload/assets/README.md` lists the real artwork the
design office must supply to replace the placeholders.
