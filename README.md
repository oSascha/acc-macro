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

**Pop!_OS compatibility is expected** but requires setup and calibration.
See [docs/SETUP_POP_OS.md](docs/SETUP_POP_OS.md).

## Important: Manual Calibration Required

All screen coordinates are specific to your monitor resolution, Gamescope window
size, and display scaling. **No pre-filled coordinates are committed here.**

After copying config templates you must calibrate every point before running in
live mode. See [docs/CALIBRATION.md](docs/CALIBRATION.md).

## Quick Start (Pop!_OS)

1. Install dependencies:

   ```bash
   sudo apt update
   sudo apt install -y bash coreutils grep sed gawk python3 \
     xdotool xdg-utils flatpak gamescope wl-clipboard
   ```

2. Install Sober via Flatpak:

   ```bash
   flatpak install flathub org.vinegarhq.Sober
   ```

3. Clone this repo and enter it:

   ```bash
   git clone <repo-url> acc
   cd acc
   ```

4. Copy config templates into `runtime_config/`:

   ```bash
   cp -r config_templates/* runtime_config/
   # (runtime_config/ is gitignored — safe to store your private settings here)
   ```

5. Calibrate your coordinates (see [docs/CALIBRATION.md](docs/CALIBRATION.md)).

6. Start Gamescope with Sober, then run a dry-run to validate:

   ```bash
   ./bin/acc --dry-run
   ```

7. Once dry-run passes, run live:

   ```bash
   ./bin/acc
   ```

## Repository Layout

```
bin/                  Executable entry points (acc, macroctl, pack-opener-ui, ...)
src/                  Source library and module scripts
config_templates/     Starter config files — copy to runtime_config/ and calibrate
tests/                Dry-run and static validation tests
docs/                 Setup, calibration, and security documentation
samples/              Example config files with placeholder values (safe to read)
runtime_config/       Your local runtime config (gitignored — never committed)
```

## What Is NOT Included

This repository intentionally omits:

- Private Roblox server URLs (set locally in `runtime_config/recovery/defaults.conf`)
- Calibrated screen coordinates (must be filled in `runtime_config/` after calibration)
- Debug logs and run snapshots
- Internal development notes and implementation contracts

## Security

See [docs/SECURITY_AND_PRIVACY.md](docs/SECURITY_AND_PRIVACY.md) before pushing
changes to your own fork.

## Pop!_OS Notes

See [docs/SETUP_POP_OS.md](docs/SETUP_POP_OS.md) and
[docs/POP_OS_COMPATIBILITY_AUDIT.md](docs/POP_OS_COMPATIBILITY_AUDIT.md).
