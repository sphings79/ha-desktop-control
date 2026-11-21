#!/bin/zsh
# Builds build/HADesktopControl.app (release). Set SIGN_IDENTITY to a stable certificate name
# to keep macOS permissions (Accessibility, Automation) across rebuilds; default is ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

# Strip the local checkout path from debug strings so the binary does not leak it.
root=$(pwd -P)
flags=(-Xcc "-ffile-prefix-map=$root=." -Xswiftc -file-prefix-map -Xswiftc "$root=.")
swift build -c release "${flags[@]}"
bin_dir=$(swift build -c release --show-bin-path)

version=$(tr -d '[:space:]' < VERSION)
app="build/HADesktopControl.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/HADesktopControl" "$app/Contents/MacOS/HADesktopControl"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.sphings79.HADesktopControl</string>
    <key>CFBundleName</key><string>HA Desktop Control</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleExecutable</key><string>HADesktopControl</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsLocalNetworking</key><true/></dict>
    <key>NSFocusStatusUsageDescription</key>
    <string>HA Desktop Control can skip popups while a Focus (Do Not Disturb) is on.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>HA Desktop Control pauses video playback in your browsers when a Home Assistant contact opens.</string>
</dict>
</plist>
PLIST

codesign --force --sign "${SIGN_IDENTITY:--}" --identifier com.sphings79.HADesktopControl "$app"
echo "Built $app"
