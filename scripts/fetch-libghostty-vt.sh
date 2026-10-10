#!/usr/bin/env sh
# Download the prebuilt libghostty-vt (built by the libghostty-vt workflow
# from the Ghostty commit pinned in build-libghostty-vt.sh) into
# ./vendor/ghostty-vt, so building ghostnim doesn't need Zig.
#
# Environment:
#   GHOSTNIM_REPO  GitHub repo with the libghostty-vt release (default: codegod100/ghostnim)
set -eu

REPO=${GHOSTNIM_REPO:-codegod100/ghostnim}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
URL="https://github.com/$REPO/releases/download/libghostty-vt/libghostty-vt-linux-x86_64.tar.gz"

mkdir -p "$ROOT/vendor"
rm -rf "$ROOT/vendor/ghostty-vt"
echo "Downloading $URL"
curl -fsSL "$URL" | tar -C "$ROOT/vendor" -xzf -
echo "libghostty-vt installed in $ROOT/vendor/ghostty-vt"
