# OpenClaw Mac Scheduler

A small macOS automation project for running OpenClaw on a MacBook with a user-friendly schedule:

- Start OpenClaw during the day
- Stop OpenClaw at night
- Keep the Mac awake only when OpenClaw is running and AC power is connected
- Avoid draining battery unnecessarily when unplugged

This project is built around `launchd`, a lightweight watchdog, and a power-aware keep-awake monitor.

## What It Solves

Running OpenClaw on a MacBook usually needs a bit of operational glue:

- You want it running in the background after Terminal is closed
- You may only want it online during certain hours
- You may want different behavior on AC power vs battery power
- You may want automatic recovery if the gateway stops listening

This repository packages that setup into a reusable project.

## Features

- User-scheduled start and stop windows
- Background launch via `launchd`
- Optional watchdog that checks service state and listening port
- AC-only keep-awake behavior using `caffeinate`
- Night-stop guard to prevent the watchdog from restarting the service outside the allowed window
- Install and uninstall scripts

## Project Layout

```text
openclaw-mac-scheduler/
├── bin/
│   ├── common.sh
│   ├── openclaw-keepawake-monitor.sh
│   ├── openclaw-schedule-start.sh
│   ├── openclaw-schedule-stop.sh
│   └── openclaw-watchdog.sh
├── config/
│   └── default.env
├── launchd/
│   ├── ai.openclaw.scheduler.keepawake.plist.template
│   ├── ai.openclaw.scheduler.watchdog.plist.template
│   ├── com.openclaw.scheduler.gateway.start.plist.template
│   └── com.openclaw.scheduler.gateway.stop.plist.template
├── install.sh
├── uninstall.sh
├── LICENSE
└── README.md
```

## Requirements

- macOS
- OpenClaw installed locally
- Node available locally
- `launchctl`, `pmset`, `caffeinate`, and `lsof` available on the machine

## Quick Start

```bash
git clone <your-repo-url>
cd openclaw-mac-scheduler
./install.sh
```

By default, the installer uses:

- Start time: `08:30`
- Stop time: `00:00`
- Keep-awake window: `08:00-24:00`
- Watchdog interval: `120` seconds
- OpenClaw gateway port: `18801`

Preview generated files without loading agents:

```bash
SCHEDULER_SKIP_LAUNCHD=1 ./install.sh
```

## Customization

Override any of these when installing:

```bash
START_HOUR=9 \
START_MINUTE=0 \
STOP_HOUR=23 \
STOP_MINUTE=30 \
KEEP_AWAKE_START_HOUR=9 \
KEEP_AWAKE_END_HOUR=23 \
WATCHDOG_INTERVAL=180 \
OPENCLAW_GATEWAY_PORT=18801 \
./install.sh
```

You can also override installation paths:

```bash
OPENCLAW_SCHEDULER_HOME="$HOME/.openclaw-power-scheduler" \
OPENCLAW_STATE_ROOT="$HOME/.openclaw" \
./install.sh
```

## How It Works

`com.openclaw.scheduler.gateway.start`
- runs once per day
- clears the night-stop flag
- ensures helper agents are loaded
- starts the OpenClaw gateway

`com.openclaw.scheduler.gateway.stop`
- runs once per day
- creates the night-stop flag
- unloads helper agents
- stops the OpenClaw gateway

`ai.openclaw.scheduler.watchdog`
- runs every N seconds
- only acts during the allowed daytime window
- verifies that the gateway service is loaded, running, and listening
- attempts recovery if needed

`ai.openclaw.scheduler.keepawake`
- runs continuously while loaded
- only starts `caffeinate` when:
  - the gateway is running
  - the Mac is on AC power
  - the current time is inside the keep-awake window

## Logs

Logs are written under:

```text
$OPENCLAW_SCHEDULER_HOME/logs
```

Generated runtime config is written to:

```text
$OPENCLAW_SCHEDULER_HOME/config/runtime.env
```

## Install Notes

This project installs four user-level `LaunchAgents` into:

```text
~/Library/LaunchAgents
```

It does not require root.

If you want to install files first and load agents later, use:

```bash
SCHEDULER_SKIP_LAUNCHD=1 ./install.sh
```

## Uninstall

```bash
./uninstall.sh
```

This unloads the scheduler agents and removes the generated install directory.

## Publishing

Suggested next steps:

```bash
git init
git add .
git commit -m "Initial release"
```

Then create a GitHub repository and push:

```bash
git remote add origin <your-repo-url>
git branch -M main
git push -u origin main
```

## Notes

- This is an independent helper project for OpenClaw users on macOS.
- Review the generated `runtime.env` before using it on a production machine.
- If your OpenClaw install path is unusual, set `NODE_BIN` and `OPENCLAW_ENTRY` explicitly when running `install.sh`.
