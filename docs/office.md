# Office on Dominican OS

The classroom image ships **two** office suites and a compatibility layer for a
**third**, licensed one:

| Role | What ships | Licence |
|---|---|---|
| Default suite | OnlyOffice Desktop Editors 10.0.0 | AGPLv3, redistributable |
| Fallback | LibreOffice 24.2 (already in the Ubuntu Cinnamon base) | MPL/LGPL |
| Compatibility layer | Wine 9.0 + winetricks | LGPL |
| Microsoft Office | **not bundled** — installed from DCT's own licensed media | Microsoft EULA |

## Why Microsoft Office is not in the ISO

Microsoft Office is proprietary. It is **not redistributable**, there is no
lawful public download of the installer, and bundling it (or a product key) in
an image that is copied to USB sticks would breach the licence. That is also
what `docs/licensing.md` already requires.

What the image *does* carry is everything needed to run Office once DCT supplies
its own licensed media:

- `wine`, `wine64`, `winetricks`, `cabextract`, `p7zip-full`
- `/usr/local/bin/dct-office-install` and a menu entry
  **Install Microsoft Office (licensed media)**

Frame this in the proposal as **"supports installation of licensed Microsoft
Office"**, never as "includes Microsoft Office".

## Which Office version, and why 2016

| Version | Under Wine | Verdict |
|---|---|---|
| Office 2013 | Works | older, out of support |
| **Office 2016 (VL, MSI)** | **Works with prerequisites** | **target** |
| Office 2019 (VL, MSI) | Mostly works | acceptable alternative |
| Office 2021 | Unreliable | do not promise |
| Microsoft 365 | Click-to-Run; will not activate | do not promise |

Office 2016 Volume Licence is MSI-based, which Wine can drive. 2021/365 are
Click-to-Run and depend on services Wine does not reproduce. The installer
helper therefore targets **Office 2016 (64-bit)**.

**32-bit caveat:** the image does not ship `wine32`/i386 multiarch, so the
helper expects **64-bit** Office 2016 media. Supporting 32-bit Office means
enabling i386 and adding `wine32` — a separate, larger change.

## Using it

On the live desktop or an installed machine:

```bash
# with the licensed media on a USB stick or network share
dct-office-install /media/usb/office2016.iso
dct-office-install /srv/software/office2016/setup.exe

# or, if the media was baked into the image at build time
dct-office-install            # reads /opt/dct-office-media
```

The helper creates a dedicated prefix at `~/.wine-office`, installs the Wine
prerequisites (`corefonts`, `msxml6`, `riched20`, `gdiplus`), then runs
`setup.exe`. To start over, `rm -rf ~/.wine-office`.

## Building an image that carries the licensed media

Only do this if DCT holds the licence and is entitled to deploy that media to
its own machines:

```bash
sudo ./scripts/build-live-iso.sh --with-office \
     --office-media /path/to/office2016.iso
```

`--office-media` implies `--with-office` and copies the media to
`/opt/dct-office-media/` **inside the image**. The media is never committed to
this repository.

## What `--with-office` installs

- OnlyOffice: the vendor `.deb` for 10.0.0, downloaded from the vendor pool and
  verified against the SHA-256 published in the vendor's own `Packages` index
  (`2190edb4022a2ac2f6eee0f78815520f0e4ece1e8a1097c645a6f9b225c8b59c`). No
  third-party APT source or signing key is added to the image.
- Wine 9.0, `wine64`, `winetricks`, `cabextract`, `p7zip-full`, `unzip`.
- The `dct-office-install` helper and its menu entry.

OnlyOffice's Debian-era dependency names (`libasound2`, `libgtk-3-0`,
`libcups2`, `libatk1.0-0`) resolve on noble through the `t64` packages'
`Provides:` fields; this was checked against the real noble `Packages` indexes,
not assumed.

## Verify on a built image

```bash
# OnlyOffice
gsettings get org.cinnamon favorite-apps        # includes onlyoffice-desktopeditors.desktop
ls /usr/share/applications/onlyoffice-desktopeditors.desktop

# Wine + helper
command -v wine winetricks dct-office-install
dct-office-install --help
```
