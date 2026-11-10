#!/bin/sh
# Builds build/InkPad.app (menu-bar app, ad-hoc signed).
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=build/InkPad.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/InkPad "$APP/Contents/MacOS/InkPad"
mkdir -p "$APP/Contents/Resources"; cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.inkpad.InkPad</string>
<key>CFBundleName</key><string>InkPad</string>
<key>CFBundleExecutable</key><string>InkPad</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
codesign --force --deep --sign - "$APP"
echo "Built $APP"
