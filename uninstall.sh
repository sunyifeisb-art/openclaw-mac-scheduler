#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
source "$ROOT_DIR/config/default.env"

OPENCLAW_SCHEDULER_HOME="${OPENCLAW_SCHEDULER_HOME:-$HOME/.openclaw-power-scheduler}"
LAUNCH_AGENTS_DIR="${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
SCHEDULER_START_LABEL="${SCHEDULER_START_LABEL:-com.openclaw.scheduler.gateway.start}"
SCHEDULER_STOP_LABEL="${SCHEDULER_STOP_LABEL:-com.openclaw.scheduler.gateway.stop}"
SCHEDULER_WATCHDOG_LABEL="${SCHEDULER_WATCHDOG_LABEL:-ai.openclaw.scheduler.watchdog}"
SCHEDULER_KEEPAWAKE_LABEL="${SCHEDULER_KEEPAWAKE_LABEL:-ai.openclaw.scheduler.keepawake}"
INSTALL_OPENCLAW_WRAPPER="${INSTALL_OPENCLAW_WRAPPER:-0}"
OPENCLAW_WRAPPER_TARGET="${OPENCLAW_WRAPPER_TARGET:-/opt/homebrew/bin/openclaw}"

UID_VAL="$(id -u)"

launchctl bootout "gui/${UID_VAL}/${SCHEDULER_START_LABEL}" >/dev/null 2>&1 || true
launchctl bootout "gui/${UID_VAL}/${SCHEDULER_STOP_LABEL}" >/dev/null 2>&1 || true
launchctl bootout "gui/${UID_VAL}/${SCHEDULER_WATCHDOG_LABEL}" >/dev/null 2>&1 || true
launchctl bootout "gui/${UID_VAL}/${SCHEDULER_KEEPAWAKE_LABEL}" >/dev/null 2>&1 || true

rm -f "$LAUNCH_AGENTS_DIR/${SCHEDULER_START_LABEL}.plist"
rm -f "$LAUNCH_AGENTS_DIR/${SCHEDULER_STOP_LABEL}.plist"
rm -f "$LAUNCH_AGENTS_DIR/${SCHEDULER_WATCHDOG_LABEL}.plist"
rm -f "$LAUNCH_AGENTS_DIR/${SCHEDULER_KEEPAWAKE_LABEL}.plist"

if [ "$INSTALL_OPENCLAW_WRAPPER" = "1" ]; then
  if [ -e "$OPENCLAW_WRAPPER_TARGET.scheduler-backup" ]; then
    rm -f "$OPENCLAW_WRAPPER_TARGET"
    mv "$OPENCLAW_WRAPPER_TARGET.scheduler-backup" "$OPENCLAW_WRAPPER_TARGET"
  fi
fi

rm -rf "$OPENCLAW_SCHEDULER_HOME"

echo "Uninstalled OpenClaw Mac Scheduler"
