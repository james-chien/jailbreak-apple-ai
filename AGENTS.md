# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project

This repository contains a Bash-based macOS helper for inspecting and editing Apple eligibility plist files related to Apple Intelligence features.

Primary files:

- `jailbreak.sh`: user-facing command-line/TUI script.
- `test_jailbreak.sh`: local test harness with stubbed macOS commands.
- `assets/`: supporting media for documentation.

## Safety Rules

- Treat `/private/var/db/eligibilityd` and `/private/var/db/os_eligibility` as protected system locations.
- Do not remove SIP checks, Full Disk Access checks, backup creation, per-command confirmations, or restore support.
- Do not make the script silently modify plist files.
- Keep production defaults pointed at real macOS paths, but preserve `JAILBREAK_*` environment overrides for tests.
- Always create or preserve backups before code paths that write plist files.

## Development

- Prefer Bash builtins and standard macOS tools.
- Keep functions small and command-oriented.
- Run syntax checks before finishing:

```bash
bash -n jailbreak.sh
bash -n test_jailbreak.sh
```

- Run the test harness when changing behavior:

```bash
./test_jailbreak.sh
```

The tests intentionally stub macOS-specific commands so they can run without touching real system plist files.

