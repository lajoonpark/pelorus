#!/bin/bash
#
# Builds Lodestar.app.
#
#   ./scripts/build.sh              # build into ./build/Lodestar.app
#   ./scripts/build.sh --install    # build and copy into /Applications
#   ./scripts/build.sh --run        # build and launch
#   ./scripts/build.sh --verify     # build with SIL verification (see below)
#
# --verify runs the SIL verifier on the optimized module. Release builds use cross-module
# optimization, which serializes RadialCore's optimized SIL and links it into this target; a
# type disagreement between the two (e.g. the two views of CGPoint, swiftlang/swift#92222) can
# otherwise crash the compiler in a random later pass, so a green build is not proof of a sane
# one. The verifier turns that into a deterministic error instead. Slower, so opt-in.

# Ad-hoc signed by default. Ad-hoc signatures are fine locally but the Full Disk Access
# grant is tied to the signature, so rebuilding invalidates it — re-grant after a rebuild,
# or sign with a Developer ID if you plan to iterate a lot.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Lodestar"
DISPLAY_NAME="Lodestar"
BUNDLE_ID="com.local.lodestar"
VERSION="1.0.0"
BUILD_NUMBER="1"
MIN_MACOS="14.0"

CONFIG="release"
INSTALL=0
RUN=0
VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --run) RUN=1 ;;
    --debug) CONFIG="debug" ;;
    --verify) VERIFY=1 ;;
    -h|--help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this app can only be built on macOS (AppKit/SwiftUI)." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift not found. Install Xcode or the Command Line Tools." >&2
  exit 1
fi

BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

echo "==> Compiling ($CONFIG)"
SCRATCH=".build"
if [[ $VERIFY -eq 1 ]]; then
  # A separate scratch path, so the verifier actually recompiles instead of reusing objects
  # from an earlier (possibly crashing) build.
  SCRATCH=".build/verify"
  swift build -c "$CONFIG" --product "$APP_NAME" --scratch-path "$SCRATCH" \
    -Xswiftc -Xfrontend -Xswiftc -sil-verify-all
else
  swift build -c "$CONFIG" --product "$APP_NAME"
fi

BIN_PATH="$(swift build -c "$CONFIG" --scratch-path "$SCRATCH" --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "error: expected binary at $BIN_PATH" >&2
  exit 1
fi

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"

# The app icon (source art and the export scripts live in docs/icon-prototypes).
ICON_SRC="assets/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"
else
  echo "warning: $ICON_SRC not found; the app will have the generic icon." >&2
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT licensed</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Lodestar can open links in your current Safari tab or a new window, and can open Safari's bookmark editor.</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP_DIR" >/dev/null 2>&1 \
  || echo "warning: codesign failed; the app may still run, but permissions will not stick."

echo "==> Built $APP_DIR"

if [[ $INSTALL -eq 1 ]]; then
  if [[ -w /Applications ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_DIR" /Applications/
    echo "==> Installed to /Applications/$APP_NAME.app"
    APP_DIR="/Applications/$APP_NAME.app"
    if [[ -d "/Applications/SafariRadial.app" || -d "/Applications/Pelorus.app" ]]; then
      echo "note: the old SafariRadial/Pelorus app in /Applications is still installed. Quit it and delete it;" >&2
      echo "      Lodestar has a new bundle ID, so re-grant Full Disk Access and the login item." >&2
    fi
  else
    echo "warning: /Applications is not writable; leaving the app in ./$BUILD_DIR" >&2
  fi
fi

if [[ $RUN -eq 1 ]]; then
  echo "==> Launching"
  open "$APP_DIR"
else
  cat <<EOF

Done. Next steps:

  open "$APP_DIR"            # launch it
  ./scripts/build.sh --install  # or copy into /Applications

Then:
  1. Look for the ring icon in the menu bar.
  2. Grant Full Disk Access (System Settings › Privacy & Security › Full Disk Access)
     so the app can read ~/Library/Safari/Bookmarks.plist.
  3. Press Command-R anywhere to open the menu at your cursor.

Note: Command-R is also Safari's Reload. A system-wide hotkey is claimed before
the frontmost app sees the key, so while this app runs Command-R opens the
radial instead of reloading. Settings says so and offers Command-Control-R as a
one-click switch if you want Reload back.
EOF
fi
