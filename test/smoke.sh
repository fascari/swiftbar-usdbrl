#!/bin/bash
# Smoke test for the plugin. Uses the network (Yahoo Finance, AwesomeAPI and example.com)
# and temporary cache/config directories, so it never touches the user's real files.
#
# Usage: test/smoke.sh [plugin-path]

set -u
umask 077
PLUGIN=${1:-"$(cd "$(dirname "$0")/.." && pwd)/usdbrl.1m.sh"}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/usdbrl-smoke.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export USDBRL_CONFIG_DIR="$TMP/config"

YAHOO='https://query1.finance.yahoo.com/v8/finance/chart/USDBRL=X?range=1d&interval=1d'
AWESOME='https://economia.awesomeapi.com.br/json/last/USD-BRL'
DOWN='https://host-that-does-not-exist.invalid/x'
fails=0

# run <cache_dir> <yahoo_url> <awesome_url>: stores the output in $OUT and the status in $RC.
run() {
  OUT=$(USDBRL_CACHE_DIR="$1" USDBRL_YAHOO_URL="$2" USDBRL_AWESOME_URL="$3" "$PLUGIN")
  RC=$?
}

check() {
  local desc=$1
  shift
  if "$@"; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n' "$desc"
    fails=$((fails + 1))
  fi
}

# Matches only the menu bar text, without SwiftBar parameters (" | color=...").
bar_matches() {
  local bar
  bar=$(printf '%s\n' "$OUT" | head -n 1)
  [[ ${bar%% | *} =~ $1 ]]
}
out_has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }
out_lacks() { ! out_has "$1"; }
# lines_are <text>...: every argument must appear as a whole menu line.
lines_are() {
  local want
  for want in "$@"; do
    printf '%s\n' "$OUT" | grep -qxF -- "$want" || return 1
  done
}
mode_is() { [ "$(stat -f %Lp "$1")" = "$2" ]; }
rc_is_zero() { [ "$RC" -eq 0 ]; }

# forge_cache <dir> <price> <change%> <timestamp>
forge_cache() {
  mkdir -p "$1"
  printf 'yahoo\t%s\t%s\t6.0\t5.0\t%s\n' "$2" "$3" "$4" >"$1/last.tsv"
}

QUOTE_RE='^US\$ [0-9]+\.[0-9]{2} (▲|▼|•) [0-9]+\.[0-9]{2}%'
NOW=$(date +%s)

echo '# Yahoo as the primary source'
run "$TMP/live" "$YAHOO" "$AWESOME"
check 'exits with status 0' rc_is_zero
check 'menu bar text looks like US$ 0.00 <arrow> 0.00%' bar_matches "$QUOTE_RE\$"
check 'source is Yahoo Finance' out_has 'Source: Yahoo Finance'
check 'no fallback warning' out_lacks 'using AwesomeAPI'
check 'menu shows day high and low' out_has 'Day low: R$ '
check 'menu has the refresh item' out_has 'Refresh now | refresh=true'
check 'menu has the language selector' out_has '--Português | bash='
check 'submenu titles are whole lines' lines_are 'Alerts' 'Refresh interval' 'Language'
check 'cache directory is mode 700' mode_is "$TMP/live" 700
check 'cache file is mode 600' mode_is "$TMP/live/last.tsv" 600

echo '# fallback to AwesomeAPI'
for y in "$DOWN" 'https://example.com/' 'https://query1.finance.yahoo.com/v8/finance/chart/XXXYYY=X?range=1d&interval=1d'; do
  run "$TMP/fb.$RANDOM" "$y" "$AWESOME"
  check "AwesomeAPI takes over: $y" out_has 'Source: AwesomeAPI'
  check "primary source warning: $y" out_has 'Yahoo Finance unavailable'
  check "no ⚠ in the menu bar: $y" bar_matches "$QUOTE_RE\$"
done
run "$TMP/fb.html" 'https://example.com/' "$AWESOME"
check 'invalid response reports the HTTP status' out_has 'invalid response (HTTP 200)'

echo '# Yahoo pause after a failure'
run "$TMP/pause" "$DOWN" "$AWESOME"
run "$TMP/pause" "$YAHOO" "$AWESOME"
check 'second run skips Yahoo' out_has 'Yahoo Finance paused'
check 'pause warning keeps the failure reason' out_has 'recent failure (no connection or timeout)'

echo '# no source responds, valid cache'
for url in "$DOWN" 'https://example.com/' 'http://economia.awesomeapi.com.br/json/last/USD-BRL'; do
  rm -rf "$TMP/warm" && cp -R "$TMP/live" "$TMP/warm"
  run "$TMP/warm" "$DOWN" "$url"
  check "keeps the quote with ⚠: $url" bar_matches '⚠$'
  check "exits with status 0: $url" rc_is_zero
done

echo '# no source responds, no valid quote'
run "$TMP/none" "$DOWN" "$DOWN"
check 'no cache: shows US$ --.-- and makes up no value' bar_matches '^US\$ --\.-- ⚠$'
check 'no cache: menu explains why' out_has '⚠ No quote available: no source responded'
mkdir -p "$TMP/bad" && printf 'yahoo\tjunk\t1\t2\t3\t4\n' >"$TMP/bad/last.tsv"
run "$TMP/bad" "$DOWN" "$DOWN"
check 'corrupted cache: shows US$ --.--' bar_matches '^US\$ --\.-- ⚠$'

echo '# colors and newest-quote rule'
forge_cache "$TMP/up" 5.90 0.70 "$((NOW - 30))"
run "$TMP/up" "$DOWN" "$DOWN"
check 'rise is green' out_has 'color=#1a7f37,#3fb950'
forge_cache "$TMP/flat" 5.90 0.001 "$((NOW - 30))"
run "$TMP/flat" "$DOWN" "$DOWN"
check 'flat uses the system color' bar_matches '^US\$ 5\.90 • 0\.00% ⚠$'
forge_cache "$TMP/future" 9.99 5.0 "$((NOW + 3600))"
run "$TMP/future" "$YAHOO" "$AWESOME"
check 'a cached quote newer than the response wins' bar_matches '^US\$ 9\.99'

echo '# language selector'
"$PLUGIN" --set-lang pt
check 'language file is mode 600' mode_is "$USDBRL_CONFIG_DIR/lang" 600
forge_cache "$TMP/pt" 5.90 -1.5 "$((NOW - 30))"
run "$TMP/pt" "$DOWN" "$DOWN"
check 'pt-BR uses a decimal comma' bar_matches '^US\$ 5,90 ▼ 1,50% ⚠$'
check 'pt-BR menu labels' out_has 'Cotação atual: R$ 5,90'
check 'pt-BR submenu titles are whole lines' lines_are 'Alertas' 'Intervalo de atualização' 'Idioma'
run "$TMP/none" "$DOWN" "$DOWN"
check 'pt-BR no cache: menu explains why' out_has '⚠ Sem cotação disponível: nenhuma fonte respondeu'
check 'pt-BR is checked in the selector' out_has 'param2=pt terminal=false refresh=true checked=true'
"$PLUGIN" --set-lang xx
check 'unknown language is ignored' [ "$(cat "$USDBRL_CONFIG_DIR/lang")" = pt ]
"$PLUGIN" --set-lang en
run "$TMP/pt" "$DOWN" "$DOWN"
check 'back to English' out_has 'Current rate: R$ 5.90'

echo '# alerts'
export USDBRL_NOTIFY_LOG="$TMP/notify.log"
forge_cache "$TMP/alert" 5.70 -1.0 "$NOW"
alert() { USDBRL_CACHE_DIR="$TMP/alert" "$PLUGIN" "$@"; }
alert --add-alert 5,80
alert --add-alert 'R$ 5.60'
alert --add-alert 5.8
alert --add-alert abc
alert --add-alert -1
check 'targets above and below the rate get their direction' [ "$(cat "$USDBRL_CONFIG_DIR/alerts")" = $'above 5.8\nbelow 5.6' ]
check 'alerts file is mode 600' mode_is "$USDBRL_CONFIG_DIR/alerts" 600
run "$TMP/alert" "$DOWN" "$DOWN"
check 'menu lists the alerts' out_has '--≥ R$ 5.80 | bash='
check 'a cached rate never fires an alert' [ ! -e "$USDBRL_NOTIFY_LOG" ]
printf 'below 99\nabove 99\n' >"$USDBRL_CONFIG_DIR/alerts"
run "$TMP/live" "$YAHOO" "$AWESOME"
check 'a fresh rate fires the alert it reached' grep -q 'reached R$ 99.00' "$USDBRL_NOTIFY_LOG"
check 'the current rate is shown when it differs from the target' grep -qE 'reached R\$ 99\.00 \(now R\$ [0-9]+\.[0-9]{2}\)$' "$USDBRL_NOTIFY_LOG"
rate=$(cut -f2 "$TMP/live/last.tsv")
printf 'below %s\n' "$rate" >"$USDBRL_CONFIG_DIR/alerts"
: >"$USDBRL_NOTIFY_LOG"
forge_cache "$TMP/exact" "$rate" -1.0 "$((NOW + 60))"
run "$TMP/exact" "$YAHOO" "$AWESOME"
check 'no "(now ...)" when the rate equals the target' grep -qE '^USD/BRL reached R\$ [0-9]+\.[0-9]{2}$' "$USDBRL_NOTIFY_LOG"
printf 'above 5.74\nbelow 5.73\n' >"$USDBRL_CONFIG_DIR/alerts"
: >"$USDBRL_NOTIFY_LOG"
forge_cache "$TMP/rounded" 5.7351 -1.0 "$((NOW + 60))"
run "$TMP/rounded" "$YAHOO" "$AWESOME"
check 'a rate shown as 5.74 (5.7351) fires a 5.74 alert' grep -qxF 'USD/BRL reached R$ 5.74' "$USDBRL_NOTIFY_LOG"
check 'the same rate keeps a 5.73 alert below it' [ "$(cat "$USDBRL_CONFIG_DIR/alerts")" = 'below 5.73' ]
printf 'above 99\n' >"$USDBRL_CONFIG_DIR/alerts"
check 'the fired alert is removed and the other kept' [ "$(cat "$USDBRL_CONFIG_DIR/alerts")" = 'above 99' ]
alert --remove-alert above 99
check 'removing the last alert deletes the file' [ ! -e "$USDBRL_CONFIG_DIR/alerts" ]
unset USDBRL_NOTIFY_LOG

echo '# refresh interval selector'
mkdir -p "$TMP/plugins"
cp "$PLUGIN" "$TMP/plugins/usdbrl.1m.sh"
SWIFTBAR_PLUGIN_PATH="$TMP/plugins/usdbrl.1m.sh" run "$TMP/live" "$DOWN" "$DOWN"
check 'current interval is checked' out_has 'param2=1m terminal=false checked=true'
check 'menu offers 30 min' out_has '--30 min | bash='
SWIFTBAR_PLUGIN_PATH="$TMP/plugins/usdbrl.1m.sh" "$PLUGIN" --set-interval 5m
check 'choosing 5 min renames the plugin file' [ -f "$TMP/plugins/usdbrl.5m.sh" ] && [ ! -e "$TMP/plugins/usdbrl.1m.sh" ]
SWIFTBAR_PLUGIN_PATH="$TMP/plugins/usdbrl.5m.sh" "$PLUGIN" --set-interval 7m
check 'an interval outside the presets is ignored' [ -f "$TMP/plugins/usdbrl.5m.sh" ]
cp "$PLUGIN" "$TMP/plugins/other.sh"
SWIFTBAR_PLUGIN_PATH="$TMP/plugins/other.sh" "$PLUGIN" --set-interval 1m
check 'only usdbrl.*.sh files are renamed' [ -f "$TMP/plugins/other.sh" ]

echo
if [ "$fails" -eq 0 ]; then echo 'all tests passed'; else echo "$fails failure(s)"; fi
[ "$fails" -eq 0 ]
