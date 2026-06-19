# Event Voter — EXPERIMENTAL

> **EXPERIMENTAL.** This module uses computer vision to vote at ACC Live Events. It may click the wrong option. Enable at your own risk.

> **Disabled by default.** The setup wizard auto-disables Event Voter if `python3-opencv`
> is not installed or if training images are missing. It will never block the full macro
> from running — all failures are logged and pack opening continues.

## Quick setup checklist

1. Run `./bin/setup-acc` and choose the known-good 800x600 profile
2. Install OpenCV: `sudo apt install python3-opencv`
3. Capture training screenshots (see below)
4. Run live diagnostics to verify: `./bin/macroctl dry-run event-voter-live-diagnostics`
5. Enable in ACC menu → Module Toggles → Event Voter

## Event schedule (Amsterdam / CEST)

```
07:00  07:20  07:40
19:00  19:20  19:40
```

## Priority

1. **3x XP** — preferred first
2. **3x Mutation Chance** — preferred second
3. **Anything else** — skipped (no click if confidence is below threshold)

## Fail-soft guarantee

Event Voter **never stops the full macro.** All failure modes (no screenshot tool, screenshot failure, detector crash, popup not found, no target detected, click error) are logged and the macro continues pack opening.

The `no_target` result means no configured target option was detected above the confidence threshold. It is **not** an error — it is the expected result when the event popup is absent or when neither 3x XP nor 3x Mutation Chance appears.

## Adding training screenshots

Place screenshots in `runtime_config/event_voter/training/`:

| File | Description |
|------|-------------|
| `live_event_seed.png` | Screenshot of the ACC Live Event popup showing 3x XP |
| `live_event_seed_mutation.png` | Screenshot showing 3x Mutation Chance |

The module will generate templates from these on first run and save them to `runtime_config/event_voter/generated/`.

## Running the offline detector

```bash
./bin/macroctl dry-run event-voter --image runtime_config/event_voter/training/live_event_seed.png
./bin/macroctl dry-run event-voter --image runtime_config/event_voter/training/live_event_seed_mutation.png
```

To dump debug crops without running detection:

```bash
./bin/macroctl dry-run event-voter-crops --image <path>
```

## Viewing the schedule

```bash
./bin/macroctl dry-run event-voter-schedule
```

## Running the live diagnostics check

```bash
./bin/macroctl dry-run event-voter-live-diagnostics
```

This prints config status, cv2 availability, training image status, screenshot tool detection, and all output paths **without** taking a screenshot or sending any input. Run this to verify your setup before enabling live voting.

## Enabling live voting

Edit `runtime_config/event_voter/defaults.conf`:

```
EVENT_VOTER_ENABLED=1
EVENT_VOTER_LIVE_ALLOWED=1
```

Also configure click points in `runtime_config/event_voter/points.conf`:

```
EVENT_OPTION_LEFT_X=<x>
EVENT_OPTION_LEFT_Y=<y>
EVENT_OPTION_MIDDLE_X=<x>
EVENT_OPTION_MIDDLE_Y=<y>
EVENT_OPTION_RIGHT_X=<x>
EVENT_OPTION_RIGHT_Y=<y>
```

Then enable the Event Voter toggle in the UI (Module Toggles → press 5).

## Fail-safe

If no option exceeds `EVENT_VOTER_MIN_CONFIDENCE` (default: 0.55), no click is sent (`SAFE_TO_CLICK=0`, `BEST_SLOT=none`).

## Inspecting live attempts

### Last attempt log

After every live Event Voter attempt, a full diagnostic log is written to:

```
runtime_config/event_voter/last_attempt.log
```

This contains:
- `timestamp` — when the attempt ran
- `event_slot` — which schedule slot triggered it (e.g. `07:00`)
- `screenshot_cmd` — which tool was used (`import`, `scrot`, or `none`)
- `screenshot_path` — where the last live screenshot was saved
- `detector_cmd` — the exact Python command that was invoked
- `detector_exit` — exit code from the detector (`0` = ok)
- `BEST_LABEL / BEST_SLOT / BEST_CONFIDENCE / SAFE_TO_CLICK` — parsed detector output
- `final_action` — `clicked` or `skipped`
- `reason` — `target_found`, `no_target`, `capture_error`, `detector_error`, `click_error`
- Full detector stdout and stderr

Read this first when diagnosing a missed or unexpected vote.

### Live screenshots and crops

The most recent live attempt saves:

```
runtime_config/event_voter/generated/live_last_screen.png   ← full screenshot
runtime_config/event_voter/generated/live_last_left.png     ← left slot crop
runtime_config/event_voter/generated/live_last_middle.png   ← middle slot crop
runtime_config/event_voter/generated/live_last_right.png    ← right slot crop
```

These are overwritten on each live attempt and are never committed to git.

### Results TSV

```bash
cat runtime_config/event_voter/results.tsv
```

Format: `timestamp  slot  label  confidence  action  reason`

Example lines:
```
2026-06-19T07:00:00+0200  none   unknown          0.00  skipped  no_target
2026-06-19T07:20:00+0200  none   unknown          0.00  skipped  capture_error
2026-06-19T07:40:00+0200  right  3x_xp            0.91  clicked  target_found
```

## Diagnosing a missed event

1. Run `./bin/macroctl dry-run event-voter-live-diagnostics` to check configuration.
2. Read `runtime_config/event_voter/last_attempt.log` and look at `reason:`.
   - `no_target` — popup absent or neither priority option detected above threshold
   - `capture_error` — screenshot tool failed or not installed
   - `detector_error` — Python/cv2 error (check `detector_exit` and stderr in log)
   - `click_error` — click was attempted but blocked (check live gate config)
3. Inspect `live_last_screen.png` and crop images for visual confirmation.
4. Run the offline detector against the saved screenshot:
   ```bash
   ./bin/macroctl dry-run event-voter --image runtime_config/event_voter/generated/live_last_screen.png
   ```

## Turning it off

Set `EVENT_VOTER_ENABLED=0` in `runtime_config/event_voter/defaults.conf`, or toggle off in the UI Module Toggles screen.

## Warning

- Experimental — detection is template-matching based and depends on screenshot quality
- Wrong votes can occur when the popup layout changes or confidence is marginal
- Review `results.tsv` after each event window to verify behavior
