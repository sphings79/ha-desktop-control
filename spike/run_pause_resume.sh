#!/bin/zsh
app="${1:?browser app name}"
tmp=$(mktemp -t pr).applescript
sed "s/__APP__/$app/" "$(dirname "$0")/pause_resume_chromium.applescript" > "$tmp"
osascript "$tmp"
rm -f "$tmp"
