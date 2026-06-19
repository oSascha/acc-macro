# ACC Changelog

## 2026-06-19 — Non-interactive setup mode, clean step numbering, and diagnose guard

### Setup wizard (`bin/setup-acc`)

- **Non-interactive mode**: `--profile known-good-800x600 --yes --no-install-deps --skip-private-server`
  runs the full setup without prompts. Safe to use with a temporary `HOME` for test
  isolation (launcher and PATH updates use `$HOME`). This supports both scripted installs
  and a clean fresh-clone acceptance test.
- **`--profile known-good-800x600`**: Pre-selects the known-good 800x600 profile without
  interactive prompting. The `choose_setup_profile()` step is skipped; Step 2 shows
  "Profile: known_good_800x600 (pre-selected)".
- **`--yes`**: Auto-answers all yes/no prompts (non-interactive mode).
- **`--no-install-deps`**: Skips `apt` and `flatpak install` steps.
- **`--skip-private-server`**: Skips the private server URL setup step.
- **Fixed step numbering**: Steps 1–10 are now clean and sequential in both dry-run
  and interactive output. Previously Step 5 appeared twice (Sober and runtime_config)
  and Step 9 appeared twice (launcher and validation). Now:
  Step 1 system check, Step 2 profile, Step 3 dep check, Step 4 dep install,
  Step 5 Sober, Step 6 runtime_config, Step 7 private URL, Step 8 Event Voter,
  Step 9 launcher, Step 10 validation.
- **Diagnose guard**: `--diagnose` no longer bootstraps blank templates when
  `runtime_config/pack_opener/points.conf` is absent. Instead it prints:
  "Known-good setup has not been applied yet. Run setup first." — and skips the
  dry-run section, keeping diagnose fully read-only on a fresh clone.
- **Diagnose HOME guard**: `run_diagnose` creates `$HOME` before writing the
  output file, so `HOME=/tmp/acc-test-home ./bin/setup-acc --diagnose` works
  even when the temp home directory does not yet exist.
- **arg parsing refactor**: `main()` uses a `while` loop over all arguments
  instead of a single-arg case, so multiple flags can be combined freely.

### Tests (`tests/dry_runs/setup_acc_dry_run.sh`)

- Added 20 new assertions covering: `--profile`/`--yes`/`--no-install-deps`/
  `--skip-private-server` flags present in source, `NONINTERACTIVE`/`SKIP_DEPS_INSTALL`/
  `SKIP_PRIVATE_SERVER` vars, non-interactive exit 0, temp-HOME launcher install
  (path, not-symlink, not-recursive), runtime_config populated with preset coords,
  no duplicate step numbers in dry-run output, diagnose source guard message,
  `--profile` with unknown/missing value exits non-zero.
- **Total**: 133 assertions, all pass.

## 2026-06-19 — Known-good setup wizard profile and persistent module toggles

### Setup wizard (`bin/setup-acc`)

- **First-class known-good 800x600 profile**: The setup wizard now offers a
  "Known-good 800x600 Sober/Gamescope" option near the beginning. This option
  copies the full 800x600 preset into `runtime_config/` with a timestamped backup,
  sets safe module defaults (Pack Opener ON; Market/Figurines/Recovery/Event Voter OFF),
  and installs the `acc` terminal command.
- **Launcher installation step**: The wizard now installs `~/.local/bin/acc` as a
  wrapper that `cd`s to the repo and exports the required live env gates before
  exec'ing `./bin/acc`. This makes `acc` work from any terminal after setup.
  PATH is updated in `~/.bashrc` / `~/.zshrc` if `~/.local/bin` is not already present.
- **`--diagnose` flag**: `./bin/setup-acc --diagnose` writes a full support file to
  `~/acc_setup_diagnose.txt` including git state, launcher content, all runtime_config
  values, dependency paths, process checks, xdotool result, dry-run output, and latest
  logs. Final message: "Send this file for debugging: ~/acc_setup_diagnose.txt"
- **Event Voter auto-disable**: If Event Voter is found enabled but `python3-opencv`
  is not installed or training images are missing, the wizard auto-disables it and
  explains why with exact repair instructions.
- **Improved final summary**: Setup ends with a complete status summary — dependencies,
  config status, module toggle state, Event Voter status, installed command path, and
  the exact next command to run.
- **Numbered steps and plain-English messages** throughout the wizard.

### Module toggles (`bin/pack-opener-ui`)

- **Persistent module toggles**: The UI no longer uses hardcoded session defaults.
  On startup, `load_ui_toggles()` reads `runtime_config/ui/toggles.conf` (preferred)
  or falls back to `runtime_config/orchestrator/defaults.conf` plus module-specific
  configs. When the user changes a toggle, `save_ui_toggles()` writes the new state
  to `runtime_config/ui/toggles.conf` immediately.
- **Safe startup defaults**: The code-level defaults for Market Buyer and Figurines
  Buyer changed from `1` to `0` so that a fresh install without any config file shows
  the correct safe state.

### Preset (`presets/800x600_known_good/`)

- **`orchestrator/defaults.conf`**: `MARKET_BUYER_ENABLED=0` and
  `FIGURINES_BUYER_ENABLED=0` — safe startup state for new users.
- **`ui/toggles.conf`** (new): Pre-set UI toggle file so toggle state is correct from
  first run without requiring any user interaction in the toggle screen.

### Tests (`tests/dry_runs/setup_acc_dry_run.sh`)

- Added tests for: known-good profile option, launcher installation function,
  `--diagnose` flag, diagnose output file name, final summary function, new preset
  `ui/toggles.conf`, orchestrator preset safe defaults, pack-opener-ui toggle
  load/save functions, no hardcoded home paths in committed files, and
  `--dry-run` output mentioning the launcher step.

## 2026-06-19 — Set default placement click burst delay to 8ms

- **`PLACE_LIVE_CLICK_BURST_DELAY=8ms`**: Inter-click delay within each placement click burst
  is now 8ms in all defaults (template, 800x600 preset, and source fallbacks). Prior values
  (0ms in template, 3ms in preset, 1ms in source fallbacks) were found to be unstable in
  live testing. 8ms is the live-validated stable value.

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
