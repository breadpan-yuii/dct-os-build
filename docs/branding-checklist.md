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

The palette is **purple + gray**, and every surface pulls its accent from
`payload/branding/tokens.env`. The theme is Ubuntu's own `Yaru-purple-dark`,
which ships in the base and carries exactly `#7764D8`
(`X-Yaru-Accent-Color` in its `index.theme`). Nothing is hand-authored, so
nothing can rot on the next Yaru update.

| Item | Path | Notes |
|---|---|---|
| Greeter logo | `/usr/share/pixmaps/dct-logo.png` | 🎨 256×256, transparent |
| Greeter background | `/usr/share/backgrounds/dct/dct-greeter.png` | 🎨 purple→gray 3840×2160 |
| Greeter policy | `/etc/lightdm/slick-greeter.conf` | ✅ wins over the schema at every start |
| Greeter defaults | gschema `x.dm.slick-greeter` | ✅ kept in sync with the conf |
| Wallpapers (day/dark/lock/greeter) | `/usr/share/backgrounds/dct/` | 🎨 3840×2160 |
| GTK theme | `/usr/share/themes/Yaru-purple-dark/` | ✅ ships in the base |
| Icon theme | `/usr/share/icons/Yaru-purple-dark/` | ✅ ships in the base |
| Cursor theme | `/usr/share/icons/Yaru/` | ✅ ships in the base |
| Window borders | `/usr/share/themes/Yaru-dark/` | ✅ only Yaru theme with `metacity-1/` |
| Sound theme | `/usr/share/sounds/Yaru/` | ✅ ships in the base |
| Fonts | `/usr/share/fonts/` | `Inter` + `JetBrains Mono` (OFL), installed by the build |
| Layout (taskbar/start menu) | Cinnamon panel | ✍️ Windows-like or macOS-like? |

`apply-branding.sh` checks every theme name in the override **section-aware**
(`theme-name` is the GTK theme in the greeter but the sound theme in a
`.sound` section, and the Cinnamon wm theme needs `metacity-1/`). A missing
theme falls back to Adwaita/freedesktop and prints a warning instead of
silently producing a half-branded desktop.

Do **not** reintroduce `dct-gtk`, `dct-cursors` or `dct` sound themes. They
were removed on purpose: they duplicated upstream themes for no visual gain
and broke on every Yaru release.

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
| Product name/URLs | `branding.desc` — rendered from `payload/branding/tokens.env` |
| Colours | `stylesheet.qss` + `branding.desc` — rendered from `tokens.env` |
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
