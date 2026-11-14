#!/bin/sh
# Builds AgentHuddle.app in the project root.
set -e
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/AgentHuddle"
APP=AgentHuddle.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/AgentHuddle"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Agent Huddle</string>
  <key>CFBundleIdentifier</key><string>local.agent-huddle</string>
  <key>CFBundleExecutable</key><string>AgentHuddle</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Agent Huddle switches to the terminal tab that runs a session.</string>
</dict>
</plist>
PLIST
codesign --force -s - "$APP" >/dev/null 2>&1 || true
echo "Built $PWD/$APP"
