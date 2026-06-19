# Event Voter — EXPERIMENTAL

> **EXPERIMENTAL.** This module uses computer vision to vote at ACC Live Events. It may click the wrong option. Enable at your own risk.

## Event schedule (Amsterdam / CEST)

```
07:00  07:20  07:40
19:00  19:20  19:40
```

## Priority

1. **3x XP** — preferred first
2. **3x Mutation Chance** — preferred second
3. **Anything else** — skipped (no click if confidence is below threshold)

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

## Inspecting results

```bash
cat runtime_config/event_voter/results.tsv
```

Format: `ISO_timestamp <tab> slot <tab> label <tab> confidence <tab> action`

## Turning it off

Set `EVENT_VOTER_ENABLED=0` in `runtime_config/event_voter/defaults.conf`, or toggle off in the UI Module Toggles screen.

## Warning

- Experimental — detection is template-matching based and depends on screenshot quality
- Wrong votes can occur when the popup layout changes or confidence is marginal
- Review `results.tsv` after each event window to verify behavior
