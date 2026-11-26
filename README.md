# swiftbar-usdbrl

SwiftBar plugin that shows the USD/BRL exchange rate in the macOS menu bar. The Go plugin checks Yahoo Finance every minute by default, falls back to AwesomeAPI and keeps the last valid quote in a local cache. It runs on macOS 12 or later, on Apple Silicon and Intel.

## Features

- Menu bar text with the rate and the daily change, for example `US$ 5.73 ▼ 1.62%`.
- Green when the dollar rises against the previous close, red when it falls, system color when flat. Works in light and dark mode.
- Menu with the current rate, daily change, day high, day low, source timestamp, last check time and source link.
- Quotes a few seconds behind the market through Yahoo Finance, with AwesomeAPI as a documented fallback.
- Last valid quote cached locally and shown with a stale warning when every source fails.
- Rate alerts: set a target such as 5.80 and get a macOS notification once the rate reaches it.
- Refresh interval submenu with 30 s, 1, 5, 15 and 30 min presets.
- English by default, with a Language submenu to switch the menu to Brazilian Portuguese.
- HTTPS only, 4 s connect timeout and 8 s total per request. Requests carry no data about the computer.

## Tech stack

- [SwiftBar](https://swiftbar.app/) runs the plugin and draws the menu.
- [Yahoo Finance](https://finance.yahoo.com/quote/USDBRL%3DX/) chart endpoint as the primary source.
- [AwesomeAPI](https://docs.awesomeapi.com.br/api-de-moedas) as the fallback source.
- Go 1.26.5 and its standard library. A short Bash wrapper connects the binary to SwiftBar.
- [mise](https://mise.jdx.dev/) tasks for checks, tests and installation.

## Getting started

Download the installer from the latest release, read it, then run it. It installs SwiftBar through Homebrew when missing, verifies its signature and notarization, and verifies the downloaded plugin binary against the SHA-256 for your Mac.

```bash
curl -fsSLO https://github.com/fascari/swiftbar-usdbrl/releases/latest/download/install.sh
bash install.sh --login-item
```

Drop `--login-item` to skip starting SwiftBar at login. `bash install.sh --uninstall` removes the plugin and keeps SwiftBar.

From a clone, `mise run build` builds `bin/usdbrl`, `mise run install` installs it, and `mise run test` runs the Go unit tests and a smoke test that needs network access.

## Docs

- [Setup, configuration and removal](docs/guide/pages/dev-env/index.md)
- [How the plugin works and how the sources behave](docs/guide/pages/how-it-works/index.md)
