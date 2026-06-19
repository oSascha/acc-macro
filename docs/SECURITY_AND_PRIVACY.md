# Security and Privacy

## What Is Automatically Protected

The following are listed in `.gitignore` and will not be staged by `git add`:

| Path | Reason |
|------|--------|
| `runtime_config/` | Contains calibrated coordinates and private URLs |
| `00_handoff/` | Internal development handoff materials |
| `01_docs/` | Internal architecture and spec notes |
| `02_contracts/` | Internal implementation contracts |
| `03_codex_reports/` | Internal Codex/AI session reports |
| `04_manual_tests/` | Test notes, timing data, and tuning results |
| `05_debug_snapshots/` | Logs, traces, and calibration snapshots |
| `*.log`, `*.trace` | Generated log files |
| `.env`, `*.secret` | Environment and secret files |

## Private Server URL

If you use the recovery restart module, your private Roblox server URL goes in:

```
runtime_config/recovery/defaults.conf
```

This file is gitignored. **Never paste a private server URL into any committed
file, README, or documentation.**

Example of what a private URL looks like (do not commit):
```
RECOVERY_PRIVATE_SERVER_URL='https://www.roblox.com/share?code=XXXXXXXX&type=Server'
```

## Diagnostic File

Running `./bin/setup-acc --diagnose` writes `~/acc_setup_diagnose.txt`. This file
contains config values, dependency paths, and dry-run output. **It does not
contain private server URLs** (those are redacted in the diagnostic). Review it
before sharing to confirm no sensitive paths or tokens appear.

## Before Pushing a Fork

Run these checks before `git push`:

```bash
# 1. Confirm only expected files are tracked
git ls-files | sort

# 2. Check for any sensitive strings in tracked files
grep -RInE \
  'roblox\.com/share|RECOVERY_PRIVATE_SERVER_URL=.+|/home/[a-z]|private server' \
  . --exclude-dir=.git

# 3. Confirm runtime_config is not staged
git status --short --untracked-files=all | grep runtime_config

# 4. Confirm no debug snapshots or logs are staged
git status --short --untracked-files=all | grep -E '05_debug|\.log|\.trace'
```

If any of those commands produce unexpected output, do not push until resolved.

## What Is Safe to Push

The following are public-safe and committed:

- `bin/` — executable scripts (no hardcoded credentials)
- `src/` — library and module source (reads config at runtime from `runtime_config/`)
- `config_templates/` — starter config files with **empty placeholder values**
- `tests/` — dry-run and static validation tests
- `docs/` — setup and compatibility documentation
- `samples/` — example config files with placeholder values only
- `README.md` — public project overview
- `.gitignore` — this exclusion list

## Personal Information

The source code uses `${HOME}` (not a hardcoded path) for any paths it constructs.
No personal usernames, email addresses, or home directory paths appear in committed
files.

## Coordinate Privacy

Screen coordinates are personal to your monitor layout and game window size.
They are stored only in `runtime_config/` (gitignored) and never committed.
The `config_templates/` files use empty placeholder values.
