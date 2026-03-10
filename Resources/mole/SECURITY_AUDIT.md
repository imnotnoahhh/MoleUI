# Mole Security Reference

Version 1.30.0 | 2026-03-08

This document describes the security-relevant behavior of the current codebase on `main`.

## Path Validation

All destructive file operations go through `lib/core/file_ops.sh`.

- `validate_path_for_deletion()` rejects empty paths, relative paths, traversal segments such as `/../`, and control characters.
- Security-sensitive cleanup paths do not use raw `find ... -delete`.
- Removal flows use guarded helpers such as `safe_remove()`, `safe_sudo_remove()`, `safe_find_delete()`, and `safe_sudo_find_delete()`.

Blocked paths remain protected even with sudo, including:

```text
/
/System
/bin
/sbin
/usr
/etc
/var
/private
/Library/Extensions
```

Some subpaths under protected roots are explicitly allowlisted for bounded cache and log cleanup, for example:

- `/private/tmp`
- `/private/var/tmp`
- `/private/var/log`
- `/private/var/folders`
- `/private/var/db/diagnostics`
- `/private/var/db/DiagnosticPipeline`
- `/private/var/db/powerlog`
- `/private/var/db/reportmemoryexception`

When running with sudo, symlinked targets are validated before deletion and system-target symlinks are refused.

## Cleanup Rules

### Orphan Detection

Orphaned app data is handled in `lib/clean/apps.sh`.

- Generic orphaned app data requires both:
  - the app is not found by installed-app scanning and fallback checks, and
  - the target has been inactive for at least 30 days.
- Claude VM bundles use a stricter app-specific window:
  - `~/Library/Application Support/Claude/vm_bundles/claudevm.bundle` must appear orphaned, and
  - it must be inactive for at least 7 days before cleanup.
- Sensitive categories such as keychains, password-manager data, and protected app families are excluded from generic orphan cleanup.

Installed-app detection is broader than a simple `/Applications` scan and includes:

- `/Applications`
- `/System/Applications`
- `~/Applications`
- Homebrew Caskroom locations
- Setapp application paths

Spotlight fallback checks are bounded with short timeouts to avoid hangs.

### Uninstall Matching

App uninstall behavior is implemented in `lib/uninstall/batch.sh` and related helpers.

- LaunchAgent and LaunchDaemon lookups require a valid reverse-DNS bundle identifier.
- Deletion candidates are decoded and validated as absolute paths before removal.
- Homebrew casks are preferentially removed with `brew uninstall --cask --zap`.
- LaunchServices unregister and rebuild steps are skipped safely if `lsregister` is unavailable.

### Developer and Project Cleanup

Project artifact cleanup in `lib/clean/project.sh` protects recently modified targets:

- recently modified project artifacts are treated as recent for 7 days
- protected vendor and build-output heuristics prevent broad accidental deletions
- nested artifacts are filtered to avoid duplicate or parent-child over-deletion

Developer-cache cleanup preserves toolchains and other high-value state. Examples intentionally left alone include:

- `~/.cargo/bin`
- `~/.rustup`
- `~/.mix/archives`
- `~/.stack/programs`

## Protected Categories

Protected or conservatively handled categories include:

- system components such as Control Center, System Settings, TCC, Spotlight, and `/Library/Updates`
- password managers and keychain-related data
- VPN / proxy tools such as Shadowsocks, V2Ray, Clash, and Tailscale
- AI tools in generic protected-data logic, including Cursor, Claude, ChatGPT, and Ollama
- `~/Library/Messages/Attachments`
- browser history and cookies
- Time Machine data while backup state is active or ambiguous
- `com.apple.*` LaunchAgents and LaunchDaemons

## Analyzer

`mo analyze` is intentionally lower-risk than cleanup flows:

- it does not require sudo
- it respects normal user permissions and SIP
- interactive deletion requires an extra confirmation sequence
- deletions route through Trash/Finder behavior rather than direct permanent removal

Code lives under `cmd/analyze/*.go`.

## Timeouts and Hang Resistance

`lib/core/timeout.sh` uses this fallback order:

1. `gtimeout` / `timeout`
2. a Perl helper with process-group cleanup
3. a shell fallback

Current notable timeouts in security-relevant paths:

- orphan/Spotlight `mdfind` checks: 2s
- LaunchServices rebuild during uninstall: 10s / 15s bounded steps
- Homebrew uninstall cask flow: 300s default, extended to 600s or 900s for large apps
- Application Support sizing: direct file `stat`, bounded `du` for directories

Additional safety behavior:

- `brew_uninstall_cask()` treats exit code `124` as timeout failure and returns failure immediately
- font cache rebuild is skipped while browsers are running
- project-cache discovery and scans use strict timeouts to avoid whole-home stalls

## User Configuration

Protected paths can be added to `~/.config/mole/whitelist`, one path per line.

Example:

```bash
/Users/me/important-cache
~/Library/Application Support/MyApp
```

Exact path protection is preferred over pattern-style broad deletion rules.

Use `--dry-run` before destructive operations when validating new cleanup behavior.

## Testing

There is no dedicated `tests/security.bats`. Security-relevant behavior is covered by targeted BATS suites, including:

- `tests/clean_core.bats`
- `tests/clean_user_core.bats`
- `tests/clean_dev_caches.bats`
- `tests/clean_system_maintenance.bats`
- `tests/clean_apps.bats`
- `tests/purge.bats`
- `tests/core_safe_functions.bats`
- `tests/optimize.bats`

Local verification used for the current branch includes:

```bash
bats tests/clean_core.bats tests/clean_user_core.bats tests/clean_dev_caches.bats tests/clean_system_maintenance.bats tests/purge.bats tests/core_safe_functions.bats tests/clean_apps.bats tests/optimize.bats
bash -n lib/core/base.sh lib/clean/apps.sh tests/clean_apps.bats tests/optimize.bats
```

CI additionally runs shell and Go validation on push.

## Dependencies

Primary Go dependencies are pinned in `go.mod`, including:

- `github.com/charmbracelet/bubbletea v1.3.10`
- `github.com/charmbracelet/lipgloss v1.1.0`
- `github.com/shirou/gopsutil/v4 v4.26.2`
- `github.com/cespare/xxhash/v2 v2.3.0`

System tooling relies mainly on Apple-provided binaries and standard macOS utilities such as:

- `tmutil`
- `diskutil`
- `plutil`
- `launchctl`
- `osascript`
- `find`
- `stat`

Dependency vulnerability status should be checked separately from this document.

## Limitations

- Cleanup is destructive. There is no undo.
- Generic orphan data waits 30 days before automatic cleanup.
- Claude VM orphan cleanup waits 7 days before automatic cleanup.
- Time Machine safety windows are hour-based, not day-based, and remain more conservative.
- Localized app names may still be missed in some heuristic paths, though bundle IDs are preferred where available.
- Users who want immediate removal of app data should use explicit uninstall flows rather than waiting for orphan cleanup.
