#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
PLUGIN="${PLUGIN:-$PWD/bin/usdbrl}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git show v1.1.1:usdbrl.1m.sh > "$work/legacy.sh"
export TZ=UTC LC_ALL=C
export USDBRL_YAHOO_URL=https://127.0.0.1:1/quotes
export USDBRL_AWESOME_URL=https://127.0.0.1:1/quotes
export NO_PROXY=127.0.0.1 no_proxy=127.0.0.1
export SWIFTBAR_PLUGIN_PATH="$work/SwiftBar Plugins/usdbrl.5m.sh"
unset USDBRL_PLUGIN_PATH

normalize() {
  sed -E \
    -e '/^(Checked at |Consultado às ).*/s/[0-9]{2}:[0-9]{2}:[0-9]{2}/<TIME>/' \
    -e '/^(Last successful check|Última consulta bem-sucedida): /s/: .*/: <TIME> (<AGE>)/' \
    -e '/^(Source updated|Atualizado na fonte): /s/ \([^)]*\)$/ (<AGE>)/'
}

compare() {
  local name=$1 lang=$2 source=${3:-} price=${4:-} change=${5:-} alerts=${6:-}
  local state="$work/$name"
  local -x USDBRL_CACHE_DIR="$state/cache"
  local -x USDBRL_CONFIG_DIR="$state/config"
  mkdir -p "$USDBRL_CACHE_DIR" "$USDBRL_CONFIG_DIR"
  printf '%s\n' "$lang" > "$USDBRL_CONFIG_DIR/lang"
  printf '%s' "$alerts" > "$USDBRL_CONFIG_DIR/alerts"
  if [[ -n "$source" ]]; then
    printf '%s\t%s\t%s\t5.824\t5.615\t1795704835\n' "$source" "$price" "$change" > "$USDBRL_CACHE_DIR/last.tsv"
  fi
  printf '%s\n' 'no connection or timeout' > "$USDBRL_CACHE_DIR/yahoo.paused"
  bash "$work/legacy.sh" | normalize > "$state/legacy"
  "$PLUGIN" | normalize > "$state/go"
  diff -u "$state/legacy" "$state/go"
  printf 'ok   %s\n' "$name"
}

# Retry if the feed changes between requests. Matching error menus do not count as live parity.
compare_live() {
  local lang=$1 side legacy_pid go_pid
  local state="$work/live-$lang"
  local -x USDBRL_AWESOME_URL=https://economia.awesomeapi.com.br/json/last/USD-BRL
  for _ in 1 2 3; do
    rm -rf "$state"
    mkdir -p "$state/legacy/cache" "$state/legacy/config" "$state/go/cache" "$state/go/config"
    for side in legacy go; do
      printf '%s\n' "$lang" > "$state/$side/config/lang"
      printf '%s\n' 'no connection or timeout' > "$state/$side/cache/yahoo.paused"
    done
    USDBRL_CACHE_DIR="$state/legacy/cache" USDBRL_CONFIG_DIR="$state/legacy/config" \
      bash "$work/legacy.sh" | normalize > "$state/legacy.out" &
    legacy_pid=$!
    USDBRL_CACHE_DIR="$state/go/cache" USDBRL_CONFIG_DIR="$state/go/config" \
      "$PLUGIN" | normalize > "$state/go.out" &
    go_pid=$!
    local failed=0
    wait "$legacy_pid" || failed=1
    wait "$go_pid" || failed=1
    if [ "$failed" -ne 0 ]; then
      printf 'FAIL live-%s: a comparison command exited with an error\n' "$lang" >&2
      return 1
    fi
    if diff -u "$state/legacy.out" "$state/go.out" > "$state/diff" &&
      grep -qE '^(Checked at|Consultado às) ' "$state/go.out"; then
      printf 'ok   live-%s\n' "$lang"
      return
    fi
    sleep 2
  done
  cat "$state/diff"
  printf 'FAIL live-%s never reached the success path, is AwesomeAPI reachable?\n' "$lang" >&2
  return 1
}

compare rise en yahoo 5.735 1.21
compare fall en awesome 5.74 -1.62
compare flat en yahoo 5.72 -0.001
compare portuguese pt awesome 5.735 0.50 $'above 5.80\nbelow 5.6\n'
compare empty en
compare_live en
compare_live pt
