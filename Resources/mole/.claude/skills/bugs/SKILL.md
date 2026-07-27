---
name: bugs
description: "Mole's own defect catalog, mined from 656 fix commits: the eleven bug shapes that actually recur in this repo, the grep probe that surfaces each, and the guard that keeps it from coming back. Read before reviewing a diff, auditing an area, debugging a report, or accepting a contributed PR in this repo."
---

# Mole bug patterns

What 2689 commits of history say about where this codebase actually breaks. Use it as the catalog; the generic sweep workflow lives in the global `bugscan` skill, root-causing a live symptom lives in `hunt`. This file is the part that is specific to Mole.

## What the history measures

Run these to refresh the numbers before trusting them:

```bash
git log --oneline | wc -l                                    # 2689 commits
git log --pretty=format:%s --grep='^fix' -i | wc -l          # 656 fix-flavored
git log --pretty=format:%s --grep='^fix' -i | grep -cE '#[0-9]{3,4}'   # 159 cite an issue/PR
```

Three facts that should shape how you work here:

- **Most fixes were not reported by a user.** Only about a quarter of fix commits cite an issue or PR. The rest came out of review passes, release audits, and sibling sweeps after another fix. Waiting for a report is not the operating mode.
- **A fix ships with a guard.** 215 of the 300 most recent fix commits touch `tests/` or a `_test.go` in the same commit. A patch with no test is off-pattern for this repo.
- **The dominant defect is not a crash.** It is a path deleted on weak evidence, a number that disagrees with another number computed elsewhere, or a scan that looks hung while it is merely unbounded. Nothing throws. So the productive question is never "can this crash", it is:

  > What does this produce when the probe is denied, the app is installed in a place the probe does not look, the machine is slow but healthy, or the cache was written by the previous release?

## The eleven archetypes

Ranked by how often they recur. Walk the ones the area touches and write down present / absent / unsure for each. "Absent" is a result worth reporting.

| # | Shape | Probe | Evidence |
|---|---|---|---|
| 1 | Deletion candidate built from a weak name signal | grep name-derived globs | `3fa3eb5c` `5498edd1` `ec1cd647` `229bd0f9` |
| 2 | Existence decided by a single probe | grep `mdfind` / `command -v` / `pgrep` as sole gate | `6a055de4` `28ee58c9` `37a446c9` |
| 3 | Guard present on one branch only | diff dry-run branch against real branch | `cfe14601` `36f52a95` `8c781372` |
| 4 | Unbounded external command | grep the command, count `run_with_timeout` wraps | `edb214c0` `35d856f1` `63030e3a` |
| 5 | bash 3.2, errexit, pipefail semantics | grep array expansions and `fn \|\| handler` | `893b4e6f` `2c06cb91` |
| 6 | TTY, stdin, and process-group theft | grep background callers of `run_with_timeout` | `c93afca3` `63030e3a` |
| 7 | Parsing system command output | grep for missing `LC_ALL=C` and format assumptions | `4e83743b` `51b352a2` `f0896d03` |
| 8 | Stale persisted derived data | grep cache write sites, check schema and invalidation | `7a996aa5` |
| 9 | Two paths computing the same number differently | find every total, assert they agree | `3cbafed7` `7a996aa5` |
| 10 | Silence read as a freeze | walk each section for a >1s gap with no spinner | `8f064707` `c4258f5e` |
| 11 | Test that cannot fail | grep bare `[[ ]]` assertions, then verify red-green | `1b127787` `4db8a0d8` `20392444` |

### 1. Deletion candidate built from a weak name signal

The most expensive class in this repo, and the one that produced both reverts. A matcher derived from a display name, a bundle-id prefix, or a substring glob will eventually match a neighbour.

- `find_app_files` built `~/.config/<name>` from a GUI app's display name, so uninstalling Claude.app wiped the Claude Code CLI's entire state directory. Case-insensitive APFS widened it further (`3fa3eb5c`).
- A `${bundle_id}*.plist` glob matched sibling vendors: `com.foo` also matched `com.foobar.plist` (`5498edd1`).
- Downstream matchers are substring-based, so uninstalling `Foo.app` while `Foo-beta.app` survived still removed the survivor's launch agents (`ec1cd647`).
- A TeamID-prefix wildcard in a fallback branch is why PR #874 and #875 were merged and then reverted (`229bd0f9`, `bc7f4c0a`).

```bash
command grep -rnE '\*\$\{?(app_name|bundle_id|name)\}?\*|\$\{bundle_id\}\*' lib/ bin/
```

For every hit, name the narrowest evidence that authorizes the delete. Exact bundle id or exact app path passes. Vendor prefix, generic word, or fallback wildcard does not. Check the fallback branch separately: it regresses to a broad glob even when the primary branch looks correct.

### 2. Existence decided by a single probe

Every "is this app installed" and "is this service active" question in this repo has been wrong at least once because it asked exactly one source.

- `mdfind` alone misses Homebrew casks with no metadata importer and never indexes SMJobBless helpers embedded under `Contents/Library/LaunchServices` (`6a055de4`).
- `command -v` plus a LaunchAgents grep only covers CLI-style owners, so `~/.bridge` was flagged orphan while Proton Mail Bridge.app was installed (`28ee58c9`).
- Any UP `utun*` interface read as "VPN active" flagged every Mac with iCloud Private Relay (`37a446c9`).

```bash
command grep -rn 'mdfind' lib/ bin/ | command grep -v run_with_timeout
```

The method: for each predicate, list every way the subject can legitimately exist, then check the probe sees all of them. Slow Spotlight is a timeout, not an absence; treat a timed-out probe as unknown and fall back to the filesystem rather than concluding "not installed".

### 3. Guard present on one branch only

Protection that lives at the call site instead of in the funnel will be missing from the next call site.

- `should_protect_path` ran only inside the real-clean branch, so `--dry-run` promised to remove files the real run silently skipped (`cfe14601`).
- The user whitelist was consulted per caller, so `clean_user_caches` simply forgot it. The fix hoisted the check into `safe_find_delete` and `safe_sudo_find_delete` next to the existing protection gate, so future callers get it for free (`5498edd1`).
- A Raycast v2 exclusion existed in one place but not in the `find` predicates that actually ran (`452e194d`).

The method: enumerate every caller of each protection helper, then every deletion site, and diff the two lists. The gap is the bug. Then check dry-run and real paths compute the same verdict, and prefer moving the guard into `validate_path_for_deletion` / `should_protect_path` over adding a fourth call site.

### 4. Unbounded external command

`du`, `mdfind`, `find`, `xcrun simctl`, and `brew` have no internal bound, and the caller usually pipes them into a command substitution that just waits. One stalled SMB mount wedges the whole scan.

All 19 real `du -s` sites are wrapped today, and `tests/core_timeout.bats` pins that with a source-invariant test so a new sizing site cannot regress it. Copy that shape for any new unbounded command.

Two subtler variants:

- **Checkpoint at the wrong nesting level.** `probe_project_artifact_hints` checked its deadline at the top of each root but not inside the nested-subdirectory loop, so once an iteration was entered it ran up to 120 more times past the budget. Every loop level needs its own checkpoint, not just the outer one (`edb214c0`).
- **A timeout tuned on a warm machine.** CoreSimulatorService takes over 2s on cold boot, so a 2s probe reported "simctl not available" (`35d856f1`). For each constant, name the slowest healthy case and check the constant clears it.

```bash
for c in 'du -s' mdfind xcrun system_profiler ioreg brew; do
  printf '%-16s total=%-4s wrapped=%s\n' "$c" \
    "$(command grep -rn -- "$c" lib/ bin/ | wc -l | tr -d ' ')" \
    "$(command grep -rn -- "$c" lib/ bin/ | command grep -c run_with_timeout)"
done
```

### 5. bash 3.2, errexit, pipefail semantics

macOS ships bash 3.2.57 and the shipped code runs under `set -u`. Sixteen fixes are pure shell semantics. The cumulative list lives in `AGENTS.md` under "Shell and Test Pitfalls"; read it rather than duplicating it here. The two highest-frequency shapes:

- **Empty array expansion under nounset.** `"${arr[@]}"` on an empty array aborts. When it aborts inside a scan, the spinner subshell is orphaned and the user sees "scanning forever" (`893b4e6f`, `2c06cb91`). Guard with `[[ ${#arr[@]} -gt 0 ]]`.
- **`fn || handler` disables errexit inside `fn` for its whole body**, converting every unchecked failure into a no-op. That is how eight consecutive failed copies still reported a successful install. Safety-critical steps use explicit `if ! cmd; then return 1; fi`.

```bash
command grep -rn '\$\{[a-z_]*\[@\]\}' lib/ bin/ | wc -l   # 317 sites; spot-check new ones
```

### 6. TTY, stdin, and process-group theft

Background workers that never need the terminal keep stealing it.

- The perl timeout fallback hands the controlling terminal to its child whenever stdin is a tty. A background metadata-refresh worker still holding the tty stole the foreground process group, so `mo uninstall` stopped with SIGTTIN at the confirmation prompt (`c93afca3`).
- BSD `mv`/`cp` prompt on stderr and read stdin when the destination exists and is not writable, so the UI froze on a `getchar()` with the spinner pinned to "Updating cache..." (`63030e3a`).

The method: every background subshell, `&`, or disowned worker that calls `run_with_timeout` needs `< /dev/null`. Every command that can prompt needs stdin closed plus `-f`. Every trap installed by a menu or scan must save and restore the caller's traps (`lib/ui/menu_paginated.sh` is the reference implementation).

### 7. Parsing system command output

Fifty-plus commits. The output of a macOS tool is not a stable contract: it is localized, it drifts across OS releases, and its error text looks like data.

- Metric subprocesses inherited the user's locale, so comma-decimal locales broke process collection, then system-health rendering, then more metrics. The eventual fix forces `LC_ALL=C` for every metric subprocess rather than patching each parser (`51b352a2`, `fa05b8cc`, `4e83743b`). Note the shape: three separate reports before someone fixed the class.
- `DTSDKBuild` ("24A335") was compared as a version string where `DTPlatformVersion` ("15.0") was meant (`f0896d03`).
- PlistBuddy prints `File Doesn't Exist, Will Create:` to stdout, and that text has been accepted as data.
- On stock macOS, `grep -Z` means `--decompress`, so a `grep -rlZ | while read -d ''` loop shipped dead for months.

The method: force `LC_ALL=C` on anything parsed, validate the shape before trusting a field (absolute path, numeric, expected key present), reject error text as data, and prefer a structured signal (exit code, plist key) over re-parsing prose. Note that `grep` on a dev machine here may be ugrep-aliased; use `command grep` when flag behavior matters.

### 8. Stale persisted derived data

Changing how a cached value is computed without invalidating the cache means the fix is invisible and the old value keeps shipping.

`7a996aa5` is the model: the hardlink dedup fix bumped the cache schema to v2 to discard entries written before the change, and marked dedup-dependent subtrees non-cacheable so a standalone re-scan is not poisoned. The analyze cache has separately needed expiry, selective invalidation on delete, and a manual-refresh path that bypasses nested caches.

The method: for every cache, confirm it has a TTL, a schema version, and invalidation on each mutation that changes its inputs. When a fix changes a computed value, bump the schema in the same commit. When verifying any fix, confirm you are not reading last release's cache.

### 9. Two paths computing the same number differently

Any number rendered twice will eventually disagree: dry-run preview against the summary total, the item count against the raw target count, a subtree size against `du`, base-10 against base-2.

The method: locate every site that computes a given total and make one of them the definition. Then add a test that compares the two renderings rather than asserting a literal, which is what `tests/clean_core.bats` does for preview against summary totals. Sub-megabyte rounding to `0` and per-link counting of hardlinks are both in this family.

### 10. Silence read as a freeze

A hundred commits mention spinners, frozen terminals, or blank sections. The bug is almost never the work being slow; it is the work happening outside the spinner window.

The spinner was stopped at the start of the removal loop, so the terminal was silent for the full removal (`8f064707`). Dotdir, login-item, System Data, and large-file scans ran for seconds with no loading state, leaving the section blank.

The method: walk each section and ask whether every operation over roughly one second sits inside a spinner window, and whether the spinner stops immediately before the line it would otherwise paint over. Section output follows one fixed rhythm here: title, loading state, content, one trailing blank line. When touching any step, re-read the whole rendered output rather than the one step reported.

### 11. Test that cannot fail

The meta-bug. Several regression tests passed against the pre-fix code, so the fix was never actually pinned.

A non-final `[[ ]]` that returns non-zero does not fail the test; a non-final `[ ]` does. The bracket form decides it, which is why the same test can catch a crashed subshell through `[ "$status" -eq 0 ]` while every `[[ "$output" == ... ]]` above the last one is dead weight. Minimal repro, run it before trusting any assertion in this suite:

```bash
cat > tests/zz_min.bats <<'EOF'
@test "non-final [[ ]] false" { [[ 1 -eq 2 ]]; [[ 1 -eq 1 ]]; }
@test "non-final [ ] false"  { [ 1 -eq 2 ];  [ 1 -eq 1 ];  }
EOF
bats tests/zz_min.bats   # test 1 passes, test 2 fails
rm tests/zz_min.bats
```

There are currently **551** dead non-final `[[ ]]` assertions across 1119 tests, and **473** tests whose only bare gate is the final `[[ ]]`. Count them per test block, not per line: a line-level grep counts the final assertions too and overstates the problem.

Four other ways a test here has passed vacuously:

- `MOLE_TEST_MODE=1` (exported by `scripts/test.sh`) makes the function under test early-return, leaving `$output` empty, so a negative `!=` assertion is trivially true. Override to `0` and mock `sudo -n true` when the body must run.
- A shell-function mock puts the test in the wrong branch. Mocking `xcrun` as a function took the `declare -F xcrun` path, not the timeout-retry path where the fix lived. Use a PATH stub directory when the code under test execs the binary, because `run_with_timeout` execs and bypasses function mocks.
- A test inherited a previous test's cache through the shared `HOME`, so it validated a stale cache instead of a real scan.
- The asserted string does not exist. A Maven test asserted the absence of "Maven repository cache" when the real label is "Maven local repository", so it passed even if protection regressed.

The rule: end every assertion with `|| return 1`, include a positive control proving the negative assertions are not vacuous, and verify red-green by reverting the fix and watching the test fail.

## Three methods that produced most of the finds

1. **Diff two things that must agree.** Dry-run against real, preview total against summary total, cached against cold, first paint against refresh, the guard's caller list against the deletion-site list. Disagreement is mechanical to find and almost always a real defect.
2. **Enumerate call sites, not files.** Sweeping file by file finds far less than picking one helper (`should_protect_path`, `is_path_whitelisted`, `mole_delete`, `run_with_timeout`) and checking every site that should route through it.
3. **Turn the fix into a source invariant.** A one-off regression test pins one instance; a bats test that greps `lib/` and `bin/` pins the class. `tests/core_timeout.bats` (unbounded `du`) and the unsafe-`rm` scan in `.github/workflows/test.yml` are the two working examples. Prefer this whenever the bug is "someone will add another call site and forget".

## Verification bar

Never report a defect inferred from a function name or a file name. Grep the implementation. Confirm the code is production code: an unguarded call inside `#[cfg(test)]`, a bats fixture, a comment, or a string literal is not a defect.

```bash
./scripts/check.sh --format
MOLE_TEST_NO_AUTH=1 bats tests/<area>.bats
MOLE_TEST_NO_AUTH=1 ./scripts/test.sh
go test ./...
MOLE_DRY_RUN=1 ./mole clean
```

Per-area test targets are listed under "Hotspot Ownership" in `AGENTS.md`. Use those rather than guessing.

## Sibling sweep obligation

One archetype hit means sweep the repo for its signature. Every first pass over a pattern in this history under-counted, and the follow-up review always found more. Grep the shape, not the literal text, and report the count: checked N sites, M defective, K not applicable. A bug the maintainer has seen before ("this was fixed once already") ships with a guard, not just a patch.
