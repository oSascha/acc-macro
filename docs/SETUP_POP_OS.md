# Setting Up ACC on Pop!_OS

ACC was originally developed on Fedora/Hyprland. This guide covers the differences
for Pop!_OS (GNOME desktop, apt package manager).

## Install Dependencies

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

## Install Sober (Roblox Client)

```bash
flatpak install flathub org.vinegarhq.Sober
```

Sober must be running inside the Gamescope session when ACC is in live mode.

## Gamescope

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

## GNOME vs Hyprland

Pop!_OS uses GNOME (X11 or Wayland), not Hyprland. ACC does not use any
Hyprland-specific tools (`hyprctl`, workspace commands, etc.) in its runtime paths.
No changes are needed for the compositor difference.

## Coordinate Recalibration Required

Screen coordinates depend on:

- Your monitor's resolution and scaling
- The Gamescope window size (`-W` / `-H` flags)
- Roblox's UI layout at that resolution

Coordinates calibrated on the original Fedora/1080p setup **will not work** on
your machine without recalibration. See [CALIBRATION.md](CALIBRATION.md).

## Recovery Private Server URL

If you use the optional recovery/restart module, you must set your private server
URL locally in `runtime_config/recovery/defaults.conf`:

```
RECOVERY_PRIVATE_SERVER_URL='https://www.roblox.com/share?code=YOUR_CODE&type=Server'
```

**Never commit this file.** It is gitignored. See [SECURITY_AND_PRIVACY.md](SECURITY_AND_PRIVACY.md).

## Quick Setup Sequence

```bash
# 1. Clone and enter the repo
git clone <repo-url> acc && cd acc

# 2. Copy templates
cp -r config_templates/* runtime_config/

# 3. Edit runtime_config/pack_opener/points.conf with your calibrated coordinates
# 4. Edit runtime_config/recovery/defaults.conf if you want recovery restarts

# 5. Start Gamescope+Sober, then validate with dry-run
./bin/acc --dry-run

# 6. Run macroctl to check config validity
./bin/macroctl validate-config pack-opener
```
