# Pop!_OS Compatibility Audit

This document records the portability analysis of ACC for use on Pop!_OS
(GNOME desktop, apt package manager) compared to the original Fedora/Hyprland
development environment.

Last audited: 2026-06-18

## Summary

| Item | Status | Notes |
|------|--------|-------|
| Hyprland-specific tools | OK | None found in runtime paths |
| `wl-copy` / `wl-clipboard` | Setup req | Guarded — graceful fallback if absent |
| `xdg-open` | OK | Works on Pop!_OS GNOME |
| `xdotool` | Setup req | Must be installed; targets nested X display |
| `gamescope` | Setup req | Must be installed and launched |
| Sober (Flatpak) | Setup req | Same Flatpak install as on Fedora |
| Hardcoded home paths | OK | Not present in source |
| Hardcoded `DISPLAY=:1` | OK | Read dynamically from `env-attached.txt` |
| `dnf` / Fedora packages | OK | No `dnf` calls in runtime source |
| `ydotool` / `ydotoold` | OK | Not used |
| `uinput` | OK | Not used |
| `hyprctl` | OK | Not used |

## Detailed Findings

### OK — No Hyprland tools in runtime

No calls to `hyprctl`, Hyprland workspace commands, or any other
Hyprland-specific utility were found in `src/`, `bin/`, or `tests/`.
ACC does not depend on the compositor.

### OK — No hardcoded home paths

`src/lib/env.sh` uses `${HOME}` to construct the Gamescope manager directory path.
No hardcoded home directory paths appear in committed source files.

The Gamescope manager directory:
```
${HOME}/.config/autoclicker/background-static-shop-buyer/gamescope-wayland-attached/
```
...must exist and contain `env-attached.txt` (written by the Gamescope manager on
startup). On Pop!_OS, create this directory as part of your Gamescope setup.

### OK — DISPLAY read dynamically

`DISPLAY` and `WAYLAND_DISPLAY` are not hardcoded. The macro reads them from the
Gamescope manager's `env-attached.txt` file at runtime. If Gamescope attaches to
`:1`, that value is used. If it attaches to a different display, the file reflects that.

No source changes are needed.

### Setup requirement — `wl-copy` (clipboard)

Files affected:
- `bin/pack-opener-ui` (lines 532, 533, 850, 851)
- `bin/potion-tuner` (lines 354, 355)
- `bin/walk-tuner` (lines 299, 300)
- `bin/potion-point-calibrator` (lines 448, 449)

All usages are guarded with `command -v wl-copy >/dev/null 2>&1` and fall back to
a warning message if `wl-copy` is absent. **Not a blocker.** ACC continues normally
without it; clipboard copy of logs is simply skipped.

Fix: `sudo apt install wl-clipboard`

### Setup requirement — `xdotool`

`xdotool` is used in `src/lib/input.sh` to send mouse/keyboard events to the
nested Gamescope X display. It is the primary input mechanism.

Fix: `sudo apt install xdotool`

Pop!_OS uses an X11 or XWayland environment where `xdotool` works. Input is sent
to the nested Gamescope display (e.g. `DISPLAY=:1`), not to the GNOME desktop.

### Setup requirement — `gamescope`

Gamescope must be installed and running for ACC to work. The nested session
provides the X display that `xdotool` targets.

Fix: `sudo apt install gamescope`

Note: Gamescope on Pop!_OS may have different version availability than Fedora.
If the version in apt is outdated, consider installing from a PPA or building
from source.

### Setup requirement — `xdg-open`

Used in `src/modules/recovery_restart.sh` to open the private server URL and
launch Roblox via Sober. `xdg-open` is standard on GNOME/Pop!_OS.

Fix: `sudo apt install xdg-utils` (usually pre-installed)

### Setup requirement — Gamescope manager directory

`src/lib/env.sh` looks for:
```
${HOME}/.config/autoclicker/background-static-shop-buyer/gamescope-wayland-attached/env-attached.txt
```

This file is written by the Gamescope startup manager when it attaches. On
Pop!_OS, you must set up your Gamescope launch process to create this directory
and write the attached environment to `env-attached.txt`.

A minimal `env-attached.txt` example:
```
DISPLAY=:1
WAYLAND_DISPLAY=gamescope-0
```

The macro will fail preflight checks if this file does not exist.

## Blockers vs Setup Requirements

| Issue | Blocker? | Resolution |
|-------|----------|-----------|
| `wl-copy` absent | No — graceful fallback | `apt install wl-clipboard` |
| `xdotool` absent | Yes — input fails | `apt install xdotool` |
| `gamescope` absent | Yes — no nested display | `apt install gamescope` |
| `xdg-open` absent | Yes for recovery only | `apt install xdg-utils` |
| Manager dir absent | Yes — env read fails | Create dir + `env-attached.txt` |
| Coordinate mismatch | Yes for live mode | Recalibrate all points |

## Recommended Actions for Pop!_OS Users

1. Install all dependencies: see [SETUP_POP_OS.md](SETUP_POP_OS.md)
2. Set up Gamescope to write `env-attached.txt` on launch
3. Calibrate all points for your display: see [CALIBRATION.md](CALIBRATION.md)
4. Run `./bin/acc --dry-run` and resolve any preflight errors before going live

No source code changes are required for Pop!_OS compatibility.
