# Shell and test pitfalls

Read this reference when changing Shell code, Bats tests, update/install flows, timeout wrappers, TTY handling, plist fixtures, or macOS-version-specific CI behavior. The defect classes and repo-wide probes stay in the parent `bugs` skill.

- **`BASH_SOURCE` / `$0` change meaning when a function moves files**: they name the file the code lives in, so copy-paste extraction is not behavior-preserving. `mole` captures `MOLE_ENTRY_SCRIPT="${BASH_SOURCE[0]}"` before sourcing anything, and update code reads that stable entrypoint. Before extracting a function, grep it for `BASH_SOURCE`, `$0`, and `FUNCNAME`. Regression coverage lives in `tests/update.bats`.
- **Every `du -s` must run under `run_with_timeout`**: one stalled mount can wedge the whole scan. Use `MOLE_TIMEOUT_DISK_VERIFY_SEC`. `tests/core_timeout.bats` pins the source invariant across `lib/` and `bin/`.
- **Bash 3.2 nounset rejects empty array expansion**: guard `"${arr[@]}"` with `[[ ${#arr[@]} -gt 0 ]]` under `set -u`.
- **`fn || handler` disables errexit inside `fn` for its whole body**: safety-critical steps must use explicit `if ! cmd; then return 1; fi` checks and installers must verify the installed binary's reported version before claiming success. `tests/install_checksum.bats` covers the exact caller shape.
- **`[[ -n "$var" ]] && cmd` returns 1 when the variable is empty**: inside exit-code-sensitive blocks, use `if/fi` so an optional action does not turn the block into failure.
- **Bats heredocs share stdin with `read -n1`**: an inner `read -r -s -n1` can consume the next byte of the heredoc source. Redirect the function under test from `/dev/null`.
- **macOS `script(1)` rejects socket-backed stdin**: PTY test helpers must redirect the wrapper's stdin from `/dev/null` or `script` can fail before starting the child.
- **`run_with_timeout` execs the binary and bypasses shell-function mocks**: tests must use a PATH stub directory for commands such as `osascript`.
- **CI runners may lack `/Library/PrivilegedHelperTools`**: orphan-service tests should exercise `/Library/LaunchDaemons`, which exists on GitHub macOS runners.
- **A test can pass vacuously after an early return**: `MOLE_TEST_MODE=1` can leave `$output` empty, and a final negative assertion then passes. End assertions with `|| return 1`, override test mode when the body must run, and add a positive control proving the output path executed. In an inner heredoc script use `|| exit 1`. Confirm the bracket behavior with a minimal repro when it matters: a non-final `[[ ]]` can be swallowed while `[ ]` still gates.
- **BSD grep has no GNU null-output `-Z` contract**: on stock macOS it means `--decompress`. Enumerate files with `find ... -print0`, then probe each file with `grep -qF`.
- **PlistBuddy reports missing-file creation on stdout**: redirect both stdout and stderr when creating plist fixtures so diagnostic prose does not pollute Bats `$output`.
- **macOS 14 Bash can fire errexit through an if-guarded exported mock**: a failing exported `sudo` function inside an `if fn; then` path may terminate a `set -e` script on that runner while passing locally. Around the first sudo probe, disable errexit only for the probe and restore it before validation-gate returns. CI-only failures must print exit status, output, and a mock call trace rather than a bare return-code assertion.
