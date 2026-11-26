# Setup, configuration and removal

## Requirements

- macOS 12 or later on Apple Silicon or Intel.
- [Homebrew](https://brew.sh/), used to install SwiftBar when it's missing.
- [mise](https://mise.jdx.dev/), only to work from a clone.

## Install

Download `install.sh` from the latest release, read it, then run it.

The steps below describe the Go installer from v2.0.0 onward. Older releases install the Bash plugin. To try the Go version before release, [work from a clone](#work-from-a-clone).

```bash
curl -fsSLO https://github.com/fascari/swiftbar-usdbrl/releases/latest/download/install.sh
bash install.sh --login-item
```

The installer runs these steps and stops at the first failure.

1. Installs SwiftBar from the official Homebrew cask when `/Applications/SwiftBar.app` is missing.
2. Checks the code signature, requires the Ameba Labs team ID `X93LWC49WV` and requires Gatekeeper to accept the app as notarized.
3. Keeps the plugin directory already set in SwiftBar, or sets `~/Library/Application Support/SwiftBar/Plugins` when there is none.
4. Downloads `usdbrl-darwin-arm64` for Apple Silicon, including under Rosetta, or `usdbrl-darwin-amd64` for Intel. It compares the SHA-256 with the pin in `install.sh` and checks the binary's format, architecture and version.
5. Installs the Go binary at `~/Library/Application Support/usdbrl-swiftbar/bin/usdbrl` and the wrapper `usdbrl.<interval>.sh` in the SwiftBar plugin directory. It opens or refreshes SwiftBar.

The plugin binary is not notarized. On Apple Silicon the Go linker signs it ad hoc. The installer downloads it with `curl`, which does not add the browser's quarantine attribute. The installer leaves macOS security settings and quarantine attributes alone. Only `--login-item` asks for Automation permission.

### Options

| Option | Effect |
|---|---|
| `--login-item` | Start SwiftBar at login through System Events. macOS asks once for Automation permission. |
| `--interval <n>` | Refresh interval, such as `30s`, `5m` or `1h`. Defaults to the installed one, or `1m`. |
| `--plugin <file>` | Install a local Go binary for this Mac instead of downloading the release asset. |
| `--uninstall` | Remove the plugin, its cache and its settings, keeping SwiftBar. |

Running the installer again updates the plugin in place. The pinned checksum protects against a corrupted or altered download, but `install.sh` and the plugin come from the same release, so reading `install.sh` before running it is still the way to trust it.

An update from v1.1.1 keeps the refresh interval, language, alerts and cache. To downgrade, run the [v1.1.1 installer](https://github.com/fascari/swiftbar-usdbrl/releases/download/v1.1.1/install.sh). It replaces the wrapper with the old script, which can read the same data. The Go binary stays unused in the config directory until uninstall removes it.

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

## Alerts

Pick Alerts, then Add alert, type a target such as `5,80`, `5.80` or `R$ 5,80` and confirm. An invalid value brings the dialog back with the error, up to three times. A target above the current rate fires when the rate rises to it, and a target below fires when the rate drops to it. Each alert fires once, shows a macOS notification and goes away. Click an alert in the menu to remove it before it fires.

Alerts live in `~/Library/Application Support/usdbrl-swiftbar/alerts`. The same actions work from a terminal.

```bash
PLUGIN="$HOME/Library/Application Support/SwiftBar/Plugins/usdbrl.1m.sh"
"$PLUGIN" --add-alert 5.80
"$PLUGIN" --remove-alert above 5.8
"$PLUGIN" --clear-alerts
```

The notification comes from `osascript`, so macOS lists it under Script Editor in System Settings, Notifications. If no notification shows up, allow notifications for Script Editor there.

## Change the refresh interval

Pick Refresh interval in the plugin menu and choose 30 s, 1, 5, 15 or 30 min. SwiftBar reads the interval from the file name, so the plugin renames itself, for example to `usdbrl.5m.sh`, and SwiftBar reloads it.

The installer accepts other values too, and keeps the installed interval when `--interval` is left out.

```bash
bash install.sh --interval 2h
```

Intervals under 1 minute add load on the sources without much gain. See [How the plugin works](../how-it-works/index.md) for how fresh each source is. If the menu bar item moves after a change, hold Command and drag it back.

## Work from a clone

```bash
mise trust
mise run build
mise run test
mise run install
```

`mise run install` passes extra flags to `install.sh`, for example `mise run install -- --interval 5m`. The smoke test uses temporary cache and config directories and the network, and never touches the real files.

`mise run check` checks Bash syntax and runs ShellCheck. `mise run lint` checks Go code and formatting. `bash scripts/parity.sh` compares the menu against the v1.1.1 tag after `mise run build`. Its offline cases cover the cached and empty states, and two live cases compare the success path with the real AwesomeAPI, so the script needs network access.

Edit menu text in `internal/locale/en.json` and `internal/locale/pt.json`. Go embeds both catalogs in the binary. Keep the same keys and format placeholders in both files.

## Release

```bash
mise run release v2.0.0
```

The release task builds both binaries twice, including once from a clean git export, and verifies that their checksums match. It runs the checks and tests, pins both checksums in `install.sh`, commits, tags, pushes and publishes the installer and both binaries.

### Rebuild and check a release

From a clone with tags and the pinned Go toolchain installed through mise:

```bash
version=v2.0.0
work=$(mktemp -d)
mkdir "$work/source"
git archive "$version" | tar -xf - -C "$work/source"
(
  cd "$work/source"
  for arch in arm64 amd64; do
    binary="usdbrl-darwin-$arch"
    mise exec -- env GOOS=darwin GOARCH="$arch" GOARM64=v8.0 GOAMD64=v1 \
      CGO_ENABLED=0 GOTOOLCHAIN=local GOWORK=off GOFLAGS='' \
      go build -trimpath -buildvcs=false -ldflags "-s -w -X main.version=$version" \
      -o "$work/$binary" ./cmd
    curl -fsSL "https://github.com/fascari/swiftbar-usdbrl/releases/download/$version/$binary" \
      -o "$work/downloaded-$binary"
    cmp "$work/$binary" "$work/downloaded-$binary" || exit 1
    shasum -a 256 "$work/$binary"
  done
)
grep '^readonly PLUGIN_SHA256_' "$work/source/install.sh"
```

Compare the two printed SHA-256 values with the matching pins from `install.sh`.

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
