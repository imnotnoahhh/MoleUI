---
name: bugs
description: "Mole's project-specific incident catalog: twelve recurring bug shapes, grep probes, and regression guards. Use when a Mole symptom or diff touches destructive candidates or guards, uncertain discovery, bounded scans or TTY, Bash 3.2 or system parsing, stale derivations, inconsistent totals, silent progress, test validity, or refusal diagnostics. Not for generic review preflight, unrelated documentation or release-copy work, or other repositories."
---

# Mole bug patterns

Use this project-specific catalog after reading the current diff and code. Generic pattern sweeps belong to Waza `check` Pattern-Fix Completeness; root-causing a live symptom belongs to `hunt`.

Load only the archetypes signaled by the symptom or touched surface, then use their probes to sweep siblings. A whole-project audit should classify surfaces before opening sections instead of treating all twelve as a mandatory checklist. Read [references/shell-and-test-pitfalls.md](references/shell-and-test-pitfalls.md) only for Shell code, Bats tests, install/update flows, timeout wrappers, TTY handling, plist fixtures, or macOS-specific CI.

## How to use the catalog

- **Sweep siblings without waiting for another report.** One instance of a recurring shape is evidence to inspect every same-shape call site.
- **A fix ships with a guard.** Add a regression or source-invariant test that fails on the pre-fix code. Inspect current history only when a numerical trend matters to the decision.
- **The dominant defect is not a crash.** It is a path deleted on weak evidence, a number that disagrees with another number computed elsewhere, or a scan that looks hung while it is merely unbounded. Nothing throws. So the productive question is never "can this crash", it is:

  > What does this produce when the probe is denied, the app is installed in a place the probe does not look, the machine is slow but healthy, or the cache was written by the previous release?

## The twelve archetypes

Ranked by how often they recur. Walk the ones the area touches and write down present / absent / unsure for each. "Absent" is a result worth reporting.

| # | Shape | Probe | Evidence |
|---|---|---|---|
| 1 | Deletion candidate built from a weak name signal | grep name-derived globs | `3fa3eb5c` `5498edd1` `ec1cd647` `229bd0f9` |
| 2 | Existence decided by a single probe | grep `mdfind` / `command -v` / `pgrep` as sole gate | `6a055de4` `28ee58c9` `37a446c9` |
| 3 | Guard present on one branch only | diff dry-run branch against real branch | `cfe14601` `36f52a95` `8c781372` `3f42ad39` |
| 4 | Unbounded external command | grep the command, count `run_with_timeout` wraps | `edb214c0` `35d856f1` `63030e3a` |
| 5 | bash 3.2, errexit, pipefail semantics | grep array expansions and `fn \|\| handler` | `893b4e6f` `2c06cb91` `a33a0b51` |
| 6 | TTY, stdin, and process-group theft | grep background callers of `run_with_timeout` | `c93afca3` `63030e3a` |
| 7 | Parsing system command output | grep for missing `LC_ALL=C` and format assumptions | `4e83743b` `51b352a2` `f0896d03` |
| 8 | Stale persisted derived data | grep cache write sites, check schema and invalidation | `7a996aa5` |
| 9 | Two paths computing the same number differently | find every total, assert they agree | `3cbafed7` `7a996aa5` |
| 10 | Silence read as a freeze | walk each section for a >1s gap with no spinner | `8f064707` `c4258f5e` |
| 11 | Test that cannot fail | grep bare `[[ ]]` assertions, then verify red-green | `1b127787` `4db8a0d8` `20392444` |
| 12 | A gate that cannot say why it refused | count distinct `return 1` causes against distinct messages | `e2020772` `926c2efa` `46f5ba77` |

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
- A probe can carry side effects that outweigh its answer: `brew list mole` asked whether Homebrew owns the install, but brew's entry point resets the user's sudo timestamp, so the probe executed the pre-authed ticket and every update paid a second password prompt (`cb4a3d66`). When a filesystem fact answers the question (the Cellar directory), never run the tool. Then apply this archetype to the replacement: the first Cellar version checked only `HOMEBREW_PREFIX`, `/opt/homebrew`, and `/usr/local`, so a custom prefix that does not export the variable went undetected where the old query had found it (`73f89841`). Swapping a probe for a filesystem fact still owes you every legitimate location of that fact, which here means deriving the prefix from `command -v brew` as well; reading the path is not running the binary.

```bash
command grep -rn 'mdfind' lib/ bin/ | command grep -v run_with_timeout
```

The method: for each predicate, list every way the subject can legitimately exist, then check the probe sees all of them. Slow Spotlight is a timeout, not an absence; treat a timed-out probe as unknown and fall back to the filesystem rather than concluding "not installed".

### 3. Guard present on one branch only

Protection that lives at the call site instead of in the funnel will be missing from the next call site.

- `should_protect_path` ran only inside the real-clean branch, so `--dry-run` promised to remove files the real run silently skipped (`cfe14601`).
- The user whitelist was consulted per caller, so one `clean_*` function simply forgot it on a system sweep. The fix hoisted the check into `safe_find_delete` and `safe_sudo_find_delete` next to the existing protection gate, so future callers get it for free (`5498edd1`). The forgetful caller has since been renamed; the commit names it, and this line deliberately does not, because a dead symbol here reads as a stale catalog.
- A Raycast v2 exclusion existed in one place but not in the `find` predicates that actually ran (`452e194d`).
- `_safe_clean_impl` ran its delete guard only on the real branch, so dry-run previewed (and counted) items an active-process guard would refuse at the same moment. The guard must run after protected, whitelisted, compiled-cache, and missing targets are filtered, but before any preview registration; otherwise dry-run can report a stopped cleanup whose real candidate set is empty (`3f42ad39`).

The method: enumerate every caller of each protection helper, then every deletion site, and diff the two lists. The gap is the bug. Then check dry-run and real paths compute the same verdict, and prefer moving the guard into `validate_path_for_deletion` / `should_protect_path` over adding a fourth call site.

### 4. Unbounded external command

`du`, `mdfind`, `find`, `xcrun simctl`, and `brew` have no internal bound, and the caller usually pipes them into a command substitution that just waits. One stalled SMB mount wedges the whole scan.

Every production `du -s` site should route through the timeout wrapper. `tests/core_timeout.bats` pins that with a source-invariant test; copy the shape for any new unbounded command.

Installed-binary verification is the same class: every post-update `mo --version` or `"$mole_path" --version` probe must use `run_with_timeout` with `MOLE_TIMEOUT_QUICK_DETECT_SEC`, and standalone `install.sh` must use its bounded local wrapper for both `--version` and `--help`. A broken executable is exactly when a verification probe is most likely to hang. The update entrypoint also stays single-flight per install directory; otherwise one process can verify another process's metadata or binary generation. Standalone install and self-heal verification share the same target-adjacent `/usr/bin/lockf`; keep the kernel lock held by a parent-liveness-bound process instead of replacing it with a check-then-remove shell sequence.

Two subtler variants:

- **Checkpoint at the wrong nesting level.** `probe_project_artifact_hints` checked its deadline at the top of each root but not inside the nested-subdirectory loop, so once an iteration was entered it ran up to 120 more times past the budget. Every loop level needs its own checkpoint, not just the outer one (`edb214c0`).
- **A timeout tuned on a warm machine.** CoreSimulatorService takes over 2s on cold boot, so a 2s probe reported "simctl not available" (`35d856f1`). For each constant, name the slowest healthy case and check the constant clears it.
- **A bounded producer with an unbounded or status-blind consumer.** Wrapping `find` is not enough when process substitution adds `|| true`, hides status 124, and lets a deletion loop consume the partial prefix. Materialize the complete scan first, discard it on any nonzero status, then run the guarded delete pass. Bound the delete command too and propagate timeout/failure instead of returning a false success.
- **Probe and action use different eligibility plans.** A shallow `find -maxdepth 1` probe followed by a depth-5 delete does not authorize what the action reaches. Use one scan-to-delete helper, or make pattern, type, age, and depth identical and test the exact arguments.
- **The bound is on the right command but the slow stage is the consumer.** The lsregister dump finished in 2.3s; the bash parser behind it forked one command substitution per line and turned 250k lines into minutes, so the scan blew a 10s, then 30s, then 60s bound while every bump targeted the wrong stage. Before ever raising a timeout, time the producer and the consumer separately; a bash `while read` with `$(...)` per iteration over command output is minutes the moment the input is large, and belongs in one awk pass with the audited policy filter kept in bash over the survivors. Small bounded inputs (a directory listing, a plugin folder) are fine; a machine-wide dump is not.

```bash
for c in 'du -s' mdfind xcrun system_profiler ioreg brew; do
  printf '%-16s total=%-4s wrapped=%s\n' "$c" \
    "$(command grep -rn -- "$c" lib/ bin/ | wc -l | tr -d ' ')" \
    "$(command grep -rn -- "$c" lib/ bin/ | command grep -c run_with_timeout)"
done
```

### 5. bash 3.2, errexit, pipefail semantics

macOS ships bash 3.2.57 and the shipped code runs under `set -u`. Read [references/shell-and-test-pitfalls.md](references/shell-and-test-pitfalls.md) before changing Shell code, Bats tests, install/update flows, timeout wrappers, TTY handling, plist fixtures, or macOS-specific CI behavior. The two highest-frequency shapes:

- **Empty array expansion under nounset.** `"${arr[@]}"` on an empty array aborts. When it aborts inside a scan, the spinner subshell is orphaned and the user sees "scanning forever" (`893b4e6f`, `2c06cb91`). Guard with `[[ ${#arr[@]} -gt 0 ]]`.
- **`fn || handler` disables errexit inside `fn` for its whole body**, converting every unchecked failure into a no-op. That is how eight consecutive failed copies still reported a successful install. Safety-critical steps use explicit `if ! cmd; then return 1; fi`.
- **A graceful-skip path that only works because the caller's section window ran `set +e`.** `clean_orphaned_app_data` called `scan_installed_apps` bare, then read `$?`; under errexit the failing call aborts the shell before the skip message prints, and only the `set +e` window in `bin/clean.sh` masked it. Capture failures with explicit `if !` so degradation does not depend on the calling environment (`a33a0b51`).

```bash
command grep -rn '\$\{[a-z_]*\[@\]\}' lib/ bin/ | wc -l   # spot-check new sites
```

### 6. TTY, stdin, and process-group theft

Background workers that never need the terminal keep stealing it.

- The perl timeout fallback hands the controlling terminal to its child whenever stdin is a tty. A background metadata-refresh worker still holding the tty stole the foreground process group, so `mo uninstall` stopped with SIGTTIN at the confirmation prompt (`c93afca3`).
- BSD `mv`/`cp` prompt on stderr and read stdin when the destination exists and is not writable, so the UI froze on a `getchar()` with the spinner pinned to "Updating cache..." (`63030e3a`).

The method: every background subshell, `&`, or disowned worker that calls `run_with_timeout` needs `< /dev/null`. Every command that can prompt needs stdin closed plus `-f`. Every trap installed by a menu or scan must save and restore the caller's traps (`lib/ui/menu_paginated.sh` is the reference implementation).

### 7. Parsing system command output

The output of a macOS tool is not a stable contract: it is localized, it drifts across OS releases, and its error text looks like data.

- Metric subprocesses inherited the user's locale, so comma-decimal locales broke process collection, then system-health rendering, then more metrics. The eventual fix forces `LC_ALL=C` for every metric subprocess rather than patching each parser (`51b352a2`, `fa05b8cc`, `4e83743b`). Note the shape: three separate reports before someone fixed the class.
- `DTSDKBuild` ("24A335") was compared as a version string where `DTPlatformVersion` ("15.0") was meant (`f0896d03`).
- PlistBuddy prints `File Doesn't Exist, Will Create:` to stdout, and that text has been accepted as data.
- On stock macOS, `grep -Z` means `--decompress`, so a `grep -rlZ | while read -d ''` loop shipped dead for months.

The method: force `LC_ALL=C` on anything parsed, validate the shape before trusting a field (absolute path, numeric, expected key present), reject error text as data, and prefer a structured signal (exit code, plist key) over re-parsing prose. Note that `grep` on a dev machine here may be ugrep-aliased; use `command grep` when flag behavior matters.

### 8. Stale persisted derived data

Changing how a cached value is computed without invalidating the cache means the fix is invisible and the old value keeps shipping.

`7a996aa5` is the model: the hardlink dedup fix bumped the cache schema to v2 to discard entries written before the change, and marked dedup-dependent subtrees non-cacheable so a standalone re-scan is not poisoned. The analyze cache has separately needed expiry, selective invalidation on delete, and a manual-refresh path that bypasses nested caches.

The method: for every cache, confirm it has a TTL, a schema version, and invalidation on each mutation that changes its inputs. When a fix changes a computed value, bump the schema in the same commit. When verifying any fix, confirm you are not reading last release's cache.

A TTL proves "not too old". It never proves "complete", so check what the caller does with the answer. `pkg_receipt_nonstandard_app_paths --require-complete` feeds the shared-bundle-id sibling guard, which reads a complete answer as proof that no other install owns an app's leftovers; the cache short-circuit returned 0 without consulting `require_complete`, so a package installed after the last write stayed invisible for an hour and the guard cleared leftovers the survivor still needed (`b4f00651`). When a result is consumed as proof of absence, either bypass the cache for those callers or key it to a fingerprint of the evidence itself, so the entry dies the moment the evidence changes. That cache now stores a checksum of `pkgutil --pkgs` as a header: installing anything adds a receipt, which changes the fingerprint. Re-verifying each cached path still exists only filters entries that disappeared, never ones that appeared.

### 9. Two paths computing the same number differently

Any number rendered twice will eventually disagree: dry-run preview against the summary total, the item count against the raw target count, a subtree size against `du`, base-10 against base-2.

The method: locate every site that computes a given total and make one of them the definition. Then add a test that compares the two renderings rather than asserting a literal, which is what `tests/clean_core.bats` does for preview against summary totals. Sub-megabyte rounding to `0` and per-link counting of hardlinks are both in this family.

### 10. Silence read as a freeze

Silence is often mistaken for a freeze when slow work happens outside the spinner window.

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

Count ineffective assertions per test block, not per line: a line-level grep includes final assertions and overstates the problem. Treat any count as a live diagnostic, not durable project truth.

Four other ways a test here has passed vacuously:

- `MOLE_TEST_MODE=1` (exported by `scripts/test.sh`) makes the function under test early-return, leaving `$output` empty, so a negative `!=` assertion is trivially true. Override to `0` and mock `sudo -n true` when the body must run.
- A shell-function mock puts the test in the wrong branch. Mocking `xcrun` as a function took the `declare -F xcrun` path, not the timeout-retry path where the fix lived. Use a PATH stub directory when the code under test execs the binary, because `run_with_timeout` execs and bypasses function mocks.
- A timeout test checks elapsed time but accepts status 0, so the old "swallow 124 and continue" implementation still passes. Assert the exact nonzero status, prove partial output was discarded, and add a positive trace showing the production external-command branch ran.
- A test inherited a previous test's cache through the shared `HOME`, so it validated a stale cache instead of a real scan.
- The asserted string does not exist. A Maven test asserted the absence of "Maven repository cache" when the real label is "Maven local repository", so it passed even if protection regressed.

The rule: end every assertion with `|| return 1`, include a positive control proving the negative assertions are not vacuous, and verify red-green by reverting the fix and watching the test fail.

The mirror image is also a test defect, not a product bug. A case that fails in the full suite and passes in isolation is usually asserting a boundary the code never promised: `get_path_size_kb` was given a 1s budget and the test asserted `mdls` had run, but deadlines count in whole `SECONDS`, so that budget can collapse before the probe is spawned (`e95dd750`). A case can also fail on prose: a source-invariant test grepped `install.sh` for `brew list mole`, and the comment explaining why that call was removed read as the call coming back (`73f89841`). Before chasing a red run into production code, ask whether the assertion is timing-sensitive or is matching text outside the code path.

### 12. A gate that cannot say why it refused

A guard with many independent failure causes and one message. The user cannot act, and the maintainer cannot triage, so the report arrives as "it does not work" and the fix targets whichever wording was quoted.

`acquire_install_lock` refused for an untrusted ancestor, a denied `sudo -n`, an unusable lock directory, a lock path replaced by a symlink or fifo, a missing `/usr/bin/lockf`, and genuine contention. All printed one line about the lock being unavailable. Counting the causes is the probe, but do not quote the count here: it moves with every refactor, and a number this file cannot measure reads as rot the next time someone checks it. Three things followed, and each is worth checking for separately:

- **The reporter did the triage.** #1335 reverse-engineered `install_lock_has_unsafe_ancestor` by hand from the source to learn why a plain install failed.
- **A new gate silently downgraded an older diagnosis.** `d4a4b80c` already printed the actionable `Cache credentials first, then retry: sudo -v && mo update` for a missing admin session. `e2020772` put the lock in front of it, hit the same condition first, and reported it as a busy lock. Nothing failed; the diagnosis just got worse. When adding a gate ahead of an existing failure path, read what the old path said and keep the new one at least as actionable.
- **The test suite pinned the regression.** `926c2efa` replaced one catch-all string with another and added `grep -qF 'Could not acquire the Mole installation lock for'` as a source invariant, making the vague message a requirement. Pin reason codes, never a catch-all string.

Swallowed stderr is what hides this class during debugging: the privileged steps ran under `2> /dev/null`, so no run of the real command ever showed the underlying `sudo` error. Static reading went in circles until a differential probe (same code with and without a controlling terminal) isolated it in one run.

```bash
# Distinct failure causes vs distinct messages, per gate.
command grep -c 'return 1' install.sh
command grep -c 'log_error' install.sh
# Any privileged step whose stderr cannot reach the user.
command grep -rn 'sudo .*2> */dev/null' install.sh lib/
```

For each gate, list every reachable `return 1` and name the message and the remedy a user gets from it. Two causes sharing one message is the defect; a cause whose remedy is "reinstall" when reinstalling re-enters the same gate is the same defect wearing a fix.

## Three methods that produced most of the finds

1. **Diff two things that must agree.** Dry-run against real, preview total against summary total, cached against cold, first paint against refresh, the guard's caller list against the deletion-site list. Disagreement is mechanical to find and almost always a real defect.
2. **Enumerate call sites, not files.** Sweeping file by file finds far less than picking one helper (`should_protect_path`, `is_path_whitelisted`, `mole_delete`, `run_with_timeout`) and checking every site that should route through it.
3. **Turn the fix into a source invariant.** A one-off regression test pins one instance; a bats test that greps `lib/` and `bin/` pins the class. `tests/core_timeout.bats` (unbounded `du`) and the unsafe-`rm` scan in `.github/workflows/test.yml` are the two working examples. Prefer this whenever the bug is "someone will add another call site and forget".

## Verification bar

Never report a defect inferred from a function name or a file name. Grep the implementation. Confirm the code is production code: an unguarded call inside a bats fixture, a Go `_test.go` file, a comment, or a string literal is not a defect.

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
