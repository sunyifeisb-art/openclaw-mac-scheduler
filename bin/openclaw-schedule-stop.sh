#!/bin/zsh
set -euo pipefail

source "${0:A:h}/common.sh"

touch "$NIGHT_STOP_FLAG"

launchctl_bootout_if_loaded "$SCHEDULER_KEEPAWAKE_LABEL"
launchctl_bootout_if_loaded "$SCHEDULER_WATCHDOG_LABEL"

openclaw_gateway stop || true
