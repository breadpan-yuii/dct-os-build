# Dominican OS — build repo

An **internally deployed** Ubuntu Cinnamon 24.04 LTS image, rebranded for
Dominican College of Tarlac. Not a public distribution. Not derived from Zorin
OS assets.

> Dominican OS is built on Ubuntu Cinnamon 24.04 LTS. Not affiliated with Zorin
> OS or Canonical.

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
| 4 | ISO assembly (live-build) + Calamares branding | you | `live-build/`, `installer/` |
| 5 | Deployment + fleet config | you | `ansible/`, `scripts/audit-secureboot.sh` |

Everything in `payload/` is **build-system agnostic**. That is the whole trick:
the same payload drives the slow reproducible live-build pipeline *and* the fast
"apply to a running VM" loop. You never re-invent the branding twice.

## The dev loop (this is the part that saves you weeks)

Re **never** iterate by rebuilding an ISO. An ISO build is 25–60 minutes.

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
| **Boot test** | `./scripts/test-live-iso.sh` | Before writing any ISO to a stick |
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

| | State |
|---|---|
| Branding layer (`payload/` + `scripts/`) | Written **and tested** against a fake root |
| Update resilience (diversion + apt hook) | Written; verified by `--check-updates` in the ISO build |
| Demo material (`demo/mockups/`, `payload/assets/`) | Generated from the **real DCT artwork** in `payload/assets/source/` |
| Live ISO (remaster of Ubuntu 24.04) | Built by `scripts/build-live-iso.sh`; boot-tested by `scripts/test-live-iso.sh` |
| Reproducible ISO (`.deb` packages, live-build) | Written, **never executed** — needs a container runtime |

`make demo` regenerates every asset and render from `tokens.env`.

For a demo this week, use **Tier 2** in `docs/demo.md`: the bootable live ISO.
Do not wait on the container build.
