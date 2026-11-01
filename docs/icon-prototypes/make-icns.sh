#!/bin/sh
# Builds Lodestar.icns from png/lodestar-d-brass-tile.png (1024px, transparent corners).
# Usage: ./make-icns.sh [source.png]   (run ./export.sh first)
set -e
cd "$(dirname "$0")"
SRC="${1:-png/lodestar-d-brass-tile.png}"
SET="Lodestar.iconset"
rm -rf "$SET" && mkdir "$SET"
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x 128:icon_128x128 \
            256:icon_128x128@2x 256:icon_256x256 512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x; do
  px="${spec%%:*}"; name="${spec#*:}"
  sips -z "$px" "$px" "$SRC" --out "$SET/$name.png" >/dev/null
done
iconutil -c icns "$SET" -o Lodestar.icns
echo "built Lodestar.icns from $SRC"
