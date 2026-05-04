# Mole Agent Guide

## Project

Mole is a macOS system cleanup and optimization tool with shell and Go components. It performs file cleanup, app protection checks, and maintenance tasks, so safety rules matter more than speed.

## Repository Map

- `mole` - main shell entrypoint.
- `lib/core/` - shared shell safety, UI, file operations, and app protection logic.
- `lib/clean/` - cleanup flows.
- `lib/optimize/` - optimization tasks.
- `cmd/` - Go command implementations.
- `tests/` - Bats and shell test coverage.
- `scripts/` - check, test, build, and release helpers.
- `SECURITY_AUDIT.md` - security review notes.

## Commands

```bash
./scripts/check.sh --format
MOLE_TEST_NO_AUTH=1 ./scripts/test.sh
MOLE_TEST_NO_AUTH=1 bats tests/clean_core.bats
MOLE_DRY_RUN=1 ./mole clean
MOLE_TEST_NO_AUTH=1 ./mole clean --dry-run
bash -n lib/clean/*.sh
make build
go test ./...
```

## Critical Safety Rules

- Never use raw `rm -rf` or `find -delete`; use safe deletion helpers.
- Never modify protected paths such as `/System`, `/Library/Apple`, or `com.apple.*`.
- Never let verification block on sudo, AppleScript, or macOS authorization prompts unless the task explicitly targets auth behavior.
- Use `MOLE_DRY_RUN=1` before destructive cleanup flows.
- Use `MOLE_TEST_NO_AUTH=1` for tests, manual repro, and verification unless real auth behavior is being tested.
- Do not change ESC timeout behavior in `lib/core/ui.sh` unless explicitly requested.

## Working Rules

- Use helpers from `lib/core/file_ops.sh` for deletion logic.
- Check `should_protect_path()` before adding cleanup behavior.
- Keep shell code formatted with `./scripts/check.sh --format`.
- Prefer targeted Bats tests during development; run the full suite before committing.
- Do not add AI attribution trailers to commits.

## Verification

- Shell changes: run `./scripts/check.sh --format`, then the relevant Bats test or `MOLE_TEST_NO_AUTH=1 ./scripts/test.sh`.
- Go changes: run `go test ./...`.
- Cleanup behavior: verify with dry-run or test mode first.
- Documentation-only changes: check links and commands.

## GitHub Operations

- Use `gh` for issue, PR, and release inspection.
- Do not comment, close, merge, or publish unless the maintainer explicitly asks.
- When closing a fixed bug or shipped feature, use the project wording from the issue context and include the expected release path only when confirmed.

## Claude Code

`CLAUDE.md` imports this file. Keep shared project facts here and put personal overrides in `CLAUDE.local.md`, which is ignored.
