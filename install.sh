#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"

source_if_present() {
  local file="$1"
  [ -f "$file" ] && source "$file"
}

source_if_present "$ROOT_DIR/config/default.env"

OPENCLAW_SCHEDULER_HOME="${OPENCLAW_SCHEDULER_HOME:-$HOME/.openclaw-power-scheduler}"
OPENCLAW_STATE_ROOT="${OPENCLAW_STATE_ROOT:-$HOME/.openclaw}"
LAUNCH_AGENTS_DIR="${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
SCHEDULER_START_LABEL="${SCHEDULER_START_LABEL:-com.openclaw.scheduler.gateway.start}"
SCHEDULER_STOP_LABEL="${SCHEDULER_STOP_LABEL:-com.openclaw.scheduler.gateway.stop}"
SCHEDULER_WATCHDOG_LABEL="${SCHEDULER_WATCHDOG_LABEL:-ai.openclaw.scheduler.watchdog}"
SCHEDULER_KEEPAWAKE_LABEL="${SCHEDULER_KEEPAWAKE_LABEL:-ai.openclaw.scheduler.keepawake}"
OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18801}"
START_HOUR="${START_HOUR:-8}"
START_MINUTE="${START_MINUTE:-30}"
STOP_HOUR="${STOP_HOUR:-0}"
STOP_MINUTE="${STOP_MINUTE:-0}"
KEEP_AWAKE_START_HOUR="${KEEP_AWAKE_START_HOUR:-8}"
KEEP_AWAKE_END_HOUR="${KEEP_AWAKE_END_HOUR:-24}"
WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-120}"
WATCHDOG_COOLDOWN_SECONDS="${WATCHDOG_COOLDOWN_SECONDS:-180}"
SCHEDULER_SKIP_LAUNCHD="${SCHEDULER_SKIP_LAUNCHD:-0}"

INSTALL_BIN_DIR="$OPENCLAW_SCHEDULER_HOME/bin"
INSTALL_CONFIG_DIR="$OPENCLAW_SCHEDULER_HOME/config"
INSTALL_LOG_DIR="$OPENCLAW_SCHEDULER_HOME/logs"
INSTALL_STATE_DIR="$OPENCLAW_SCHEDULER_HOME/state"

find_node_bin() {
  if [ -n "${NODE_BIN:-}" ] && [ -x "${NODE_BIN}" ]; then
    echo "$NODE_BIN"
    return
  fi
  if [ -x "/opt/homebrew/opt/node/bin/node" ]; then
    echo "/opt/homebrew/opt/node/bin/node"
    return
  fi
  if [ -x "/usr/local/bin/node" ]; then
    echo "/usr/local/bin/node"
    return
  fi
  if command -v node >/dev/null 2>&1; then
    command -v node
    return
  fi
  echo "Unable to find node binary" >&2
  exit 1
}

find_openclaw_entry() {
  if [ -n "${OPENCLAW_ENTRY:-}" ] && [ -f "${OPENCLAW_ENTRY}" ]; then
    echo "$OPENCLAW_ENTRY"
    return
  fi
  if [ -f "/opt/homebrew/lib/node_modules/openclaw/dist/index.js" ]; then
    echo "/opt/homebrew/lib/node_modules/openclaw/dist/index.js"
    return
  fi
  if [ -f "/usr/local/lib/node_modules/openclaw/dist/index.js" ]; then
    echo "/usr/local/lib/node_modules/openclaw/dist/index.js"
    return
  fi
  echo "Unable to find OpenClaw dist/index.js" >&2
  echo "Set OPENCLAW_ENTRY when running install.sh" >&2
  exit 1
}

render_template() {
  local src="$1"
  local dest="$2"
  sed \
    -e "s|__INSTALL_DIR__|$OPENCLAW_SCHEDULER_HOME|g" \
    -e "s|__START_LABEL__|$SCHEDULER_START_LABEL|g" \
    -e "s|__STOP_LABEL__|$SCHEDULER_STOP_LABEL|g" \
    -e "s|__KEEPAWAKE_LABEL__|$SCHEDULER_KEEPAWAKE_LABEL|g" \
    -e "s|__WATCHDOG_LABEL__|$SCHEDULER_WATCHDOG_LABEL|g" \
    -e "s|91001|$START_HOUR|g" \
    -e "s|91002|$START_MINUTE|g" \
    -e "s|92001|$STOP_HOUR|g" \
    -e "s|92002|$STOP_MINUTE|g" \
    -e "s|93001|$WATCHDOG_INTERVAL|g" \
    "$src" > "$dest"
}

NODE_BIN="$(find_node_bin)"
OPENCLAW_ENTRY="$(find_openclaw_entry)"
UID_VAL="$(id -u)"

mkdir -p "$INSTALL_BIN_DIR" "$INSTALL_CONFIG_DIR" "$INSTALL_LOG_DIR" "$INSTALL_STATE_DIR" "$LAUNCH_AGENTS_DIR"

cp "$ROOT_DIR/bin/common.sh" "$INSTALL_BIN_DIR/common.sh"
cp "$ROOT_DIR/bin/openclaw-schedule-start.sh" "$INSTALL_BIN_DIR/openclaw-schedule-start.sh"
cp "$ROOT_DIR/bin/openclaw-schedule-stop.sh" "$INSTALL_BIN_DIR/openclaw-schedule-stop.sh"
cp "$ROOT_DIR/bin/openclaw-watchdog.sh" "$INSTALL_BIN_DIR/openclaw-watchdog.sh"
cp "$ROOT_DIR/bin/openclaw-keepawake-monitor.sh" "$INSTALL_BIN_DIR/openclaw-keepawake-monitor.sh"
chmod +x "$INSTALL_BIN_DIR"/*

cat > "$INSTALL_CONFIG_DIR/runtime.env" <<EOF
OPENCLAW_SCHEDULER_HOME="$OPENCLAW_SCHEDULER_HOME"
OPENCLAW_STATE_ROOT="$OPENCLAW_STATE_ROOT"
SCHEDULER_LOG_DIR="$INSTALL_LOG_DIR"
SCHEDULER_STATE_DIR="$INSTALL_STATE_DIR"
UID_VAL="$UID_VAL"
NODE_BIN="$NODE_BIN"
OPENCLAW_ENTRY="$OPENCLAW_ENTRY"
OPENCLAW_GATEWAY_LABEL="ai.openclaw.gateway"
OPENCLAW_GATEWAY_PORT="$OPENCLAW_GATEWAY_PORT"
KEEP_AWAKE_START_HOUR="$KEEP_AWAKE_START_HOUR"
KEEP_AWAKE_END_HOUR="$KEEP_AWAKE_END_HOUR"
WATCHDOG_COOLDOWN_SECONDS="$WATCHDOG_COOLDOWN_SECONDS"
WATCHDOG_LAST_RESTART_FILE="$INSTALL_STATE_DIR/watchdog-last-restart"
NIGHT_STOP_FLAG="$INSTALL_STATE_DIR/schedule-night-stop"
SCHEDULER_START_LABEL="$SCHEDULER_START_LABEL"
SCHEDULER_STOP_LABEL="$SCHEDULER_STOP_LABEL"
SCHEDULER_WATCHDOG_LABEL="$SCHEDULER_WATCHDOG_LABEL"
SCHEDULER_KEEPAWAKE_LABEL="$SCHEDULER_KEEPAWAKE_LABEL"
WATCHDOG_PLIST="$LAUNCH_AGENTS_DIR/${SCHEDULER_WATCHDOG_LABEL}.plist"
KEEPAWAKE_PLIST="$LAUNCH_AGENTS_DIR/${SCHEDULER_KEEPAWAKE_LABEL}.plist"
EOF

render_template \
  "$ROOT_DIR/launchd/com.openclaw.scheduler.gateway.start.plist.template" \
  "$LAUNCH_AGENTS_DIR/${SCHEDULER_START_LABEL}.plist"
render_template \
  "$ROOT_DIR/launchd/com.openclaw.scheduler.gateway.stop.plist.template" \
  "$LAUNCH_AGENTS_DIR/${SCHEDULER_STOP_LABEL}.plist"
render_template \
  "$ROOT_DIR/launchd/ai.openclaw.scheduler.keepawake.plist.template" \
  "$LAUNCH_AGENTS_DIR/${SCHEDULER_KEEPAWAKE_LABEL}.plist"
render_template \
  "$ROOT_DIR/launchd/ai.openclaw.scheduler.watchdog.plist.template" \
  "$LAUNCH_AGENTS_DIR/${SCHEDULER_WATCHDOG_LABEL}.plist"

if [ "$SCHEDULER_SKIP_LAUNCHD" != "1" ]; then
  launchctl bootout "gui/${UID_VAL}/${SCHEDULER_START_LABEL}" >/dev/null 2>&1 || true
  launchctl bootout "gui/${UID_VAL}/${SCHEDULER_STOP_LABEL}" >/dev/null 2>&1 || true
  launchctl bootout "gui/${UID_VAL}/${SCHEDULER_WATCHDOG_LABEL}" >/dev/null 2>&1 || true
  launchctl bootout "gui/${UID_VAL}/${SCHEDULER_KEEPAWAKE_LABEL}" >/dev/null 2>&1 || true

  launchctl bootstrap "gui/${UID_VAL}" "$LAUNCH_AGENTS_DIR/${SCHEDULER_START_LABEL}.plist"
  launchctl bootstrap "gui/${UID_VAL}" "$LAUNCH_AGENTS_DIR/${SCHEDULER_STOP_LABEL}.plist"
  launchctl bootstrap "gui/${UID_VAL}" "$LAUNCH_AGENTS_DIR/${SCHEDULER_WATCHDOG_LABEL}.plist"
  launchctl bootstrap "gui/${UID_VAL}" "$LAUNCH_AGENTS_DIR/${SCHEDULER_KEEPAWAKE_LABEL}.plist"
fi

echo "Installed OpenClaw Mac Scheduler"
echo "Install dir: $OPENCLAW_SCHEDULER_HOME"
echo "Runtime env: $INSTALL_CONFIG_DIR/runtime.env"
if [ "$SCHEDULER_SKIP_LAUNCHD" = "1" ]; then
  echo "LaunchAgents were rendered but not loaded"
fi
