#!/usr/bin/env python3
"""Generate the installer artwork for Dominican OS from the single source seal.

The Ubuntu desktop installer (snap `ubuntu-desktop-bootstrap`) is a Flutter app.
It draws every page from six files inside the snap:

    bin/data/flutter_assets/packages/ubuntu_provision/assets/
        images/logo-light.svg          small mark, light theme
        images/logo-dark.svg           small mark, dark theme
        images/mascot.svg              big illustration (refresh page)
        images/mascot_no_background.svg
        theme/light-theme.png          page background, light
        theme/dark-theme.png           page background, dark

This script writes those six files into payload/installer/. The build copies
them over the snap's copies at boot (see payload/installer/dct-installer-brand);
the snap itself is signed, so it is never repacked.

The seal source is raster, so the mark is traced with potrace. Two things make
the trace faithful:

  * supersampling — trace at 4x so curves are smooth when the 900px mascot is
    drawn, then keep the 4x coordinates in the viewBox;
  * one compound path — potrace emits one contour per closed boundary and
    expresses holes by winding direction. Every contour must live in a single
    <path> so the holes subtract. One <path> per contour fills them solid.

Re-run only when payload/assets/dct-logo.png changes:

    uv run --with potracer --with pillow --with numpy \
        python3 scripts/make-installer-assets.py

The script verifies its own output and exits non-zero if the trace drifts.
"""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import potrace
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "payload" / "assets" / "dct-logo.png"
OUT = REPO / "payload" / "installer"

NAVY = "#0B2545"
NAVY_DEEP = "#071A33"
WHITE = "#FFFFFF"

SUPERSAMPLE = 4          # trace resolution multiplier
INK_THRESHOLD = 150      # gray level below which a pixel is seal ink
MIN_IOU = 0.90           # refuse to ship a trace that lost the artwork


def ink_mask(scale: int) -> np.ndarray:
    """Boolean mask of the seal's ink, at `scale` times the source size."""
    img = Image.open(SRC)
    if scale != 1:
        img = img.resize((img.width * scale, img.height * scale), Image.LANCZOS)
    arr = np.array(img)
    gray, alpha = arr[:, :, 0].astype(int), arr[:, :, 1]
    return (gray < INK_THRESHOLD) & (alpha > 96)


def trace(mask: np.ndarray) -> str:
    """Return the mask as one compound SVG path `d`, in mask pixel units.

    potracer traces the *complement* of the array it is given, so the mask is
    inverted on the way in. The returned string concatenates every contour:
    filling them as a single path makes potrace's hole winding cancel them out.
    """
    plist = potrace.Bitmap(~mask).trace(
        turdsize=2, alphamax=1.0, opticurve=True, opttolerance=0.2
    )
    parts: list[str] = []
    for curve in plist:
        start = curve.start_point
        d = [f"M{start.x:.2f} {start.y:.2f}"]
        for seg in curve:
            if seg.is_corner:
                d.append(
                    f"L{seg.c.x:.2f} {seg.c.y:.2f}"
                    f"L{seg.end_point.x:.2f} {seg.end_point.y:.2f}"
                )
            else:
                d.append(
                    f"C{seg.c1.x:.2f} {seg.c1.y:.2f} "
                    f"{seg.c2.x:.2f} {seg.c2.y:.2f} "
                    f"{seg.end_point.x:.2f} {seg.end_point.y:.2f}"
                )
        d.append("Z")
        parts.append("".join(d))
    if len(parts) < 5:
        raise SystemExit(f"trace produced only {len(parts)} contours — check the source")
    return "".join(parts)


def mark(d: str, fill: str, width: float, height: float, scale: float) -> str:
    """Place the traced seal (in 4x units) inside a width x height box."""
    unit = SRC_SIZE * SUPERSAMPLE
    s = min(width, height) / unit * scale
    tx = (width - unit * s) / 2
    ty = (height - unit * s) / 2
    return (
        f'<g transform="translate({tx:.2f} {ty:.2f}) scale({s:.6f})">'
        f'<path fill="{fill}" d="{d}"/></g>'
    )


def svg(width: float, height: float, inner: str, defs: str = "") -> str:
    return (
        f'<svg width="{width:g}" height="{height:g}" '
        f'viewBox="0 0 {width:g} {height:g}" '
        f'xmlns="http://www.w3.org/2000/svg">{defs}{inner}</svg>\n'
    )


def gradient_png(path: Path, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> None:
    """Vertical two-stop gradient, same canvas size Ubuntu uses (3168x2448)."""
    w, h = 3168, 2448
    column = Image.new("RGB", (1, h))
    px = column.load()
    for y in range(h):
        t = y / (h - 1)
        px[0, y] = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    column.resize((w, h), Image.BILINEAR).save(path, optimize=True)


def verify(d: str) -> float:
    """Render the trace back and compare it with the ink mask."""
    size = SRC_SIZE * SUPERSAMPLE
    test = (
        f'<svg width="{size}" height="{size}" viewBox="0 0 {size} {size}" '
        'xmlns="http://www.w3.org/2000/svg">'
        f'<rect width="{size}" height="{size}" fill="white"/>'
        f'<path fill="black" d="{d}"/></svg>'
    )
    with tempfile.TemporaryDirectory() as td:
        src, png = Path(td) / "t.svg", Path(td) / "t.png"
        src.write_text(test)
        subprocess.run(
            ["rsvg-convert", "-w", str(SRC_SIZE), "-h", str(SRC_SIZE),
             "-o", str(png), str(src)],
            check=True,
        )
        im = Image.open(png).convert("RGBA")
        bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
        rendered = np.array(Image.alpha_composite(bg, im).convert("L")) < 128
    target = ink_mask(1)
    return float((rendered & target).sum() / (rendered | target).sum())


SRC_SIZE = 0


def main() -> None:
    global SRC_SIZE
    SRC_SIZE = Image.open(SRC).width

    mask = ink_mask(SUPERSAMPLE)
    d = trace(mask)
    iou = verify(d)
    print(f"trace: {mask.shape[0]}px, {d.count('M')} contours, IoU {iou:.3f}")
    if iou < MIN_IOU:
        raise SystemExit(f"trace fidelity {iou:.3f} < {MIN_IOU} — refusing to write")

    OUT.mkdir(parents=True, exist_ok=True)

    (OUT / "logo-light.svg").write_text(svg(190, 66, mark(d, NAVY, 190, 66, 0.96)))
    (OUT / "logo-dark.svg").write_text(svg(190, 66, mark(d, WHITE, 190, 66, 0.96)))

    defs = (
        '<defs><linearGradient id="dct" x1="450" y1="0" x2="450" y2="901" '
        'gradientUnits="userSpaceOnUse">'
        f'<stop stop-color="{NAVY}"/><stop offset="1" stop-color="{NAVY_DEEP}"/>'
        "</linearGradient></defs>"
    )
    (OUT / "mascot.svg").write_text(
        svg(900, 901,
            '<circle cx="450" cy="450.5" r="450" fill="url(#dct)"/>'
            + mark(d, WHITE, 900, 901, 0.60),
            defs)
    )
    (OUT / "mascot_no_background.svg").write_text(
        svg(900, 901, mark(d, NAVY, 900, 901, 0.60))
    )

    # Launcher icon: the seal knocked out of a navy disc, so it reads at 48px.
    icon_defs = (
        '<defs><linearGradient id="dct" x1="96" y1="0" x2="96" y2="192" '
        'gradientUnits="userSpaceOnUse">'
        f'<stop stop-color="{NAVY}"/><stop offset="1" stop-color="{NAVY_DEEP}"/>'
        "</linearGradient></defs>"
    )
    (OUT / "dct-os.svg").write_text(
        svg(192, 192,
            '<circle cx="96" cy="96" r="96" fill="url(#dct)"/>'
            + mark(d, WHITE, 192, 192, 0.74),
            icon_defs)
    )

    # The installer paints these behind every page. Keep light/dark contrast
    # near Ubuntu's (mean ~0.85 / ~0.18) so the app's text stays readable.
    # Names match the snap's own files (light-theme.png, not theme-light.png).
    gradient_png(OUT / "light-theme.png", (0xF7, 0xF9, 0xFC), (0xE1, 0xE8, 0xF3))
    gradient_png(OUT / "dark-theme.png", (0x0B, 0x25, 0x45), (0x07, 0x1A, 0x33))

    for f in sorted(OUT.iterdir()):
        if f.is_file():
            print(f"{f.name:26} {f.stat().st_size:>8} bytes")


if __name__ == "__main__":
    sys.exit(main())
