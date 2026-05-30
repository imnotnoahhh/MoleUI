# Mole Agent Guide

This file is the shared source of truth for any AI agent working on this repo (Claude Code, Codex, etc.). `CLAUDE.md` is a symlink to this file. Put machine-specific or personal overrides in `AGENTS.local.md` / `CLAUDE.local.md`; both are gitignored.

## Project

Mole is a macOS system cleanup and optimization tool with shell and Go components. It performs file cleanup, app protection checks, and maintenance tasks, so safety rules matter more than speed.

## Repository Map

- `mole` - main shell entrypoint.
- `bin/` - command entry scripts such as clean, analyze, status, uninstall, purge, installer, completion, and touchid.
- `lib/core/` - shared shell safety, UI, file operations, operation logs, app protection logic, and centralized timeout constants (`timeouts.sh`).
- `lib/core/app_protection_data.sh` - readonly bundle ID and pattern arrays consumed by `app_protection.sh`. Data only, no logic.
- `lib/clean/` - cleanup flows.
- `lib/manage/` - whitelist, update, autofix, and purge path management.
- `lib/optimize/` - optimization tasks.
- `lib/check/` - health, diagnostics, and dev environment checks.
- `lib/uninstall/` - app uninstall flows and package-manager removal helpers.
- `lib/ui/` - reusable menus and app selectors.
- `cmd/analyze/` - Go disk-analysis TUI. `main.go` is bootstrap only; `model.go` holds types and accessor methods; `update.go` holds the Bubble Tea Update chain.
- `cmd/status/` - Go status dashboard.
- `tests/` - Bats and shell test coverage. `tests/fuzz_corpus/` holds property-test corpora consumed by `path_validation_fuzz.bats`.
- `scripts/` - check, test, build, and release helpers. `audit_bundle_drift.sh` backs the monthly bundle audit; per-PR perf is covered by `tests/core_performance.bats`.
- `docs/SECURITY_DESIGN.md` - design doc for the path validation / app protection / # SAFE annotation contract.
- `SECURITY_AUDIT.md` - security review notes.

## Commands

```bash
./scripts/check.sh --format
MOLE_TEST_NO_AUTH=1 ./scripts/test.sh
MOLE_TEST_NO_AUTH=1 bats tests/clean_core.bats
MOLE_DRY_RUN=1 ./mole clean
MOLE_TEST_NO_AUTH=1 ./mole clean --dry-run
MOLE_TEST_NO_AUTH=1 ./mole purge --dry-run
MOLE_TEST_NO_AUTH=1 ./mole installer --dry-run
find bin lib -name '*.sh' -print0 | xargs -0 -n1 bash -n
make build
go test ./...
```

Public docs and examples should prefer the installed `mo` command. Use `./mole` in this repository when verifying source-tree behavior before installation. `analyze` and `analyse` are both accepted command spellings.

## Critical Safety Rules

- Never use raw `rm -rf` or `find -delete`; use safe deletion helpers.
- Use `mole_delete` from `lib/core/file_ops.sh` for removals so Trash routing, operation logs, dry-run behavior, and path protection stay consistent.
- Never modify protected paths such as `/System`, `/Library/Apple`, or `com.apple.*`.
- Route user-facing cleanup through Trash where the project expects recoverability, especially for analyze-driven ad hoc cleanup.
- Never let verification block on sudo, AppleScript, or macOS authorization prompts unless the task explicitly targets auth behavior.
- Use `MOLE_DRY_RUN=1` before destructive cleanup flows.
- Use `MOLE_TEST_NO_AUTH=1` for tests, manual repro, and verification unless real auth behavior is being tested.
- Any new direct use of `sudo`, `osascript`, or `launchctl` must have a `MOLE_TEST_MODE` / `MOLE_TEST_NO_AUTH` guard or be fully mocked in tests.
- Do not change ESC timeout behavior in `lib/core/ui.sh` unless explicitly requested.
- Preserve operation logging to the project log path unless the user explicitly asks to change `MO_NO_OPLOG` behavior.
- **AI-generated PRs touching destructive sinks need line-by-line review.** Any PR touching `find_app_files`, `mole_delete`, `remove_file_list`, Group Container / `~/Library/Containers` traversal, `TeamID.*.prefix*` style wildcards, or any `find` recursion that ends in deletion must be audited per branch (fallback branches often regress to broad globs even when the primary branch looks correct), per protected-path coverage (does `should_protect_path` already include the new entry point?), and per user-confirmation step (does the PR silently skip an existing prompt?). When the PR is plausibly AI-generated, raise the bar: ask the contributor to narrow matchers to the exact bundle ID or app path before merge; do not approve "this looks fine." PR #874 (Group Container + diagnostic discovery) and PR #875 (interactive file selector) were merged and then reverted (`6ea1987`, `b4e9205`) precisely because a TeamID-prefix wildcard in a fallback branch matched far more than intended. Same shape, same revert risk.

## Working Rules

- Use helpers from `lib/core/file_ops.sh` for deletion logic.
- Check `should_protect_path()` before adding cleanup behavior.
- Check app protection helpers before adding app cache, uninstall, or leftover cleanup behavior.
- Keep AI-tool cache cleanup conservative. Claude Code, opencode, Copilot CLI, Zed, Warp, Ghostty, and similar developer tools may have active versions, config, credentials, or session state that must not be removed accidentally.
- Keep shell code formatted with `./scripts/check.sh --format`.
- Prefer targeted Bats tests during development; run the full suite before committing.
- Do not add AI attribution trailers to commits.
- `start_section` / `end_section` / `note_activity` have three intentionally different implementations in `lib/core/base.sh`, `bin/clean.sh`, and `bin/purge.sh`. Source order decides which one wins, and the wording, color, and dry-run export semantics differ on purpose. Read the cross-reference comment in `lib/core/base.sh` before changing any of them.
- **Test-orphan pattern: grep the whole repo including top-level entry scripts before declaring a function dead.** Mole has a recurring shape where a helper is defined in `lib/core/base.sh` (or similar core lib), has full bats coverage in `tests/`, and is referenced by zero production callers. Known instances: `is_sip_enabled`, `is_darwin_ge`, `get_invoking_user`, `get_brand_name`, `get_mole_temp_root`, `scan_external_volumes`, `clean_dev_editors`, `perform_updates`, `format_brew_update_label`, `brew_has_outdated`. A "zero callers" verdict requires three checks: (1) grep across `lib`, `bin`, `cmd`, `scripts`, `tests`, AND the top-level entry (`mole` shim, install/uninstall scripts), not just core lib dirs; (2) check for string-built call sites (`eval`, `declare -f`, `compgen`); (3) re-grep after removal to confirm nothing was hand-wired. When deleting a write-only helper, also trace every variable it wrote and every config it read; the entire data path may be orphaned. Sub-agent "dead code" reports are starting points, not verdicts.

## Hotspot Ownership

These files are intentionally large. Do not start by splitting them. Keep edits narrow, preserve local safety boundaries, and run the listed tests when touching each area.

- `lib/clean/user.sh` owns user-level cleanup flows, browser caches, cloud/app support cleanup, device firmware, and Apple Silicon caches. Run `MOLE_TEST_NO_AUTH=1 bats tests/clean_user_core.bats tests/clean_app_caches.bats tests/clean_cached_device_firmware.bats` when touching this area, or `MOLE_TEST_NO_AUTH=1 ./scripts/test.sh` if behavior crosses sections.
- `lib/core/app_protection.sh` owns uninstall/data/path protection policy and bundle matching; `lib/core/app_protection_data.sh` owns the protected app category lists. Run `MOLE_TEST_NO_AUTH=1 bats tests/uninstall_safety.bats tests/uninstall_naming_variants.bats tests/bundle_resolver.bats`.
- `lib/clean/project.sh` owns purge discovery, project artifact filtering, purge menus, and purge config. Run `MOLE_TEST_NO_AUTH=1 bats tests/purge.bats tests/purge_config_paths.bats`.
- `bin/uninstall.sh` owns uninstall command orchestration, app inventory, metadata refresh, and list/json output. Run `MOLE_TEST_NO_AUTH=1 bats tests/uninstall.bats tests/uninstall_scan_bash32.bats`.
- `lib/clean/dev.sh` owns developer-tool cleanup, language/toolchain caches, AI agent caches, and Codex runtime handling. Run `MOLE_TEST_NO_AUTH=1 bats tests/clean_dev_caches.bats tests/dev_extended.bats`.
- `lib/optimize/tasks.sh` owns optimize task registration and system maintenance actions. Run `MOLE_TEST_NO_AUTH=1 bats tests/optimize.bats tests/optimize_db.bats`.
- `bin/clean.sh` owns clean command orchestration, section output, and safe cleanup execution. Run `MOLE_TEST_NO_AUTH=1 bats tests/clean_core.bats tests/clean_apps.bats tests/cli.bats`.
- `cmd/analyze/update.go` owns the Bubble Tea `Update` chain and message handlers (Init, scanCmd, updateKey, goBack, switchToOverviewMode, enterSelectedDir). This is the largest file in `cmd/analyze/` and the natural landing spot for new key bindings, message types, or navigation behavior. Run `go test ./cmd/analyze`. `cmd/analyze/main.go` is bootstrap only (flag parsing, `main()`, helpers); `cmd/analyze/model.go` holds types and the model struct.
- `cmd/analyze/analyze_test.go` and `cmd/status/view_test.go` are test hotspots. Add new cases near related behavior; split later only when touching many adjacent cases. Run `go test ./cmd/...`.

## Command Surface

- `mo clean` - deep cleanup and leftovers for apps that are already gone.
- `mo uninstall` - remove installed apps and related leftovers.
- `mo optimize` - maintenance and diagnostics, with `--whitelist` support.
- `mo analyze` / `mo analyse` - Go disk explorer; safer for ad hoc cleanup because it uses Trash routing.
- `mo status` - live health dashboard and JSON output for automation.
- `mo purge` - project build artifact cleanup, with configurable scan paths through `mo purge --paths`.
- `mo installer` - installer-file discovery and cleanup.
- `mo completion`, `mo touchid`, `mo update`, and `mo remove` manage shell integration, sudo auth convenience, updates, and uninstalling Mole itself.

## Verification

- Shell changes: run `./scripts/check.sh --format`, then the relevant Bats test or `MOLE_TEST_NO_AUTH=1 ./scripts/test.sh`.
- Go changes: run `go test ./...`.
- Cleanup behavior: verify with dry-run or test mode first.
- File operation changes: run `MOLE_TEST_NO_AUTH=1 bats tests/file_ops_mole_delete.bats tests/user_file_ops.bats`.
- Installer changes: run `MOLE_TEST_NO_AUTH=1 bats tests/installer.bats tests/installer_fd.bats tests/installer_zip.bats`.
- Purge changes: run `MOLE_TEST_NO_AUTH=1 bats tests/purge.bats tests/purge_config_paths.bats`.
- Whitelist or management changes: run `MOLE_TEST_NO_AUTH=1 bats tests/manage_whitelist.bats tests/manage_sudo.bats`.
- Uninstall changes: run `MOLE_TEST_NO_AUTH=1 bats tests/uninstall.bats tests/uninstall_remove_file_list.bats`.
- Documentation-only changes: check links and commands.

`make check`, `make format`, `make test`, `make test-go`, and `make verify` are wrappers around the scripts above. `make verify` intentionally runs `check` plus Go tests only; use the full Bats suite before risky cleanup, uninstall, or release work.

If `golangci-lint` reports issues from deleted temporary worktrees or non-existent paths, clear its local cache and rerun the linter:

```bash
golangci-lint cache clean
golangci-lint run ./cmd/...
```

## GitHub Operations

- When closing a fixed bug or shipped feature, use project wording from the issue context and include the expected release path only when confirmed.

## Release

Tag-driven flow. The `release.yml` workflow watches `'V*'` tag pushes (capital `V`), builds amd64 and arm64 binaries on macOS, generates `SHA256SUMS`, attaches build provenance, creates the GitHub Release without notes, then bumps the personal Homebrew tap and opens a Homebrew core PR.

### Pre-flight checklist

1. `grep '^VERSION=' mole` matches the new version.
2. `SECURITY_AUDIT.md` opening line reflects the new version and date.
3. `git status -s` is empty or only contains intentionally staged release work.
4. `git log origin/main..HEAD --oneline` shows only commits you intend to ship.
5. `./scripts/check.sh --format` and `MOLE_TEST_NO_AUTH=1 MOLE_TEST_JOBS=2 BATS_FORMATTER=tap ./scripts/test.sh` both exit 0.
6. `go test ./cmd/...` and `make build` both pass.

### Tag and publish

```bash
git push origin main
git tag V<version>          # capital V; release workflow ignores lowercase v
git push origin V<version>
```

Wait for the workflow to finish (typically 2 minutes for V1.38.0). The workflow creates the release with assets but `generate_release_notes: false`, so notes must be added in a follow-up step.

### Apply curated release notes

```bash
gh release edit V<version> --repo tw93/Mole \
  --title "V<version> <CodeName> <emoji>" \
  --notes-file <path>
```

Format follows V1.37.0 onward: bilingual numbered changelog (English first, 中文 second), then a `Thanks 💖` block with sponsors and contributors, ending with the repo blockquote link. Order changelog items by user-perceived impact, not chronological commit order.

Recent sponsors via `gh api graphql`:

```bash
gh api graphql -f query='{user(login:"tw93"){sponsorshipsAsMaintainer(first:30, orderBy:{field:CREATED_AT, direction:DESC}){nodes{sponsorEntity{... on User{login} ... on Organization{login}}}}}}'
```

The minimal query above works on a token without `read:user` scope. Adding `createdAt` or `privacyLevel` requires `read:user`.

Add the standard reaction set (`+1`, `laugh`, `hooray`, `heart`, `rocket`, `eyes`):

```bash
RELEASE_ID=$(gh api repos/tw93/Mole/releases/tags/V<version> --jq '.id')
for r in +1 laugh hooray heart rocket eyes; do
  gh api "repos/tw93/Mole/releases/$RELEASE_ID/reactions" -X POST -f content="$r" --silent
done
```

### Shell and release pitfalls (cumulative)

These are real bugs hit on this codebase. Each one cost time. Re-read before touching the same area.

- **bash 3.2 nounset on empty arrays**: macOS default bash raises "unbound variable" when expanding `"${arr[@]}"` on an empty array under `set -u`. Always guard with `[[ ${#arr[@]} -gt 0 ]]` before expansion. Hit in `lib/manage/whitelist.sh` for `DEFAULT_OPTIMIZE_WHITELIST_PATTERNS=()`.
- **`[[ -n "$var" ]] && cmd` returns 1 when var is empty**: under `set -e` (or any caller that reads the exit code), this short-circuit form propagates exit 1 from the test, even though the intent was "skip silently". If the surrounding compound command relies on exit 0 (for example a `{...} > file ||` redirect), the optional cmd silently breaks the success path. Use plain `if/fi` whenever the conditional sits inside an exit-code-sensitive block. Hit in `install.sh` `write_install_channel_metadata` (stable channel always tripped the warning).
- **bats heredoc steals bytes from `read -n1`**: when the inner script runs via `bash <<'EOF' ... EOF`, a `read -r -s -n1` in the function under test consumes the next byte from the heredoc source itself, corrupting the next command (e.g. `echo` becomes `cho`, exit 127). Fix is to redirect the function's stdin from `/dev/null` inside the test.
- **`run_with_timeout` execs the binary, bypassing bash function mocks**: gtimeout/timeout exec the real PATH binary, so a shell-function override of (e.g.) `osascript` is invisible. Tests must use a PATH stub directory and prepend it to `PATH`, not function shadowing.
- **`gh release create` conflicts with the workflow-created release**: the workflow already creates the release on tag push, so post-tag note publishing must use `gh release edit`, never `create`.
- **Tag prefix is case-sensitive**: `release.yml` filters on `'V*'`. A lowercase `v1.38.0` tag will not trigger the workflow.

### Release-notes craft

- **Order items by user-perceived impact, not commit chronology**. The headline change goes first; internal safety hardening, performance, and bug fixes follow.
- **Verify every mentioned command still exists in HEAD before listing it**. `mo check / mo doctor` was removed in the same release cycle that I almost shipped notes claiming it as a feature.
- **Pick icons that match the action, not the category**. A broom (🧹) on insight rows mis-signalled "all of these are safe to delete", which is wrong for iOS Backups, Xcode Archives, and Old Downloads. Eyes (👀) match "look here" without that false promise.
- **No em dash anywhere in user-facing text**. Use commas, periods, colons, or semicolons. (Global rule, but worth re-stating because it has been violated repeatedly in release drafts.)
- **No parenthesised PR refs or thanks inline**. Move PR numbers and contributor handles to a single closing thanks block to keep the changelog scannable.
