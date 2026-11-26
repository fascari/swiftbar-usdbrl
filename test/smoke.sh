#!/bin/bash

set -eu
umask 077
PLUGIN=${1:-"$(cd "$(dirname "$0")/.." && pwd)/bin/usdbrl"}
PLUGIN="$(cd "$(dirname "$PLUGIN")" && pwd)/$(basename "$PLUGIN")"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/usdbrl-smoke.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export USDBRL_CONFIG_DIR="$TMP/config"
unset USDBRL_PLUGIN_PATH SWIFTBAR_PLUGIN_PATH

YAHOO='https://query1.finance.yahoo.com/v8/finance/chart/USDBRL=X?range=1d&interval=1d'
AWESOME='https://economia.awesomeapi.com.br/json/last/USD-BRL'
DOWN='https://host-that-does-not-exist.invalid/x'
fails=0

run() {
  RC=0
  OUT=$(USDBRL_CACHE_DIR="$1" USDBRL_YAHOO_URL="$2" USDBRL_AWESOME_URL="$3" "$PLUGIN") || RC=$?
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

bar_matches() {
  local bar=${OUT%%$'\n'*}
  [[ ${bar%% | *} =~ $1 ]]
}

out_has() {
  [[ $OUT == *"$1"* ]]
}

mode_is() {
  [ "$(stat -f %Lp "$1")" = "$2" ]
}

forge_cache() {
  mkdir -p "$1"
  printf 'yahoo\t%s\t%s\t6.0\t5.0\t%s\n' "$2" "$3" "$4" >"$1/last.tsv"
}

alert() {
  USDBRL_CACHE_DIR="$TMP/alert" "$PLUGIN" "$@"
}

QUOTE_RE='^US\$ [0-9]+\.[0-9]{2} (▲|▼|•) [0-9]+\.[0-9]{2}%'
NOW=$(date +%s)

echo '# Yahoo as the primary source'
run "$TMP/live" "$YAHOO" "$AWESOME"
check 'exits with status 0' [ "$RC" -eq 0 ]
check 'menu bar text looks like US$ 0.00 <arrow> 0.00%' bar_matches "$QUOTE_RE\$"
check 'source is Yahoo Finance' out_has 'Source: Yahoo Finance'
check 'cache directory is mode 700' mode_is "$TMP/live" 700
check 'cache file is mode 600' mode_is "$TMP/live/last.tsv" 600

echo '# fallback to AwesomeAPI'
run "$TMP/fallback" "$DOWN" "$AWESOME"
check 'AwesomeAPI takes over' out_has 'Source: AwesomeAPI'
check 'menu explains the fallback' out_has 'Yahoo Finance unavailable'

echo '# Yahoo pause after a failure'
run "$TMP/fallback" "$YAHOO" "$AWESOME"
check 'pause warning keeps the failure reason' out_has 'recent failure (no connection or timeout)'

echo '# no source responds, valid cache'
cp -R "$TMP/live" "$TMP/warm"
run "$TMP/warm" "$DOWN" "$DOWN"
check 'keeps the quote with ⚠' bar_matches '⚠$'
check 'exits with status 0 when sources fail' [ "$RC" -eq 0 ]

echo '# no source responds, no valid quote'
run "$TMP/none" "$DOWN" "$DOWN"
check 'no cache: shows US$ --.-- and makes up no value' bar_matches '^US\$ --\.-- ⚠$'
check 'no cache: menu explains why' out_has '⚠ No quote available: no source responded'

echo '# language selector'
"$PLUGIN" --set-lang pt
check 'language file is mode 600' mode_is "$USDBRL_CONFIG_DIR/lang" 600
forge_cache "$TMP/pt" 5.90 -1.5 "$((NOW - 30))"
run "$TMP/pt" "$DOWN" "$DOWN"
check 'pt-BR uses a decimal comma' bar_matches '^US\$ 5,90 ▼ 1,50% ⚠$'
check 'pt-BR is checked in the selector' out_has 'param2=pt terminal=false refresh=true checked=true'
"$PLUGIN" --set-lang en

echo '# alerts'
export USDBRL_NOTIFY_LOG="$TMP/notify.log"
forge_cache "$TMP/alert" 5.70 -1.0 "$NOW"
alert --add-alert 5,80
alert --add-alert 'R$ 5.60'
alert --add-alert 5.8
alert --add-alert abc
alert --add-alert -1
check 'targets above and below the rate get their direction' [ "$(cat "$USDBRL_CONFIG_DIR/alerts")" = $'above 5.8\nbelow 5.6' ]
check 'alerts file is mode 600' mode_is "$USDBRL_CONFIG_DIR/alerts" 600
printf 'below 99\nabove 99\n' >"$USDBRL_CONFIG_DIR/alerts"
run "$TMP/alert" "$DOWN" "$DOWN"
check 'a cached rate after a fetch failure does not fire an alert' [ ! -e "$USDBRL_NOTIFY_LOG" ]
check 'an alert that would have fired stays active' out_has '--≤ R$ 99.00 | bash='
run "$TMP/live" "$YAHOO" "$AWESOME"
check 'a fresh rate fires the alert it reached' grep -qE 'reached R\$ 99\.00 \(now R\$ [0-9]+\.[0-9]{2}\)$' "$USDBRL_NOTIFY_LOG"
check 'the fired alert is removed and the other alert is kept' [ "$(cat "$USDBRL_CONFIG_DIR/alerts")" = 'above 99' ]
alert --remove-alert above 99
check 'removing the last alert deletes the file' [ ! -e "$USDBRL_CONFIG_DIR/alerts" ]
unset USDBRL_NOTIFY_LOG

echo '# refresh interval selector'
mkdir -p "$TMP/plugins"
printf '#!/bin/bash\nexec %q "$@"\n' "$PLUGIN" >"$TMP/plugins/usdbrl.1m.sh"
chmod 700 "$TMP/plugins/usdbrl.1m.sh"
SWIFTBAR_PLUGIN_PATH="$TMP/plugins/usdbrl.1m.sh" run "$TMP/live" "$DOWN" "$DOWN"
check 'current interval is checked' out_has 'param2=1m terminal=false checked=true'
SWIFTBAR_PLUGIN_PATH="$TMP/plugins/usdbrl.1m.sh" "$TMP/plugins/usdbrl.1m.sh" --set-interval 5m
check 'choosing 5 min creates the new wrapper' [ -f "$TMP/plugins/usdbrl.5m.sh" ]
check 'choosing 5 min removes the old wrapper' [ ! -e "$TMP/plugins/usdbrl.1m.sh" ]

echo
if [ "$fails" -ne 0 ]; then
  printf '%s failure(s)\n' "$fails"
  exit 1
fi
echo 'all tests passed'
