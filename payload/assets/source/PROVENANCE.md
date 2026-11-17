# Source artwork — provenance

These are the **only** files in this repository that are not original work. Record
where each came from and who owns it.

| File | Origin | Downloaded | Size | Notes |
|---|---|---|---|---|
| `dct-seal.png` | <https://dct.edu.ph/wp-content/uploads/2024/11/DCT-Logo-alt.png> | 12 Nov 2026 | 5000×5000 RGBA | Institutional seal, black line art on a white disc, transparent surround. The master. |
| `dct-lockup.png` | <https://dct.edu.ph/wp-content/themes/wp-bootstrap-creative-agency/img/DCT-long-alt.png> | 12 Nov 2026 | 4608×1536 RGBA | Seal + `DCT` wordmark, light art for dark backgrounds. |
| `dct-lockup-alt.png` | <https://dct.edu.ph/wp-content/themes/wp-bootstrap-creative-agency/img/DCT-long.png> | 12 Nov 2026 | 4608×1536 RGBA | Same lockup, alternate treatment. Kept for comparison. |
| `dct-seal-small.png` | <https://dct.edu.ph/wp-content/themes/wp-bootstrap-creative-agency/img/dctLogo.png> | 12 Nov 2026 | 355×350 RGBA | Site favicon copy of the seal. Low resolution — not used for output. |

Publisher: **Dominican College of Tarlac, Inc.**, <https://dct.edu.ph>.
The site footer credits the DCT MIS Department as designer/developer.

## Status of this download

Supplied by the institution for its own use, so using these assets in a DCT
internal deployment is consistent with the project's purpose. It is **not** the
same as written approval, and it is **not** a licence.

Outstanding before the pilot:

- [ ] Written permission from DCT to reproduce the seal on an operating-system
      image (a separate approval from "this is a DCT project")
- [ ] The official **vector** master (SVG/AI/EPS). Everything here is raster.
      A 5000 px PNG is adequate for the demo and for a 4K wallpaper. It is not
      adequate as a permanent source — a 5000 px seal scaled to a 192 px greeter
      icon every build loses the ability to thin measured strokes.
- [ ] Confirmation of the official brand colours. The seal is monochrome, so the
      **purple + gray** palette in `payload/branding/tokens.env` is **our**
      accent choice, not a DCT brand value. The purple (`#7764D8`) was picked
      because it is the exact accent of the `Yaru-purple-dark` theme that ships
      in the Ubuntu Cinnamon base, so the desktop, icons and greeter agree
      without a hand-authored theme. If DCT publishes a brand sheet, change the
      hex in `tokens.env` and rebuild — every generated asset follows.

## Rules

1. Do not edit these files. Derive from them (see `scripts/make-demo-assets.sh`).
2. Do not use them outside a DCT project.
3. If DCT supplies a vector master, drop it here and delete the raster copies.
4. Nothing in this directory is redistributed outside DCT. This matters: the
   project's own licensing position (`docs/licensing.md`) is that the image is
   for internal institutional deployment only.
