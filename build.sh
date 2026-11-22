#!/bin/zsh
# Builds "Logi Battery.app" next to this script.
set -e
cd "$(dirname "$0")"
APP="Logi Battery.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -framework IOKit -framework ServiceManagement HIDPP.swift main.swift -o "$APP/Contents/MacOS/LogiBattery"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Logi Battery</string>
  <key>CFBundleIdentifier</key><string>io.github.logi-battery-menubar</string>
  <key>CFBundleExecutable</key><string>LogiBattery</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
