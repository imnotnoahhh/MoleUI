# Mole Agent Guide

This file is the shared source of truth for any AI agent working on this repo (Claude Code, Codex, etc.). `CLAUDE.md` is a symlink to this file. Put machine-specific or personal overrides in `AGENTS.local.md` / `CLAUDE.local.md`; both are gitignored.

## Project

Mole is a macOS system cleanup and optimization tool with shell and Go components. It performs file cleanup, app protection checks, and maintenance tasks, so safety rules matter more than speed.

## Product Direction

Mole is a terminal-first macOS maintenance toolkit. Its core job is to help power users inspect reclaimable space, remove known-safe leftovers, uninstall apps safely, run bounded maintenance, and check health from a CLI, script, or compact TUI. It is not a general Mac control center, package manager, background monitor, or GUI feature mirror.

### What Mole Should Do

- Make cleanup and uninstall actions boring, reviewable, logged, protected by path/app rules, and dry-run capable.
- Prefer reversible user-facing removals through Trash where the command surface expects recoverability.
- Keep `clean`, `uninstall`, `purge`, and `installer` focused on reclaimable files, app leftovers, rebuildable caches, installer artifacts, and exact known cleanup targets.
- Keep `analyze` as a disk explorer and ad hoc cleanup surface. Optimize first paint, navigation, sorting, filtering, and safe deletion before adding dashboard-style features.
- Keep `status` as a compact read-only health dashboard plus stable JSON/NDJSON automation output. It may surface actionable signals, but should not become an iStat clone, alerting daemon, or configurable metrics workbench.
- Keep `optimize` focused on explicit, bounded maintenance tasks that can be explained before execution and tested without real authorization prompts.
- Keep command UX dense and terminal-native: short labels, stable alignment, predictable shortcuts, one-screen summaries, then optional drill-down.
- Keep Mole Mac references as a cross-link or support path. The CLI and Mac app can share product values without requiring feature parity.

### What Mole Should Not Do

- Do not add broad system modification, privacy reset, package management, app bundle patching, or device-management features just because they are technically possible.
- Do not remove or rewrite third-party app bundle contents, signed resources, user documents, credentials, sessions, active databases, or active developer-tool state.
- Do not add background agents, persistent monitoring, notifications, schedulers, menu bar behavior, or GUI-like state unless explicitly requested and justified as CLI scope.
- Do not broaden leftover matching from exact app or bundle evidence into vendor-wide, TeamID-prefix, generic-name, or fallback wildcard deletion.
- Do not turn `status` into a noisy dashboard. Extra rows, live alerts, and tuning controls need a common user action, not just an available metric.
- Do not add prompts, preferences, or output modes to solve every edge case. Prefer quieter defaults, preview/read-only guidance, or declining unsupported operations.
- Do not treat Mole Mac features as required CLI gaps. The CLI should stay narrower, scriptable, and safety-first when parity would add complexity or ambiguity.

### Product Decision Filter

Before accepting a new feature, answer these questions in the PR, issue, or review notes when the fit is not obvious:

1. Does it clearly belong to cleanup, uninstall, analyze, optimize, status, purge, installer, update, completion, touchid, install, or remove?
2. Is it safe by default, previewable where destructive, testable without real auth, and explainable in one terminal screen?
3. Can the user verify what will change before Mole changes it?
4. Is the target data locally rebuildable, disposable, or backed by exact app/bundle evidence?
5. Would this be better as Mole Mac UI, documentation, a warning, or an explicit "not supported" answer?

If the answer is no or unclear, decline the feature, narrow it, or park it until the product value beats the added surface area.

## Repository Map

- `mole` - main shell entrypoint.
- `bin/` - command entry scripts such as clean, analyze, status, uninstall, purge, installer, completion, and touchid.
- `lib/core/` - shared shell safety, UI, file operations, operation logs, app protection logic, and centralized timeout constants (`timeouts.sh`).
- `lib/core/app_protection_data.sh` - readonly bundle ID and pattern arrays consumed by `app_protection.sh`. Data only, no logic.
- `lib/clean/` - cleanup flows.
- `lib/manage/` - whitelist and purge path management.
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
- Do not clean tiny macOS UI state just because it is rebuildable. Wallpaper previews, preference thumbnails, and similar cover/state caches can create visible blank or cloud-download UI while reclaiming only a few MB; keep them unless there is strong user value and a regression test.
- Homebrew cleanup must be preview-first. Show the exact `brew autoremove` candidates before removal, preserve dry-run behavior, and keep tests on mocked `brew`; do not let a cleanup path execute real package-manager removals in verification.
- Sudo gates must not treat typed password characters as "skip". Only an explicit skip key should skip privileged cleanup; direct typed input must proceed into the real sudo prompt and have a regression test.
- Long cleanup scans need both an overall wall-clock budget and inner-loop checkpoints. If a project/artifact scan times out, degrade to partial or skipped-slow-scan output instead of appearing hung.
- System-service orphan scans must parse plist `Program` / `ProgramArguments` values as absolute paths only. Use non-interactive sudo for unreadable root-owned plists when needed, reject PlistBuddy error text as data, and keep CI tests on `/Library/LaunchDaemons` rather than relying on `/Library/PrivilegedHelperTools`.
- Uninstall leftover expansion must stay exact and boring: bundle ID or app-name variants only, reject generic/common words, keep short-name floors, skip broad locations like `Preferences/ByHost`, and only remove helper remnants after the parent app is confirmed gone and protected-path checks pass.
- Preference repair and optimize cleanup must skip protected and whitelisted plists before attempting removal.
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

- Re-read the live issue or PR title, body, comments, state, labels, and author language before any public reply or closeout.
- Keep CLI issues and Mole Mac app issues separate. A fix in `mole-mac` does not imply a close in this CLI repo, and a CLI fix does not prove a Mac app issue is fixed unless the Mac app release path is verified.
- When closing a fixed bug or shipped feature, use project wording from the issue context and include the expected release path only when confirmed.
- If a fix is on `main` but not in a stable release, prefer telling CLI users to try `mo update --nightly` now, then mention the next stable release only when that path is confirmed.

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

Format follows the recent compact release pages: centered Mole header, English `Changelog`, Chinese `更新日志`, optional `Mole Mac App` cross-link, then a short `Thanks 💖` line for issue reporters and PR contributors in this cycle. Do not add sponsor lists by default. Order changelog items by user-perceived impact, not chronological commit order.

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
- **CI runners lack `/Library/PrivilegedHelperTools`**: `clean_orphaned_system_services` guards that scan with `[[ -d /Library/PrivilegedHelperTools ]]`, which is false on GitHub macOS runners, so a test that feeds an orphan helper through that path finds zero orphans in CI even though it passes locally (the dir exists on dev machines). Route orphan-service tests through `/Library/LaunchDaemons`, which always exists on macOS. Hit fixing #1082.
- **A test can pass vacuously when the function early-returns**: `clean_apps.bats` `setup_file` exports `MOLE_TEST_MODE=1`, and `clean_orphaned_system_services` returns immediately under that flag, leaving `$output` empty. A test whose *last* assertion is a `[[ "$output" != *"..."* ]]` (true on empty) then passes green while its real `==` assertion in the middle is silently swallowed (same shape as #886). Always end each assertion with `|| return 1`, and override `MOLE_TEST_MODE=0` (plus a `sudo -n true` mock) when the test needs the function body to actually run.
- **`gh release create` conflicts with the workflow-created release**: the workflow already creates the release on tag push, so post-tag note publishing must use `gh release edit`, never `create`.
- **Tag prefix is case-sensitive**: `release.yml` filters on `'V*'`. A lowercase `v1.38.0` tag will not trigger the workflow.

### Release-notes craft

- **Order items by user-perceived impact, not commit chronology**. The headline change goes first; internal safety hardening, performance, and bug fixes follow.
- **Verify every mentioned command still exists in HEAD before listing it**. `mo check / mo doctor` was removed in the same release cycle that I almost shipped notes claiming it as a feature.
- **Pick icons that match the action, not the category**. A broom (🧹) on insight rows mis-signalled "all of these are safe to delete", which is wrong for iOS Backups, Xcode Archives, and Old Downloads. Eyes (👀) match "look here" without that false promise.
- **No em dash anywhere in user-facing text**. Use commas, periods, colons, or semicolons. (Global rule, but worth re-stating because it has been violated repeatedly in release drafts.)
- **No parenthesised PR refs or thanks inline**. Move PR numbers and contributor handles to a single closing thanks block to keep the changelog scannable.
