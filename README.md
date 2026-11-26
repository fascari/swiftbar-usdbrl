# swiftbar-usdbrl

SwiftBar plugin that shows the USD/BRL exchange rate in the macOS menu bar. A single Bash script checks Yahoo Finance every minute, falls back to AwesomeAPI when Yahoo fails, and keeps the last valid quote in a local cache. It runs on tools that ship with macOS.

## Features

- Menu bar text with the rate and the daily change, for example `US$ 5.73 ▼ 1.62%`.
- Green when the dollar rises against the previous close, red when it falls, system color when flat. Works in light and dark mode.
- Menu with the current rate, daily change, day high, day low, source timestamp, last check time and source link.
- Quotes a few seconds behind the market through Yahoo Finance, with AwesomeAPI as a documented fallback.
- Last valid quote cached locally and shown with a stale warning when every source fails.
- English by default, with a Language submenu to switch the menu to Brazilian Portuguese.
- HTTPS only, 4 s connect timeout and 8 s total per request. Requests carry no data about the computer.

## Tech stack

- [SwiftBar](https://swiftbar.app/) runs the plugin and draws the menu.
- [Yahoo Finance](https://finance.yahoo.com/quote/USDBRL%3DX/) chart endpoint as the primary source.
- [AwesomeAPI](https://docs.awesomeapi.com.br/api-de-moedas) as the fallback source.
- Bash 3.2, `curl`, `plutil` and `awk`, all built into macOS.
- [mise](https://mise.jdx.dev/) tasks for checks, tests and installation.

## Getting started

```bash
brew install --cask swiftbar
defaults write com.ameba.SwiftBar PluginDirectory -string "$HOME/Library/Application Support/SwiftBar/Plugins"
mise run install
open -a SwiftBar
```

`mise run test` checks the syntax and runs the smoke test, which needs network access.

## Docs

- [Setup, configuration and removal](docs/guide/pages/dev-env/index.md)
- [How the plugin works and how the sources behave](docs/guide/pages/how-it-works/index.md)
