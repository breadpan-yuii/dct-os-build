# How DCT OS fits together

## Layers

```
┌─────────────────────────────────────────────────────────────┐
│ 5  Deployment     ansible/  ·  Clonezilla / PXE  ·  epoptes │
├─────────────────────────────────────────────────────────────┤
│ 4  ISO assembly   remaster of the Ubuntu ISO (scripts/build-live-iso.sh) │
├─────────────────────────────────────────────────────────────┤
│ 3  dct-os-defaults   identity + theme + dconf + policy      │
│                       payload/  ← all branding lives here   │
├─────────────────────────────────────────────────────────────┤
│ 2  dct-os-desktop    the app set, one metapackage           │
├─────────────────────────────────────────────────────────────┤
│ 1  Ubuntu 24.04 LTS  + Canonical signed boot chain          │
└─────────────────────────────────────────────────────────────┘
```

Layer 1 is not yours. Layers 2–4 are about 1,500 lines of shell, CSS and debian
control files. That is the whole "distro".

This is not a simplification for a school project — it is how Zorin OS itself is
built. Their image is 30 `zorin-*` packages over stock Ubuntu 24.04, including
`zorin-os-desktop`, `zorin-os-defaults`-equivalent, `zorin-gtk-theme` and
`zorin-os-wallpapers`. Same architecture, different logo.

## Why `payload/` is separate from the ISO builder

The single most expensive mistake in a project like this is treating the ISO as
the editable artefact. You then spend 40 minutes per typo.

`payload/` holds plain files destined for final system paths. Three consumers read
it:

1. `scripts/apply-branding.sh` — copies them into a *running* system in ~15 s.
2. `packages/dct-os-defaults` — ships them in a `.deb`, which a full build
   installs.
3. `scripts/build-live-iso.sh` — runs the same script with `--root` against the
   materialised ISO tree, so the bootable demo and the installed system cannot
   drift apart.

Both go through the same script (`/usr/share/dct-os/apply-branding.sh`), so
there is exactly one implementation of "what DCT OS branding means".

### The loop

```
edit payload/  →  sudo ./scripts/apply-branding.sh  →  look  →  repeat
                              ↓ satisfied
              ./scripts/verify-branding.sh  →  make pkgs  →  make iso
```

`--dry-run` prints every action without touching anything. `--no-initramfs`
skips the slow initramfs rebuild while you are only changing wallpapers.

## What live-build actually does

This is the native, fully-reproducible path, kept for the production rollout. It
is **not** what produces the demo ISO — see "Demo path" below.

Three stages, each resumable:

| Stage | Output | What happens |
|---|---|---|
| `bootstrap` | `chroot/` | `debootstrap` a minimal Ubuntu 24.04 into a directory |
| `chroot` | `chroot/` (populated) | apt-installs the package list, then runs `config/hooks/live/*.hook.chroot` inside it |
| `binary` | `binary/` → `.iso` | squashes the chroot to `filesystem.squashfs`, adds kernel/initrd, writes the ISO with `xorriso` |

The hooks are the interesting part:

- `0100-dct-install-debs.hook.chroot` — `dpkg -i` the local packages that
  `build-iso.sh` copied into `/var/tmp/dct-debs`.
- `0200-dct-branding.hook.chroot` — re-runs branding after everything else has
  installed, and trims the 13 LibreOffice locales Zorin ships down to `en`.

`auto/config` regenerates `config/` on every run, which is why `build-iso.sh`
copies the debs *after* `auto/config` and not before.

## Demo path (this week): remaster, not live-build

The bootable artefact for the proposal defence is produced by **remastering the
official Ubuntu 24.04.5.1 ISO**, not by `lb build`. `scripts/build-live-iso.sh`
does this end to end and needs only `xorriso`, `squashfs-tools` and root — it
runs from this Arch host, needs no Docker, and leaves Canonical's signed
shim/GRUB/kernel chain untouched, so the result still boots with Secure Boot on.

```bash
sudo pacman -S --needed xorriso squashfs-tools      # Arch host, once
sudo ./scripts/build-live-iso.sh --fast --check-updates   # ~40 min
./scripts/test-live-iso.sh                                # prove it boots
```

Then write it to a stick (`docs/demo.md` has the `dd` line).

The pipeline, in order:

1. verify the cached `base.iso` against Canonical's published SHA-256;
2. detect the live layer and walk the layer chain down to the base;
3. extract each layer, overlay-mount the union (`lowerdir=l2:l1:l0`), and
   materialise it with `rsync -aHAX --numeric-ids` so ownership, ACLs,
   xattrs and capabilities survive;
4. run `apply-branding.sh --root` against the materialised tree, including the
   update shield;
5. rebuild the initrd for the branded Plymouth splash, then **re-sync the medium
   UUID** (see below);
6. write the whole branded system back into the base layer, ship empty-but-valid
   upper layers, patch the GRUB/loopback menus, rewrite `install-sources.yaml`;
7. squash, reassemble with `xorriso -boot_image any replay`, and verify the
   result (volume ID, menu strings, UUID match, branding in the squashfs).

### What the layered casper layout changes

Ubuntu 24.04.5.1 no longer ships a single `filesystem.squashfs`. `/casper` holds
`minimal.squashfs`, `minimal.standard.squashfs`, `minimal.standard.live.squashfs`
plus per-language layers, and the initrd's `/etc/casper.conf` sets
`LAYERFS_PATH=minimal.standard.live.squashfs`. casper walks that name down one
dot-component at a time and overlays the stack **live → standard → minimal**, so
the live layer is topmost. The upper layers carry whiteouts that delete files
from the layers below; that is why the union must be materialised rather than
the layers edited individually.

Two consequences the script has to handle:

- **All branding goes into the base layer.** The upper layers are rebuilt as
  empty squashfs images of the same name. `install-sources.yaml` therefore points
  both installer entries at the base layer — pointing one at an intentionally
  empty upper layer would install a blank system.
- **The medium UUID is load-bearing.** `casperize.conf` sets
  `CASPER_GENERATE_UUID=1`, so every initrd rebuild runs `uuidgen -r` and bakes a
  *new* random UUID into `conf/uuid.conf`. casper finds its own medium by
  matching that UUID against `/.disk/casper-uuid-generic` on the ISO. A rebuilt
  initrd with an unchanged ISO therefore cannot boot. The script extracts the new
  UUID from the rebuilt initrd and rewrites `/.disk/casper-uuid-generic` to
  match, and adds `ignore_uuid` to every `linux` line as a second line of
  defence.

`filesystem.size` is not used by the layered path; `install-sources.yaml`
carries the size instead, and the script sets it to the total uncompressed bytes.

### Why the builder refuses to delete a tree with mounts

`rm -rf` follows bind mounts. If the chroot has the host's `/dev` bind-mounted
and the script then deletes its own tree, it will delete the **host's** device
nodes. That happened once during development and is the reason for four
safeguards, none of which should be removed:

- chroot mounts are unmounted in reverse order (children first), with `umount -R`;
- a stale mount is peeled before mounting again, and the build stops if it cannot be;
- the tree is deleted with `rm -rf --one-file-system`, and only after `/proc/mounts`
  shows nothing left underneath it;
- preflight refuses to start if `/dev/null`, `/dev/zero` or `/dev/tty` are missing.

### Plymouth on 24.04

Ubuntu 24.04 no longer ships `plymouth-set-default-theme`. Runtime selection is
`Theme=dct` in `/etc/plymouth/plymouthd.conf`, but the initramfs hook picks the
theme from the `default.plymouth` **alternative**, so both are set: the
alternative via `update-alternatives`, the runtime config via `plymouthd.conf`.
The initrd is rebuilt only if the result still contains `scripts/casper`, the
casper boot config (`conf/conf.d/default-boot-to-casper.conf`) and the dct
theme; otherwise Ubuntu's original initrd is kept, because a rebuilt initrd
with an unknown medium UUID cannot boot.


> Earlier drafts proposed `penguins-eggs`. It is dropped: it clones a *running*
> system, is not reproducible, and would require building on a clean Ubuntu VM.
> The remaster is reproducible from a checksummed upstream image and is the only
> path that keeps the signed boot chain intact.

## Native path (if containers cannot mount)

On a real Ubuntu 24.04 host:

```bash
sudo apt install live-build debootstrap squashfs-tools xorriso \
                 mtools dosfstools grub-pc-bin grub-efi-amd64-bin
cd live-build
./auto/config
sudo lb build
```

## First-build failures, and what they mean

Expect three or four iterations. These are the usual culprits, in order of
likelihood:

| Symptom | Cause | Fix |
|---|---|---|
| `lb build` exits at chroot stage, package not found | A name in `package-lists/dct.list.chroot` does not exist on 24.04 | `apt-cache policy <name>` inside an `ubuntu:24.04` container |
| `dct-os-desktop` uninstallable | A `Depends:` name is wrong — most likely a GNOME extension package | move it to `Recommends:` (see the comment in `debian/control`) |
| Installs, but boots to black screen | `casper` / live-boot mismatch in ubuntu mode | keep `--mode ubuntu`; check `binary/live/` contains `vmlinuz` and `initrd.img` |
| Boots, but branding missing | hook ran before the package installed | check hook numbering; `0200-` must sort after `0100-` |
| ISO boots in QEMU but not on hardware | Secure Boot / missing firmware | see `secureboot.md`; test on one real PC early |
| Build takes over an hour | Fetching from archive.ubuntu.com in PH | set `DCT_MIRROR` to a local mirror |

Always test with:

```bash
./scripts/test-live-iso.sh        # structure + serial boot + UEFI screenshots
```

...before writing it to a USB stick. The serial boot is the decisive check: it
boots the ISO's own kernel and initrd in text mode and waits for a login prompt.

### Remaster failures, and what they mean

| Symptom | Cause | Fix |
|---|---|---|
| `Unable to find a medium containing a live file system` | the initrd's `conf/uuid.conf` and the ISO's `/.disk/casper-uuid-generic` disagree | rebuild; the script re-syncs them, do not hand-edit |
| Boots, then panics looking for `/casper` | layer chain broken — a renamed or missing layer file | check the build log's `layer chain:` line against `xorriso -find /casper` |
| Boots the branded GRUB, then stock Ubuntu | branding went into the wrong layer | it must go into the base layer; check `branded content goes into:` |
| Installed system is blank | `install-sources.yaml` points at an empty upper layer | both entries must point at the base layer |
| Installer offers two identical entries | expected — both are DCT OS; the ids are kept only so the installer recognises them | — |
| Build dies with "not enough disk space" | peak is ~22 GB (ISO + tree + new squashfs) | free space; layers are deleted as soon as they are mounted |
| Branding gone after `apt upgrade` | the update shield did not install | run `dct-rebrand`; see `updates.md` |

## What ships inside

| Content | Source |
|---|---|
| Ubuntu 24.04 LTS base + signed boot chain | Canonical |
| DCT app set | `dct-os-desktop` |
| Identity, themes, dconf, Firefox policy | `dct-os-defaults` + `payload/` |
| LibreOffice (en only) | Ubuntu archive, locales trimmed by hook |
| Wine + winetricks | Ubuntu archive |
| OnlyOffice | optional third-party repo — **disabled by default**, see `config/archives/` |
| Calamares installer with DCT branding | Ubuntu archive + `installer/` |
| Microsoft Office | **never** — see `licensing.md` |
