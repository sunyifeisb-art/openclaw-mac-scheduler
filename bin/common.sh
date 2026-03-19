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
  local message="$2"
  printf "%s %s\n" "$(ts)" "$message" >> "$file"
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
  local label="$1"
  launchctl print "gui/${UID_VAL}/${label}" >/dev/null 2>&1
}

service_pid() {
  local label="$1"
  launchctl print "gui/${UID_VAL}/${label}" 2>/dev/null | awk '
    $1 == "state" && $2 == "=" && $3 == "running" { running = 1 }
    $1 == "pid" && $2 == "=" && $3 ~ /^[0-9]+$/ { pid = $3 }
    END {
      if (running && pid != "") {
        print pid
      }
    }
  '
}

within_hour_window() {
  local start_hour="$1"
  local end_hour="$2"
  local hour
  hour="$(date +%H)"
  [ "$hour" -ge "$start_hour" ] && [ "$hour" -lt "$end_hour" ]
}
