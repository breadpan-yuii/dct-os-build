#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# make-demo-mockups.sh — render the branded screens as PNGs for slides.
#
# These are RENDERS, not screenshots of a running system. Label them as such
# in any deck: "design render". Do not present them as a working build.
#
# Uses the real DCT artwork in payload/assets/source/ when present.
#
#   ./scripts/make-demo-mockups.sh   ->  demo/mockups/*.png
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
. "$REPO/payload/branding/tokens.env"

WORK="$REPO/.demo-build"
OUT="$REPO/demo/mockups"
SRC="$REPO/payload/assets/source"
mkdir -p "$WORK" "$OUT"

PURPLE="#$DCT_PURPLE"; PURPLE_DEEP="#$DCT_PURPLE_DEEP"; PURPLE_LIGHT="#$DCT_PURPLE_LIGHT"
GRAY="#$DCT_GRAY"; GRAY_DARK="#$DCT_GRAY_DARK"; GRAY_MID="#$DCT_GRAY_MID"; GRAY_LIGHT="#$DCT_GRAY_LIGHT"
WHITE="#$DCT_WHITE"; MUTED="#$DCT_TEXT_MUTED"
F="${DCT_FONT:-Inter}"
LOGIN_DATE="$(date '+%A, %-d %B %Y')"
CURRENT_CLOCK="$(date '+%H:%M')"
DESKTOP_CLOCK="$(date '+%a %d %b   %H:%M')"

# Working copies of the source art (same derivation as make-demo-assets.sh).
HAVE_LOCKUP=0; HAVE_SEAL=0
[ -f "$SRC/dct-lockup.png" ] && { magick "$SRC/dct-lockup.png" -trim +repage "$WORK/lockup.png"; HAVE_LOCKUP=1; }
[ -f "$SRC/dct-seal.png" ]   && { magick "$SRC/dct-seal.png"   -trim +repage "$WORK/seal.png";   HAVE_SEAL=1; }
cp "$REPO/payload/installer/light-theme.png" "$WORK/installer-light-theme.png"
cp "$REPO/payload/installer/dark-theme.png" "$WORK/installer-dark-theme.png"
cp "$REPO/payload/installer/logo-light.svg" "$WORK/installer-logo-light.svg"
cp "$REPO/payload/installer/logo-dark.svg" "$WORK/installer-logo-dark.svg"
cp "$REPO/payload/installer/dct-os.svg" "$WORK/dct-os.svg"

LOCKUP_RATIO=2.85
if [ "$HAVE_LOCKUP" -eq 1 ]; then
    read -r LW LH <<<"$(magick identify -format '%w %h' "$WORK/lockup.png")"
    LOCKUP_RATIO="$(awk -v w="$LW" -v h="$LH" 'BEGIN{printf "%.4f", w/h}')"
fi

r() { rsvg-convert -w 1920 -h 1080 -o "$2" "$1"; }

# Emit a placed lockup (or a drawn fallback, so this never renders blank).
lockup() {   # w x y opacity
    local w="$1" x="$2" y="$3" op="$4"
    local h; h="$(awk -v w="$w" -v r="$LOCKUP_RATIO" 'BEGIN{printf "%.1f", w/r}')"
    if [ "$HAVE_LOCKUP" -eq 1 ]; then
        printf '  <image x="%s" y="%s" width="%s" height="%s" opacity="%s" xlink:href="lockup.png"/>\n' \
            "$x" "$y" "$w" "$h" "$op"
    else
        printf '  <g transform="translate(%s,%s) scale(%.4f)" opacity="%s">\n' "$x" "$y" "$(awk -v w="$w" 'BEGIN{print w/512}')" "$op"
        printf '    <rect width="512" height="512" rx="96" fill="%s"/>\n' "$PURPLE_DEEP"
        printf '    <text x="256" y="290" font-family="%s" font-size="140" font-weight="bold" fill="%s" text-anchor="middle">DCT</text>\n' "$F" "$PURPLE"
        printf '  </g>\n'
    fi
}

seal() {     # size x y opacity
    if [ "$HAVE_SEAL" -eq 1 ]; then
        printf '  <image x="%s" y="%s" width="%s" height="%s" opacity="%s" xlink:href="seal.png"/>\n' \
            "$2" "$3" "$1" "$1" "$4"
    fi
}

HEAD='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1920" height="1080">'

# ---------------------------------------------------------------------------
# 1. GRUB boot menu
# ---------------------------------------------------------------------------
{
    echo "$HEAD"
    cat <<EOF
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="$PURPLE_DEEP"/><stop offset="100%" stop-color="$GRAY_DARK"/>
    </linearGradient>
    <radialGradient id="rg" cx="0.85" cy="0.08" r="0.7">
      <stop offset="0%" stop-color="$PURPLE" stop-opacity="0.08"/>
      <stop offset="100%" stop-color="$PURPLE" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1920" height="1080" fill="url(#g)"/>
  <rect width="1920" height="1080" fill="url(#rg)"/>
EOF
    lockup 380 150 104 1
    cat <<EOF
  <rect x="150" y="256" width="96" height="3" fill="$PURPLE"/>
  <text x="150" y="296" font-family="$F" font-size="16" fill="$MUTED" letter-spacing="2">$DCT_PRETTY_NAME &#183; $DCT_VENDOR</text>

  <!-- selected entry -->
  <rect x="150" y="400" width="1200" height="64" rx="4" fill="$PURPLE"/>
  <text x="182" y="440" font-family="$F" font-size="26" font-weight="bold" fill="$PURPLE_DEEP">$DCT_PRETTY_NAME</text>
  <text x="1290" y="440" font-family="$F" font-size="15" fill="$PURPLE_DEEP" text-anchor="end" opacity="0.75">GNU/Linux 7.0.0-31</text>

  <g font-family="$F" font-size="24" fill="$MUTED">
    <text x="182" y="512">$DCT_PRETTY_NAME (recovery mode)</text>
    <text x="182" y="580">Memory test (memtest86+)</text>
    <text x="182" y="648">Windows Boot Manager</text>
  </g>
  <g stroke="$WHITE" stroke-opacity="0.07">
    <line x1="150" y1="532" x2="1350" y2="532"/>
    <line x1="150" y1="600" x2="1350" y2="600"/>
    <line x1="150" y1="668" x2="1350" y2="668"/>
  </g>

  <rect x="150" y="800" width="240" height="10" rx="5" fill="$WHITE" fill-opacity="0.12"/>
  <rect x="150" y="800" width="168" height="10" rx="5" fill="$PURPLE"/>
  <text x="410" y="810" font-family="$F" font-size="17" fill="$MUTED">Booting &#8216;$DCT_PRETTY_NAME&#8217; in 3 seconds&#8230;</text>
  <text x="150" y="960" font-family="$F" font-size="16" fill="$MUTED" opacity="0.7">
    Use &#8593; and &#8595; to select &#183; Enter to boot &#183; e to edit</text>
</svg>
EOF
} > "$WORK/m-grub.svg"

# ---------------------------------------------------------------------------
# 2. Plymouth boot splash
# ---------------------------------------------------------------------------
{
    echo "$HEAD"
    cat <<EOF
  <rect width="1920" height="1080" fill="$PURPLE_DEEP"/>
EOF
    lockup 560 680 350 1
    cat <<EOF
  <text x="960" y="660" font-family="$F" font-size="15" fill="$MUTED"
        text-anchor="middle" letter-spacing="3">STARTING</text>
  <rect x="760" y="720" width="400" height="6" rx="3" fill="$WHITE" fill-opacity="0.10"/>
  <rect x="760" y="720" width="248" height="6" rx="3" fill="$PURPLE"/>
  <text x="960" y="900" font-family="$F" font-size="13" fill="$MUTED"
        text-anchor="middle" opacity="0.65">$DCT_VENDOR &#183; authorized use only</text>
</svg>
EOF
} > "$WORK/m-plymouth.svg"

# ---------------------------------------------------------------------------
# 3. Actual installer overlay preview.
# This is deliberately an asset-overlay preview, not a drawn installer window:
# the live image launches Canonical's signed ubuntu-desktop-bootstrap Flutter
# app, and the branding overlay replaces only its six logo/mascot/theme assets.
# The app's layout and screens remain upstream and are not represented here.
# ---------------------------------------------------------------------------
{
    echo "$HEAD"
    cat <<EOF
  <defs>
    <pattern id="light" patternUnits="userSpaceOnUse" width="692" height="392">
      <image width="692" height="392" preserveAspectRatio="none" xlink:href="installer-light-theme.png"/>
    </pattern>
    <pattern id="dark" patternUnits="userSpaceOnUse" width="692" height="392">
      <image width="692" height="392" preserveAspectRatio="none" xlink:href="installer-dark-theme.png"/>
    </pattern>
  </defs>
  <rect width="1920" height="1080" fill="$GRAY_DARK"/>
  <text x="160" y="150" font-family="$F" font-size="16" fill="$PURPLE_LIGHT" letter-spacing="3">$DCT_PRETTY_NAME</text>
  <text x="160" y="220" font-family="$F" font-size="42" font-weight="bold" fill="$WHITE">Installer branding preview</text>
  <text x="160" y="264" font-family="$F" font-size="20" fill="$MUTED">DCT logos and purple/gray theme assets for the existing installer</text>

  <rect x="160" y="330" width="760" height="520" rx="12" fill="#F4F6FA"/>
  <rect x="160" y="330" width="760" height="64" rx="12" fill="#E8EBF0"/>
  <rect x="160" y="382" width="760" height="12" fill="#E8EBF0"/>
  <circle cx="198" cy="362" r="8" fill="#B9BEC8"/>
  <circle cx="226" cy="362" r="8" fill="#B9BEC8"/>
  <circle cx="254" cy="362" r="8" fill="#B9BEC8"/>
  <text x="290" y="369" font-family="$F" font-size="17" fill="$GRAY_DARK">Dominican OS · light appearance</text>
  <rect x="194" y="424" width="692" height="392" rx="8" fill="url(#light)"/>
  <image x="250" y="470" width="300" height="104" xlink:href="installer-logo-light.svg"/>
  <text x="250" y="638" font-family="$F" font-size="30" font-weight="bold" fill="$PURPLE_DEEP">DCT logo + light theme</text>
  <text x="250" y="682" font-family="$F" font-size="18" fill="$GRAY_MID">The real installer supplies the controls,</text>
  <text x="250" y="712" font-family="$F" font-size="18" fill="$GRAY_MID">navigation and page content.</text>

  <rect x="1000" y="330" width="760" height="520" rx="12" fill="#F4F6FA"/>
  <rect x="1000" y="330" width="760" height="64" rx="12" fill="#E8EBF0"/>
  <rect x="1000" y="382" width="760" height="12" fill="#E8EBF0"/>
  <circle cx="1038" cy="362" r="8" fill="#B9BEC8"/>
  <circle cx="1066" cy="362" r="8" fill="#B9BEC8"/>
  <circle cx="1094" cy="362" r="8" fill="#B9BEC8"/>
  <text x="1130" y="369" font-family="$F" font-size="17" fill="$GRAY_DARK">Dominican OS · dark appearance</text>
  <rect x="1034" y="424" width="692" height="392" rx="8" fill="url(#dark)"/>
  <image x="1090" y="470" width="300" height="104" xlink:href="installer-logo-dark.svg"/>
  <text x="1090" y="638" font-family="$F" font-size="30" font-weight="bold" fill="$WHITE">DCT logo + dark theme</text>
  <text x="1090" y="682" font-family="$F" font-size="18" fill="$MUTED">The installer's real workflow stays;</text>
  <text x="1090" y="712" font-family="$F" font-size="18" fill="$MUTED">DCT supplies these artwork assets.</text>
EOF
    cat <<EOF
  <text x="160" y="930" font-family="$F" font-size="17" fill="$MUTED">Overlay scope: logo-light.svg, logo-dark.svg, mascot.svg, mascot_no_background.svg, light-theme.png, dark-theme.png.</text>
  <text x="160" y="968" font-family="$F" font-size="16" fill="$MUTED">Shows the exact DCT assets overlaid; it is not a screenshot of the installer's screens.</text>
</svg>
EOF
} > "$WORK/m-installer.svg"

# ---------------------------------------------------------------------------
# 4. Login screen
# ---------------------------------------------------------------------------
{
    echo "$HEAD"
    cat <<EOF
  <defs>
    <linearGradient id="l" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="$PURPLE"/><stop offset="100%" stop-color="$GRAY_DARK"/>
    </linearGradient>
    <radialGradient id="lg" cx="0.25" cy="0.85" r="0.6">
      <stop offset="0%" stop-color="$PURPLE" stop-opacity="0.16"/>
      <stop offset="100%" stop-color="$PURPLE" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1920" height="1080" fill="url(#l)"/>
  <rect width="1920" height="1080" fill="url(#lg)"/>
EOF
    lockup 420 1500 880 0.06
    cat <<EOF
  <text x="1860" y="90" font-family="$F" font-size="44" fill="$WHITE" text-anchor="end">$CURRENT_CLOCK</text>
  <text x="1860" y="126" font-family="$F" font-size="18" fill="$MUTED" text-anchor="end">$LOGIN_DATE</text>
EOF
    seal 148 886 300 1
    cat <<EOF
  <text x="960" y="492" font-family="$F" font-size="34" font-weight="bold" fill="$WHITE"
        text-anchor="middle">$DCT_NAME</text>
  <text x="960" y="526" font-family="$F" font-size="15" fill="$MUTED"
        text-anchor="middle" letter-spacing="1">$DCT_VENDOR</text>
  <rect x="700" y="620" width="520" height="54" rx="27" fill="$WHITE" fill-opacity="0.10"
        stroke="$WHITE" stroke-opacity="0.18"/>
  <g fill="$MUTED">
    <circle cx="742" cy="647" r="5"/><circle cx="766" cy="647" r="5"/><circle cx="790" cy="647" r="5"/>
    <circle cx="814" cy="647" r="5"/><circle cx="838" cy="647" r="5"/><circle cx="862" cy="647" r="5"/>
    <circle cx="886" cy="647" r="5"/><circle cx="910" cy="647" r="5"/>
  </g>
  <rect x="840" y="704" width="240" height="48" rx="24" fill="$PURPLE"/>
  <text x="960" y="735" font-family="$F" font-size="17" font-weight="bold" fill="$PURPLE_DEEP" text-anchor="middle">Sign In</text>

  <text x="960" y="920" font-family="$F" font-size="15" fill="$MUTED" text-anchor="middle" letter-spacing="0.5">
    $DCT_VENDOR</text>
  <text x="960" y="948" font-family="$F" font-size="13" fill="$MUTED" text-anchor="middle" opacity="0.6">
    $DCT_PRETTY_NAME ($DCT_CODENAME) &#183; Dominican OS</text>
</svg>
EOF
} > "$WORK/m-login.svg"

# ---------------------------------------------------------------------------
# 5. Cinnamon desktop
# ---------------------------------------------------------------------------
{
    echo "$HEAD"
    cat <<EOF
  <defs>
    <linearGradient id="d" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="$PURPLE_LIGHT"/><stop offset="100%" stop-color="$PURPLE_DEEP"/>
    </linearGradient>
    <radialGradient id="dg" cx="0.22" cy="0.82" r="0.62">
      <stop offset="0%" stop-color="$PURPLE" stop-opacity="0.18"/>
      <stop offset="100%" stop-color="$PURPLE" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1920" height="1080" fill="url(#d)"/>
  <rect width="1920" height="1080" fill="url(#dg)"/>
EOF
    lockup 400 1450 730 0.10
    cat <<EOF
  <!-- Nemo file manager window with Cinnamon-style titlebar/window controls -->
  <rect x="286" y="112" width="1348" height="812" rx="8" fill="#000000" opacity="0.22"/>
  <rect x="270" y="96" width="1348" height="812" rx="8" fill="#F5F4F8" stroke="#292735" stroke-width="2"/>
  <rect x="270" y="96" width="1348" height="54" rx="8" fill="$GRAY_DARK"/>
  <rect x="270" y="138" width="1348" height="12" fill="$GRAY_DARK"/>
  <text x="310" y="131" font-family="$F" font-size="17" fill="$WHITE">Files — Home</text>
  <circle cx="1548" cy="123" r="8" fill="$GRAY_MID"/>
  <circle cx="1578" cy="123" r="8" fill="$GRAY_MID"/>
  <circle cx="1600" cy="123" r="8" fill="$PURPLE"/>

  <!-- Nemo toolbar and places sidebar -->
  <rect x="270" y="150" width="1348" height="58" fill="#E9E7EF"/>
  <text x="304" y="187" font-family="$F" font-size="17" fill="$GRAY_DARK">‹</text>
  <text x="340" y="187" font-family="$F" font-size="17" fill="$GRAY_DARK">›</text>
  <rect x="390" y="164" width="980" height="32" rx="16" fill="$WHITE"/>
  <text x="414" y="186" font-family="$F" font-size="13" fill="$GRAY_MID">Home</text>
  <rect x="270" y="208" width="290" height="700" fill="#ECEAF1"/>
  <g font-family="$F" font-size="16" fill="$GRAY_DARK">
    <text x="302" y="258" font-weight="bold">Places</text>
    <text x="316" y="304">⌂  Home</text>
    <text x="316" y="350">▣  Desktop</text>
    <text x="316" y="396">▤  Documents</text>
    <text x="316" y="442">▧  Downloads</text>
    <text x="302" y="506" font-weight="bold">Devices</text>
    <text x="316" y="552">◉  Computer</text>
    <text x="302" y="616" font-weight="bold">Network</text>
  </g>
  <g font-family="$F" font-size="14" fill="$GRAY_DARK" text-anchor="middle">
    <rect x="604" y="244" width="120" height="112" rx="8" fill="#E9E7EF"/>
    <text x="664" y="294" font-size="34" fill="$PURPLE">▰</text><text x="664" y="334">Documents</text>
    <rect x="754" y="244" width="120" height="112" rx="8" fill="#E9E7EF"/>
    <text x="814" y="294" font-size="34" fill="$PURPLE">▣</text><text x="814" y="334">Downloads</text>
    <rect x="904" y="244" width="120" height="112" rx="8" fill="#E9E7EF"/>
    <text x="964" y="294" font-size="34" fill="$PURPLE">▧</text><text x="964" y="334">Pictures</text>
    <rect x="1054" y="244" width="120" height="112" rx="8" fill="#E9E7EF"/>
    <text x="1114" y="294" font-size="34" fill="$PURPLE">▰</text><text x="1114" y="334">Music</text>
  </g>

  <!-- Cinnamon bottom panel: Menu, launchers, window list, tray and clock -->
  <rect x="0" y="1018" width="1920" height="62" fill="#24222B" opacity="0.97"/>
  <rect x="14" y="1025" width="242" height="48" rx="7" fill="$PURPLE"/>
  <image x="25" y="1033" width="32" height="32" xlink:href="dct-os.svg"/>
  <text x="67" y="1056" font-family="$F" font-size="16" font-weight="bold" fill="$WHITE">Dominican OS</text>
  <g font-family="$F" font-size="19" text-anchor="middle">
    <rect x="272" y="1027" width="46" height="44" rx="7" fill="#3D3949"/><text x="295" y="1056" fill="$WHITE">⌂</text>
    <rect x="324" y="1027" width="46" height="44" rx="7" fill="#3D3949"/><text x="347" y="1056" fill="$WHITE">▣</text>
    <rect x="376" y="1027" width="46" height="44" rx="7" fill="#3D3949"/><text x="399" y="1056" fill="$WHITE">W</text>
  </g>
  <rect x="448" y="1025" width="266" height="48" rx="6" fill="#3D3949"/>
  <rect x="448" y="1025" width="4" height="48" rx="2" fill="$PURPLE"/>
  <text x="472" y="1055" font-family="$F" font-size="15" fill="$WHITE">Files — Home</text>
  <text x="1654" y="1056" font-family="$F" font-size="15" fill="$WHITE">◉  ◖  ▴</text>
  <text x="1896" y="1056" font-family="$F" font-size="14" fill="$WHITE" text-anchor="end">$DESKTOP_CLOCK</text>
</svg>
EOF
} > "$WORK/m-desktop.svg"

for m in grub plymouth installer login desktop; do
    r "$WORK/m-$m.svg" "$OUT/$m.png"
    printf '   %-14s %s\n' "$m.png" "$(du -h "$OUT/$m.png" | cut -f1)"
done
echo
echo "mockups -> demo/mockups/"
