#!/bin/sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
RUNTIME_ENV="${SCRIPT_DIR%/bin}/config/runtime.env"

if [ ! -f "$RUNTIME_ENV" ]; then
  echo "Missing runtime env: $RUNTIME_ENV" >&2
  exit 1
fi

. "$RUNTIME_ENV"

caffeinate_pid=""
caffeinate_target_pid=""

on_ac_power() {
  /usr/bin/pmset -g batt 2>/dev/null | /usr/bin/grep -q "AC Power"
}

within_keepawake_hours() {
  hour="$(/bin/date +%H)"
  [ "$hour" -ge "$KEEP_AWAKE_START_HOUR" ] && [ "$hour" -lt "$KEEP_AWAKE_END_HOUR" ]
}

gateway_running() {
  /bin/launchctl print "gui/$UID_VAL/$OPENCLAW_GATEWAY_LABEL" 2>/dev/null | /usr/bin/awk '
    $1 == "state" && $2 == "=" && $3 == "running" { running = 1 }
    $1 == "pid" && $2 == "=" && $3 ~ /^[0-9]+$/ { pid = $3 }
    END {
      if (running && pid != "") {
        print pid
      }
    }
  '
}

start_caffeinate() {
  target_pid="$1"
  if [ -n "$caffeinate_pid" ] && [ "$caffeinate_target_pid" = "$target_pid" ] && /bin/kill -0 "$caffeinate_pid" 2>/dev/null; then
    return
  fi

  stop_caffeinate
  /usr/bin/caffeinate -w "$target_pid" -s -i >/dev/null 2>&1 &
  caffeinate_pid="$!"
  caffeinate_target_pid="$target_pid"
}

stop_caffeinate() {
  if [ -n "$caffeinate_pid" ] && /bin/kill -0 "$caffeinate_pid" 2>/dev/null; then
    /bin/kill "$caffeinate_pid" 2>/dev/null || true
    /bin/wait "$caffeinate_pid" 2>/dev/null || true
  fi
  caffeinate_pid=""
  caffeinate_target_pid=""
}

cleanup() {
  stop_caffeinate
}

trap cleanup EXIT INT TERM

while true; do
  pid="$(gateway_running)"

  if [ -f "$NIGHT_STOP_FLAG" ]; then
    stop_caffeinate
  elif [ -n "$pid" ] && /bin/kill -0 "$pid" 2>/dev/null && on_ac_power && within_keepawake_hours; then
    start_caffeinate "$pid"
  else
    stop_caffeinate
  fi

  /bin/sleep 5
done
