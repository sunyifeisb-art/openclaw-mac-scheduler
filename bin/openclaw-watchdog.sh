#!/bin/zsh
set -euo pipefail

source "${0:A:h}/common.sh"

WATCHDOG_LOG="${SCHEDULER_LOG_DIR}/watchdog.log"

port_listening() {
  /usr/sbin/lsof -nP -iTCP:"$OPENCLAW_GATEWAY_PORT" -sTCP:LISTEN >/dev/null 2>&1
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
    delta="$WATCHDOG_COOLDOWN_SECONDS"
  fi

  if [ "$delta" -lt "$WATCHDOG_COOLDOWN_SECONDS" ]; then
    log_line "$WATCHDOG_LOG" "restart skipped by cooldown (${delta}s < ${WATCHDOG_COOLDOWN_SECONDS}s)"
    return 1
  fi

  echo "$now" > "$WATCHDOG_LAST_RESTART_FILE"
  return 0
}

restart_gateway() {
  local reason="$1"

  if ! can_restart_now; then
    return 0
  fi

  log_line "$WATCHDOG_LOG" "restart: $reason"
  openclaw_gateway restart >> "$WATCHDOG_LOG" 2>&1 || {
    openclaw_gateway install --port "$OPENCLAW_GATEWAY_PORT" --force >> "$WATCHDOG_LOG" 2>&1 || true
    openclaw_gateway start >> "$WATCHDOG_LOG" 2>&1 || true
  }
}

if [ ! -x "$NODE_BIN" ] || [ ! -f "$OPENCLAW_ENTRY" ]; then
  log_line "$WATCHDOG_LOG" "skip: runtime missing"
  exit 0
fi

if [ -f "$NIGHT_STOP_FLAG" ] || ! within_hour_window "$KEEP_AWAKE_START_HOUR" "$KEEP_AWAKE_END_HOUR"; then
  log_line "$WATCHDOG_LOG" "skip: outside operating window"
  exit 0
fi

if ! service_loaded "$OPENCLAW_GATEWAY_LABEL"; then
  log_line "$WATCHDOG_LOG" "service label missing, reinstall"
  openclaw_gateway install --port "$OPENCLAW_GATEWAY_PORT" --force >> "$WATCHDOG_LOG" 2>&1 || true
  openclaw_gateway start >> "$WATCHDOG_LOG" 2>&1 || true
  exit 0
fi

if [ -z "$(service_pid "$OPENCLAW_GATEWAY_LABEL")" ]; then
  restart_gateway "gateway service not running"
  exit 0
fi

if ! port_listening; then
  restart_gateway "gateway port ${OPENCLAW_GATEWAY_PORT} is not listening"
  exit 0
fi

log_line "$WATCHDOG_LOG" "ok"
