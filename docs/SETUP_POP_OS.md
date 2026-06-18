# Setting Up ACC on Pop!_OS

ACC was originally developed on Fedora/Hyprland. This guide covers setup on
Pop!_OS (GNOME desktop, apt package manager).

## Recommended: Use the Setup Wizard

The easiest way to get started is to run the included setup wizard:

```bash
chmod +x bin/setup-acc
./bin/setup-acc
```

The wizard will walk you through every step interactively. It will:

- Check your OS and installed programs
- Offer to install missing dependencies via `apt` (asks before running sudo)
- Offer to install Sober (Roblox via Flatpak)
- Create your local `runtime_config/` folder
- Let you choose the 800x600 preset or a blank config
- Optionally store your private server URL for recovery restarts
- Run non-live validation checks

**The wizard does not run the live macro.** Test carefully before going live.

### Setup wizard commands

```bash
./bin/setup-acc           # Full interactive setup (recommended first run)
./bin/setup-acc --check   # Check system and config status only
./bin/setup-acc --dry-run # Print what the setup would do, without doing it
./bin/setup-acc --help    # Show help
```

---

## Manual Setup (Alternative)

If you prefer to set things up step by step, follow the sections below.

### Install Dependencies

Pop!_OS uses `apt`, not `dnf`:

```bash
sudo apt update
sudo apt install -y \
  bash \
  coreutils \
  grep \
  sed \
  gawk \
  python3 \
  xdotool \
  xdg-utils \
  flatpak \
  gamescope \
  wl-clipboard
```

> `wl-clipboard` provides `wl-copy` and `wl-paste`. ACC uses `wl-copy` for optional
> clipboard output of logs. If `wl-copy` is not installed, ACC falls back gracefully
> with a warning — it does not block execution.

### Install Sober (Roblox Client)

```bash
flatpak install flathub org.vinegarhq.Sober
```

Sober must be running inside the Gamescope session when ACC is in live mode.

### Gamescope

ACC sends input to the **nested Gamescope X display**, not to the GNOME desktop.

Start Gamescope with Sober inside it. A common invocation:

```bash
gamescope -W 800 -H 600 -r 60 --force-grab-cursor -- \
  flatpak run org.vinegarhq.Sober
```

The nested Gamescope session will attach to a virtual display (commonly `DISPLAY=:1`).
ACC reads this display value from the Gamescope manager's `env-attached.txt` file.

> **If your display ID differs from `:1`**, update or verify your Gamescope manager
> setup before running live mode.

### GNOME vs Hyprland

Pop!_OS uses GNOME (X11 or Wayland), not Hyprland. ACC does not use any
Hyprland-specific tools (`hyprctl`, workspace commands, etc.) in its runtime paths.
No changes are needed for the compositor difference.

### Set Up runtime_config/

#### Option A — 800x600 preset (easiest if your setup matches)

If you will use Gamescope at `800x600` and your Roblox UI layout matches the
preset, copy the included preset:

```bash
cp -r presets/800x600_known_good/* runtime_config/
```

The preset includes pre-filled coordinates for all modules. The setup wizard
applies this automatically when you choose option 1.

**Important:** The 800x600 preset only works if your Gamescope window is exactly
800x600 and the Roblox UI matches. If clicks land in the wrong place, recalibrate.
See [CALIBRATION.md](CALIBRATION.md).

#### Option B — Blank templates (safest for different screen sizes)

```bash
cp -r config_templates/* runtime_config/
```

Then calibrate every coordinate in `runtime_config/` before running live.
See [CALIBRATION.md](CALIBRATION.md).

### Recovery Private Server URL

If you use the optional recovery/restart module, you must set your private server
URL locally in `runtime_config/recovery/defaults.conf`:

```
RECOVERY_PRIVATE_SERVER_URL='https://www.roblox.com/share?code=YOUR_CODE&type=Server'
```

**Never commit this file.** It is gitignored. See [SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md).

### Validate and Run

```bash
# Check config is valid (non-live)
./bin/macroctl validate-config pack-opener
./bin/macroctl validate-config orchestrator
./bin/macroctl validate-config recovery

# Run a dry-run to confirm no live input would be sent
./bin/macroctl dry-run orchestrator --cycles 3

# Start the macro control panel
./bin/acc
```
