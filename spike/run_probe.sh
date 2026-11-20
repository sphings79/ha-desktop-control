#!/bin/zsh
# Compile the probe for a specific Chromium-based browser and run it.
app="${1:?browser app name}"
tmp=$(mktemp -t probe).applescript
sed "s/__APP__/$app/" "$(dirname "$0")/probe_chromium.applescript" > "$tmp"
osascript "$tmp"
rm -f "$tmp"
