# Calibrating Screen Coordinates

All coordinate values in `runtime_config/` must be calibrated for your specific
monitor resolution, Gamescope window size, and Roblox UI scaling. No pre-filled
coordinates are committed to this repository.

## How to Read Coordinates

With Gamescope and Sober running, the nested display is accessible via
`DISPLAY=:1` (or whatever your display ID is). Use `xdotool` to read the mouse
position:

```bash
DISPLAY=:1 xdotool getmouselocation --shell
```

Move your mouse to the button or point you want to capture, run the command, and
record `X=` and `Y=` from the output.

> Tip: run it in a loop and press Ctrl-C when the cursor is on the target:
> ```bash
> while true; do DISPLAY=:1 xdotool getmouselocation --shell; sleep 0.5; done
> ```

## Files to Calibrate

All point files live in `runtime_config/` (gitignored). Start from the templates
in `config_templates/` then fill in each value.

### Pack Opener — `runtime_config/pack_opener/points.conf`

| Variable | Purpose |
|----------|---------|
| `BASE_TELEPORT_BUTTON_X/Y` | Button that teleports to the base/spawn area |
| `PLACE_HOLD_POINT_X/Y`     | Point held down during the place action |
| `PACK_CLICK_POINT_X/Y`     | Point clicked to open a pack |
| `MENU_BUTTON_X/Y`          | Inventory/menu button |
| `POTION_2_MIN_X/Y`         | 2-minute potion icon in the inventory |
| `POTION_2_MIN_USE_SINGLE_BUTTON_X/Y` | Use x1 button for 2-min potion |
| `POTION_2_MIN_USE_10X_BUTTON_X/Y`   | Use x10 button for 2-min potion |
| `POTION_6_MIN_X/Y`         | 6-minute potion icon |
| `POTION_6_MIN_USE_SINGLE_BUTTON_X/Y` | Use x1 button for 6-min potion |
| `POTION_6_MIN_USE_10X_BUTTON_X/Y`   | Use x10 button for 6-min potion |
| `POTION_15_MIN_X/Y`        | 15-minute potion icon |
| `POTION_15_MIN_USE_SINGLE_BUTTON_X/Y`| Use x1 button for 15-min potion |
| `POTION_15_MIN_USE_10X_BUTTON_X/Y`  | Use x10 button for 15-min potion |
| `USE_SINGLE_BUTTON_X/Y`    | Generic use x1 button (fallback) |
| `USE_10X_BUTTON_X/Y`       | Generic use x10 button (fallback) |
| `CLOSE_BUTTON_X/Y`         | Close/dismiss dialog button |
| `ITEM_POINT_X/Y`           | Item icon position (if used) |
| `USE_BUTTON_X/Y`           | Generic use button (if used) |

### Market Buyer — `runtime_config/market_buyer/points.conf`

| Variable | Purpose |
|----------|---------|
| `TOP_MARKET_BUTTON_X/Y` | Top-of-market navigation button |
| `MARKET_BUY_ALL_X/Y`    | Buy All button in market UI |

### Figurines Buyer — `runtime_config/figurines_buyer/points.conf`

| Variable | Purpose |
|----------|---------|
| `BASE_TELEPORT_BUTTON_X/Y` | Teleport to base button |
| `FIGURINES_BUY_ALL_X/Y`    | Buy All button in figurines shop |

### Recovery Restart — `runtime_config/recovery/points.conf`

| Variable | Purpose |
|----------|---------|
| `RECOVERY_POPUP_CLOSE_BUTTON_X/Y` | Close the "Disconnected" / recovery popup |
| `RECOVERY_ITEMS_TAB_BUTTON_X/Y`   | Items tab in the inventory after relaunch |

> `MENU_BUTTON` and `BASE_TELEPORT_BUTTON` are reused from `pack_opener/points.conf`.

## Calibration Tips

- Always calibrate with Gamescope running at the same resolution and scale you
  will use during live runs.
- Roblox UI positions shift with different window sizes — recalibrate if you
  change the Gamescope `-W`/`-H` flags.
- Use dry-run mode (`./bin/acc --dry-run`) to validate config loading without
  sending any real input.
- The `./bin/macroctl validate-config pack-opener` command checks for missing
  required points and reports them.

## Never Commit Calibrated Values

`runtime_config/` is gitignored. Keep your calibrated coordinates there.
Do not copy them into `config_templates/` or documentation.
