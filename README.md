# USD/BRL for SwiftBar

SwiftBar plugin that shows the USD/BRL exchange rate in the macOS menu bar. The Go plugin checks Yahoo Finance every minute by default, falls back to AwesomeAPI and keeps the last valid quote in a local cache. It runs on macOS 12 or later, on Apple Silicon and Intel.

## Features

- See the rate and daily change in the menu bar, for example `US$ 5.73 ▼ 1.62%`. Open the menu for the day high, day low, source, and timestamps.
- Keep the last valid quote visible with a stale warning when both sources fail.
- Set a target such as `5.80` and get a macOS notification once the rate reaches it.
- Choose **Higlobe · USDC/BRL** under **Show in menu bar** to see the conversion rate and, if you have saved payments, the estimated BRL total. **Higlobe → Open converter** opens the native editor and simulator.
- Change the refresh interval or switch between English and Brazilian Portuguese from the menu.

## Tech stack

- [SwiftBar](https://swiftbar.app/) runs the plugin and draws the menu.
- Go and its standard library. A short Bash wrapper connects the binary to SwiftBar.
- [mise](https://mise.jdx.dev/) tasks for checks, tests and installation.

## Getting started

Download the installer from the [latest release](https://github.com/fascari/swiftbar-usdbrl/releases/latest), read it, then run it. The Go installer is available starting with v2.0.0. If the latest release is older, it installs the legacy Bash plugin. To try the Go version before release, build from a clone.

```bash
curl -fsSLO https://github.com/fascari/swiftbar-usdbrl/releases/latest/download/install.sh
bash install.sh --login-item
```

Drop `--login-item` to skip starting SwiftBar at login. The installer uses [Homebrew](https://brew.sh/) if SwiftBar is missing. Run `bash install.sh --uninstall` to remove the plugin while keeping SwiftBar.

From a clone with mise installed, run `mise trust` after reviewing `mise.toml`, then `mise run install` to build and install the Go plugin.

## Documentation and contributing

- [Setup, configuration and removal](docs/guide/pages/dev-env/index.md)
- [How the plugin works and how the sources behave](docs/guide/pages/how-it-works/index.md)
- [Report a bug or contribute a change](CONTRIBUTING.md)

## License

This project is licensed under the [MIT License](LICENSE).
