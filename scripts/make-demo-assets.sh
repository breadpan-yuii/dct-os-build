#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# make-demo-assets.sh — build every branding PNG from the source artwork.
#
# Source of truth:
#   payload/assets/source/          real DCT artwork (see PROVENANCE.md)
#   payload/branding/tokens.env     colours, version, names
#
# Output:
#   payload/assets/*.png            the files apply-branding.sh installs
#
# If payload/assets/source/ is empty, draws a placeholder emblem instead so the
# build still works. That fallback is never acceptable for a pilot.
#
#   ./scripts/make-demo-assets.sh
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
. "$REPO/payload/branding/tokens.env"

WORK="$REPO/.demo-build"
OUT="$REPO/payload/assets"
SRC="$OUT/source"
mkdir -p "$WORK" "$OUT"

NAVY="#$DCT_NAVY"
DEEP="#$DCT_NAVY_DEEP"
GOLD="#$DCT_GOLD"
WHITE="#$DCT_WHITE"
MUTED="$DCT_TEXT_MUTED"
MUTED="#$MUTED"
FONT="${DCT_FONT:-Inter}"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Prepare working copies of the source art.
#
# dct-seal.png   5000² seal, white disc + black line art, transparent outside.
# dct-lockup.png seal + "DCT" wordmark, light art for dark backgrounds.
# ---------------------------------------------------------------------------
HAVE_SEAL=0
HAVE_LOCKUP=0

if [ -f "$SRC/dct-seal.png" ]; then
    magick "$SRC/dct-seal.png" -trim +repage "$WORK/seal.png"
    HAVE_SEAL=1
fi
if [ -f "$SRC/dct-lockup.png" ]; then
    magick "$SRC/dct-lockup.png" -trim +repage "$WORK/lockup.png"
    HAVE_LOCKUP=1
fi

LOCKUP_RATIO=2.85
if [ "$HAVE_LOCKUP" -eq 1 ]; then
    read -r LW LH <<<"$(magick identify -format '%w %h' "$WORK/lockup.png")"
    LOCKUP_RATIO="$(awk -v w="$LW" -v h="$LH" 'BEGIN{printf "%.4f", w/h}')"
fi

if [ "$HAVE_SEAL" -eq 0 ] || [ "$HAVE_LOCKUP" -eq 0 ]; then
    warn "no DCT artwork in payload/assets/source/ — drawing placeholders"
    warn "see payload/assets/source/PROVENANCE.md before any pilot"
fi

# ---------------------------------------------------------------------------
# SVG fragments
# ---------------------------------------------------------------------------

# Placed lockup: $1=width $2=x $3=y $4=opacity
lockup_svg() {
    local w="$1" x="$2" y="$3" op="$4"
    local h
    h="$(awk -v w="$w" -v r="$LOCKUP_RATIO" 'BEGIN{printf "%.1f", w/r}')"
    if [ "$HAVE_LOCKUP" -eq 1 ]; then
        printf '  <image x="%s" y="%s" width="%s" height="%s" opacity="%s" xlink:href="lockup.png"/>\n' \
            "$x" "$y" "$w" "$h" "$op"
    else
        # Draw the old placeholder lockup so the output is never empty.
        printf '  <g transform="translate(%s,%s) scale(%.4f)" opacity="%s">\n' \
            "$x" "$y" "$(awk -v w="$w" 'BEGIN{print w/512}')" "$op"
        printf '    <rect width="512" height="512" rx="96" fill="%s"/>\n' "$DEEP"
        printf '    <rect x="28" y="28" width="456" height="456" rx="76" fill="none" stroke="%s" stroke-width="6"/>\n' "$GOLD"
        printf '    <text x="256" y="268" font-family="%s" font-size="132" font-weight="bold" fill="%s" text-anchor="middle">DCT</text>\n' "$FONT" "$GOLD"
        printf '    <text x="256" y="330" font-family="%s" font-size="40" font-weight="bold" fill="%s" text-anchor="middle">OS</text>\n' "$FONT" "$MUTED"
        printf '  </g>\n'
    fi
}

# Placed seal: $1=width $2=x $3=y $4=opacity
seal_svg() {
    local w="$1" x="$2" y="$3" op="$4"
    if [ "$HAVE_SEAL" -eq 1 ]; then
        printf '  <image x="%s" y="%s" width="%s" height="%s" opacity="%s" xlink:href="seal.png"/>\n' \
            "$x" "$y" "$w" "$w" "$op"
    fi
}

svg_head() {   # $1=width $2=height
    cat <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
     width="$1" height="$2" viewBox="0 0 $1 $2">
EOF
}

# ---------------------------------------------------------------------------
# 1. Wallpapers — 3840×2160, three variants.
# ---------------------------------------------------------------------------
wallpaper() {   # $1=variant  $2=out.svg
    local variant="$1" top="$NAVY" bottom="$DEEP" glow="0.20" op="0.10"
    case "$variant" in
        dark) top="$DEEP";    bottom="#04101F"; glow="0.10"; op="0.07" ;;
        lock) top="#04101F";  bottom="#020A14"; glow="0.06"; op="0.05" ;;
    esac

    # Watermark: right third, width 1080.
    local wm_w=1080
    local wm_h
    wm_h="$(awk -v w="$wm_w" -v r="$LOCKUP_RATIO" 'BEGIN{printf "%.0f", w/r}')"
    local wm_x=$((3840 - wm_w - 260))
    local wm_y=$(((2160 - wm_h) / 2))

    {
        svg_head 3840 2160
        cat <<EOF
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="$top"/>
      <stop offset="100%" stop-color="$bottom"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.22" cy="0.82" r="0.62">
      <stop offset="0%" stop-color="$GOLD" stop-opacity="$glow"/>
      <stop offset="100%" stop-color="$GOLD" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="stripe" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="$GOLD" stop-opacity="0.55"/>
      <stop offset="100%" stop-color="$GOLD" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect width="3840" height="2160" fill="url(#bg)"/>
  <rect width="3840" height="2160" fill="url(#glow)"/>
  <path d="M0 1500 L3840 900 L3840 1010 L0 1610 Z" fill="$WHITE" opacity="0.025"/>
  <path d="M0 1560 L3840 960 L3840 972 L0 1572 Z" fill="url(#stripe)"/>
EOF
        lockup_svg "$wm_w" "$wm_x" "$wm_y" "$op"
        cat <<EOF
  <g transform="translate(180,180)">
    <rect width="14" height="86" fill="$GOLD"/>
    <text x="46" y="34" font-family="$FONT" font-size="34" font-weight="bold"
          fill="$WHITE" letter-spacing="3">$DCT_NAME</text>
    <text x="46" y="72" font-family="$FONT" font-size="22" fill="$MUTED"
          letter-spacing="1">$DCT_VENDOR</text>
  </g>
</svg>
EOF
    } > "$2"
}

# ---------------------------------------------------------------------------
# 2. GRUB background — 1920×1080. Crisp lockup top-left; GRUB draws the menu
#    over it (see payload/grub/theme/theme.txt).
# ---------------------------------------------------------------------------
grub_background() {   # $1=out.svg
    {
        svg_head 1920 1080
        cat <<EOF
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="$DEEP"/>
      <stop offset="100%" stop-color="#020A14"/>
    </linearGradient>
    <radialGradient id="rg" cx="0.85" cy="0.1" r="0.7">
      <stop offset="0%" stop-color="$GOLD" stop-opacity="0.07"/>
      <stop offset="100%" stop-color="$GOLD" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1920" height="1080" fill="url(#g)"/>
  <rect width="1920" height="1080" fill="url(#rg)"/>
EOF
        lockup_svg 460 130 96 1
        # Rule + product line under the mark. Menu starts at 30% (324 px).
        cat <<EOF
  <rect x="130" y="248" width="120" height="4" fill="$GOLD"/>
  <text x="130" y="292" font-family="$FONT" font-size="17" fill="$MUTED"
        letter-spacing="2">$DCT_PRETTY_NAME  ·  $DCT_VENDOR</text>
</svg>
EOF
    } > "$1"
}

say "deriving assets"

# ---------------------------------------------------------------------------
# 3. Render
# ---------------------------------------------------------------------------
wallpaper day  "$WORK/wall-day.svg";  rsvg-convert -w 3840 -h 2160 -o "$OUT/dct-default.png"      "$WORK/wall-day.svg"
wallpaper dark "$WORK/wall-dark.svg"; rsvg-convert -w 3840 -h 2160 -o "$OUT/dct-default-dark.png" "$WORK/wall-dark.svg"
wallpaper lock "$WORK/wall-lock.svg"; rsvg-convert -w 3840 -h 2160 -o "$OUT/dct-lock.png"         "$WORK/wall-lock.svg"

grub_background "$WORK/grub-bg.svg"
rsvg-convert -w 1920 -h 1080 -o "$OUT/background.png" "$WORK/grub-bg.svg"

# Greeter icon — the seal, centred on a transparent 192².
if [ "$HAVE_SEAL" -eq 1 ]; then
    magick "$WORK/seal.png" -resize 168x168 \
           -background none -gravity center -extent 192x192 "$OUT/dct-logo.png"
else
    # Placeholder: navy rounded tile with the wordmark.
    cat > "$WORK/emblem.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512">
  <rect width="512" height="512" rx="96" fill="$DEEP"/>
  <rect x="28" y="28" width="456" height="456" rx="76" fill="none" stroke="$GOLD" stroke-width="6"/>
  <text x="256" y="268" font-family="$FONT" font-size="132" font-weight="bold"
        fill="$GOLD" text-anchor="middle" letter-spacing="6">DCT</text>
  <text x="256" y="330" font-family="$FONT" font-size="40" font-weight="bold"
        fill="$MUTED" text-anchor="middle" letter-spacing="14">OS</text>
</svg>
EOF
    rsvg-convert -w 192 -h 192 -o "$OUT/dct-logo.png" "$WORK/emblem.svg"
fi

# Plymouth logo — the lockup, contained in 480×270 with breathing room.
{
    svg_head 480 270
    lockup_svg 420 30 "$(awk -v r="$LOCKUP_RATIO" 'BEGIN{printf "%.0f", (270 - 420/r)/2}')" 1
    echo "</svg>"
} > "$WORK/plymouth-logo.svg"
rsvg-convert -w 480 -h 270 -o "$OUT/logo.png" "$WORK/plymouth-logo.svg"

# Plymouth progress bar.
cat > "$WORK/progress_bg.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="300" height="8">
  <rect width="300" height="8" rx="4" fill="$DEEP"/>
  <rect width="300" height="8" rx="4" fill="none" stroke="$GOLD" stroke-opacity="0.35"/>
</svg>
EOF
cat > "$WORK/progress_fg.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="300" height="8">
  <rect width="300" height="8" rx="4" fill="$GOLD"/>
</svg>
EOF
rsvg-convert -w 300 -h 8 -o "$OUT/progress_bg.png" "$WORK/progress_bg.svg"
rsvg-convert -w 300 -h 8 -o "$OUT/progress_fg.png" "$WORK/progress_fg.svg"

say "assets -> payload/assets/"
ls -lh "$OUT"/*.png | awk '{printf "   %-28s %s\n", $9, $5}' | sed "s|$OUT/||"
