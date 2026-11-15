#!/bin/sh
# Builds AgentHuddle.app in the project root.
set -e
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
ARGS="-c release"
# UNIVERSAL=1 builds one binary for both Apple Silicon and Intel Macs.
[ "${UNIVERSAL:-0}" = 1 ] && ARGS="$ARGS --arch arm64 --arch x86_64"
swift build $ARGS
BIN="$(swift build $ARGS --show-bin-path)/AgentHuddle"
APP=AgentHuddle.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/AgentHuddle"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Agent Huddle</string>
  <key>CFBundleIdentifier</key><string>local.agent-huddle</string>
  <key>CFBundleExecutable</key><string>AgentHuddle</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Agent Huddle switches to the terminal tab that runs a session.</string>
</dict>
</plist>
PLIST
codesign --force -s - "$APP" >/dev/null 2>&1 || true
echo "Built $PWD/$APP"
