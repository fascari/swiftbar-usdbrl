# Setup, configuration and removal

## Requirements

- macOS 12 or later, required by the SwiftBar cask.
- [Homebrew](https://brew.sh/), used to install SwiftBar when it's missing.
- [mise](https://mise.jdx.dev/), only to work from a clone.

## Install

Download `install.sh` from the latest release, read it, then run it.

```bash
curl -fsSLO https://github.com/fascari/swiftbar-usdbrl/releases/latest/download/install.sh
bash install.sh --login-item
```

The installer runs these steps and stops at the first failure.

1. Installs SwiftBar from the official Homebrew cask when `/Applications/SwiftBar.app` is missing.
2. Checks the code signature, requires the Ameba Labs team ID `X93LWC49WV` and requires Gatekeeper to accept the app as notarized.
3. Keeps the plugin directory already set in SwiftBar, or sets `~/Library/Application Support/SwiftBar/Plugins` when there is none.
4. Downloads `usdbrl.1m.sh` from the same release and compares its SHA-256 with the value pinned in `install.sh`.
5. Installs the plugin with mode 700 and opens or refreshes SwiftBar.

The installer never turns off Gatekeeper, never strips the quarantine attribute and only asks for a permission with `--login-item`.

### Options

| Option | Effect |
|---|---|
| `--login-item` | Start SwiftBar at login through System Events. macOS asks once for Automation permission. |
| `--interval <n>` | Refresh interval, such as `30s`, `5m` or `1h`. Defaults to `1m`. |
| `--plugin <file>` | Install a local plugin file instead of the release asset. |
| `--uninstall` | Remove the plugin, its cache and its settings, keeping SwiftBar. |

Running the installer again updates the plugin in place. The pinned checksum protects against a corrupted or altered download, but `install.sh` and the plugin come from the same release, so reading `install.sh` before running it is still the way to trust it.

### Verify SwiftBar by hand

```bash
APP=/Applications/SwiftBar.app
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier'
spctl --assess --type execute --verbose=4 "$APP"
```

Version 2.1.1 (build 597), checked on 2026-11-26, is signed by `Developer ID Application: Ameba Labs, LLC (X93LWC49WV)` and `spctl` reports `source=Notarized Developer ID`.

## Language

The menu is in English by default. Pick Language, then Português, in the plugin menu to switch it to Brazilian Portuguese. The choice lives in `~/Library/Application Support/usdbrl-swiftbar/lang`.

## Change the refresh interval

```bash
bash install.sh --interval 5m
```

The installer replaces the previous `usdbrl.*.sh` file, because SwiftBar reads the interval from the file name. Intervals under 1 minute add load on the sources without much gain. See [How the plugin works](../how-it-works/index.md) for how fresh each source is.

## Work from a clone

```bash
mise trust
mise run test
mise run install
```

`mise run install` passes extra flags to `install.sh`, for example `mise run install -- --interval 5m`. The smoke test uses temporary cache and config directories and the network, and never touches the real files.

## Release

```bash
mise run release v1.0.0
```

The release task pins the plugin version and SHA-256 in `install.sh`, runs the smoke test, commits, tags, pushes and creates the GitHub release with `install.sh` and `usdbrl.1m.sh` as assets.

## Uninstall

```bash
bash install.sh --uninstall
```

This removes the plugin, `~/Library/Caches/usdbrl-swiftbar` and `~/Library/Application Support/usdbrl-swiftbar`. To remove SwiftBar too, quit it from its menu and run the commands the uninstaller prints.

```bash
osascript -e 'tell application "System Events" to delete login item "SwiftBar"'
defaults delete com.ameba.SwiftBar
brew uninstall --zap --cask swiftbar
```

`--zap` removes `~/Library/Caches/com.ameba.SwiftBar`, `~/Library/Preferences/com.ameba.SwiftBar.plist` and the login helper folders.
