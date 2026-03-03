#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_EXECUTABLE_NAME="VoiceMemoTranscriptsApp"
APP_BUNDLE_NAME="Oh Memo"
APP_BUNDLE_DIR_NAME="Oh Memo.app"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_BUNDLE_DIR_NAME"
LEGACY_APP_DIR="$DIST_DIR/VoiceMemoTranscriptsApp.app"
ZIP_PATH="$DIST_DIR/oh-memo-macos.zip"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE_PRIMARY="$ROOT_DIR/output/logo-concepts/transcriptmanager 2.png"
ICON_SOURCE_FALLBACK="$ROOT_DIR/output/logo-concepts/transcriptmanager.png"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_ICNS_PATH="$RESOURCES_DIR/AppIcon.icns"
BIN_PATH=""
APP_SHORT_VERSION="$(date +%Y.%m.%d)"
APP_BUILD_VERSION="$(date +%Y%m%d%H%M%S)"

echo "Building release binary..."
cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/ModuleCache"
swift build -c release

BIN_PATH="$(find "$BUILD_DIR" -type f -path "*/release/$APP_EXECUTABLE_NAME" | head -n 1 || true)"
if [[ -z "$BIN_PATH" || ! -f "$BIN_PATH" ]]; then
  echo "Error: could not find release binary for $APP_EXECUTABLE_NAME." >&2
  exit 1
fi

echo "Creating app bundle at $APP_DIR"
rm -rf "$APP_DIR"
if [[ "$LEGACY_APP_DIR" != "$APP_DIR" ]]; then
  rm -rf "$LEGACY_APP_DIR"
fi
rm -f "$ZIP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$APP_EXECUTABLE_NAME"

# The extractor must ship with the app bundle.
cp "$ROOT_DIR/Sources/AppShell/Resources/extract-apple-voice-memos-transcript" \
  "$RESOURCES_DIR/extract-apple-voice-memos-transcript"
chmod +x "$RESOURCES_DIR/extract-apple-voice-memos-transcript"

# Build an .icns app icon if a custom source is available.
ICON_SOURCE=""
if [[ -f "$ICON_SOURCE_PRIMARY" ]]; then
  ICON_SOURCE="$ICON_SOURCE_PRIMARY"
elif [[ -f "$ICON_SOURCE_FALLBACK" ]]; then
  ICON_SOURCE="$ICON_SOURCE_FALLBACK"
fi

if [[ -n "$ICON_SOURCE" ]]; then
  echo "Generating app icon from $ICON_SOURCE"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  ICON_INPUT="$ICON_SOURCE"
  TMP_ICON_INPUT="$BUILD_DIR/AppIconSource.png"
  WIDTH="$(sips -g pixelWidth "$ICON_SOURCE" 2>/dev/null | awk '/pixelWidth:/ {print $2}')"
  HEIGHT="$(sips -g pixelHeight "$ICON_SOURCE" 2>/dev/null | awk '/pixelHeight:/ {print $2}')"

  if [[ -n "$WIDTH" && -n "$HEIGHT" && "$WIDTH" != "$HEIGHT" ]]; then
    CROP_SIZE="$WIDTH"
    if (( HEIGHT < WIDTH )); then
      CROP_SIZE="$HEIGHT"
    fi
    sips -c "$CROP_SIZE" "$CROP_SIZE" "$ICON_SOURCE" --out "$TMP_ICON_INPUT" >/dev/null
    ICON_INPUT="$TMP_ICON_INPUT"
  fi

  sips -z 16 16 "$ICON_INPUT" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_INPUT" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_INPUT" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_INPUT" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_INPUT" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_INPUT" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_INPUT" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_INPUT" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_INPUT" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_INPUT" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS_PATH"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.serdarsalim.transcript-manager</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_BUNDLE_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_SHORT_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# Apply ad-hoc signing so macOS can validate bundle integrity.
echo "Signing app bundle..."
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

# Build a clean distributable zip from this app bundle.
echo "Creating zip archive at $ZIP_PATH"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo
echo "Done."
echo "Version: $APP_SHORT_VERSION ($APP_BUILD_VERSION)"
echo "App bundle: $APP_DIR"
echo "Zip archive: $ZIP_PATH"
echo "Launch with: open \"$APP_DIR\""
