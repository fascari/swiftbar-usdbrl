#!/bin/bash
# Smoke test for the plugin. Uses the network (Yahoo Finance, AwesomeAPI and example.com)
# and temporary cache/config directories, so it never touches the user's real files.
#
# Usage: test/smoke.sh [plugin-path]

set -u
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
mode_is() { [ "$(stat -f %Lp "$1")" = "$2" ]; }
rc_is_zero() { [ "$RC" -eq 0 ]; }

# forge_cache <dir> <price> <change%> <timestamp>
forge_cache() {
  mkdir -p -m 700 "$1"
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
mkdir -p -m 700 "$TMP/bad" && printf 'yahoo\tjunk\t1\t2\t3\t4\n' >"$TMP/bad/last.tsv"
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
check 'pt-BR is checked in the selector' out_has 'param2=pt terminal=false refresh=true checked=true'
"$PLUGIN" --set-lang xx
check 'unknown language is ignored' [ "$(cat "$USDBRL_CONFIG_DIR/lang")" = pt ]
"$PLUGIN" --set-lang en
run "$TMP/pt" "$DOWN" "$DOWN"
check 'back to English' out_has 'Current rate: R$ 5.90'

echo
if [ "$fails" -eq 0 ]; then echo 'all tests passed'; else echo "$fails failure(s)"; fi
[ "$fails" -eq 0 ]
