# Assets — supplied by the DCT design office, not generated here

Drop files here before running `scripts/apply-branding.sh`. Names are load-bearing.

> **Current contents are placeholders.** The PNGs in this directory were generated
> by `scripts/make-demo-assets.sh` from `payload/branding/tokens.env` so the demo
> and the brand audit can run before the design office delivers anything. They are
> flat colour + the letters "DCT" — not the institutional seal. Replace every one
> of them before the pilot, and before you show this to anyone outside the project.
> Regenerate with `make demo`.

## Required

| File | Where it ends up | Spec |
|---|---|---|
| `logo.png` | `/usr/share/plymouth/themes/dct/logo.png` | 480×270, transparent PNG |
| `logo.svg` | `/usr/share/pixmaps/dct-logo.svg` | vector source, the master |
| `dct-logo.png` | `/usr/share/pixmaps/dct-logo.png` | 192×192 for the greeter |
| `background.png` | `/boot/grub/themes/dct/background.png` | 1920×1080 |
| `dct-default.png` | `/usr/share/backgrounds/dct/` | 3840×2160, day |
| `dct-default-dark.png` | `/usr/share/backgrounds/dct/` | 3840×2160, dark |
| `dct-lock.png` | `/usr/share/backgrounds/dct/` | 3840×2160, lock screen |
| `progress_bg.png` / `progress_fg.png` | plymouth theme dir | 300×8, optional |

## Rules

1. **Vector first.** Get the SVG/seal from DCT, never trace a JPEG off the website.
2. **Get written permission** to use the institutional seal on an operating system
   image. That is a separate approval from "we are a DCT project".
3. **Do not use Zorin or Ubuntu artwork** as a base or reference file. Derive from
   your own brand sheet.
4. Fonts: `Inter` and `JetBrains Mono` are SIL OFL — safe to redistribute. Do not
   drop a proprietary typeface here, even if the brand sheet specifies one.
5. Flat colours only in the PNGs that plymouth loads — alpha gradients in the
   splash render badly on some firmware.
