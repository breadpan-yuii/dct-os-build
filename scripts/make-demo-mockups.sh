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

NAVY="#$DCT_NAVY"; DEEP="#$DCT_NAVY_DEEP"; GOLD="#$DCT_GOLD"
WHITE="#$DCT_WHITE"; MUTED="#$DCT_TEXT_MUTED"
F="${DCT_FONT:-Inter}"

# Working copies of the source art (same derivation as make-demo-assets.sh).
HAVE_LOCKUP=0; HAVE_SEAL=0
[ -f "$SRC/dct-lockup.png" ] && { magick "$SRC/dct-lockup.png" -trim +repage "$WORK/lockup.png"; HAVE_LOCKUP=1; }
[ -f "$SRC/dct-seal.png" ]   && { magick "$SRC/dct-seal.png"   -trim +repage "$WORK/seal.png";   HAVE_SEAL=1; }

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
        printf '    <rect width="512" height="512" rx="96" fill="%s"/>\n' "$DEEP"
        printf '    <text x="256" y="290" font-family="%s" font-size="140" font-weight="bold" fill="%s" text-anchor="middle">DCT</text>\n' "$F" "$GOLD"
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
      <stop offset="0%" stop-color="$DEEP"/><stop offset="100%" stop-color="#020A14"/>
    </linearGradient>
    <radialGradient id="rg" cx="0.85" cy="0.08" r="0.7">
      <stop offset="0%" stop-color="$GOLD" stop-opacity="0.08"/>
      <stop offset="100%" stop-color="$GOLD" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1920" height="1080" fill="url(#g)"/>
  <rect width="1920" height="1080" fill="url(#rg)"/>
EOF
    lockup 380 150 104 1
    cat <<EOF
  <rect x="150" y="256" width="96" height="3" fill="$GOLD"/>
  <text x="150" y="296" font-family="$F" font-size="16" fill="$MUTED" letter-spacing="2">$DCT_PRETTY_NAME &#183; $DCT_VENDOR</text>

  <!-- selected entry -->
  <rect x="150" y="400" width="1200" height="64" rx="4" fill="$GOLD"/>
  <text x="182" y="440" font-family="$F" font-size="26" font-weight="bold" fill="$DEEP">$DCT_PRETTY_NAME</text>
  <text x="1290" y="440" font-family="$F" font-size="15" fill="$DEEP" text-anchor="end" opacity="0.75">GNU/Linux 6.17.0</text>

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
  <rect x="150" y="800" width="168" height="10" rx="5" fill="$GOLD"/>
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
  <rect width="1920" height="1080" fill="$DEEP"/>
EOF
    lockup 560 680 350 1
    cat <<EOF
  <text x="960" y="660" font-family="$F" font-size="15" fill="$MUTED"
        text-anchor="middle" letter-spacing="3">STARTING</text>
  <rect x="760" y="720" width="400" height="6" rx="3" fill="$WHITE" fill-opacity="0.10"/>
  <rect x="760" y="720" width="248" height="6" rx="3" fill="$GOLD"/>
  <text x="960" y="900" font-family="$F" font-size="13" fill="$MUTED"
        text-anchor="middle" opacity="0.65">$DCT_VENDOR &#183; authorized use only</text>
</svg>
EOF
} > "$WORK/m-plymouth.svg"

# ---------------------------------------------------------------------------
# 3. Calamares installer
# ---------------------------------------------------------------------------
{
    echo "$HEAD"
    cat <<EOF
  <rect width="1920" height="1080" fill="#0A1626"/>
  <rect x="240" y="130" width="1440" height="820" rx="10" fill="$WHITE"/>
  <rect x="240" y="130" width="400" height="820" rx="10" fill="$NAVY"/>
  <rect x="600" y="130" width="40" height="820" fill="$NAVY"/>
EOF
    lockup 300 290 190 1
    cat <<EOF
  <rect x="290" y="330" width="80" height="3" fill="$GOLD"/>
  <text x="290" y="368" font-family="$F" font-size="14" fill="$MUTED" letter-spacing="1">$DCT_VERSION &#183; $DCT_CODENAME</text>

  <g font-family="$F" font-size="17">
    <rect x="290" y="470" width="4" height="26" fill="$GOLD"/>
    <text x="310" y="491" fill="$GOLD" font-weight="bold">Welcome</text>
    <text x="310" y="539" fill="$MUTED">Location</text>
    <text x="310" y="587" fill="$MUTED">Keyboard</text>
    <text x="310" y="635" fill="$MUTED">Partitions</text>
    <text x="310" y="683" fill="$MUTED">Users</text>
    <text x="310" y="731" fill="$MUTED">Summary</text>
    <text x="310" y="779" fill="$MUTED">Install</text>
  </g>

  <text x="700" y="250" font-family="$F" font-size="34" font-weight="bold" fill="$NAVY">Welcome to $DCT_NAME</text>
  <text x="700" y="292" font-family="$F" font-size="17" fill="#5A6B85">
    This installer will guide you through installing $DCT_NAME on this computer.</text>

  <g fill="#EEF2F8">
    <rect x="700" y="340" width="900" height="96" rx="6"/>
    <rect x="700" y="456" width="900" height="96" rx="6"/>
  </g>
  <g font-family="$F" font-size="15" fill="$NAVY">
    <text x="726" y="378" font-weight="bold">English (Philippines)</text>
    <text x="726" y="404" fill="#5A6B85">Language for the installed system</text>
    <text x="726" y="494" font-weight="bold">Asia / Manila</text>
    <text x="726" y="520" fill="#5A6B85">Time zone and clock</text>
  </g>
  <rect x="700" y="340" width="900" height="96" rx="6" fill="none" stroke="$GOLD" stroke-width="2"/>

  <text x="700" y="620" font-family="$F" font-size="15" fill="#5A6B85">
    $DCT_NAME is built on Ubuntu 24.04 LTS. Not affiliated with Zorin OS or Canonical.</text>

  <rect x="1290" y="860" width="150" height="46" rx="5" fill="#E3E8F0"/>
  <text x="1365" y="889" font-family="$F" font-size="16" fill="#8A97AB" text-anchor="middle">Back</text>
  <rect x="1452" y="860" width="150" height="46" rx="5" fill="$GOLD"/>
  <text x="1527" y="889" font-family="$F" font-size="16" font-weight="bold" fill="$NAVY" text-anchor="middle">Next</text>
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
      <stop offset="0%" stop-color="$NAVY"/><stop offset="100%" stop-color="#020A14"/>
    </linearGradient>
    <radialGradient id="lg" cx="0.25" cy="0.85" r="0.6">
      <stop offset="0%" stop-color="$GOLD" stop-opacity="0.16"/>
      <stop offset="100%" stop-color="$GOLD" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1920" height="1080" fill="url(#l)"/>
  <rect width="1920" height="1080" fill="url(#lg)"/>
EOF
    lockup 420 1500 880 0.06
    cat <<EOF
  <text x="1860" y="90" font-family="$F" font-size="44" fill="$WHITE" text-anchor="end">21:40</text>
  <text x="1860" y="126" font-family="$F" font-size="18" fill="$MUTED" text-anchor="end">Wednesday, 11 November 2026</text>
EOF
    seal 160 880 240 1
    cat <<EOF
  <text x="960" y="470" font-family="$F" font-size="15" fill="$MUTED"
        text-anchor="middle" letter-spacing="3">$DCT_NAME</text>
  <text x="960" y="530" font-family="$F" font-size="30" font-weight="bold" fill="$WHITE" text-anchor="middle">student</text>

  <rect x="700" y="576" width="520" height="54" rx="27" fill="$WHITE" fill-opacity="0.10"
        stroke="$WHITE" stroke-opacity="0.18"/>
  <g fill="$MUTED">
    <circle cx="742" cy="603" r="5"/><circle cx="766" cy="603" r="5"/><circle cx="790" cy="603" r="5"/>
    <circle cx="814" cy="603" r="5"/><circle cx="838" cy="603" r="5"/><circle cx="862" cy="603" r="5"/>
    <circle cx="886" cy="603" r="5"/><circle cx="910" cy="603" r="5"/>
  </g>
  <rect x="840" y="662" width="240" height="48" rx="24" fill="$GOLD"/>
  <text x="960" y="693" font-family="$F" font-size="17" font-weight="bold" fill="$DEEP" text-anchor="middle">Sign In</text>

  <text x="960" y="920" font-family="$F" font-size="15" fill="$MUTED" text-anchor="middle" letter-spacing="0.5">
    $DCT_VENDOR &#8212; authorized users only. Activity is logged.</text>
  <text x="960" y="948" font-family="$F" font-size="13" fill="$MUTED" text-anchor="middle" opacity="0.6">
    $DCT_PRETTY_NAME ($DCT_CODENAME) &#183; built on Ubuntu 24.04 LTS</text>
</svg>
EOF
} > "$WORK/m-login.svg"

# ---------------------------------------------------------------------------
# 5. Desktop
# ---------------------------------------------------------------------------
{
    echo "$HEAD"
    cat <<EOF
  <defs>
    <linearGradient id="d" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="$NAVY"/><stop offset="100%" stop-color="$DEEP"/>
    </linearGradient>
    <radialGradient id="dg" cx="0.22" cy="0.82" r="0.62">
      <stop offset="0%" stop-color="$GOLD" stop-opacity="0.18"/>
      <stop offset="100%" stop-color="$GOLD" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1920" height="1080" fill="url(#d)"/>
  <rect width="1920" height="1080" fill="url(#dg)"/>
  <path d="M0 820 L1920 500 L1920 560 L0 880 Z" fill="$WHITE" opacity="0.03"/>
EOF
    lockup 620 1240 700 0.12
    cat <<EOF
  <rect width="1920" height="34" fill="#000000" fill-opacity="0.32"/>
  <text x="20" y="23" font-family="$F" font-size="14" fill="$WHITE">Activities</text>
  <text x="110" y="23" font-family="$F" font-size="14" font-weight="bold" fill="$WHITE">DCT Portal</text>
  <text x="1900" y="23" font-family="$F" font-size="13" fill="$WHITE" text-anchor="end">Wed 11 Nov   21:40</text>

  <rect x="14" y="360" width="66" height="368" rx="16" fill="#000000" fill-opacity="0.28"/>
  <g>
    <rect x="22" y="370" width="50" height="50" rx="12" fill="#2E5AAC"/>
    <text x="47" y="403" font-family="$F" font-size="18" font-weight="bold" fill="$WHITE" text-anchor="middle">F</text>
    <rect x="22" y="428" width="50" height="50" rx="12" fill="#C0392B"/>
    <text x="47" y="461" font-family="$F" font-size="18" font-weight="bold" fill="$WHITE" text-anchor="middle">O</text>
    <rect x="22" y="486" width="50" height="50" rx="12" fill="#1E8449"/>
    <text x="47" y="519" font-family="$F" font-size="18" font-weight="bold" fill="$WHITE" text-anchor="middle">L</text>
    <rect x="22" y="544" width="50" height="50" rx="12" fill="#E67E22"/>
    <text x="47" y="577" font-family="$F" font-size="18" font-weight="bold" fill="$WHITE" text-anchor="middle">P</text>
    <rect x="22" y="602" width="50" height="50" rx="12" fill="$GOLD"/>
    <text x="47" y="635" font-family="$F" font-size="18" font-weight="bold" fill="$DEEP" text-anchor="middle">D</text>
    <rect x="22" y="660" width="50" height="50" rx="12" fill="#4A5A73"/>
    <text x="47" y="693" font-family="$F" font-size="18" font-weight="bold" fill="$WHITE" text-anchor="middle">S</text>
  </g>

  <rect x="220" y="180" width="1080" height="620" rx="10" fill="#F7F9FC" stroke="#000" stroke-opacity="0.25"/>
  <rect x="220" y="180" width="1080" height="46" rx="10" fill="$NAVY"/>
  <rect x="220" y="212" width="1080" height="14" fill="$NAVY"/>
  <text x="248" y="210" font-family="$F" font-size="14" font-weight="bold" fill="$WHITE">DCT Portal</text>
  <g fill="$WHITE" fill-opacity="0.5">
    <circle cx="1268" cy="203" r="6"/><circle cx="1246" cy="203" r="6"/><circle cx="1224" cy="203" r="6"/>
  </g>
  <rect x="240" y="242" width="1040" height="34" rx="17" fill="#E7ECF4"/>
  <text x="262" y="264" font-family="$F" font-size="13" fill="#7A879B">https://dct.edu.ph</text>

  <text x="264" y="332" font-family="$F" font-size="26" font-weight="bold" fill="$NAVY">Student Portal</text>
  <text x="264" y="360" font-family="$F" font-size="14" fill="#5A6B85">Grades, enrolment and announcements</text>
  <g fill="#E9EEF6">
    <rect x="264" y="392" width="320" height="150" rx="8"/>
    <rect x="604" y="392" width="320" height="150" rx="8"/>
    <rect x="944" y="392" width="316" height="150" rx="8"/>
  </g>
  <g fill="#D3DBE8">
    <rect x="284" y="414" width="120" height="12" rx="6"/>
    <rect x="284" y="438" width="240" height="9" rx="4"/>
    <rect x="284" y="456" width="200" height="9" rx="4"/>
    <rect x="624" y="414" width="120" height="12" rx="6"/>
    <rect x="624" y="438" width="240" height="9" rx="4"/>
    <rect x="624" y="456" width="180" height="9" rx="4"/>
    <rect x="964" y="414" width="120" height="12" rx="6"/>
    <rect x="964" y="438" width="240" height="9" rx="4"/>
    <rect x="964" y="456" width="210" height="9" rx="4"/>
  </g>
  <g fill="#EEF2F8">
    <rect x="264" y="562" width="996" height="40" rx="6"/>
    <rect x="264" y="614" width="996" height="40" rx="6"/>
    <rect x="264" y="666" width="996" height="40" rx="6"/>
  </g>
  <g fill="#D3DBE8">
    <rect x="284" y="578" width="300" height="9" rx="4"/>
    <rect x="284" y="630" width="380" height="9" rx="4"/>
    <rect x="284" y="682" width="260" height="9" rx="4"/>
  </g>

  <rect x="700" y="900" width="520" height="56" rx="28" fill="#04101F" fill-opacity="0.92"/>
  <circle cx="732" cy="928" r="12" fill="$GOLD"/>
  <text x="756" y="934" font-family="$F" font-size="15" fill="$WHITE">
    Welcome to $DCT_NAME &#183; $DCT_VENDOR</text>
</svg>
EOF
} > "$WORK/m-desktop.svg"

for m in grub plymouth installer login desktop; do
    r "$WORK/m-$m.svg" "$OUT/$m.png"
    printf '   %-14s %s\n' "$m.png" "$(du -h "$OUT/$m.png" | cut -f1)"
done
echo
echo "mockups -> demo/mockups/"
