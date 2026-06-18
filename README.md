# ACC — Automated Cycle Controller

ACC is a Bash-based local automation macro for Roblox on Linux. It runs through
[Sober](https://sober.vinegarhq.org/) (the Roblox Flatpak client) inside a nested
[Gamescope](https://github.com/ValveSoftware/gamescope) session and automates
pack-opening cycles, optional shop/market buying, and figurines buying.

Features:
- Pack opener with configurable potion use and click burst control
- Shop buyer, market buyer, and figurines buyer modules
- Orchestrator for scheduled cycling between tasks
- Optional recovery/restart after long sessions
- Dry-run mode for validation without live input
- Terminal UI (`pack-opener-ui`) with pause/resume/stop controls

## Tested Environment

Originally developed and tested on:

| Component    | Detail                                         |
|-------------|------------------------------------------------|
| Distro      | Fedora Linux                                   |
| Compositor  | Hyprland (Wayland)                             |
| Roblox      | Sober Flatpak (`org.vinegarhq.Sober`)          |
| Nest session| Gamescope nested inside the Wayland compositor |
| Input tool  | xdotool (X11, targeting the nested display)    |

**Pop!_OS compatibility is expected** and an included setup wizard makes it easy.
See [docs/SETUP_POP_OS.md](docs/SETUP_POP_OS.md).

## Quick Start (Pop!_OS — Recommended)

The easiest way to get started is the setup wizard:

```bash
# 1. Clone and enter the repo
git clone <repo-url> acc
cd acc

# 2. Make the setup wizard executable and run it
chmod +x bin/setup-acc
./bin/setup-acc
```

The wizard will:
- Check your system and installed programs
- Offer to install missing dependencies via `apt` (asks before running sudo)
- Offer to install Sober via Flatpak
- Create your local `runtime_config/` folder
- Let you choose the **800x600 preset** (pre-filled coordinates) or a **blank config**
- Optionally store your private server URL for recovery restarts
- Run non-live validation checks

**The wizard does not run the live macro.** Test carefully before running live.

### Setup wizard flags

```bash
./bin/setup-acc           # Full interactive setup
./bin/setup-acc --check   # Check system and config status only (no writes)
./bin/setup-acc --dry-run # Print what the setup would do, without doing it
./bin/setup-acc --help    # Show help
```

## Manual Setup (Alternative)

If you prefer to set up manually, see [docs/SETUP_POP_OS.md](docs/SETUP_POP_OS.md).

## Important: Calibration Required

All screen coordinates are specific to your monitor resolution, Gamescope window
size, and display scaling. The included 800x600 preset only works if your setup
matches. If clicks land in the wrong place, calibrate manually.

See [docs/CALIBRATION.md](docs/CALIBRATION.md).

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

## What Is NOT Included

This repository intentionally omits:

- Private Roblox server URLs (set locally in `runtime_config/recovery/defaults.conf`)
- Debug logs and run snapshots
- Internal development notes and implementation contracts

## Security

See [docs/SECURITY_AND_PRIVACY.md](docs/SECURITY_AND_PRIVACY.md) before pushing
changes to your own fork.

## Pop!_OS Notes

See [docs/SETUP_POP_OS.md](docs/SETUP_POP_OS.md) and
[docs/POP_OS_COMPATIBILITY_AUDIT.md](docs/POP_OS_COMPATIBILITY_AUDIT.md).
