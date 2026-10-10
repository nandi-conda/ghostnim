#!/usr/bin/env sh
# Render packaging/ghostnim.svg into packaging/ghostnim.png (256x256), the
# window icon and the AppImage's / desktop menus' icon.
#
# Requirements: rsvg-convert (librsvg) and ImageMagick (magick or convert).
# Without them it leaves the committed icons alone, as long as the SVG still
# matches the checksum recorded when they were rendered (ghostnim.svg.sha256).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SVG="$ROOT/packaging/ghostnim.svg"
PNG="$ROOT/packaging/ghostnim.png"
SUM="$ROOT/packaging/ghostnim.svg.sha256"

svg_sum() { sha256sum "$SVG" | cut -d' ' -f1; }

if command -v magick >/dev/null 2>&1; then IM=magick
elif command -v convert >/dev/null 2>&1; then IM=convert
else IM=""
fi

if ! command -v rsvg-convert >/dev/null 2>&1 || [ -z "$IM" ]; then
  if [ "$(svg_sum)" != "$(cat "$SUM" 2>/dev/null)" ]; then
    echo "error: $SVG changed; install rsvg-convert and ImageMagick to re-render the icon" >&2
    exit 1
  fi
  echo "rsvg-convert/ImageMagick not found; using the committed icon"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rsvg-convert -w 256 -h 256 -o "$tmp/256.png" "$SVG"
# Strip timestamps/metadata so unchanged icons stay byte-identical.
"$IM" "$tmp/256.png" -strip -define png:exclude-chunks=date,time "$PNG"
svg_sum > "$SUM"
echo "rendered $PNG"
