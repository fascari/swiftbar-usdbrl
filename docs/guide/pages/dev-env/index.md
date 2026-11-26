# Setup, configuration and removal

## Requirements

- macOS 12 or later, required by the SwiftBar cask.
- [Homebrew](https://brew.sh/).
- [mise](https://mise.jdx.dev/), to run the project tasks.

## Install SwiftBar and verify it

Install SwiftBar only through the official Homebrew cask.

```bash
brew install --cask swiftbar
```

Check the signature, notarization and Gatekeeper assessment of the installed app.

```bash
APP=/Applications/SwiftBar.app
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier'
spctl --assess --type execute --verbose=4 "$APP"
xcrun stapler validate "$APP"
```

Version 2.1.1 (build 597), checked on 2026-11-26, gives these results.

- Signed by `Developer ID Application: Ameba Labs, LLC (X93LWC49WV)`.
- `spctl` accepts the app with `source=Notarized Developer ID`.
- `stapler` prints `The validate action worked!`.

If any check fails, don't open the app. Don't turn off Gatekeeper and don't strip the quarantine attribute. If macOS asks for confirmation on first launch, confirm in the system dialog.

## Set the plugin directory

SwiftBar stores its plugin directory in the `PluginDirectory` key. Check for an existing value before writing one.

```bash
defaults read com.ameba.SwiftBar PluginDirectory
```

If the key doesn't exist, point SwiftBar to a dedicated directory.

```bash
mkdir -p -m 700 "$HOME/Library/Application Support/SwiftBar/Plugins"
defaults write com.ameba.SwiftBar PluginDirectory -string "$HOME/Library/Application Support/SwiftBar/Plugins"
```

If another directory is already set, keep it and install there with `PLUGIN_DIR=<directory> mise run install`.

## Install the plugin

```bash
mise trust
mise run install
open -a SwiftBar
```

`mise run install` checks the syntax and copies the script with mode 700. SwiftBar picks it up on its own and runs it every minute.

## Start at login

Register SwiftBar as a login item through System Events. macOS asks once for Automation permission so the terminal can control System Events.

```bash
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/SwiftBar.app", hidden:false}'
```

Confirm it in System Settings, General, Login Items. Turning on the launch-at-login option in the SwiftBar preferences works too and needs no extra permission. Use one of the two, not both.

## Language

The menu is in English by default. Pick Language, then Português, in the plugin menu to switch it to Brazilian Portuguese. The choice lives in `~/Library/Application Support/usdbrl-swiftbar/lang`.

## Change the refresh interval

SwiftBar reads the interval from the installed file name, with the units `s`, `m`, `h` and `d`. To refresh every 5 minutes, reinstall with another interval and delete the old file.

```bash
INTERVAL=5m mise run install
rm "$HOME/Library/Application Support/SwiftBar/Plugins/usdbrl.1m.sh"
```

Intervals under 1 minute add load on the sources without much gain. See [How the plugin works](../how-it-works/index.md) for how fresh each source is.

## Test

```bash
mise run test
```

The smoke test uses temporary cache and config directories and the network. It never touches the real files.

## Uninstall

1. Remove the login item, or turn off the option in the SwiftBar preferences if that's the one in use.

```bash
osascript -e 'tell application "System Events" to delete login item "SwiftBar"'
```

2. Quit SwiftBar from its menu.
3. Remove the app and its data.

```bash
defaults delete com.ameba.SwiftBar
brew uninstall --zap --cask swiftbar
```

4. Remove the plugin files. If the `SwiftBar` directory holds other plugins, delete only `usdbrl.*.sh`.

```bash
rm -rf "$HOME/Library/Application Support/SwiftBar" \
  "$HOME/Library/Application Support/usdbrl-swiftbar" \
  "$HOME/Library/Caches/usdbrl-swiftbar"
```

`--zap` removes `~/Library/Caches/com.ameba.SwiftBar`, `~/Library/Preferences/com.ameba.SwiftBar.plist` and the login helper folders.
