# ACC — Automated Cycle Controller

ACC is a Bash-based local automation macro for Roblox on Linux. It runs through
[Sober](https://sober.vinegarhq.org/) (the Roblox Flatpak client) inside a nested
[Gamescope](https://github.com/ValveSoftware/gamescope) session and automates
pack-opening cycles, optional shop/market buying, figurines buying, and more.

## Features

- **Pack Opener** — configurable potion use, click burst control, timing presets
- **Market Buyer** — scheduled market purchase cycles
- **Figurines Buyer** — automated figurine purchase runs
- **Full Macro Orchestrator** — cycles between all active modules on a schedule
- **Live Dashboard** — terminal UI with status display, pause/resume/stop controls
- **Sober Instance Launcher** — launches Sober inside Gamescope, optionally joins a private server
- **Recovery Restart** — automatic rejoin after long sessions or crashes (optional)
- **Event Voter** *(experimental)* — visual module that auto-votes in Roblox in-game events using OpenCV template matching
- **Dry-run mode** — validate config and timing without sending any live input
- **Pop!_OS setup wizard** — guided install and config wizard for Pop!_OS/Ubuntu users

## Quick Start

```bash
git clone <repo-url> acc
cd acc
chmod +x bin/setup-acc
./bin/setup-acc
```

When prompted, choose **1) Known-good 800x600 Sober/Gamescope** (the default).
The wizard installs everything and sets up the `acc` command.

Once set up, **open a new terminal** and run:

```bash
acc
```

### Setup wizard flags

```bash
./bin/setup-acc           # Full interactive setup
./bin/setup-acc --check   # Check system and config status only (no writes)
./bin/setup-acc --dry-run # Print what the setup would do, without doing it
./bin/setup-acc --diagnose # Write ~/acc_setup_diagnose.txt for support
./bin/setup-acc --help    # Show help
```

**Non-interactive mode** (for testing and scripted installs):

```bash
./bin/setup-acc --profile known-good-800x600 --yes --no-install-deps --skip-private-server
```

This applies the 800x600 preset to `runtime_config/`, installs the `acc` launcher
under `$HOME/.local/bin/acc`, and runs validation — all without prompts.
Safe to use with a temporary `HOME` for testing.

The wizard checks your system, installs dependencies via `apt`, sets up your local
`runtime_config/` folder with the 800x600 preset, installs the `acc` terminal command,
and runs non-live validation. **It does not run the live macro.**

**Safe startup state** after setup: Pack Opener enabled. Market Buyer, Figurines Buyer,
Recovery Restart, and Event Voter all disabled. Enable them one at a time from the
ACC menu → Module Toggles after confirming each module is calibrated and ready.

## Tested Environment

Originally developed and tested on:

| Component    | Detail                                         |
|-------------|------------------------------------------------|
| Distro      | Fedora Linux                                   |
| Compositor  | Hyprland (Wayland)                             |
| Roblox      | Sober Flatpak (`org.vinegarhq.Sober`)          |
| Nest session| Gamescope nested inside the Wayland compositor |
| Input tool  | xdotool (X11, targeting the nested display)    |

**Pop!_OS compatibility is expected.** The included setup wizard makes it easy.
See [docs/SETUP_POP_OS.md](docs/SETUP_POP_OS.md).

## Calibration Required

All screen coordinates are specific to your monitor resolution, Gamescope window
size, and display scaling. The included 800x600 preset only works if your setup
matches. If clicks land in the wrong place, calibrate manually.

See [docs/CALIBRATION.md](docs/CALIBRATION.md).

## Event Voter — Training Images

Event Voter is disabled by default (`EVENT_VOTER_ENABLED=0`). To use it you must
provide your own training screenshots — the public repo does not ship private game
screenshots.

After setup, place your training images here:

```
runtime_config/event_voter/training/live_event_seed.png
runtime_config/event_voter/training/live_event_seed_mutation.png
```

See [docs/EVENT_VOTER_EXPERIMENT.md](docs/EVENT_VOTER_EXPERIMENT.md) for how to
capture them and configure the module.

Requires `python3-opencv`. The setup wizard will check for it.

## Repository Layout

```
bin/                  Executable entry points (acc, macroctl, setup-acc, ...)
src/                  Source library and module scripts
config_templates/     Starter config files — blank placeholders
presets/              Ready-to-use configs for known-good setups
  800x600_known_good/ Pre-filled coordinates for 800x600 Gamescope window
tests/                Dry-run and static validation tests
docs/                 Setup, calibration, and security documentation
runtime_config/       Your local runtime config (gitignored — never committed)
```

## Privacy and Security

`runtime_config/` is gitignored. It contains your personal coordinates,
timings, and optionally a private server URL. It is never committed.

Private server URLs are stored locally only:
- `runtime_config/recovery/defaults.conf`
- `runtime_config/sober_launcher/defaults.conf`

See [docs/SECURITY_AND_PRIVACY.md](docs/SECURITY_AND_PRIVACY.md) before pushing
changes to your own fork.

## What Is NOT Included

This repository intentionally omits:

- Private Roblox server URLs (set locally in `runtime_config/`)
- Event Voter training screenshots (add your own locally)
- Debug logs, run snapshots, audit logs
- Internal development notes and contracts

## Docs

- [docs/SETUP_POP_OS.md](docs/SETUP_POP_OS.md) — Pop!_OS / Ubuntu setup guide
- [docs/CALIBRATION.md](docs/CALIBRATION.md) — coordinate calibration
- [docs/EVENT_VOTER_EXPERIMENT.md](docs/EVENT_VOTER_EXPERIMENT.md) — Event Voter module
- [docs/SOBER_INSTANCE_LAUNCHER.md](docs/SOBER_INSTANCE_LAUNCHER.md) — Sober Launcher module
- [docs/SECURITY_AND_PRIVACY.md](docs/SECURITY_AND_PRIVACY.md) — security guidance
- [docs/POP_OS_COMPATIBILITY_AUDIT.md](docs/POP_OS_COMPATIBILITY_AUDIT.md) — compatibility notes
- [docs/CHANGELOG.md](docs/CHANGELOG.md) — release notes
