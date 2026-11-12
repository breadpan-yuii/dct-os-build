# Updates — where they come from and why branding survives them

Short answer, because this comes up in every panel: **DCT OS is not based on
Zorin OS, so it receives no Zorin updates.** It is Ubuntu 24.04 LTS underneath,
and it receives Canonical's updates. That is intentional — Zorin's terms do not
permit rebranded derivatives, and inheriting their repositories would drag their
artwork and their packages onto every classroom PC.

The rest of this document is the interesting part: what happens to the branding
when an update lands.

---

## 1. What is actually configured to update

| Source | What it delivers | Can it overwrite branding? |
|---|---|---|
| `archive.ubuntu.com` / `security.ubuntu.com` (`noble`, `noble-updates`, `noble-security`, `noble-backports`) | Every Ubuntu package, including `base-files`, the kernel, GRUB, Plymouth | **Yes** — see §3 |
| Snap Store | Firefox, Snap Store, firmware | No — separate mount namespace, never touches `/etc` or `/usr/share/backgrounds` |
| Ubuntu Pro / ESM (optional) | Security patches for universe after 5 years | Same as archive: handled by §3 |
| Zorin repositories | — | **Not configured. Not wanted.** |

Verify that last row any time:

```bash
grep -ril zorin /etc/apt/ 2>/dev/null || echo "no Zorin sources configured"
apt-cache policy | grep -i zorin || echo "no Zorin packages in the index"
```

If either command ever prints something, someone copy-pasted a Zorin
instructions page into this machine. Remove the source list and run
`apt update` before doing anything else.

> **Why not hook up to Zorin's repos anyway?** Because they are Zorin's. Their
> packages assume Zorin's `base-files`, Zorin's themes and Zorin's `zorin-os-*`
> metapackages. You would be running a half-Zorin system with a DCT logo on it,
> which is exactly the derivative that `docs/licensing.md` §3 rules out — and
> the first `zorin-desktop` update would repaint the desktop regardless of what
> we do here.

---

## 2. The upgrade question, stated properly

"What happens when Ubuntu pushes an update?" splits into two very different
risks:

1. **A package owns a file we replaced.** dpkg overwrites those silently.
   This is real and used to be the thing that broke rebranded distros.
2. **A package owns a file we created.** It doesn't, because we put our files
   at paths no package claims.

The inventory:

| Path | Owner before we touch it | Ours after |
|---|---|---|
| `/etc/os-release` | `base-files` | diverted (§3) |
| `/usr/lib/os-release` | `base-files` | diverted (§3) |
| `/etc/lsb-release` | `base-files` | diverted (§3) |
| `/etc/issue`, `/etc/issue.net` | `base-files` | diverted (§3) |
| `/etc/motd` | nobody (pam_motd generates it) | ours, untouched |
| `/etc/default/grub` | `grub-common` (**conffile**) | edited in place; dpkg keeps local edits |
| `/boot/grub/themes/dct/` | nobody | ours, untouched |
| `/usr/share/plymouth/themes/dct/` | nobody | ours, untouched |
| `/usr/share/glib-2.0/schemas/99_dct-os.gschema.override` | nobody | ours, untouched |
| `/usr/share/backgrounds/dct/` | nobody | ours, untouched |
| `/etc/firefox/policies/policies.json` | nobody | ours, untouched |

So the entire exposure is **five files owned by `base-files`**, plus the
conffile behaviour of GRUB — which is already what we want.

---

## 3. Three layers, in order of importance

### Layer 1 — dpkg diversions (the actual fix)

`apply-branding.sh` registers a diversion for each of the five `base-files`
paths:

```bash
dpkg-divert --package dct-os-defaults \
            --divert /etc/os-release.dct-orig \
            --no-rename --add /etc/os-release
```

What this does: dpkg's database now says "any package that writes
`/etc/os-release` writes `/etc/os-release.dct-orig` instead". `base-files`
continues to upgrade normally — it is not held, not pinned, and still receives
security fixes — but its copy of the file lands beside ours instead of on top of
it. `/etc/os-release` keeps saying DCT OS.

Inspect it:

```bash
dpkg-divert --list | grep dct
head -3 /etc/os-release          # DCT OS 1.0 (tarlac)
head -3 /etc/os-release.dct-orig # what base-files last delivered
```

On Ubuntu 24.04 `base-files` ships `/etc/os-release` as a symlink to
`/usr/lib/os-release`, so the quarantined copy can land at either
`/etc/os-release.dct-orig` or `/usr/lib/os-release.dct-orig`. Both are diverted;
check whichever one exists.

`.dct-orig` is supposed to exist and is supposed to change on upgrades. It is
the upstream file, quarantined. If you ever need to hand control back:

```bash
sudo dpkg-divert --package dct-os-defaults --divert /etc/os-release.dct-orig \
                 --rename --remove /etc/os-release
```

### Layer 2 — an APT hook (the safety net)

`/etc/apt/apt.conf.d/99dct-branding` runs `/usr/sbin/dct-rebrand` after every
dpkg transaction. It re-applies identity files, the schema override and the
wallpaper keys. It is deliberately narrow: it never rebuilds the initramfs and
never invokes apt, so it cannot recurse or slow a normal install down.

It exists for the cases a diversion cannot cover — a future theme package that
ships a file at one of our paths, a maintainer script that regenerates
`/etc/issue`, a snapshot restore that drops files in with the wrong content.

### Layer 3 — the payload lives on the machine

`apply-branding.sh` is installed at `/usr/share/dct-os/apply-branding.sh` with
its `payload/` beside it. So the self-healing in layer 2 does not depend on the
repository being present, and an admin on a classroom PC can simply run:

```bash
sudo /usr/share/dct-os/apply-branding.sh
```

It is idempotent. That is the whole maintenance model: if something looks
off-brand, run the script. It converges.

---

## 4. What upgrades do *not* touch, and why

- **GRUB menu theme.** `/etc/default/grub` carries
  `GRUB_THEME="/boot/grub/themes/dct/theme.txt"` and `GRUB_DISTRIBUTOR="DCT OS"`.
  A kernel update runs `update-grub`, which reads that file and regenerates
  `grub.cfg` *with our theme*. The theme directory itself is not package-owned.
- **Plymouth splash.** The theme directory is ours, and
  `/etc/plymouth/plymouthd.conf` selects it. A `plymouth` package update adds
  files but does not remove or reselect our theme. The one exception: a kernel
  update rebuilds the initramfs, so the *early* splash is regenerated from
  whatever theme is selected — which is ours.
- **Desktop defaults.** GSettings overrides are separate files; updating
  `gnome-shell` does not delete `99_dct-os.gschema.override`. The
  `glib-compile-schemas` trigger runs automatically as part of the package
  upgrade, so our keys stay compiled in.

## 5. Verify it yourself

The build has a flag that answers this question with evidence rather than
assertion. It extracts the root filesystem, reinstalls the one package that
would do the damage, and checks the result:

```bash
sudo ./scripts/build-live-iso.sh --check-updates
```

Expected lines in the log:

```
ok /etc/os-release still says ID=dctos after base-files reinstall
ok identity file byte-identical (diversion held)
ok base-files wrote to /etc/os-release.dct-orig, as intended
ok apt hook repaired a deliberately clobbered identity
```

The last line is the interesting one: the test deliberately overwrites
`/etc/os-release` with Ubuntu's copy and then asks the hook to repair it. If that
passes, a surprise overwrite is an inconvenience, not a re-image.

On a running system, the same check by hand:

```bash
sudo apt install --reinstall -y base-files
head -3 /etc/os-release     # must still be DCT OS
sudo dpkg-divert --list | grep dct
```

---

## 6. Deliberate non-goals

- **No `apt-mark hold`.** Holding `base-files` would stop security updates to
  the package that owns `/etc/identity` and `/etc/debian_version`. Diversions
  are the right tool; holds are the blunt one.
- **No forked `base-files` package.** Mint and Pop!_OS do this and then have to
  track Ubuntu's releases forever. A diversion is three lines and cannot drift.
- **No automatic Zorin repository.** Discussed in §1.
- **No "re-image after every update".** If that were the answer, the project
  would be a screenshot, not a distro.
