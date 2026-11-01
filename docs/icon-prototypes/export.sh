#!/bin/sh
# Renders each app-icon SVG to a 1024px PNG with transparent corners (what production ships),
# using headless Chrome so SVG filters (the drop shadows) are rasterised at full resolution.
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p png
for f in lodestar-*.svg; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --window-size=1024,1024 --force-device-scale-factor=1 --screenshot="png/${f%.svg}.png" "file://$PWD/$f" >/dev/null 2>&1
  echo "png/${f%.svg}.png"
done
