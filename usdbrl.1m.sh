#!/bin/bash
# <xbar.title>USD/BRL</xbar.title>
# <xbar.version>v2.0.0</xbar.version>
# <xbar.desc>USD/BRL exchange rate in the menu bar, with source fallback and a local cache.</xbar.desc>
# <xbar.dependencies>curl, plutil, awk (built into macOS)</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
#
# Refresh interval comes from the file name (usdbrl.1m.sh = every minute).
# Sources, in order:
#   1. Yahoo Finance chart endpoint (undocumented, a few seconds behind the market).
#   2. AwesomeAPI (documented, CDN-cached, publishes a new quote about every 5 min).
#   3. Local cache with the last valid quote.
# Usage: usdbrl.1m.sh [--set-lang en|pt]
# Test overrides: USDBRL_YAHOO_URL, USDBRL_AWESOME_URL (https only), USDBRL_CACHE_DIR,
# USDBRL_CONFIG_DIR.

set -u
umask 077
export PATH=/usr/bin:/bin
export LC_ALL=C

readonly YAHOO_URL="${USDBRL_YAHOO_URL:-https://query1.finance.yahoo.com/v8/finance/chart/USDBRL=X?range=1d&interval=1d}"
readonly AWESOME_URL="${USDBRL_AWESOME_URL:-https://economia.awesomeapi.com.br/json/last/USD-BRL}"
readonly CACHE_DIR="${USDBRL_CACHE_DIR:-$HOME/Library/Caches/usdbrl-swiftbar}"
readonly CONFIG_DIR="${USDBRL_CONFIG_DIR:-$HOME/Library/Application Support/usdbrl-swiftbar}"
readonly CACHE_FILE="$CACHE_DIR/last.tsv"
readonly YAHOO_PAUSE="$CACHE_DIR/yahoo.paused"
readonly LANG_FILE="$CONFIG_DIR/lang"
readonly STALE_AFTER=900 # seconds without a new source quote before flagging it as stale
readonly PAUSE_FOR=300   # seconds to skip Yahoo after it fails

readonly UP='#1a7f37,#3fb950' DOWN='#cf222e,#ff7b72' WARN='#bc4c00,#ffa657'

# load_strings <en|pt>: sets the UI strings and number/date formats.
load_strings() {
  if [ "$1" = pt ]; then
    DEC=',' DATE_FMT='%d/%m/%Y %H:%M:%S'
    L_CURRENT='Cotação atual' L_CHANGE='Variação no dia' L_HIGH='Máxima do dia' L_LOW='Mínima do dia'
    L_UPDATED='Atualizado na fonte' L_CHECKED='Consultado às' L_STALE='Cotação desatualizada'
    L_LAST_OK='Última consulta bem-sucedida' L_SOURCE='Fonte' L_REFRESH='Atualizar agora'
    L_LANG='Idioma' L_NO_QUOTE='Sem cotação disponível' L_NO_CACHE='Nenhuma cotação válida em cache.'
    L_SILENT='última cotação da fonte %s (possível mercado fechado)'
    L_YAHOO_PAUSED='Yahoo Finance em pausa após falha recente (%s), usando AwesomeAPI'
    L_YAHOO_DOWN='Yahoo Finance indisponível (%s), usando AwesomeAPI'
    L_ALL_DOWN='nenhuma fonte respondeu (AwesomeAPI: %s)'
    E_HTTP='erro HTTP ou resposta cortada' E_CONN='sem conexão ou tempo esgotado'
    E_TLS='falha na verificação TLS' E_CURL='falha na consulta (curl %s)'
    E_INVALID='resposta inválida (HTTP %s)' E_CACHE='cache inválido'
    AGO_NOW='há instantes' AGO_FMT='há %s'
  else
    DEC='.' DATE_FMT='%Y-%m-%d %H:%M:%S'
    L_CURRENT='Current rate' L_CHANGE='Daily change' L_HIGH='Day high' L_LOW='Day low'
    L_UPDATED='Source updated' L_CHECKED='Checked at' L_STALE='Stale quote'
    L_LAST_OK='Last successful check' L_SOURCE='Source' L_REFRESH='Refresh now'
    L_LANG='Language' L_NO_QUOTE='No quote available' L_NO_CACHE='No valid quote in cache.'
    L_SILENT='last source quote %s (market may be closed)'
    L_YAHOO_PAUSED='Yahoo Finance paused after a recent failure (%s), using AwesomeAPI'
    L_YAHOO_DOWN='Yahoo Finance unavailable (%s), using AwesomeAPI'
    L_ALL_DOWN='no source responded (AwesomeAPI: %s)'
    E_HTTP='HTTP error or truncated response' E_CONN='no connection or timeout'
    E_TLS='TLS verification failed' E_CURL='request failed (curl %s)'
    E_INVALID='invalid response (HTTP %s)' E_CACHE='invalid cache'
    AGO_NOW='just now' AGO_FMT='%s ago'
  fi
}

is_dec()   { [[ $1 =~ ^[0-9]+(\.[0-9]+)?$ ]]; }
is_sdec()  { [[ $1 =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; }
is_epoch() { [[ $1 =~ ^[0-9]{9,11}$ ]]; }

# get <json> <keypath>: extracts one value with plutil, failing on invalid JSON.
get() { printf '%s' "$1" | plutil -extract "$2" raw -o - - 2>/dev/null; }

# quote_line <source> <price> <change%> <high> <low> <timestamp>
# Validates a quote and prints it as one TSV line, the cache format.
quote_line() {
  case $1 in yahoo | awesome) ;; *) return 1 ;; esac
  is_dec "$2" && is_sdec "$3" && is_dec "$4" && is_dec "$5" && is_epoch "$6" || return 1
  awk -v p="$2" 'BEGIN { exit !(p > 0) }' || return 1
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}

parse_yahoo() {
  local j=$1 m=chart.result.0.meta
  # Yahoo answers USDBRL=X with either symbol; BRL=X is its alias for the same pair.
  case "$(get "$j" "$m.symbol")/$(get "$j" "$m.currency")" in
    USDBRL=X/BRL | BRL=X/BRL) ;;
    *) return 1 ;;
  esac
  quote_line yahoo "$(get "$j" "$m.regularMarketPrice")" "$(get "$j" "$m.regularMarketChangePercent")" \
    "$(get "$j" "$m.regularMarketDayHigh")" "$(get "$j" "$m.regularMarketDayLow")" \
    "$(get "$j" "$m.regularMarketTime")"
}

parse_awesome() {
  local j=$1
  [ "$(get "$j" USDBRL.code)/$(get "$j" USDBRL.codein)" = "USD/BRL" ] || return 1
  quote_line awesome "$(get "$j" USDBRL.bid)" "$(get "$j" USDBRL.pctChange)" \
    "$(get "$j" USDBRL.high)" "$(get "$j" USDBRL.low)" "$(get "$j" USDBRL.timestamp)"
}

# load_line <line>: loads Q_* from a TSV line after validating it again.
load_line() {
  local extra
  IFS=$'\t' read -r Q_SRC Q_PRICE Q_PCT Q_HIGH Q_LOW Q_TS extra <<<"$1"
  quote_line "$Q_SRC" "$Q_PRICE" "$Q_PCT" "$Q_HIGH" "$Q_LOW" "$Q_TS" >/dev/null && [ -z "$extra" ]
}

source_name() { case $1 in yahoo) printf 'Yahoo Finance' ;; *) printf 'AwesomeAPI' ;; esac; }
source_href() {
  case $1 in
    yahoo) printf 'https://finance.yahoo.com/quote/USDBRL%%3DX/' ;;
    *) printf 'https://docs.awesomeapi.com.br/api-de-moedas' ;;
  esac
}

# fetch <url>: prints the body followed by a last line with the HTTP status code.
fetch() {
  curl -q -sS --fail --proto '=https' --tlsv1.2 \
    --connect-timeout 4 --max-time 8 --max-filesize 65536 \
    -A 'usdbrl-swiftbar/1.0' -H 'Accept: application/json' \
    -w '\n%{http_code}' "$1" 2>/dev/null
}

curl_error() {
  case $1 in
    22 | 56) printf '%s' "$E_HTTP" ;;
    6 | 7 | 28) printf '%s' "$E_CONN" ;;
    35 | 51 | 58 | 60 | 77 | 83 | 90 | 91) printf '%s' "$E_TLS" ;;
    *) printf "$E_CURL" "$1" ;;
  esac
}

# try_source <yahoo|awesome> <url>: sets LINE on success, ERR on failure.
try_source() {
  local out rc code
  out=$(fetch "$2")
  rc=$?
  if [ "$rc" -ne 0 ]; then
    ERR=$(curl_error "$rc")
    return 1
  fi
  code=${out##*$'\n'}
  if ! LINE=$("parse_$1" "${out%$'\n'*}"); then
    printf -v ERR "$E_INVALID" "$code"
    return 1
  fi
}

write_file() { # write_file <dir> <file> <content>
  local tmp
  mkdir -p -m 700 "$1" 2>/dev/null || return 1
  tmp=$(mktemp "$1/.tmp.XXXXXX") || return 1
  if printf '%s\n' "$3" >"$tmp" && mv -f "$tmp" "$2"; then return 0; fi
  rm -f "$tmp"
  return 1
}

sign_of() { awk -v v="$1" 'BEGIN { r = sprintf("%.2f", v) + 0; print (r > 0) - (r < 0) }'; }

num() {
  local s
  printf -v s '%.2f' "$1"
  printf '%s' "${s/./$DEC}"
}

ago() {
  local s=$1 d
  [ "$s" -lt 0 ] && s=0
  if [ "$s" -lt 60 ]; then
    printf '%s' "$AGO_NOW"
    return
  elif [ "$s" -lt 3600 ]; then
    d="$((s / 60)) min"
  elif [ "$s" -lt 86400 ]; then
    printf -v d '%d h %02d min' $((s / 3600)) $(((s % 3600) / 60))
  else
    d="$((s / 86400)) d $(((s % 86400) / 3600)) h"
  fi
  printf "$AGO_FMT" "$d"
}

stamp() { date -r "$1" "+$DATE_FMT"; }

render_footer() {
  local self=${SWIFTBAR_PLUGIN_PATH:-$0} en='' pt=''
  [ "$UI_LANG" = pt ] && pt=' checked=true' || en=' checked=true'
  echo '---'
  printf '%s | refresh=true\n' "$L_REFRESH"
  printf '%s\n' "$L_LANG"
  printf -- '--English | bash="%s" param1=--set-lang param2=en terminal=false refresh=true%s\n' "$self" "$en"
  printf -- '--Português | bash="%s" param1=--set-lang param2=pt terminal=false refresh=true%s\n' "$self" "$pt"
}

# render_quote <error> <last_ok_epoch> <primary_source_warning>
render_quote() {
  local err=$1 last_ok=$2 primary_warn=$3 now age arrow color pct bar cparam='' silent
  now=$(date +%s)
  age=$((now - Q_TS))
  case $(sign_of "$Q_PCT") in
    1) arrow='▲' color=$UP ;;
    -1) arrow='▼' color=$DOWN ;;
    *) arrow='•' color='' ;;
  esac
  pct=${Q_PCT#-}
  [ -n "$color" ] && cparam=" | color=$color"

  printf -v bar 'US$ %s %s %s%%' "$(num "$Q_PRICE")" "$arrow" "$(num "$pct")"
  [ -n "$err" ] && bar="$bar ⚠"
  printf '%s%s\n' "$bar" "$cparam"

  echo '---'
  printf '%s: R$ %s\n' "$L_CURRENT" "$(num "$Q_PRICE")"
  printf '%s: %s %s%%%s\n' "$L_CHANGE" "$arrow" "$(num "$pct")" "$cparam"
  printf '%s: R$ %s\n' "$L_HIGH" "$(num "$Q_HIGH")"
  printf '%s: R$ %s\n' "$L_LOW" "$(num "$Q_LOW")"
  echo '---'
  printf '%s: %s (%s)\n' "$L_UPDATED" "$(stamp "$Q_TS")" "$(ago "$age")"
  if [ -n "$err" ]; then
    printf '⚠ %s: %s | color=%s\n' "$L_STALE" "$err" "$WARN"
    printf '%s: %s (%s)\n' "$L_LAST_OK" "$(stamp "$last_ok")" "$(ago $((now - last_ok)))"
  else
    printf '%s %s\n' "$L_CHECKED" "$(date -r "$last_ok" '+%H:%M:%S')"
    if [ "$age" -gt "$STALE_AFTER" ]; then
      printf -v silent "$L_SILENT" "$(ago "$age")"
      printf '⚠ %s: %s | color=%s\n' "$L_STALE" "$silent" "$WARN"
    fi
  fi
  [ -n "$primary_warn" ] && printf '⚠ %s | color=%s\n' "$primary_warn" "$WARN"
  printf '%s: %s | href=%s\n' "$L_SOURCE" "$(source_name "$Q_SRC")" "$(source_href "$Q_SRC")"
  render_footer
}

render_empty() {
  echo 'US$ --.-- ⚠'
  echo '---'
  printf '⚠ %s: %s | color=%s\n' "$L_NO_QUOTE" "$1" "$WARN"
  printf '%s\n' "$L_NO_CACHE"
  render_footer
}

main() {
  if [ "${1:-}" = --set-lang ]; then
    case ${2:-} in en | pt) write_file "$CONFIG_DIR" "$LANG_FILE" "$2" ;; esac
    return
  fi

  UI_LANG=en
  [ -r "$LANG_FILE" ] && [ "$(<"$LANG_FILE")" = pt ] && UI_LANG=pt
  load_strings "$UI_LANG"

  local cached="" cache_mtime=0 now err="" primary_warn="" use="" new_ts LINE="" ERR=""
  now=$(date +%s)
  if [ -r "$CACHE_FILE" ]; then
    cached=$(<"$CACHE_FILE")
    cache_mtime=$(stat -f %m "$CACHE_FILE")
  fi

  # Yahoo first, unless it failed recently: no point in hitting an endpoint that blocks us.
  local yahoo_ok=0
  # The pause file holds the reason for the last Yahoo failure.
  local yahoo_ok=0 reason
  if [ -f "$YAHOO_PAUSE" ] && [ $((now - $(stat -f %m "$YAHOO_PAUSE"))) -lt "$PAUSE_FOR" ]; then
    reason=$(head -c 120 "$YAHOO_PAUSE" | tr -d '|\n')
    printf -v primary_warn "$L_YAHOO_PAUSED" "${reason:-?}"
  elif try_source yahoo "$YAHOO_URL"; then
    yahoo_ok=1
    rm -f "$YAHOO_PAUSE"
  else
    printf -v primary_warn "$L_YAHOO_DOWN" "$ERR"
    write_file "$CACHE_DIR" "$YAHOO_PAUSE" "$ERR"
  fi

  if [ "$yahoo_ok" = 1 ] || try_source awesome "$AWESOME_URL"; then
    use=$LINE
    load_line "$LINE"
    new_ts=$Q_TS
    # A source may return an older quote than the cached one: keep the newest.
    if [ -n "$cached" ] && load_line "$cached" && [ "$Q_TS" -gt "$new_ts" ]; then
      use=$cached
      touch "$CACHE_FILE"
    else
      write_file "$CACHE_DIR" "$CACHE_FILE" "$LINE"
    fi
    cache_mtime=$now
  else
    # Only reached when Yahoo also failed or is paused.
    printf -v err "$L_ALL_DOWN" "$ERR"
    primary_warn=''
  fi

  [ -z "$use" ] && use=$cached
  if [ -n "$use" ] && load_line "$use"; then
    render_quote "$err" "$cache_mtime" "$primary_warn"
  else
    render_empty "${err:-$E_CACHE}"
  fi
}

main "$@"
exit 0
