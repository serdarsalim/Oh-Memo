#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="VoiceMemoTranscriptsApp"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BIN_PATH=""

echo "Building release binary..."
cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/ModuleCache"
swift build -c release

BIN_PATH="$(find "$BUILD_DIR" -type f -path "*/release/$APP_NAME" | head -n 1 || true)"
if [[ -z "$BIN_PATH" || ! -f "$BIN_PATH" ]]; then
  echo "Error: could not find release binary for $APP_NAME." >&2
  exit 1
fi

echo "Creating app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# The extractor must ship with the app bundle.
cp "$ROOT_DIR/Sources/AppShell/Resources/extract-apple-voice-memos-transcript" \
  "$RESOURCES_DIR/extract-apple-voice-memos-transcript"
chmod +x "$RESOURCES_DIR/extract-apple-voice-memos-transcript"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>VoiceMemoTranscriptsApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.serdarsalim.transcript-manager</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Transcript Manager</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo
echo "Done."
echo "App bundle: $APP_DIR"
echo "Launch with: open \"$APP_DIR\""
