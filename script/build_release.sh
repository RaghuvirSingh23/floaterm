#!/usr/bin/env bash
set -euo pipefail

APP_NAME="floaterm"
BUILD_TARGET_NAME="Floaterm"
BUNDLE_ID="com.raghusi.floaterm"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist/release}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Assets/AppIcon.png"
APP_ICON_PATH="$APP_RESOURCES/AppIcon.icns"

RAW_VERSION="${1:-${RELEASE_VERSION:-}}"
if [[ -z "$RAW_VERSION" ]]; then
  RAW_VERSION="$(git -C "$ROOT_DIR" describe --tags --always --dirty)"
fi

DISPLAY_VERSION="${RAW_VERSION#v}"
BUILD_VERSION="${RELEASE_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD)}}"
ARCH="$(uname -m)"
ARTIFACT_STEM="$APP_NAME-$RAW_VERSION-macos-$ARCH"
ZIP_PATH="$DIST_DIR/$ARTIFACT_STEM.zip"
DMG_PATH="$DIST_DIR/$ARTIFACT_STEM.dmg"
CHECKSUM_PATH="$DIST_DIR/$ARTIFACT_STEM-sha256.txt"

generate_app_icon() {
  if [[ ! -f "$APP_ICON_SOURCE" ]]; then
    echo "error: missing app icon source at $APP_ICON_SOURCE" >&2
    exit 1
  fi

  local icon_work_dir
  local iconset_dir

  icon_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/floaterm-icon.XXXXXX")"
  iconset_dir="$icon_work_dir/AppIcon.iconset"
  mkdir -p "$iconset_dir"

  resize_icon() {
    local size="$1"
    local filename="$2"
    sips -z "$size" "$size" "$APP_ICON_SOURCE" --out "$iconset_dir/$filename" >/dev/null
  }

  resize_icon 16 "icon_16x16.png"
  resize_icon 32 "icon_16x16@2x.png"
  resize_icon 32 "icon_32x32.png"
  resize_icon 64 "icon_32x32@2x.png"
  resize_icon 128 "icon_128x128.png"
  resize_icon 256 "icon_128x128@2x.png"
  resize_icon 256 "icon_256x256.png"
  resize_icon 512 "icon_256x256@2x.png"
  resize_icon 512 "icon_512x512.png"
  resize_icon 1024 "icon_512x512@2x.png"

  iconutil -c icns "$iconset_dir" -o "$APP_ICON_PATH"
  rm -rf "$icon_work_dir"
}

write_info_plist() {
  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$DISPLAY_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

sign_bundle_if_configured() {
  local identity="${APPLE_SIGNING_IDENTITY:-}"
  if [[ -z "$identity" ]]; then
    return
  fi

  codesign --force --deep --options runtime --sign "$identity" "$APP_BUNDLE"
}

create_dmg() {
  local staging_dir
  staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/floaterm-release.XXXXXX")"
  cp -R "$APP_BUNDLE" "$staging_dir/"
  ln -s /Applications "$staging_dir/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$staging_dir" -ov -format UDZO "$DMG_PATH" >/dev/null
  rm -rf "$staging_dir"
}

rm -rf "$DIST_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$BUILD_TARGET_NAME"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

find "$BUILD_DIR" -maxdepth 1 -name '*.bundle' -print0 | while IFS= read -r -d '' bundle; do
  cp -R "$bundle" "$APP_RESOURCES/"
done

generate_app_icon
write_info_plist
sign_bundle_if_configured

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
create_dmg
shasum -a 256 "$ZIP_PATH" "$DMG_PATH" > "$CHECKSUM_PATH"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "app_bundle=$APP_BUNDLE"
    echo "zip_path=$ZIP_PATH"
    echo "dmg_path=$DMG_PATH"
    echo "checksum_path=$CHECKSUM_PATH"
    echo "artifact_stem=$ARTIFACT_STEM"
  } >>"$GITHUB_OUTPUT"
fi

printf 'Built release artifacts:\n'
printf '  %s\n' "$APP_BUNDLE" "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"
