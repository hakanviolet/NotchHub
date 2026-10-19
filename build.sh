#!/usr/bin/env bash
# NotchHub.app paketini oluşturur. `--install` ile ~/Applications'a kopyalar ve başlatır.
set -euo pipefail
cd "$(dirname "$0")"

[[ -f Resources/AppIcon.icns ]] || swift tools/make-icon.swift Resources/icon-source.png Resources/AppIcon.icns

swift build -c release --product NotchHub
APP="build/NotchHub.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchHub "$APP/Contents/MacOS/NotchHub"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>NotchHub</string>
    <key>CFBundleDisplayName</key><string>NotchHub</string>
    <key>CFBundleIdentifier</key><string>local.mainai.notchhub</string>
    <key>CFBundleExecutable</key><string>NotchHub</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Oluşturuldu: $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x NotchHub 2>/dev/null || true
    sleep 0.5
    mkdir -p ~/Applications
    rm -rf ~/Applications/NotchHub.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/NotchHub.app
    echo "Kuruldu ve başlatıldı: ~/Applications/NotchHub.app"
fi
