#!/bin/bash
# <xbar.title>USD/BRL</xbar.title>
# <xbar.version>v1.1.0</xbar.version>
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
# Usage: usdbrl.1m.sh [--set-lang en|pt] [--set-interval 30s|1m|5m|15m|30m]
#        usdbrl.1m.sh [--add-alert [rate]] [--remove-alert above|below <rate>] [--clear-alerts]
# Test overrides: USDBRL_YAHOO_URL, USDBRL_AWESOME_URL (https only), USDBRL_CACHE_DIR,
# USDBRL_CONFIG_DIR, USDBRL_NOTIFY_LOG.
#
# Written for the Bash 3.2 that ships with macOS: no associative arrays, namerefs or ";&".
# Sections: settings, UI strings, helpers, quote sources, cache, plugin file, alerts,
# menu rendering, entry point.

set -u
umask 077
export PATH=/usr/bin:/bin
export LC_ALL=C

# -- Settings ------------------------------------------------------------------

readonly YAHOO_URL="${USDBRL_YAHOO_URL:-https://query1.finance.yahoo.com/v8/finance/chart/USDBRL=X?range=1d&interval=1d}"
readonly AWESOME_URL="${USDBRL_AWESOME_URL:-https://economia.awesomeapi.com.br/json/last/USD-BRL}"
readonly CACHE_DIR="${USDBRL_CACHE_DIR:-$HOME/Library/Caches/usdbrl-swiftbar}"
readonly CONFIG_DIR="${USDBRL_CONFIG_DIR:-$HOME/Library/Application Support/usdbrl-swiftbar}"
readonly CACHE_FILE="$CACHE_DIR/last.tsv"
readonly YAHOO_PAUSE="$CACHE_DIR/yahoo.paused"
readonly LANG_FILE="$CONFIG_DIR/lang"
readonly ALERTS_FILE="$CONFIG_DIR/alerts" # one "above <rate>" or "below <rate>" per line
readonly MAX_ALERTS=10
readonly STALE_AFTER=900 # seconds without a new source quote before flagging it as stale
readonly PAUSE_FOR=300   # seconds to skip Yahoo after it fails
readonly INTERVALS='30s 1m 5m 15m 30m'

readonly UP='#1a7f37,#3fb950' DOWN='#cf222e,#ff7b72' WARN='#bc4c00,#ffa657'

# -- UI strings ----------------------------------------------------------------

# load_strings <en|pt>: sets the UI strings and number/date formats.
load_strings() {
  if [ "$1" = pt ]; then
    DEC=',' DATE_FMT='%d/%m/%Y %H:%M:%S'
    L_CURRENT='Cotação atual' L_CHANGE='Variação no dia' L_HIGH='Máxima do dia' L_LOW='Mínima do dia'
    L_UPDATED='Atualizado na fonte' L_CHECKED='Consultado às' L_STALE='Cotação desatualizada'
    L_LAST_OK='Última consulta bem-sucedida' L_SOURCE='Fonte' L_REFRESH='Atualizar agora'
    L_ALERTS='Alertas' L_ADD_ALERT='Adicionar alerta…' L_CLEAR_ALERTS='Remover todos'
    L_ALERT_HINT='Clique num alerta para removê-lo' L_ALERT_PROMPT='Avisar quando o USD/BRL chegar a (R$, ex.: 5,80):' L_ALERT_INVALID='Valor inválido: "%s". Use um número como 5,80.'
    L_ALERT_HIT='USD/BRL chegou a R$ %s' L_ALERT_NOW=' (agora R$ %s)' L_ALERT_NO_RATE='Sem cotação para comparar ainda.'
    L_INTERVAL='Intervalo de atualização' L_LANG='Idioma' L_NO_QUOTE='Sem cotação disponível' L_NO_CACHE='Nenhuma cotação válida em cache.'
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
    L_ALERTS='Alerts' L_ADD_ALERT='Add alert…' L_CLEAR_ALERTS='Clear all'
    L_ALERT_HINT='Click an alert to remove it' L_ALERT_PROMPT='Notify me when USD/BRL reaches (R$, e.g. 5.80):' L_ALERT_INVALID='Invalid value: "%s". Use a number like 5.80.'
    L_ALERT_HIT='USD/BRL reached R$ %s' L_ALERT_NOW=' (now R$ %s)' L_ALERT_NO_RATE='No rate to compare with yet.'
    L_INTERVAL='Refresh interval' L_LANG='Language' L_NO_QUOTE='No quote available' L_NO_CACHE='No valid quote in cache.'
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

# -- Helpers -------------------------------------------------------------------

is_dec()   { [[ $1 =~ ^[0-9]+(\.[0-9]+)?$ ]]; }
is_sdec()  { [[ $1 =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; }
is_epoch() { [[ $1 =~ ^[0-9]{9,11}$ ]]; }

# fmt <var> <format> [args...]: printf -v for the UI formats set in load_strings.
fmt() {
  # shellcheck disable=SC2059 # the format is a UI string constant, never user input
  printf -v "$1" "$2" "${@:3}"
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
  fmt d "$AGO_FMT" "$d"
  printf '%s' "$d"
}

stamp() { date -r "$1" "+$DATE_FMT"; }

# write_file <dir> <file> <content>: atomic write; umask 077 keeps new directories at 700.
write_file() {
  local tmp
  mkdir -p "$1" 2>/dev/null || return 1
  tmp=$(mktemp "$1/.tmp.XXXXXX") || return 1
  if printf '%s\n' "$3" >"$tmp" && mv -f "$tmp" "$2"; then return 0; fi
  rm -f "$tmp"
  return 1
}

# -- Quote sources -------------------------------------------------------------

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
    *)
      local s
      fmt s "$E_CURL" "$1"
      printf '%s' "$s"
      ;;
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
  out=${out%$'\n'*}
  case $1 in
    yahoo) LINE=$(parse_yahoo "$out") ;;
    awesome) LINE=$(parse_awesome "$out") ;;
  esac || {
    fmt ERR "$E_INVALID" "$code"
    return 1
  }
}

# try_yahoo <now>: tries Yahoo unless it failed in the last PAUSE_FOR seconds. Sets LINE on
# success; on failure or pause, sets the caller's primary_warn and returns 1. The pause file
# holds the reason for the last failure.
try_yahoo() {
  local reason
  if [ -f "$YAHOO_PAUSE" ] && [ $(($1 - $(stat -f %m "$YAHOO_PAUSE"))) -lt "$PAUSE_FOR" ]; then
    reason=$(head -c 120 "$YAHOO_PAUSE" | tr -d '|\n')
    fmt primary_warn "$L_YAHOO_PAUSED" "${reason:-?}"
    return 1
  fi
  if try_source yahoo "$YAHOO_URL"; then
    rm -f "$YAHOO_PAUSE"
    return 0
  fi
  fmt primary_warn "$L_YAHOO_DOWN" "$ERR"
  write_file "$CACHE_DIR" "$YAHOO_PAUSE" "$ERR"
  return 1
}

# -- Cache ---------------------------------------------------------------------

# load_line <line>: loads Q_* from a TSV line after validating it again.
load_line() {
  local extra
  IFS=$'\t' read -r Q_SRC Q_PRICE Q_PCT Q_HIGH Q_LOW Q_TS extra <<<"$1"
  quote_line "$Q_SRC" "$Q_PRICE" "$Q_PCT" "$Q_HIGH" "$Q_LOW" "$Q_TS" >/dev/null && [ -z "$extra" ]
}

# -- Plugin file and refresh interval ------------------------------------------

plugin_path() { printf '%s' "${SWIFTBAR_PLUGIN_PATH:-$0}"; }

# current_interval: reads the interval from the plugin file name (usdbrl.<interval>.sh).
current_interval() {
  local name
  name=$(basename "$(plugin_path)")
  name=${name#usdbrl.}
  printf '%s' "${name%.sh}"
}

# set_interval <interval>: renames the plugin file; SwiftBar reloads it with the new interval.
set_interval() {
  local self dir
  case " $INTERVALS " in *" $1 "*) ;; *) return ;; esac
  self=$(plugin_path)
  dir=$(dirname "$self")
  case $(basename "$self") in usdbrl.*.sh) ;; *) return ;; esac
  [ "$self" = "$dir/usdbrl.$1.sh" ] || mv -f "$self" "$dir/usdbrl.$1.sh"
}

# -- Alerts --------------------------------------------------------------------

# read_alerts: prints the valid alert lines, ignoring anything malformed.
read_alerts() {
  local dir val
  [ -r "$ALERTS_FILE" ] || return 0
  while read -r dir val; do
    case $dir in above | below) is_dec "$val" && printf '%s %s\n' "$dir" "$val" ;; esac
  done <"$ALERTS_FILE"
}

save_alerts() { # save_alerts <lines>
  if [ -n "$1" ]; then write_file "$CONFIG_DIR" "$ALERTS_FILE" "$1"; else rm -f "$ALERTS_FILE"; fi
}

notify() { # notify <message>
  if [ -n "${USDBRL_NOTIFY_LOG:-}" ]; then
    printf '%s\n' "$1" >>"$USDBRL_NOTIFY_LOG"
    return
  fi
  # The message is passed as an argument, never spliced into the AppleScript source.
  osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "USD/BRL" sound name "Glass"' \
    -e 'end run' "$1" >/dev/null 2>&1
}

# parse_target <text>: prints the target with up to 2 decimals, accepting "5,80", "5.80" and
# "R$ 5,80". Alerts work at the precision the menu bar shows.
parse_target() {
  local t=$1
  t=${t//,/.}
  t=${t//[[:space:]]/}
  t=${t#R\$}
  is_dec "$t" || return 1
  t=$(awk -v t="$t" 'BEGIN { s = sprintf("%.2f", t); sub(/0+$/, "", s); sub(/\.$/, "", s); print s }')
  awk -v t="$t" 'BEGIN { exit !(t > 0) }' || return 1
  printf '%s' "$t"
}

# ask_target: shows the dialog until a valid target is typed (3 tries) or Cancel is pressed.
ask_target() {
  local prompt=$L_ALERT_PROMPT answer _
  answer=$(num "$Q_PRICE")
  for _ in 1 2 3; do
    answer=$(osascript -e 'on run argv' \
      -e 'text returned of (display dialog (item 1 of argv) default answer (item 2 of argv) with title "USD/BRL")' \
      -e 'end run' "$prompt" "$answer" 2>/dev/null) || return 1
    parse_target "$answer" && return 0
    fmt prompt "$L_ALERT_INVALID"'\n\n%s' "${answer:0:20}" "$L_ALERT_PROMPT"
  done
  return 1
}

# add_alert [rate]: asks for a target when none is given; the direction comes from the
# cached rate, so the alert fires when the rate crosses the target from where it is now.
add_alert() {
  local target line dir alerts
  if ! line=$(cat "$CACHE_FILE" 2>/dev/null) || ! load_line "$line"; then
    notify "$L_ALERT_NO_RATE"
    return
  fi
  if [ -n "${1:-}" ]; then
    target=$(parse_target "$1") || return
  else
    target=$(ask_target) || return
  fi
  if awk -v t="$target" -v p="$Q_PRICE" 'BEGIN { exit !(t >= sprintf("%.2f", p) + 0) }'; then
    dir=above
  else
    dir=below
  fi
  alerts=$(read_alerts)
  printf '%s\n' "$alerts" | grep -qxF "$dir $target" && return
  [ "$(printf '%s' "$alerts" | grep -c .)" -lt "$MAX_ALERTS" ] || return
  save_alerts "$(printf '%s\n%s %s' "$alerts" "$dir" "$target" | grep .)"
}

remove_alert() { # remove_alert <above|below> <rate>
  save_alerts "$(read_alerts | grep -vxF "$1 $2")"
}

# check_alerts: fires and drops the alerts the current rate has reached. Rate and target are
# both compared at 2 decimals, as the menu bar shows them: 5.7351 shows as 5.74 and fires a
# 5.74 alert.
check_alerts() {
  local dir val keep='' fired=0 msg
  while read -r dir val; do
    [ -n "$dir" ] || continue
    if awk -v d="$dir" -v p="$Q_PRICE" -v t="$val" 'BEGIN {
      p = sprintf("%.2f", p) + 0; t = sprintf("%.2f", t) + 0
      exit !((d == "above" && p >= t) || (d == "below" && p <= t))
    }'; then
      fmt msg "$L_ALERT_HIT" "$(num "$val")"
      # The current rate only adds information when it jumped past the target.
      [ "$(num "$val")" = "$(num "$Q_PRICE")" ] || fmt msg "%s$L_ALERT_NOW" "$msg" "$(num "$Q_PRICE")"
      notify "$msg"
      fired=1
    else
      keep="$keep$dir $val"$'\n'
    fi
  done <<<"$(read_alerts)"
  [ "$fired" = 0 ] || save_alerts "${keep%$'\n'}"
}

# -- Menu rendering ------------------------------------------------------------

render_alerts() { # render_alerts <plugin path>
  local self=$1 dir val alerts sign
  alerts=$(read_alerts)
  printf '%s\n' "$L_ALERTS"
  while read -r dir val; do
    [ -n "$dir" ] || continue
    [ "$dir" = above ] && sign='≥' || sign='≤'
    printf -- '--%s R$ %s | bash="%s" param1=--remove-alert param2=%s param3=%s terminal=false refresh=true\n' \
      "$sign" "$(num "$val")" "$self" "$dir" "$val"
  done <<<"$alerts"
  printf -- '--%s | bash="%s" param1=--add-alert terminal=false refresh=true\n' "$L_ADD_ALERT" "$self"
  if [ -n "$alerts" ]; then
    printf -- '--%s | bash="%s" param1=--clear-alerts terminal=false refresh=true\n' "$L_CLEAR_ALERTS" "$self"
    printf -- '--%s | size=11\n' "$L_ALERT_HINT"
  fi
}

render_footer() {
  local self en='' pt='' cur n checked
  self=$(plugin_path)
  cur=$(current_interval)
  [ "$UI_LANG" = pt ] && pt=' checked=true' || en=' checked=true'
  echo '---'
  printf '%s | refresh=true\n' "$L_REFRESH"
  render_alerts "$self"
  printf '%s\n' "$L_INTERVAL"
  for n in $INTERVALS; do
    checked=''
    [ "$n" = "$cur" ] && checked=' checked=true'
    printf -- '--%s %s | bash="%s" param1=--set-interval param2=%s terminal=false%s\n' \
      "${n%[sm]}" "$([ "${n: -1}" = s ] && echo s || echo min)" "$self" "$n" "$checked"
  done
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
      fmt silent "$L_SILENT" "$(ago "$age")"
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

# -- Entry point ---------------------------------------------------------------

# load_language: loads the UI strings for the saved language, English by default.
load_language() {
  UI_LANG=en
  [ -r "$LANG_FILE" ] && [ "$(<"$LANG_FILE")" = pt ] && UI_LANG=pt
  load_strings "$UI_LANG"
}

# handle_action <flag> [args...]: runs a menu action. Unknown flags do nothing.
handle_action() {
  case $1 in
    --set-interval) set_interval "${2:-}" ;;
    --set-lang) case ${2:-} in en | pt) write_file "$CONFIG_DIR" "$LANG_FILE" "$2" ;; esac ;;
    --add-alert) add_alert "${2:-}" ;;
    --remove-alert) remove_alert "${2:-}" "${3:-}" ;;
    --clear-alerts) save_alerts '' ;;
  esac
  return 0
}

# refresh: fetches a quote (Yahoo, then AwesomeAPI, then the cache), fires the alerts it
# reached and prints the menu.
refresh() {
  local cached="" cache_mtime=0 now err="" primary_warn="" use="" new_ts LINE="" ERR=""
  now=$(date +%s)
  if [ -r "$CACHE_FILE" ]; then
    cached=$(<"$CACHE_FILE")
    cache_mtime=$(stat -f %m "$CACHE_FILE")
  fi

  if try_yahoo "$now" || try_source awesome "$AWESOME_URL"; then
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
    fmt err "$L_ALL_DOWN" "$ERR"
    primary_warn=''
  fi

  [ -z "$use" ] && use=$cached
  if [ -n "$use" ] && load_line "$use"; then
    # Alerts only fire on a rate a source just returned, never on a cached one after a failure.
    [ -z "$err" ] && check_alerts
    render_quote "$err" "$cache_mtime" "$primary_warn"
  else
    render_empty "${err:-$E_CACHE}"
  fi
}

main() {
  load_language
  if [ $# -gt 0 ]; then
    handle_action "$@"
  else
    refresh
  fi
}

main "$@"
exit 0
