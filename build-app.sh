#!/bin/bash
# Builds build/FTX1 Status.app.
#   VERSION=1.2.3   version stamped into Info.plist (default 0.0.0-dev)
#   UNIVERSAL=1     arm64 + x86_64 binary (needs full Xcode; CI uses this)
#   --install       also copy the app to ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-0.0.0-dev}"
# CFBundleVersion must be numeric (1.2.3), so drop any pre-release suffix like -beta.1.
BUILD_NUMBER="${VERSION%%-*}"
ARCH_FLAGS=()
[[ "${UNIVERSAL:-0}" == "1" ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="build/FTX1 Status.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FTX1Status" "$APP/Contents/MacOS/FTX1Status"

# App icon: every size iconutil wants, from the 1024 px master (redraw it with scripts/make-icon.swift).
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Icon/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) Icon/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>FTX1 Status</string>
  <key>CFBundleDisplayName</key><string>FTX1 Status</string>
  <key>CFBundleIdentifier</key><string>io.github.evil-wizard-corp.ftx1status</string>
  <key>CFBundleExecutable</key><string>FTX1Status</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Ben Mikiten. MIT License.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: required for arm64 to run at all; not a Developer ID, so Gatekeeper still quarantines downloads.
codesign --force --sign - "$APP"
echo "Built $APP ($VERSION)"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/"FTX1 Status.app"
  cp -R "$APP" ~/Applications/
  echo "Installed ~/Applications/FTX1 Status.app"
fi
