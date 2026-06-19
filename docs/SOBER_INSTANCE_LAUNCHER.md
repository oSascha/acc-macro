# Sober Instance Launcher

Manages launching and stopping a Sober instance inside Gamescope from the ACC terminal UI, and opens a configured private server link separately via xdg-open.

## How private server joining works (live-test findings)

Three approaches were tested. Only the third works:

1. **Passing the URL to `flatpak run org.vinegarhq.Sober`** — did not reliably join the private server.
2. **Starting Sober first, then opening the URL** — causes a double launch (browser handoff starts a second Gamescope/Sober instance).
3. **Opening only the private-server web link via xdg-open (browser handoff)** — works correctly.

The working path is:

```
browser / private-server page
  → roblox-player URI
  → sober-gamescope-url wrapper
  → Sober in Gamescope joins the private server
```

**Option 2 (Open configured private server) uses this path.** It opens the private-server web URL in your browser. Your browser will ask to open the `roblox-player://` link — this protocol handoff launches/joins Sober in Gamescope automatically.

**Option 1 (Start Sober normally) is a fallback** for when you need to start Gamescope/Sober without joining a private server (e.g., to test the environment or join a public server).

## Purpose

The Sober Instance Launcher provides a quick way to start or stop your Roblox session (via Sober/Gamescope) from the ACC menu without leaving the terminal. It tracks the process it launches and provides clean stop/restart handling.

## How it differs from Recovery Restart

| Feature | Recovery Restart | Sober Instance Launcher |
|---------|-----------------|------------------------|
| Purpose | Periodic in-session restart to clear lag | Manual launch/stop from the ACC menu |
| Trigger | Automatic, on a timed interval | Manual, via menu option 1 |
| Integration | Runs inside the orchestrator loop | Independent of the macro |
| URL source | `runtime_config/recovery/defaults.conf` | `runtime_config/sober_launcher/defaults.conf` (with recovery fallback) |

The launcher reads the private server URL from its own config first, and falls back to the recovery config URL if the launcher config has no URL set.

## Setting the private server URL

The private server URL is **never committed to the repository**. It lives only in `runtime_config/sober_launcher/defaults.conf`.

To set it up, run the following from the project root:

```bash
mkdir -p runtime_config/sober_launcher
cp -n config_templates/sober_launcher/defaults.conf runtime_config/sober_launcher/defaults.conf
python3 - <<'PY'
from pathlib import Path
p = Path("runtime_config/sober_launcher/defaults.conf")
text = p.read_text()
url = input("Paste private server URL: ").strip()
lines = []
seen = False
for line in text.splitlines():
    if line.startswith("SOBER_PRIVATE_SERVER_URL="):
        lines.append("SOBER_PRIVATE_SERVER_URL=" + url)
        seen = True
    else:
        lines.append(line)
if not seen:
    lines.append("SOBER_PRIVATE_SERVER_URL=" + url)
p.write_text("\n".join(lines) + "\n")
print("Private server URL saved in runtime_config only.")
PY
```

**The private URL is never committed. `runtime_config/` is in `.gitignore`.**

## Opening the Sober Instance submenu

From the ACC main menu, select **1) Sober Instance**.

The submenu shows:
- Current status (Live / Offline / Live (untracked))
- Private server link: Configured / Missing
- Launch mode and Gamescope size

## Submenu options

### 1) Start Sober normally

Starts Sober inside Gamescope without attempting to join the private server. The private server URL is not passed to Sober as an argument.

- If Sober is already running (Live or Live (untracked)), asks whether to stop it and start fresh.
- Launches detached from the terminal so the ACC UI stays usable.
- Writes the process PID to `runtime_config/sober_launcher/pids.env`.
- Writes launch output to `runtime_config/sober_launcher/launcher.log`.

The launch command is:
```
gamescope -W <width> -H <height> -r <refresh> -- flatpak run <flatpak-app-id>
```

No private URL is passed — use option 2 to open the private server link after Sober is running.

### 2) Open configured private server

Opens the configured private server web URL via `xdg-open` (or the method in `SOBER_PRIVATE_OPEN_METHOD`). The browser's roblox-player URI protocol handoff launches/joins Sober in Gamescope. **Sober is not started separately — the browser handoff handles it.**

- If the URL is not configured, shows a clear error and instructions.
- If `xdg-open` is not available, shows a clear error.
- Asks for confirmation regardless of whether Sober is running.
- The private URL is never shown in the UI or written to logs.
- Open results are logged (masked) to `runtime_config/sober_launcher/private_open.log`.

**Firefox "Open Link" prompt:** Firefox may ask to allow opening the roblox-player link. To avoid future prompts, tick "Always allow https://www.roblox.com to open roblox-player links" and press "Open Link". ACC does not automate clicking the browser permission prompt.

### 3) Stop current Sober instance

- If **Offline**: shows "No Sober instance appears to be running."
- If **Live (untracked)**: asks for explicit confirmation before stopping.
- If **Live** (tracked): confirms, then:
  - Sends SIGTERM to the tracked PID.
  - Waits up to 5 seconds for graceful exit.
  - Force-kills with SIGKILL if still running.
  - Removes the PID file.

### 4) Back

Returns to the main menu.

## Status meanings

| Status | Meaning |
|--------|---------|
| **Live** | A Sober instance was started by this launcher and its process is still running |
| **Offline** | No Sober/Gamescope process detected |
| **Live (untracked)** | A Sober/Gamescope process is running but was not started by this launcher |

## WARNING: private URL is never committed

`runtime_config/` is excluded from git by `.gitignore`. The private server URL must never appear in source files, templates, docs, tests, or logs.

## Troubleshooting

**Missing URL**
Set `SOBER_PRIVATE_SERVER_URL` in `runtime_config/sober_launcher/defaults.conf`. See setup instructions above.

**Sober not installed**
Install Sober via Flatpak:
```bash
flatpak install flathub org.vinegarhq.Sober
```

**Gamescope not installed**
Install Gamescope via your package manager:
```bash
sudo dnf install gamescope      # Fedora/RHEL
sudo apt install gamescope      # Debian/Ubuntu
```

**Flatpak app missing**
Confirm the app ID matches what is installed:
```bash
flatpak list | grep -i sober
```
Update `SOBER_FLATPAK_APP_ID` in `runtime_config/sober_launcher/defaults.conf` if needed.

**xdg-open not found**
Install xdg-utils:
```bash
sudo dnf install xdg-utils      # Fedora/RHEL
sudo apt install xdg-utils      # Debian/Ubuntu
```
Or set `SOBER_PRIVATE_OPEN_METHOD` in `runtime_config/sober_launcher/defaults.conf` to an alternative command.

**Option 2 opens browser but game doesn't join**
Option 2 opens the private-server web page. The browser then requests permission to open the `roblox-player://` protocol link. If Firefox shows the "Open Link" dialog, click "Open Link" (and optionally tick "Always allow..."). If the game still doesn't join, ensure `sober-gamescope-url` is registered as the handler for `roblox-player://` on your system.

**Stale PID file**
If the launcher reports "Live" but no game is running, the PID file may be stale. Remove it:
```bash
rm -f runtime_config/sober_launcher/pids.env
```
The launcher will then report "Offline" or "Live (untracked)" based on process detection.
