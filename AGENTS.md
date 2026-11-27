# Repository instructions

See the [shared engineering rules in `fascari/ai-config`](https://github.com/fascari/ai-config/tree/main/rules) for the general Go, testing, and documentation conventions. The rules below describe how they apply to this repository.

## Code

- Put reusable code with no project or business dependencies in `pkg/`. Keep feature policy, application workflows, providers, and UI adapters in `internal/`. Packages in `pkg/` must not import `internal/`.

The project started from the `cli-simple` variant of the Go scaffold in [`fascari/scaffold-templates`](https://github.com/fascari/scaffold-templates).

- Keep `cmd/main.go` limited to startup, configuration, and dependency wiring. Put command dispatch and the refresh flow in `internal/cli`, and keep quote fetching, alerts, localization, and menu rendering in their own packages under `internal/`.
- Follow the Go version pinned in `mise.toml`. Prefer the standard library, reuse existing code, and avoid abstractions that only rename a single operation.
- Prefer early returns over `else`. Keep function signatures to three parameters. If more inputs are needed, group related inputs in a named struct.
- In Go, prefer guard clauses for validation. Use a `switch` when it clarifies a type assertion or dispatch on a single typed value, such as a menu action.
- Use typed constants for values shared across the CLI, menu, and state files, such as action flags and language codes. Define interfaces where they are used and name parameters whose roles would otherwise be unclear.
- Use modern Go idioms supported by the pinned version, such as `errors.AsType` for typed error checks and `new(value)` when taking a pointer to a new value.
- Keep Go and Bash comments focused on non-obvious intent, contracts, compatibility, or ordering. Remove comments that restate the code. Preserve directives, generated code markers, and SwiftBar metadata.
- Keep unit tests focused on happy paths and critical regressions. Match test files to the source they cover, keep small fixtures with their tests, and compare whole values when the result is structured. Avoid duplicating coverage from smoke and parity checks.
- In Bash, quote path and argument expansions, prefer function-local variables to mutable globals, and pass inputs explicitly. Check each background job's exit status when the result matters.

## Compatibility

- Keep shell scripts compatible with the macOS system Bash 3.2.
- Preserve existing alert, language, interval, and cache formats across updates. The installer generates the `usdbrl.<interval>.sh` wrapper that SwiftBar uses for metadata and menu actions.
- Keep installer and release support for macOS arm64 and amd64.

## Validation

- Run `mise run lint`, `mise exec -- go vet ./...`, and `mise run test` for Go changes. The test task includes ShellCheck and live smoke tests.
- Run `bash scripts/parity.sh` after building to compare menu output with v1.1.1. Its live cases need network access.
- For changes to locking or concurrent state updates, run `mise exec -- env CGO_ENABLED=1 go test -race ./...`.
- For installer or packaging changes, run `bash test/installer.sh <assets-dir>` with a prepared installer and both binaries. Use an isolated test home and check both architectures when supported.
