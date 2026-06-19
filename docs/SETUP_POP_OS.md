# Setting Up ACC on Pop!_OS / Ubuntu

ACC supports Pop!_OS and Ubuntu via an interactive setup wizard. The recommended
path is to use the **known-good 800x600 profile** which gives you a working
pack-opener setup in minutes.

## Recommended: Setup Wizard (one command)

```bash
git clone <repo-url> acc
cd acc
chmod +x bin/setup-acc
./bin/setup-acc
```

When prompted, choose **1) Known-good 800x600 Sober/Gamescope** (the default).

The wizard will:

1. Check your OS and install missing programs (`apt`)
2. Offer to install Sober via Flatpak
3. Copy the 800x600 preset to `runtime_config/` with safe module defaults
4. Optionally save your private server URL (local only, never committed)
5. Validate Event Voter requirements; auto-disable if training images are missing
6. Install the `acc` terminal command at `~/.local/bin/acc`
7. Run non-live syntax and config checks

After setup, **open a new terminal** and run:

```bash
acc
```

> **Safe startup state**: Pack Opener is enabled. Market Buyer, Figurines Buyer,
> Recovery Restart, and Event Voter are all disabled. Enable them one at a time
> from the ACC menu → Module Toggles → after confirming each works.

## Install Dependencies Manually

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

For Event Voter (optional, requires training images):

```bash
sudo apt install -y python3-opencv
```

> `wl-clipboard` provides `wl-copy` and `wl-paste`. ACC uses `wl-copy` for optional
> clipboard output of logs. ACC falls back gracefully if it is not installed.

## Install Sober (Roblox Client)

```bash
flatpak install flathub org.vinegarhq.Sober
```

Sober must be running inside the Gamescope session when ACC is in live mode.

## Gamescope

ACC sends input to the **nested Gamescope X display**, not to the GNOME desktop.

Start Gamescope with Sober inside it:

```bash
gamescope -W 800 -H 600 -r 60 --force-grab-cursor -- \
  flatpak run org.vinegarhq.Sober
```

The nested Gamescope session will attach to a virtual display (commonly `DISPLAY=:1`).
ACC reads this display value from the Gamescope manager's `env-attached.txt` file.

> **If your display ID differs from `:1`**, update or verify your Gamescope manager
> setup before running live mode.

## Module Toggles and Persistence

When you change a module toggle in the ACC menu (option 3), the choice is saved
to `runtime_config/ui/toggles.conf`. The same toggle state is loaded next time
you run `acc`.

The known-good 800x600 profile starts with:

| Module | Default state |
|--------|--------------|
| Pack Opener | ENABLED |
| Market Buyer | DISABLED (enable after calibration) |
| Figurines Buyer | DISABLED (enable after calibration) |
| Recovery Restart | DISABLED (enable after setting private server URL) |
| Event Voter | DISABLED (enable after adding training images) |

## GNOME vs Hyprland

Pop!_OS uses GNOME (X11 or Wayland), not Hyprland. ACC does not use any
Hyprland-specific tools. No changes are needed for the compositor difference.

## Coordinate Recalibration

Screen coordinates depend on:

- Your monitor's resolution and scaling
- The Gamescope window size (`-W` / `-H` flags)
- Roblox's UI layout at that resolution

The 800x600 preset coordinates are calibrated for 800x600 Gamescope. If clicks land
in the wrong place, recalibrate. See [CALIBRATION.md](CALIBRATION.md).

## Recovery Private Server URL

If you use the optional recovery/restart module, set your private server
URL locally in `runtime_config/recovery/defaults.conf`:

```
RECOVERY_PRIVATE_SERVER_URL='https://www.roblox.com/share?code=YOUR_CODE&type=Server'
```

**Never commit this file.** It is gitignored. See [SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md).

The setup wizard will ask if you want to save a private server URL — it writes
to both `runtime_config/recovery/defaults.conf` and
`runtime_config/sober_launcher/defaults.conf` locally.

## Diagnostic Tool

If setup fails or the macro is not working:

```bash
./bin/setup-acc --diagnose
```

This writes a full diagnostic file to `~/acc_setup_diagnose.txt`. Send that file
for support.

## Quick Reference

```bash
# Run the setup wizard
./bin/setup-acc

# Check system and config status (no changes)
./bin/setup-acc --check

# See what setup would do (no changes made)
./bin/setup-acc --dry-run

# Write a diagnostic support file
./bin/setup-acc --diagnose

# Run the ACC menu (after setup, in a new terminal)
acc

# Or from the repo directory directly
./bin/acc
```
