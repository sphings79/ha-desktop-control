# ha-desktop-control

macOS menu bar app that reacts to Home Assistant window/door contacts over MQTT:

- pauses browser video (Brave, Vivaldi, Chrome) via AppleScript JavaScript,
- minimizes, hides or quits configured apps,
- restores only what it changed once all contacts are closed,
- shows up in Home Assistant through MQTT Discovery (switch, status, now playing, buttons).

See `PLAN.md` for design and decisions, `ha/automation_contacts.yaml` for the HA side.

## Build

```sh
swift test
./scripts/build_app.sh      # -> build/HADesktopControl.app
```

Set `SIGN_IDENTITY` to a stable code-signing certificate to keep macOS permissions across rebuilds.

## Permissions

- Browser: View > Developer > *Allow JavaScript from Apple Events*.
- macOS: Automation (first pause) and Accessibility (minimizing windows).
