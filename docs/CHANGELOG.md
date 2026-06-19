# ACC Changelog

## 2026-06-19 — Event Voter live diagnostics and fail-soft patch

- **Fail-soft guarantee**: Event Voter failures (screenshot capture error, detector crash,
  no target detected, click blocked) no longer stop the full macro. The orchestrator wraps
  all Event Voter calls with `|| true` and `event_voter_run_live_window` always returns 0.
- **`last_attempt.log`**: Every live Event Voter attempt now writes a full diagnostic log to
  `runtime_config/event_voter/last_attempt.log` (timestamp, event slot, screenshot cmd/path,
  detector cmd/exit/stdout/stderr, parsed detection values, final action, reason).
- **`results.tsv` reason column**: The results TSV gains a 6th column (`reason`) to
  distinguish `no_target`, `capture_error`, `detector_error`, `target_found`, and `click_error`.
- **Live screenshot/crop persistence**: The most recent live attempt's full screenshot and
  panel crops are saved to `runtime_config/event_voter/generated/live_last_{screen,left,middle,right}.png`.
  These files are gitignored and overwritten on each attempt.
- **New diagnostic command**: `./bin/macroctl dry-run event-voter-live-diagnostics` prints
  config status, cv2 availability, training image status, screenshot tool detection, and all
  output paths — no screenshots taken, no input sent.
- **Dashboard improvement**: The Live Dashboard Event Voter row now shows the last action and
  reason (e.g. `no_target @ 07:00` or `clicked 3x_xp/right @ 07:40`) instead of `---`.

## 2026-06-19 — Event Voter, Sober Launcher, and UI improvements

### New modules

**Event Voter** (experimental)
- Visual module that detects the in-game event voting panel using OpenCV template matching
- Auto-votes for a configurable priority option (e.g. `3x_xp,3x_mutation_chance`)
- Fires at configurable times of day with a pre-hold guard to avoid early clicks
- Slot-specific templates and panel auto-detection (no manual crop geometry required)
- Disabled by default (`EVENT_VOTER_ENABLED=0`, `EVENT_VOTER_LIVE_ALLOWED=0`)
- Requires `python3-opencv` and local training screenshots (not included in repo)
- 800x600 option click coordinates included in preset

**Sober Instance Launcher**
- Launches Sober inside a Gamescope nested session with configurable resolution
- Optionally opens a private server via the Roblox URI protocol (`roblox-player:`)
- Private server URL is stored only in `runtime_config/sober_launcher/defaults.conf`
- Accessible from the main ACC menu

### UI and controls

- Live dashboard with module status, run metrics, and elapsed time
- Pause/resume controls (`macroctl pause`, `macroctl resume`)
- Improved dashboard rendering and controls line layout
- Fixed ACC logo and main menu right border alignment

### Recovery restart

- Improved recovery restart flow
- Private server URL is now also written to `runtime_config/sober_launcher/defaults.conf`
  by the setup wizard (one URL configures both recovery and the launcher)

### Setup wizard (`bin/setup-acc`)

- Added `python3-opencv` to the dependency check (required for Event Voter)
- Fedora install hint shown when apt is unavailable
- Step 7 now configures both `recovery/defaults.conf` and `sober_launcher/defaults.conf`
- New Event Voter training image step: creates the training folder and explains setup
- Validation now includes `validate-config sober-launcher`, `validate-config event-voter`,
  and dry-runs for the new launcher and voter actions

### Presets (`presets/800x600_known_good/`)

- Added `event_voter/defaults.conf` — disabled by default with known timezone/times
- Added `event_voter/points.conf` — 800x600 option button coordinates
- Added `sober_launcher/defaults.conf` — 800x600 window size, blank private URL

### .gitignore

- Added `runtime_config/sober_launcher/` entries
- Added `runtime_config/event_voter/training/` and `generated/`
- Added `*.tsv` to prevent voter results from being accidentally staged
