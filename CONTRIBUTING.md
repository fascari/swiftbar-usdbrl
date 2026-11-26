# Contributing

Bug reports, documentation fixes, and code contributions are welcome. Keep discussions focused on the work and treat other contributors with respect.

## Report a problem

Search the [issues](https://github.com/fascari/swiftbar-usdbrl/issues) before opening a new one. Include the plugin version or build from **About**, your macOS and SwiftBar versions, and whether your Mac is Apple Silicon or Intel. Describe how to reproduce the issue and what you expected to happen. Share only relevant output and remove personal paths or other private information.

Open an issue to discuss changes to the installer, saved settings, quote sources, or menu behavior before starting a large change.

## Build and test locally

Clone the repository with its tags. Install [mise](https://mise.jdx.dev/) and review `mise.toml` before trusting it. Use macOS 12 or later to run the plugin.

```bash
mise trust
mise run build
mise run lint
mise exec -- go vet ./...
mise run test
bash scripts/parity.sh
```

`mise run test` runs Go unit tests, ShellCheck, and a live smoke test. The parity script uses the `v1.1.1` tag and compares generated menus, including live cases. Both scripts use temporary state, and the live checks need network access.

Use `mise run install` to try a change in SwiftBar. It replaces the installed plugin in your account. For packaging changes, use the isolated installer checks in [AGENTS.md](AGENTS.md). See the [development guide](docs/guide/pages/dev-env/index.md) for setup and removal.

## Submit a change

Open a pull request from your fork. Keep it focused, link the issue if there is one, and describe the behavior that changed and the checks you ran. Follow the project conventions in [AGENTS.md](AGENTS.md). Include a screenshot when it helps explain a visible menu change.
