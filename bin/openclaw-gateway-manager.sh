#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
RUNTIME_ENV="${PROJECT_ROOT}/config/runtime.env"

if [ ! -f "$RUNTIME_ENV" ]; then
  echo "Missing runtime env: $RUNTIME_ENV" >&2
  exit 1
fi

source "$RUNTIME_ENV"

mkdir -p "$SCHEDULER_LOG_DIR" "$SCHEDULER_STATE_DIR"

ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log_line() {
  local file="$1"
  shift
  printf "%s %s\n" "$(ts)" "$*" >> "$file"
}

openclaw_gateway() {
  "$NODE_BIN" "$OPENCLAW_ENTRY" gateway "$@"
}

launchctl_bootstrap_if_needed() {
  local label="$1"
  local plist="$2"
  launchctl print "gui/${UID_VAL}/${label}" >/dev/null 2>&1 || \
    launchctl bootstrap "gui/${UID_VAL}" "$plist" >/dev/null 2>&1 || true
}

launchctl_bootout_if_loaded() {
  local label="$1"
  launchctl bootout "gui/${UID_VAL}/${label}" >/dev/null 2>&1 || true
}

service_loaded() {
  launchctl print "gui/${UID_VAL}/${OPENCLAW_GATEWAY_LABEL}" >/dev/null 2>&1
}

service_running() {
  launchctl print "gui/${UID_VAL}/${OPENCLAW_GATEWAY_LABEL}" 2>/dev/null | awk '
    $1 == "state" && $2 == "=" && $3 == "running" { running = 1 }
    $1 == "pid" && $2 == "=" && $3 ~ /^[0-9]+$/ { pid = $3 }
    END { exit !(running && pid != "") }
  '
}

service_pid() {
  launchctl print "gui/${UID_VAL}/${OPENCLAW_GATEWAY_LABEL}" 2>/dev/null | awk '
    $1 == "state" && $2 == "=" && $3 == "running" { running = 1 }
    $1 == "pid" && $2 == "=" && $3 ~ /^[0-9]+$/ { pid = $3 }
    END { if (running && pid != "") print pid }
  '
}

port_listening() {
  /usr/sbin/lsof -nP -iTCP:"$OPENCLAW_GATEWAY_PORT" -sTCP:LISTEN >/dev/null 2>&1
}

port_listening_stable() {
  if port_listening; then
    return 0
  fi
  sleep "$WATCHDOG_PROBE_RETRY_SECONDS"
  port_listening
}

within_hour_window() {
  local start_hour="$1"
  local end_hour="$2"
  local hour

  hour="$(date +%H)"

  if [ "$start_hour" -eq "$end_hour" ]; then
    return 0
  fi

  if [ "$start_hour" -lt "$end_hour" ]; then
    [ "$hour" -ge "$start_hour" ] && [ "$hour" -lt "$end_hour" ]
    return
  fi

  [ "$hour" -ge "$start_hour" ] || [ "$hour" -lt "$end_hour" ]
}

clear_runtime_flags() {
  rm -f "$NIGHT_STOP_FLAG" "$MANUAL_STOP_FLAG"
}

ensure_runtime_agents() {
  launchctl_bootstrap_if_needed "$SCHEDULER_WATCHDOG_LABEL" "$WATCHDOG_PLIST"
  launchctl_bootstrap_if_needed "$SCHEDULER_KEEPAWAKE_LABEL" "$KEEPAWAKE_PLIST"
}

ensure_gateway_installed() {
  if ! service_loaded; then
    openclaw_gateway install --port "$OPENCLAW_GATEWAY_PORT" --force
  fi
}

read_fail_count() {
  if [ -f "$WATCHDOG_FAIL_COUNT_FILE" ]; then
    cat "$WATCHDOG_FAIL_COUNT_FILE" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

reset_fail_state() {
  rm -f "$WATCHDOG_FAIL_COUNT_FILE" "$WATCHDOG_FAIL_REASON_FILE"
}

record_failure() {
  local reason="$1"
  local count
  count="$(read_fail_count)"
  if ! [[ "$count" =~ '^[0-9]+$' ]]; then
    count=0
  fi
  count=$((count + 1))
  printf "%s" "$count" > "$WATCHDOG_FAIL_COUNT_FILE"
  printf "%s" "$reason" > "$WATCHDOG_FAIL_REASON_FILE"
  if [ "$count" -lt "$WATCHDOG_FAILURE_THRESHOLD" ]; then
    log_line "$WATCHDOG_LOG_FILE" "health check failed ($reason) [$count/$WATCHDOG_FAILURE_THRESHOLD], waiting for confirmation"
    return 1
  fi
  log_line "$WATCHDOG_LOG_FILE" "health check failed ($reason) [$count/$WATCHDOG_FAILURE_THRESHOLD], restarting"
  reset_fail_state
  return 0
}

can_restart_now() {
  local now last delta
  now="$(date +%s)"
  last=0
  if [ -f "$WATCHDOG_LAST_RESTART_FILE" ]; then
    last="$(cat "$WATCHDOG_LAST_RESTART_FILE" 2>/dev/null || echo 0)"
  fi
  if [[ "$last" =~ '^[0-9]+$' ]]; then
    delta=$((now - last))
  else
    delta=$WATCHDOG_COOLDOWN_SECONDS
  fi
  if [ "$delta" -lt "$WATCHDOG_COOLDOWN_SECONDS" ]; then
    log_line "$WATCHDOG_LOG_FILE" "restart skipped by cooldown (${delta}s < ${WATCHDOG_COOLDOWN_SECONDS}s)"
    return 1
  fi
  echo "$now" > "$WATCHDOG_LAST_RESTART_FILE"
  return 0
}

watchdog_run() {
  if [ -f "$MANUAL_STOP_FLAG" ]; then
    reset_fail_state
    log_line "$WATCHDOG_LOG_FILE" "skip: manual stop lock present"
    exit 0
  fi

  if [ -f "$NIGHT_STOP_FLAG" ] || ! within_hour_window "$OPERATING_START_HOUR" "$OPERATING_END_HOUR"; then
    reset_fail_state
    log_line "$WATCHDOG_LOG_FILE" "skip: outside operating window"
    exit 0
  fi

  if ! service_loaded; then
    reset_fail_state
    log_line "$WATCHDOG_LOG_FILE" "service label missing, reinstall"
    openclaw_gateway install --port "$OPENCLAW_GATEWAY_PORT" --force >> "$WATCHDOG_LOG_FILE" 2>&1 || true
    openclaw_gateway start >> "$WATCHDOG_LOG_FILE" 2>&1 || true
    exit 0
  fi

  if ! service_running; then
    if record_failure "gateway service not running"; then
      if can_restart_now; then
        log_line "$WATCHDOG_LOG_FILE" "restart: gateway service not running"
        openclaw_gateway restart >> "$WATCHDOG_LOG_FILE" 2>&1 || {
          openclaw_gateway install --port "$OPENCLAW_GATEWAY_PORT" --force >> "$WATCHDOG_LOG_FILE" 2>&1 || true
          openclaw_gateway start >> "$WATCHDOG_LOG_FILE" 2>&1 || true
        }
      fi
    fi
    exit 0
  fi

  if ! port_listening_stable; then
    if record_failure "gateway port $OPENCLAW_GATEWAY_PORT is not listening"; then
      if can_restart_now; then
        log_line "$WATCHDOG_LOG_FILE" "restart: gateway port $OPENCLAW_GATEWAY_PORT is not listening"
        openclaw_gateway restart >> "$WATCHDOG_LOG_FILE" 2>&1 || {
          openclaw_gateway install --port "$OPENCLAW_GATEWAY_PORT" --force >> "$WATCHDOG_LOG_FILE" 2>&1 || true
          openclaw_gateway start >> "$WATCHDOG_LOG_FILE" 2>&1 || true
        }
      fi
    fi
    exit 0
  fi

  reset_fail_state
  log_line "$WATCHDOG_LOG_FILE" "ok"
}

keepawake_monitor_run() {
  local caffeinate_pid=""
  local caffeinate_target_pid=""

  on_ac_power() {
    /usr/bin/pmset -g batt 2>/dev/null | /usr/bin/grep -q "AC Power"
  }

  start_caffeinate() {
    local target_pid="$1"
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
    local pid
    pid="$(service_pid)"

    if [ -f "$NIGHT_STOP_FLAG" ] || [ -f "$MANUAL_STOP_FLAG" ]; then
      stop_caffeinate
    elif [ -n "$pid" ] && /bin/kill -0 "$pid" 2>/dev/null && on_ac_power && within_hour_window "$KEEP_AWAKE_START_HOUR" "$KEEP_AWAKE_END_HOUR"; then
      start_caffeinate "$pid"
    else
      stop_caffeinate
    fi

    /bin/sleep 5
  done
}

scheduled_start() {
  if [ -f "$MANUAL_STOP_FLAG" ]; then
    log_line "$START_GUARD_LOG_FILE" "skip scheduled start: manual stop lock present"
    exit 0
  fi
  rm -f "$NIGHT_STOP_FLAG"
  ensure_runtime_agents
  ensure_gateway_installed
  openclaw_gateway start
}

scheduled_stop() {
  touch "$NIGHT_STOP_FLAG"
  launchctl_bootout_if_loaded "$SCHEDULER_KEEPAWAKE_LABEL"
  launchctl_bootout_if_loaded "$SCHEDULER_WATCHDOG_LABEL"
  openclaw_gateway stop || true
}

manual_stop() {
  printf 'manual-stop %s\n' "$(date -Iseconds)" >| "$MANUAL_STOP_FLAG"
  openclaw_gateway stop
}

manual_start() {
  clear_runtime_flags
  ensure_runtime_agents
  ensure_gateway_installed
  openclaw_gateway start
}

manual_restart() {
  clear_runtime_flags
  ensure_runtime_agents
  ensure_gateway_installed
  openclaw_gateway restart
}

usage() {
  cat <<'EOF'
Usage: openclaw-gateway-manager.sh <command>

Commands:
  manual-start
  manual-stop
  manual-restart
  scheduled-start
  scheduled-stop
  watchdog
  keepawake-monitor
EOF
}

cmd="${1:-}"
case "$cmd" in
  manual-start) manual_start ;;
  manual-stop) manual_stop ;;
  manual-restart) manual_restart ;;
  scheduled-start) scheduled_start ;;
  scheduled-stop) scheduled_stop ;;
  watchdog) watchdog_run ;;
  keepawake-monitor) keepawake_monitor_run ;;
  *) usage; exit 1 ;;
esac
