#!/bin/zsh
# Builds build/HADesktopControl.app (release). Set SIGN_IDENTITY to a stable certificate name
# to keep macOS permissions (Accessibility, Automation) across rebuilds; default is ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
bin_dir=$(swift build -c release --show-bin-path)

app="build/HADesktopControl.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/HADesktopControl" "$app/Contents/MacOS/HADesktopControl"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.sphings79.HADesktopControl</string>
    <key>CFBundleName</key><string>HA Desktop Control</string>
    <key>CFBundleExecutable</key><string>HADesktopControl</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>HA Desktop Control pauses video playback in your browsers when a Home Assistant contact opens.</string>
</dict>
</plist>
PLIST

codesign --force --sign "${SIGN_IDENTITY:--}" --identifier com.sphings79.HADesktopControl "$app"
echo "Built $app"
