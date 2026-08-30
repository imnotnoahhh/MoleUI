---
name: bugs
description: "Mole incident catalog for destructive cleanup safety, bounded Shell/macOS probes, dry-run/real parity, cache and accounting consistency, Bats validity, and refusal diagnostics. Use for a Mole bug or safety-sensitive diff involving deletion evidence, unknown process state, timeouts or signals, system parsing, persisted derivations, totals, progress, or tests. Not for docs, releases, generic review, or other repositories."
---

# Mole bug patterns

Use this catalog after reading the current symptom, diff, implementation, and callers. Generic review belongs to Waza `check`; root-cause investigation of a live failure belongs to `hunt`.

## Route before loading details

Choose only the reference families touched by the evidence. A whole-project audit should classify surfaces first instead of loading every incident narrative.

| # | Recurring shape | First probe | Read |
|---|---|---|---|
| 1 | Deletion candidate built from a weak name signal | Inspect name, bundle-id, and fallback globs | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |
| 2 | Existence or idleness decided by one probe | Enumerate every legitimate location and unknown outcome | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |
| 3 | Guard present on only one branch | Diff dry-run, real, direct, fallback, and final-sink paths | [Deletion evidence and final sink](references/deletion-evidence-and-final-sink.md) |
| 4 | Unbounded external command | Count producer, consumer, inner-loop, and action bounds | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 5 | Bash 3.2, errexit, or pipefail trap | Check empty arrays, `fn || handler`, and optional actions | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 6 | TTY, stdin, or process-group theft | Inspect background workers and commands that may prompt | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 7 | System output parsed as a stable API | Force locale and validate shape before accepting data | [Bounds, Shell, TTY, and parsing](references/shell-and-test-pitfalls.md) |
| 8 | Persisted derived data outlives its algorithm | Trace schema, TTL, evidence fingerprint, and mutations | [State, accounting, and progress](references/state-accounting-and-progress.md) |
| 9 | Two paths compute one number differently | Find every producer and choose one definition | [State, accounting, and progress](references/state-accounting-and-progress.md) |
| 10 | Slow work looks frozen | Find operations over roughly one second outside feedback | [State, accounting, and progress](references/state-accounting-and-progress.md) |
| 11 | Regression test cannot fail | Prove positive control and pre-fix red state | [Test validity and refusal diagnostics](references/test-validity-and-refusal-diagnostics.md) |
| 12 | Gate cannot explain why it refused | Map each reason code to one cause and next action | [Test validity and refusal diagnostics](references/test-validity-and-refusal-diagnostics.md) |

## Trace the complete mutation lifecycle

For cleanup, purge, optimize, analyze deletion, or uninstall work, review the complete chain rather than the reported branch:

```text
discover or plan
  -> cheap irreversible filters
  -> owner and open-handle probes
  -> size or metadata work
  -> final owner re-probe
  -> parent and target identity rebind
  -> deletion or Trash sink
  -> accounting, cancellation, and user output
```

At every transition, answer:

- Does live or unknown state fail closed?
- Do timeout and signal statuses remain observable and stop later mutation?
- Are probe and sink bound to the same physical parent and target?
- Do dry-run and real mode start from the same eligible plan without reusing stale authorization?
- Are cheap missing, protected, whitelisted, and compiled-model filters ahead of recursive probes?
- Does one cumulative deadline cover the dynamic scan scope, with checkpoints in nested loops?
- Do refused, filtered, timed-out, or failed items stay out of cleaned counts and reclaimed bytes?
- Can large candidates avoid per-item size work without making the reported total false?

Do not trade final-sink rebinding or fail-closed owner checks for speed. Optimize absent targets, duplicated discovery probes, report-only work, and wrong-scope scans first.

## Working contract

- Sweep siblings by call-site shape, not filename or helper name. Report `checked N / defective M / not applicable K`.
- A recurring fix ships with a regression or source invariant that fails against the pre-fix code.
- Treat tests as production consumers only after proving the production helper ran. Negative assertions require a positive trace.
- Absence-sensitive tests use an isolated `HOME` or fixture root; a shared `setup_file` home is not isolation.
- Reproduce CI through `MOLE_TEST_NO_AUTH=1 ./scripts/test.sh` when possible. If invoking Bats directly with jobs, preserve `--no-parallelize-within-files`; files share state and raw `bats --jobs 6 file.bats` changes semantics.
- Treat specialist or AI reports as leads. Read the implementation, callers, fallback branches, and final sink yourself.

## Verification bar

Use the hotspot commands in `AGENTS.md`; do not guess a narrower verifier. A typical Shell safety change finishes with:

```bash
./scripts/check.sh --format
MOLE_TEST_NO_AUTH=1 bats tests/<area>.bats
MOLE_TEST_NO_AUTH=1 ./scripts/test.sh
go test ./...
MOLE_TEST_NO_AUTH=1 MOLE_DRY_RUN=1 ./mole clean --dry-run
```

Never infer a production defect from a function name, comment, string, fixture, or `_test.go` match. Confirm the live call path and verify red-green before reporting the class fixed.
