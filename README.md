# Dominican OS — build repo

An **internally deployed** Ubuntu Cinnamon 24.04 LTS image, rebranded for
Dominican College of Tarlac. Not a public distribution. Not derived from Zorin
OS assets.

> Dominican OS is built on Ubuntu Cinnamon 24.04 LTS. Not affiliated with Zorin
> OS or Canonical.

## At a glance

| | |
|---|---|
| Product | **Dominican OS 1.0** (codename *Noble*); internal identifiers stay `dct` |
| Base | Ubuntu Cinnamon 24.04.5 LTS — an official Ubuntu flavour, Canonical's signed boot chain intact |
| Desktop | Cinnamon, purple + gray, from `Yaru-purple-dark` and one `tokens.env` |
| Office | OnlyOffice (default) · LibreOffice (fallback) · Wine. Microsoft Office only from DCT's licensed media — never bundled |
| Target hardware | Pentium-class CPU, 4 GB RAM |
| Artefact | `dist/Dominican-OS-1.0-live-amd64.iso` — 7.53 GB, boots to a live desktop without installing |
| Scope | Internal institutional deployment only. Not a public distribution |

---

## The mental model: five layers

Dominican OS is not "a distro you write". It is **Ubuntu + a thin layer of
packages**.
That is exactly how Zorin OS itself is built — its own image is 30-odd `zorin-*`
packages sitting on top of an otherwise stock Ubuntu 24.04:

| Layer | What it is | Who owns it | Lives here |
|---|---|---|---|
| 1 | Ubuntu Cinnamon 24.04 LTS base + signed boot chain | Canonical | not in this repo |
| 2 | `dct-os-desktop` — the app set (one metapackage) | you | `packages/dct-os-desktop/` |
| 3 | `dct-os-defaults` — identity, theme, dconf, policies | you | `packages/dct-os-defaults/` + `payload/` |
| 4 | ISO assembly (live remaster, or live-build) + installer branding | you | `scripts/build-live-iso.sh`, `live-build/`, `installer/` |
| 5 | Deployment + fleet config | you | `ansible/`, `scripts/audit-secureboot.sh` |

Everything in `payload/` is **build-system agnostic**. That is the whole trick:
the same payload drives the slow reproducible live-build pipeline *and* the fast
"apply to a running VM" loop. You never re-invent the branding twice.

## The dev loop (this is the part that saves you weeks)

**Never** iterate by rebuilding an ISO. An ISO build is 25–60 minutes.

```
  1. Ubuntu 24.04 VM
        │
  2. sudo ./scripts/apply-branding.sh        ← 15 seconds, idempotent
        │
  3. look at it, change payload/, goto 2     ← repeat 30–60 times
        │
  4. ./scripts/verify-branding.sh            ← catches leftover marks
        │
  5. make iso                                ← once, when it looks right
```

Step 2 is a plain shell script. Step 5 consumes the same files. If you find
yourself editing an ISO by hand, stop — the change belongs in `payload/`.

## Build paths

| Path | Command | When to use |
|---|---|---|
| **Branding loop** | `sudo ./scripts/apply-branding.sh` on a prepared VM | You are changing assets or theme |
| **Live ISO** | `sudo ./scripts/build-live-iso.sh` | You need a bootable USB for a real PC, now |
| **Boot test** | `./scripts/test-live-iso.sh --serial` (does it reach a desktop?) and `--structure` (are the parts in the image?) | Before writing any ISO to a stick |
| **Reproducible** | `make pkgs && make iso` | Production, once branding is settled |

The live ISO path remasters the official Ubuntu Cinnamon 24.04 ISO. Ubuntu
Cinnamon 24.04.5 ships the same **layered** casper filesystem as Ubuntu
(`minimal.squashfs` → `minimal.standard.squashfs` →
`minimal.standard.live.squashfs`) rather than a single `filesystem.squashfs`, so
the script overlay-mounts the chain, brands the union, writes the branded system
back into the base layer and reassembles the image with `xorriso`. It needs no
container runtime, keeps Canonical's signed boot chain (so Secure Boot still
works), and boots to a desktop **without installing anything**. The result lands
in `dist/Dominican-OS-1.0-live-amd64.iso`.

The lean build ships LibreOffice only. Add the office stack with
`--with-office` (OnlyOffice default, LibreOffice fallback, Wine + winetricks as
the compatibility layer for DCT's own licensed Office media). Microsoft Office
is never bundled; see **`docs/office.md`** for the licensing and version rules.

`./scripts/test-live-iso.sh` then boots that image in QEMU — a serial-console
boot that waits for a login prompt, plus a UEFI/GRUB boot with screenshots. Do
not skip it because the build said "ok".

The reproducible path is a step-by-step runbook in **`docs/demo.md`**. Read that
before promising anyone an ISO.

`make pkgs` / `make iso` require `podman` (or `docker`) and ~25 GB free disk.
The live ISO path needs `xorriso` and `squashfs-tools` instead.

## Theme

Purple + gray, from one file: `payload/branding/tokens.env`. The GTK theme,
icons, Cinnamon shell and login greeter all use Ubuntu's `Yaru-purple-dark`,
which ships in the base and carries exactly the DCT accent (`#7764D8`), so
there is no hand-maintained theme to break on an update. The login screen is
`dct-greeter.png` (purple→gray) plus `/etc/lightdm/slick-greeter.conf`. GRUB,
plymouth, Calamares and the installer artwork are templates with `@DCT_*@`
placeholders that `apply-branding.sh` renders from the tokens. Change a hex in
`tokens.env`, rebuild, done.

## Layout

```
payload/         branding files, placed at final system paths by the package
packages/        the two .deb source trees that make up Dominican OS
scripts/         apply, verify, audit, build, demo assets
installer/       Calamares installer sequence (build-time only)
live-build/      ISO assembly config
ansible/         post-deployment fleet config
demo/mockups/    slide-ready renders — label these "design render"
docs/            demo runbook, proposal, architecture, licensing, secure boot
```

## Read next

- `docs/demo.md` — **what you can show today**, and how to get to a bootable ISO
- `docs/updates.md` — where updates come from, and why they do not undo the branding
- `docs/proposal.md` — the project proposal, ready to fill in and submit
- `docs/architecture.md` — how the pieces actually connect
- `docs/secureboot.md` — **read this before touching firmware on any lab PC**
- `docs/branding-checklist.md` — the file-by-file list you'll work through
- `docs/licensing.md` — what you may and may not redistribute

## Status

| Area | State |
|---|---|
| Branding layer (`payload/` + `scripts/`) | Written; `apply-branding.sh` applied to the live image and `verify-branding.sh` passes with **0 failures** |
| Theme (purple + gray) | Finalized. GTK, icons, Cinnamon shell and greeter all use `Yaru-purple-dark`; every colour comes from `payload/branding/tokens.env` |
| Login greeter | `dct-greeter.png` + `/etc/lightdm/slick-greeter.conf`; confirmed present in the image, **not yet seen on screen** |
| Boot | Plymouth themed and colour-checked against the tokens. GRUB menu relabelled; the live ISO's GRUB is not themed (installed systems are) |
| Installer | Canonical's `ubuntu-desktop-bootstrap` snap, launcher renamed **Install Dominican OS**, artwork overlaid at boot. Auto-launch is masked, so the live session is try-only |
| Live ISO | Built and boot-tested: `dist/Dominican-OS-1.0-live-amd64.iso`, 7.53 GB. Serial boot **3/3** (real casper medium detection, no `ignore_uuid`), structure **15/15**. Sum in the matching `.sha256` file |
| Reproducible ISO (`.deb` packages, live-build) | Written, **never executed** — needs a container runtime |
| Office stack | OnlyOffice default, LibreOffice fallback, Wine bundled. Microsoft Office installs only from DCT's licensed media, which has not been supplied, so that path is untested |

**Proven:** the image boots to a live desktop — casper finds its medium, assembles
the layer chain and hands over to systemd, with the host named `dominican`.
Branding files are in the right paths, every theme named in the overrides exists,
greeter policy matches the schema, plymouth colours match `tokens.env`, and the
installer overlay unit is enabled.

**Not yet proven:** how the desktop and greeter actually look, idle RAM on a
4 GB machine, the installer window on screen, an install from the ISO, and a
Secure Boot boot on real hardware. These need a person at a VM or a lab PC.

**Open blockers:** official DCT brand hex, vector artwork and written permission
to use the seal, and the licensed Office media. `docs/branding-checklist.md`
lists the remaining decisions phase by phase.

`make demo` regenerates every asset and render from `tokens.env`.

For a demo this week, use **Tier 2** in `docs/demo.md`: the bootable live ISO.
Do not wait on the container build.
