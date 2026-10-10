#!/usr/bin/env sh
# Package ghostnim as an AppImage with appimagetool.
#
# Builds the Flutter release bundle (fetching the prebuilt libghostty-vt if
# vendor/ghostty-vt is missing), lays out build/AppDir with the bundle, the
# fonts ghostnim ships and the icon, and writes ghostnim-<version>-<arch>.AppImage
# into the repository root. Bundled:
#   - the Flutter bundle (ghostnim, lib/ with libghostty-vt, data/)
#   - Monaspace Neon Frozen (default font), DejaVu Sans Mono (fallback) and
#     Symbols Nerd Font Mono (icon fallback), in data/fonts, which ghostnim
#     loads at startup
#   - the icon, as SVG and a 256x256 PNG (scripts/build-icons.sh)
# GTK 3 comes from the host, as for any Flutter Linux app.
#
# Requirements: Flutter, curl, tar with bzip2/xz support.
#
# Environment:
#   APPIMAGETOOL  appimagetool executable    (default: download into build/tools)
#   VERSION       version in the file name   (default: from pubspec.yaml)
#   OUTPUT        AppImage file name         (default: ghostnim-<version>-<arch>.AppImage)
#   FLUTTER_FLAGS extra flags for `flutter build linux`, e.g.
#                 --dart-define=AUTO_UPDATE=true
#   UPDATE_INFORMATION  update information to embed; appimagetool then also
#                 writes <OUTPUT>.zsync (see .github/workflows/appimage.yml)
#   SKIP_BUILD=1  package the existing release bundle instead of rebuilding
#   APPDIR_ONLY=1 stop after laying out build/AppDir (the conda recipe
#                 packages it; see recipe/recipe.yaml)
#   MONASPACE_VERSION, DEJAVU_VERSION, NERD_FONTS_VERSION
#                 bundled font releases
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
APPDIR="$BUILD/AppDir"
TOOLS="$BUILD/tools"
ARCH=$(uname -m)
VERSION=${VERSION:-$(sed -n 's/^version: *\([^+]*\).*/\1/p' "$ROOT/pubspec.yaml")}
OUTPUT=${OUTPUT:-ghostnim-$VERSION-$ARCH.AppImage}
MONASPACE_VERSION=${MONASPACE_VERSION:-1.200}
DEJAVU_VERSION=${DEJAVU_VERSION:-2.37}
NERD_FONTS_VERSION=${NERD_FONTS_VERSION:-3.4.0}
case "$ARCH" in x86_64) FLARCH=x64 ;; aarch64) FLARCH=arm64 ;; *) FLARCH=$ARCH ;; esac
BUNDLE="$BUILD/linux/$FLARCH/release/bundle"

cd "$ROOT"
sh "$ROOT/scripts/build-icons.sh"

if [ "${SKIP_BUILD:-0}" != 1 ]; then
  if [ ! -d "$ROOT/vendor/ghostty-vt/lib" ]; then
    sh "$ROOT/scripts/fetch-libghostty-vt.sh" || sh "$ROOT/scripts/build-libghostty-vt.sh"
  fi
  # shellcheck disable=SC2086
  flutter build linux --release --build-name="$VERSION" ${FLUTTER_FLAGS:-}
fi
[ -x "$BUNDLE/ghostnim" ] || { echo "error: $BUNDLE/ghostnim not built" >&2; exit 1; }

fetch() { # name url
  [ -x "$TOOLS/$1" ] && return
  mkdir -p "$TOOLS"
  echo "fetching $1"
  curl -fL --retry 3 -o "$TOOLS/$1.part" "$2"
  chmod +x "$TOOLS/$1.part"
  mv "$TOOLS/$1.part" "$TOOLS/$1"
}
if [ -z "${APPIMAGETOOL:-}" ] && [ "${APPDIR_ONLY:-0}" != 1 ]; then
  fetch "appimagetool-$ARCH.AppImage" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage"
  APPIMAGETOOL="$TOOLS/appimagetool-$ARCH.AppImage"
fi

# Fonts: downloaded once into build/tools, then copied into the AppDir.
fetch_font() { # name url
  [ -d "$TOOLS/$1" ] && return
  mkdir -p "$TOOLS"
  echo "fetching $1"
  curl -fL --retry 3 -o "$TOOLS/$1.archive" "$2"
  rm -rf "$TOOLS/$1.part" && mkdir "$TOOLS/$1.part"
  tar -xf "$TOOLS/$1.archive" -C "$TOOLS/$1.part"
  rm "$TOOLS/$1.archive"
  mv "$TOOLS/$1.part" "$TOOLS/$1"
}
# Monaspace's release zip is ~1 GB, so fetch just the files we ship from the
# release tag.
monaspace="$TOOLS/monaspace-$MONASPACE_VERSION"
if [ ! -d "$monaspace" ]; then
  echo "fetching monaspace-$MONASPACE_VERSION"
  rm -rf "$monaspace.part" && mkdir -p "$monaspace.part"
  for f in LICENSE fonts/frozen/MonaspaceNeonFrozen-Regular.ttf \
           fonts/frozen/MonaspaceNeonFrozen-Bold.ttf fonts/frozen/MonaspaceNeonFrozen-Italic.ttf \
           fonts/frozen/MonaspaceNeonFrozen-BoldItalic.ttf; do
    curl -fL --retry 3 -o "$monaspace.part/$(basename "$f")" \
      "https://raw.githubusercontent.com/githubnext/monaspace/v$MONASPACE_VERSION/$f"
  done
  mv "$monaspace.part" "$monaspace"
fi
fetch_font "dejavu-$DEJAVU_VERSION" \
  "https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_$(echo "$DEJAVU_VERSION" | tr . _)/dejavu-fonts-ttf-$DEJAVU_VERSION.tar.bz2"
fetch_font "nerd-fonts-symbols-$NERD_FONTS_VERSION" \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/v$NERD_FONTS_VERSION/NerdFontsSymbolsOnly.tar.xz"

rm -rf "$APPDIR"
app="$APPDIR/usr/lib/ghostnim"
mkdir -p "$app"
cp -a "$BUNDLE"/. "$app/"
fonts="$app/data/fonts"
mkdir -p "$fonts/monaspace" "$fonts/dejavu" "$fonts/nerd-fonts-symbols"
cp "$monaspace"/* "$fonts/monaspace/"
dejavu="$TOOLS/dejavu-$DEJAVU_VERSION/dejavu-fonts-ttf-$DEJAVU_VERSION"
cp "$dejavu"/ttf/DejaVuSansMono*.ttf "$dejavu/LICENSE" "$fonts/dejavu/"
nerd="$TOOLS/nerd-fonts-symbols-$NERD_FONTS_VERSION"
cp "$nerd/SymbolsNerdFontMono-Regular.ttf" "$nerd/LICENSE" "$fonts/nerd-fonts-symbols/"

cp "$ROOT/packaging/ghostnim.desktop" "$APPDIR/"
cp "$ROOT/packaging/ghostnim.svg" "$ROOT/packaging/ghostnim.png" "$APPDIR/"
ln -sf ghostnim.png "$APPDIR/.DirIcon"
mkdir -p "$APPDIR/usr/share/icons/hicolor/scalable/apps"
cp "$ROOT/packaging/ghostnim.svg" "$APPDIR/usr/share/icons/hicolor/scalable/apps/"
cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
HERE=$(dirname "$(readlink -f "$0")")
exec "$HERE/usr/lib/ghostnim/ghostnim" "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

if [ "${APPDIR_ONLY:-0}" = 1 ]; then
  echo "laid out $APPDIR"
  exit 0
fi

# APPIMAGE_EXTRACT_AND_RUN: run appimagetool's own AppImage without FUSE.
set -- "$APPDIR" "$ROOT/$OUTPUT"
[ -n "${UPDATE_INFORMATION:-}" ] && set -- -u "$UPDATE_INFORMATION" "$@"
APPIMAGE_EXTRACT_AND_RUN=1 ARCH="$ARCH" VERSION="$VERSION" "$APPIMAGETOOL" --no-appstream "$@"

echo
echo "built $ROOT/$OUTPUT"
