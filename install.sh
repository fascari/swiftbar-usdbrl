#!/bin/bash
# Installer for the swiftbar-usdbrl plugin.
#
# Usage:
#   install.sh [--login-item] [--interval <n>] [--plugin <file>]
#   install.sh --uninstall
#
#   --login-item     also start SwiftBar at login (macOS asks once for Automation permission)
#   --interval <n>   refresh interval (30s, 1m, 5m, 1h...); keeps the installed one, or 1m
#   --plugin <file>  install a local plugin file instead of downloading the release asset
#   --uninstall      remove the plugin and its cache and settings, keeping SwiftBar

set -euo pipefail
umask 077
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin

# Pinned by scripts/release.sh for each release.
readonly VERSION='v1.1.0'
readonly PLUGIN_SHA256='d370d7522c08981a9d411047961f2532cef5ece610c733b61c8991fd80ed9160'

readonly REPO='fascari/swiftbar-usdbrl'
readonly APP='/Applications/SwiftBar.app'
readonly SWIFTBAR_TEAM_ID='X93LWC49WV' # Ameba Labs, LLC
readonly PREFS='com.ameba.SwiftBar'
readonly DEFAULT_PLUGIN_DIR="$HOME/Library/Application Support/SwiftBar/Plugins"
readonly CACHE_DIR="$HOME/Library/Caches/usdbrl-swiftbar"
readonly CONFIG_DIR="$HOME/Library/Application Support/usdbrl-swiftbar"

log() { printf '==> %s\n' "$*"; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  sed -n '4,12s/^# \{0,1\}//p' "$0"
  exit "${1:-0}"
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

# Sets PLUGIN_DIR, keeping a directory the user already configured in SwiftBar.
resolve_plugin_dir() {
  PLUGIN_DIR=$(defaults read "$PREFS" PluginDirectory 2>/dev/null || true)
  DIR_CHANGED=0
  if [ -n "$PLUGIN_DIR" ]; then
    log "Using the SwiftBar plugin directory already set: $PLUGIN_DIR"
  else
    PLUGIN_DIR=$DEFAULT_PLUGIN_DIR
    DIR_CHANGED=1
    log "Setting the SwiftBar plugin directory to $PLUGIN_DIR"
    defaults write "$PREFS" PluginDirectory -string "$PLUGIN_DIR"
  fi
  mkdir -p -m 700 "$PLUGIN_DIR"
}

# fetch_plugin <dest>: copies the local plugin or downloads the release asset and checks it.
fetch_plugin() {
  local dest=$1 sum
  if [ -n "$LOCAL_PLUGIN" ]; then
    [ -f "$LOCAL_PLUGIN" ] || die "plugin file not found: $LOCAL_PLUGIN"
    cp "$LOCAL_PLUGIN" "$dest"
  else
    [ "$PLUGIN_SHA256" != unreleased ] || die "this copy of install.sh is not a release; use --plugin <file>"
    log "Downloading the plugin $VERSION"
    curl -q -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 --max-time 60 \
      -o "$dest" "https://github.com/$REPO/releases/download/$VERSION/usdbrl.1m.sh" ||
      die "download failed"
    sum=$(shasum -a 256 "$dest" | awk '{ print $1 }')
    [ "$sum" = "$PLUGIN_SHA256" ] || die "checksum mismatch: expected $PLUGIN_SHA256, got $sum"
    log "Checksum OK"
  fi
  bash -n "$dest" || die "plugin has a syntax error"
}

add_login_item() {
  log "Adding SwiftBar to the login items (macOS may ask to let this terminal control System Events)"
  osascript -e 'tell application "System Events" to if not (exists login item "SwiftBar") then make login item at end with properties {path:"/Applications/SwiftBar.app", hidden:false}' >/dev/null ||
    die "could not add the login item; turn on launch at login in the SwiftBar preferences instead"
}

start_swiftbar() {
  if pgrep -xq SwiftBar; then
    if [ "$DIR_CHANGED" = 1 ]; then
      log "Restarting SwiftBar to load the new plugin directory"
      pkill -x SwiftBar
      sleep 1
      open -a "$APP"
    else
      open -g 'swiftbar://refreshallplugins'
    fi
  else
    log "Opening SwiftBar"
    open -a "$APP"
  fi
}

# Sets INTERVAL to the one already installed, so an update keeps the choice made in the menu.
keep_installed_interval() {
  local f
  for f in "$PLUGIN_DIR"/usdbrl.*.sh; do
    [ -e "$f" ] || break
    f=${f##*/usdbrl.}
    INTERVAL=${f%.sh}
    return
  done
  INTERVAL=1m
}

install_plugin() {
  if [ -n "$INTERVAL" ]; then
    [[ $INTERVAL =~ ^[0-9]+[smhd]$ ]] || die "invalid interval: $INTERVAL (examples: 30s, 1m, 5m, 1h)"
  fi
  ensure_swiftbar
  verify_swiftbar
  resolve_plugin_dir
  [ -n "$INTERVAL" ] || keep_installed_interval

  WORK_DIR=$(mktemp -d)
  trap 'rm -rf "$WORK_DIR"' EXIT
  fetch_plugin "$WORK_DIR/plugin"
  rm -f "$PLUGIN_DIR"/usdbrl.*.sh
  install -m 700 "$WORK_DIR/plugin" "$PLUGIN_DIR/usdbrl.$INTERVAL.sh"
  log "Installed $PLUGIN_DIR/usdbrl.$INTERVAL.sh"

  [ "$LOGIN_ITEM" = 1 ] && add_login_item
  start_swiftbar
  log "Done. The rate shows up in the menu bar within a few seconds."
}

uninstall_plugin() {
  local dir
  dir=$(defaults read "$PREFS" PluginDirectory 2>/dev/null || true)
  if [ -n "$dir" ]; then
    rm -f "$dir"/usdbrl.*.sh
    log "Removed the plugin from $dir"
  fi
  rm -rf "$CACHE_DIR" "$CONFIG_DIR"
  log "Removed $CACHE_DIR and $CONFIG_DIR"
  pgrep -xq SwiftBar && open -g 'swiftbar://refreshallplugins'
  cat <<EOF
==> SwiftBar itself was kept. To remove it too:
    osascript -e 'tell application "System Events" to delete login item "SwiftBar"'
    defaults delete $PREFS
    brew uninstall --zap --cask swiftbar
EOF
}

LOGIN_ITEM=0 INTERVAL='' LOCAL_PLUGIN='' MODE=install
while [ $# -gt 0 ]; do
  case $1 in
    --login-item) LOGIN_ITEM=1 ;;
    --interval) INTERVAL=${2:?--interval needs a value} && shift ;;
    --plugin) LOCAL_PLUGIN=${2:?--plugin needs a file} && shift ;;
    --uninstall) MODE=uninstall ;;
    -h | --help) usage ;;
    *) usage 1 >&2 ;;
  esac
  shift
done

[ "$(uname -s)" = Darwin ] || die "macOS only"
if [ "$MODE" = uninstall ]; then uninstall_plugin; else install_plugin; fi
