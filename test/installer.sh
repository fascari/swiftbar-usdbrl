#!/bin/bash
set -euo pipefail

assets=${1:?provide a directory with install.sh and both release binaries}
assets=$(cd "$assets" && pwd)
installer="$assets/install.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# shellcheck disable=SC2317
run_installer() (
  # shellcheck source=/dev/null
  source "$installer"
  ensure_swiftbar() { return 0; }
  verify_swiftbar() { return 0; }
  start_swiftbar() { return 0; }
  defaults() {
    case $1 in
      read)
        [ -n "$plugins" ] || return 1
        printf '%s\n' "$plugins"
        ;;
      write)
        [ "$5" = "$HOME/Library/Application Support/SwiftBar/Plugins" ]
        ;;
    esac
  }
  pgrep() { return 1; }
  sw_vers() { printf '%s\n' "${os_version:-12.0}"; }
  mv() {
    if [ "${fail_wrapper:-0}" = 1 ] && [[ ${3:-} == "$plugins"/usdbrl.*.sh ]]; then
      return 1
    fi
    command mv "$@"
  }
  sysctl() {
    if [ "$target" = arm64 ]; then
      printf '1\n'
      return
    fi
    printf 'unknown oid\n' >&2
    return 1
  }
  curl() {
    local output='' url=''
    while [ "$#" -gt 0 ]; do
      case $1 in
        -o) output=$2; shift ;;
        https://*) url=$1 ;;
      esac
      shift
    done
    case $url in
      "https://github.com/fascari/swiftbar-usdbrl/releases/download/$expected_version/usdbrl-darwin-$target" | \
      "https://github.com/fascari/swiftbar-usdbrl/releases/download/$expected_version/converter.zip") ;;
      *) return 1 ;;
    esac
    cp "$assets/${url##*/}" "$output"
    if [ "${corrupt:-0}" = 1 ]; then
      printf 'invalid\n' >>"$output"
    fi
  }
  main "$@"
)

reject_install() {
  local expected=$1
  if run_installer >"$work/rejected.log" 2>&1; then
    printf 'FAIL install succeeded, expected: %s\n' "$expected" >&2
    return 1
  fi
  grep -Fq -- "$expected" "$work/rejected.log"
}

verify_arch() {
  local target=$1 plugins config cache wrapper old expected_version build previous_binary
  local HOME="$work/$target/home"
  export HOME
  plugins="$HOME/SwiftBar Plugins"
  config="$HOME/Library/Application Support/usdbrl-swiftbar"
  cache="$HOME/Library/Caches/usdbrl-swiftbar"
  wrapper="$plugins/usdbrl.5m.sh"
  expected_version=$("$assets/usdbrl-darwin-$target" --version)

  mkdir -p "$plugins" "$config" "$cache"
  fail_wrapper=1 reject_install 'could not install plugin wrapper'
  [ ! -e "$config/bin/usdbrl" ]
  [ ! -e "$plugins/usdbrl.1m.sh" ]

  old='#!/bin/bash'
  printf '%s\n' "$old" >"$wrapper"
  printf 'en\n' >"$config/lang"
  printf 'above 5.80\n' >"$config/alerts"
  printf 'yahoo\t5.75\t1\t5.80\t5.70\t1795704835\n' >"$cache/last.tsv"

  os_version=11.7 reject_install 'macOS 12 or later is required'
  corrupt=1 reject_install 'checksum mismatch'
  [ "$(cat "$wrapper")" = "$old" ]
  [ ! -e "$config/bin/usdbrl" ]

  previous_binary="$config/bin/usdbrl"
  mkdir -p "$config/bin"
  printf '%s\n' 'previous binary' >"$previous_binary"
  chmod 700 "$previous_binary"
  fail_wrapper=1 reject_install 'could not install plugin wrapper'
  [ "$(cat "$previous_binary")" = 'previous binary' ]
  [ "$(stat -f %Lp "$previous_binary")" = 700 ]
  [ "$(cat "$wrapper")" = "$old" ]

  run_installer
  cmp "$config/bin/usdbrl" "$assets/usdbrl-darwin-$target"
  if [ -f "$assets/converter.zip" ]; then
    codesign --verify --deep --strict "$config/Converter.app"
    fail_wrapper=1 reject_install 'could not install plugin wrapper'
    codesign --verify --deep --strict "$config/Converter.app"
  fi
  [ "$(stat -f %Lp "$wrapper")" = 700 ]
  [ "$(stat -f %Lp "$config/bin/usdbrl")" = 700 ]
  [ "$(cat "$config/lang")" = en ]
  [ "$(cat "$config/alerts")" = 'above 5.80' ]
  [ "$(cut -f2 "$cache/last.tsv")" = 5.75 ]
  grep -qxF '# <xbar.about>https://github.com/fascari/swiftbar-usdbrl</xbar.about>' "$wrapper"
  build=$(sed -n "s/^readonly PLUGIN_BUILD='\(.*\)'$/\1/p" "$installer")
  if [ -z "$build" ]; then
    build=$(shasum -a 256 "$assets/usdbrl-darwin-$target" | awk '{ print substr($1, 1, 12) }')
  fi
  grep -qxF "# <xbar.version>$expected_version (build $build)</xbar.version>" "$wrapper"
  if grep -qxF '# <swiftbar.hideAbout>true</swiftbar.hideAbout>' "$wrapper"; then
    printf 'FAIL About is hidden\n' >&2
    return 1
  fi
  "$wrapper" --set-lang pt
  [ "$(cat "$config/lang")" = pt ]
  "$wrapper" --set-interval 15m
  [ -f "$plugins/usdbrl.15m.sh" ]
  [ ! -e "$wrapper" ]
  run_installer --uninstall
  [ ! -e "$plugins/usdbrl.15m.sh" ]
  [ ! -e "$config" ]
  [ ! -e "$cache" ]
  printf 'ok   install, upgrade, actions and uninstall (%s)\n' "$target"

  plugins='' run_installer --plugin "$assets/usdbrl-darwin-$target" --interval 30s
  cmp "$config/bin/usdbrl" "$assets/usdbrl-darwin-$target"
  wrapper="$HOME/Library/Application Support/SwiftBar/Plugins/usdbrl.30s.sh"
  build=$(stat -f '%Sm' -t '%Y%m%d.%H%M%S' "$assets/usdbrl-darwin-$target")
  grep -qxF "# <xbar.version>$expected_version (build $build)</xbar.version>" "$wrapper"
  [ "$("$wrapper" --version)" = "$expected_version" ]
  printf 'ok   local binary and default plugin directory (%s)\n' "$target"
}

if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ]; then
  verify_arch arm64
else
  printf 'skip arm64: requires Apple Silicon\n'
fi
if grep -qx "readonly RELEASE_ARCH='arm64'" "$installer"; then
  target=amd64
  plugins=''
  expected_version=''
  reject_install 'this release requires Apple Silicon'
  printf 'ok   Intel installation rejected\n'
elif arch -x86_64 /usr/bin/true 2>/dev/null; then
  verify_arch amd64
else
  printf 'skip amd64: requires Intel or Rosetta\n'
fi
