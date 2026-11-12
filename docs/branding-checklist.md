# Branding checklist

Work top to bottom. Each phase is independently demoable.

Legend: ✅ done by `apply-branding.sh` · 🎨 needs an asset from `payload/assets/`
· ✍️ needs a decision from DCT

---

## Phase A — Identity (✅)

| Item | Path | Notes |
|---|---|---|
| OS name/version | `/etc/os-release` | divert-protected; `UBUNTU_CODENAME=noble` must stay |
| LSB info | `/etc/lsb-release` | |
| Console banner | `/etc/issue`, `/etc/issue.net` | |
| Login message | `/etc/motd` | |
| GRUB menu label | `/etc/default/grub` → `GRUB_DISTRIBUTOR` | |
| Package vendor | `/etc/dpkg/origins/` | optional, low value |

Verify: `cat /etc/os-release`, `hostnamectl`.

## Phase B — Boot (✅ + 🎨)

| Item | Path | Notes |
|---|---|---|
| GRUB theme | `/boot/grub/themes/dct/theme.txt` | ✅ |
| GRUB background | `/boot/grub/themes/dct/background.png` | 🎨 1920×1080 |
| GRUB timeout | `/etc/default/grub` → `GRUB_TIMEOUT=3` | ✍️ decide |
| Plymouth theme | `/usr/share/plymouth/themes/dct/` | ✅ |
| Plymouth logo | `.../dct/logo.png` | 🎨 480×270 |
| Firmware boot logo | — | ❌ impossible with Secure Boot on. Skip. |

Verify: reboot and watch. `sudo plymouth-set-default-theme --list`.

## Phase C — Login and desktop (✅ + 🎨)

| Item | Path | Notes |
|---|---|---|
| Greeter logo | `/usr/share/pixmaps/dct-logo.png` | 🎨 |
| Greeter banner | gschema `org.gnome.login-screen` | ✅ |
| Wallpapers (day/dark/lock) | `/usr/share/backgrounds/dct/` | 🎨 3840×2160 |
| GTK theme | `/usr/share/themes/dct-gtk/` | 🎨 Phase 3 work — build on Materia or Colloid, not from scratch |
| Icon theme | `/usr/share/icons/` | `Papirus-Dark` recoloured, or ship as-is initially |
| Cursor theme | `/usr/share/icons/dct-cursors/` | 🎨 optional |
| Sound theme | `/usr/share/sounds/dct/` | 🎨 optional |
| Fonts | `/usr/share/fonts/` | `Inter` + `JetBrains Mono` (OFL). ✍️ confirm with DCT brand |
| Layout (taskbar/start menu) | GNOME extensions | ✍️ Windows-like or macOS-like? |

Until `dct-gtk` exists, `apply-branding.sh` warns and falls back to
`Adwaita-dark` so the desktop is never half-broken.

## Phase D — Applications (✍️)

| Item | Action |
|---|---|
| Default office suite | OnlyOffice primary, LibreOffice fallback |
| OnlyOffice | enable `config/archives/onlyoffice.*` in `live-build/` |
| Wine | installed; MS Office **not** bundled |
| Browser homepage + bookmarks | `payload/policies/firefox-policies.json` — needs real DCT URLs |
| Portal shortcut | ✍️ add a `.desktop` for the student portal |
| LMS client | ✍️ which one? Moodle PWA is usually enough |
| Hide unused apps | edit `payload/gschema/99_dct-os.gschema.override` `favorite-apps` |
| Default MIME handlers | `xdg-mime` / `/etc/xdg/mimeapps.list` |

## Phase E — Installer (✅)

| Item | Path |
|---|---|
| Calamares branding | `/etc/calamares/branding/dct/` |
| Product name/URLs | `branding.desc` |
| Colours | `stylesheet.qss` |
| Slideshow | not shipped — add later, a broken `show.qml` crashes the installer |

## Phase F — Classroom operations (✍️)

| Item | Action |
|---|---|
| Autologin | ✍️ security decision — usually **off** |
| Guest session | disabled by default (ansible) |
| Idle lock | 10 min (gschema) |
| Printer | ✍️ which model? add driver to the package list |
| Screen broadcast / management | `epoptes-client` + server address |
| Rollback | `timeshift`, weekly cron (ansible) |
| Updates | `unattended-upgrades` via campus mirror |

---

## Definition of done

`./scripts/verify-branding.sh` returns **0 failures**, and:

```bash
grep -ril zorin /etc /usr/share/{backgrounds,plymouth,themes,icons} 2>/dev/null
```

returns nothing. That grep is the one that matters legally, not aesthetically.
