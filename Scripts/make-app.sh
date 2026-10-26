#!/bin/zsh
# Wraps the release build of the demo into build/JellyGlassDemo.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 --arch x86_64      # universal: Apple silicon + Intel
APP=build/JellyGlassDemo.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/apple/Products/Release/JellyGlassDemo "$APP/Contents/MacOS/JellyGlassDemo"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>JellyGlassDemo</string>
  <key>CFBundleIdentifier</key><string>dev.jellyglass.demo</string>
  <key>CFBundleName</key><string>JellyGlass Demo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "built $APP"
ditto -c -k --keepParent "$APP" build/JellyGlassDemo.zip && echo "zipped build/JellyGlassDemo.zip"
