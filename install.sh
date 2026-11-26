#!/bin/bash
set -euo pipefail
umask 077
# scripts/release.sh replaces these assignments when preparing the release installer.
readonly VERSION='v2.0.2'
readonly PLUGIN_BUILD='20261126.222409'
readonly PLUGIN_SHA256_ARM64='ffde27d1088170bb1d9516165a3b23ee156ce129d8935404653fabb6f255666b'
readonly PLUGIN_SHA256_AMD64='e71c9dc73c7e905961d061a509ed63b410d7ae3e40ead035241b5114e9532812'

readonly REPO='fascari/swiftbar-usdbrl'
readonly APP='/Applications/SwiftBar.app'
readonly SWIFTBAR_TEAM_ID='X93LWC49WV'
readonly PREFS='com.ameba.SwiftBar'
readonly DEFAULT_PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
readonly CACHE_DIR="$HOME/Library/Caches/usdbrl-swiftbar"
readonly CONFIG_PATH='Library/Application Support/usdbrl-swiftbar'
readonly CONFIG_DIR="$HOME/$CONFIG_PATH"

log() {
  printf '==> %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  install.sh [--login-item] [--interval <n>] [--plugin <file>]
  install.sh --uninstall

  --login-item     also start SwiftBar at login (macOS may ask for Automation permission)
  --interval <n>   refresh interval (30s, 1m, 5m, 1h...); keeps the installed one, or 1m
  --plugin <file>  install a local Go binary instead of downloading the release asset
  --uninstall      remove the plugin and its cache and settings, keeping SwiftBar
EOF
}

require_supported_macos() {
  local version major
  version=$(sw_vers -productVersion)
  major=${version%%.*}
  if [[ ! $major =~ ^[0-9]+$ ]] || (( 10#$major < 12 )); then
    die "macOS 12 or later is required (found $version)"
  fi
}

hardware_arch() {
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ]; then
    printf '%s\n' arm64
  else
    printf '%s\n' amd64
  fi
}

ensure_swiftbar() {
  if [ -d "$APP" ]; then
    log "SwiftBar already installed"
    return
  fi
  command -v brew >/dev/null || die "Homebrew is required to install SwiftBar: https://brew.sh"
  log "Installing SwiftBar from the official Homebrew cask"
  brew install --cask swiftbar
  [ -d "$APP" ] || die "SwiftBar not found at $APP after installation"
}

verify_swiftbar() {
  local team
  log "Verifying SwiftBar signature and notarization"
  codesign --verify --deep --strict "$APP" 2>/dev/null || die "SwiftBar code signature is invalid"
  team=$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')
  [ "$team" = "$SWIFTBAR_TEAM_ID" ] || die "SwiftBar is signed by an unexpected team: ${team:-none}"
  spctl --assess --type execute -vv "$APP" 2>&1 | grep -q 'source=Notarized Developer ID' ||
    die "Gatekeeper does not accept SwiftBar as a notarized app"
}

configured_plugin_dir() {
  defaults read "$PREFS" PluginDirectory 2>/dev/null || true
}

download_plugin() {
  local dest=$1 arch=$2 expected=$3 sum
  [ "$expected" != unreleased ] || die "this copy of install.sh is not a release; use --plugin <file>"
  log "Downloading the plugin $VERSION for $arch"
  curl -q -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 --max-time 60 \
    -o "$dest" "https://github.com/$REPO/releases/download/$VERSION/usdbrl-darwin-$arch" ||
    die "download failed"
  sum=$(shasum -a 256 "$dest" | awk '{ print $1 }')
  [ "$sum" = "$expected" ] || die "checksum mismatch: expected $expected, got $sum"
  log "Checksum OK"
}

prepare_binary() {
  local dest=$1 local_plugin=$2 arch expected cpu format version
  arch=$(hardware_arch)
  case $arch in
    arm64)
      expected=$PLUGIN_SHA256_ARM64
      cpu=arm64
      ;;
    amd64)
      expected=$PLUGIN_SHA256_AMD64
      cpu=x86_64
      ;;
  esac

  if [ -n "$local_plugin" ]; then
    [ -f "$local_plugin" ] || die "plugin file not found: $local_plugin"
    cp -- "$local_plugin" "$dest"
  else
    download_plugin "$dest" "$arch" "$expected"
  fi
  format=$(file -b "$dest")
  [ "$format" = "Mach-O 64-bit executable $cpu" ] || die "expected a macOS $arch binary, got: $format"
  chmod 700 "$dest"
  version=$("$dest" --version) || die "could not run the plugin on this Mac"
  if [[ $version = "$VERSION" || ( -n "$local_plugin" && $version = dev ) ]]; then
    return
  fi
  die "plugin version mismatch: expected $VERSION, got $version"
}

render_wrapper() {
  local display_version=$1
  cat <<EOF
#!/bin/bash
# <xbar.title>USD/BRL</xbar.title>
# <xbar.version>$display_version</xbar.version>
# <xbar.desc>USD/BRL exchange rate in the menu bar, with source fallback and a local cache.</xbar.desc>
# <xbar.author>Felipe Ascari</xbar.author>
# <xbar.about>https://github.com/$REPO</xbar.about>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>

binary="\$HOME/$CONFIG_PATH/bin/usdbrl"
EOF
  cat <<'EOF'
if [ ! -x "$binary" ]; then
  printf '%s\n' 'US$ --.-- ⚠' '---' 'USD/BRL binary missing. Run the installer again.'
  exit 0
fi
export USDBRL_PLUGIN_PATH="$0"
exec "$binary" "$@"
EOF
}

cleanup_install() {
  local work_dir=$1 staged_binary=$2 staged_wrapper=$3
  [ -z "$staged_wrapper" ] || rm -f "$staged_wrapper"
  [ -z "$staged_binary" ] || rm -f "$staged_binary"
  rm -f "$work_dir/plugin"
  rmdir "$work_dir"
}

add_login_item() {
  log "Adding SwiftBar to the login items (macOS may ask to let this terminal control System Events)"
  osascript -e 'tell application "System Events" to if not (exists login item "SwiftBar") then make login item at end with properties {path:"/Applications/SwiftBar.app", hidden:false}' >/dev/null ||
    die "could not add the login item; turn on launch at login in the SwiftBar preferences instead"
}

start_swiftbar() {
  local previous_dir=$1
  if ! pgrep -xq SwiftBar; then
    log "Opening SwiftBar"
    open -a "$APP"
    return
  fi
  if [ -n "$previous_dir" ]; then
    open -g 'swiftbar://refreshallplugins'
    return
  fi
  log "Restarting SwiftBar to load the new plugin directory"
  pkill -x SwiftBar
  sleep 1
  open -a "$APP"
}

installed_interval() {
  local plugin_dir=$1 wrapper
  for wrapper in "$plugin_dir"/usdbrl.*.sh; do
    [ -e "$wrapper" ] || break
    wrapper=${wrapper##*/usdbrl.}
    printf '%s\n' "${wrapper%.sh}"
    return
  done
  printf '%s\n' 1m
}

replace_plugin() {
  local staged_binary=$1 staged_wrapper=$2 wrapper=$3
  local binary="$CONFIG_DIR/bin/usdbrl" backup="$1.previous"
  [ ! -d "$binary" ] || die "binary path is a directory: $binary"
  [ ! -d "$wrapper" ] || die "wrapper path is a directory: $wrapper"
  if [ -e "$binary" ] || [ -L "$binary" ]; then
    ln -P -- "$binary" "$backup" || die "could not back up the previous binary"
  fi

  if ! mv -f "$staged_binary" "$binary"; then
    rm -f "$backup"
    die "could not install plugin binary: $binary"
  fi
  if mv -f "$staged_wrapper" "$wrapper"; then
    rm -f "$backup"
    return
  fi

  if [ -e "$backup" ] || [ -L "$backup" ]; then
    mv -f "$backup" "$binary" ||
      die "could not install plugin wrapper or restore the binary; previous binary is at $backup"
  else
    rm -f "$binary" ||
      die "could not install plugin wrapper or remove the new binary at $binary"
  fi
  die "could not install plugin wrapper: $wrapper"
}

install_plugin() (
  local interval=$1 local_plugin=$2 login_item=$3
  local work_dir staged_binary='' staged_wrapper=''
  local previous_dir plugin_dir wrapper existing
  local build=$PLUGIN_BUILD
  if [ -n "$interval" ]; then
    [[ $interval =~ ^[0-9]+[smhd]$ ]] || die "invalid interval: $interval (examples: 30s, 1m, 5m, 1h)"
  fi
  require_supported_macos

  work_dir=$(mktemp -d)
  trap 'cleanup_install "$work_dir" "$staged_binary" "$staged_wrapper"' EXIT
  prepare_binary "$work_dir/plugin" "$local_plugin"
  if [ -n "$local_plugin" ]; then
    build=$(stat -f '%Sm' -t '%Y%m%d.%H%M%S' -- "$local_plugin")
  elif [ -z "$build" ]; then
    build=$(shasum -a 256 "$work_dir/plugin" | awk '{ print substr($1, 1, 12) }')
  fi
  ensure_swiftbar
  verify_swiftbar

  previous_dir=$(configured_plugin_dir)
  plugin_dir=${previous_dir:-$DEFAULT_PLUGIN_DIR}
  if [ -n "$previous_dir" ]; then
    log "Using the SwiftBar plugin directory already set: $plugin_dir"
  else
    log "Setting the SwiftBar plugin directory to $plugin_dir"
    defaults write "$PREFS" PluginDirectory -string "$plugin_dir"
  fi
  mkdir -p "$plugin_dir"
  if [ -z "$interval" ]; then
    interval=$(installed_interval "$plugin_dir")
  fi

  wrapper="$plugin_dir/usdbrl.$interval.sh"
  mkdir -p "$CONFIG_DIR/bin"
  staged_binary=$(mktemp "$CONFIG_DIR/bin/.usdbrl.XXXXXX")
  staged_wrapper=$(mktemp "$plugin_dir/.usdbrl.XXXXXX")
  install -m 700 "$work_dir/plugin" "$staged_binary"
  render_wrapper "$VERSION (build $build)" >"$staged_wrapper"
  bash -n "$staged_wrapper"
  chmod 700 "$staged_wrapper"

  replace_plugin "$staged_binary" "$staged_wrapper" "$wrapper"
  for existing in "$plugin_dir"/usdbrl.*.sh; do
    [ "$existing" = "$wrapper" ] || rm -f "$existing"
  done
  log "Installed $wrapper"

  if [ "$login_item" = 1 ]; then
    add_login_item
  fi
  start_swiftbar "$previous_dir"
  log "Done. The rate shows up in the menu bar within a few seconds."
)

uninstall_plugin() {
  local dir
  dir=$(configured_plugin_dir)
  dir=${dir:-$DEFAULT_PLUGIN_DIR}
  if [ -d "$dir" ]; then
    rm -f "$dir"/usdbrl.*.sh
    log "Removed the plugin from $dir"
  fi
  rm -rf "$CACHE_DIR" "$CONFIG_DIR"
  log "Removed $CACHE_DIR and $CONFIG_DIR"
  if pgrep -xq SwiftBar; then
    open -g 'swiftbar://refreshallplugins'
  fi
  cat <<EOF
==> SwiftBar itself was kept. To remove it too:
    osascript -e 'tell application "System Events" to delete login item "SwiftBar"'
    defaults delete $PREFS
    brew uninstall --zap --cask swiftbar
EOF
}

main() {
  export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin
  local login_item=0 interval='' local_plugin='' mode=install
  while [ $# -gt 0 ]; do
    case $1 in
      --login-item) login_item=1 ;;
      --interval)
        interval=${2:?--interval needs a value}
        shift
        ;;
      --plugin)
        local_plugin=${2:?--plugin needs a file}
        shift
        ;;
      --uninstall) mode=uninstall ;;
      -h | --help) usage; return ;;
      *) usage >&2; return 1 ;;
    esac
    shift
  done

  [ "$(uname -s)" = Darwin ] || die "macOS only"
  case $mode in
    install) install_plugin "$interval" "$local_plugin" "$login_item" ;;
    uninstall) uninstall_plugin ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
