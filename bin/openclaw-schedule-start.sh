#!/bin/zsh
set -euo pipefail

source "${0:A:h}/common.sh"

rm -f "$NIGHT_STOP_FLAG"

launchctl_bootstrap_if_needed "$SCHEDULER_WATCHDOG_LABEL" "$WATCHDOG_PLIST"
launchctl_bootstrap_if_needed "$SCHEDULER_KEEPAWAKE_LABEL" "$KEEPAWAKE_PLIST"

if ! service_loaded "$OPENCLAW_GATEWAY_LABEL"; then
  openclaw_gateway install --port "$OPENCLAW_GATEWAY_PORT" --force
fi

openclaw_gateway start
