# Local Audit TODO (Internal)

Last updated: 2026-03-04
Scope: Architecture alignment, CI workflow integrity, docs accuracy, test target completeness.

## 0) CI intent confirmation (your point #6)

Confirmed: current CI does implement the intended strategy:
- detect upstream Mole release
- run compatibility checks
- create PR when compatible
- create Issue when incompatible
- tag and release MoleUI after compatible update

Workflow: `.github/workflows/auto-update-mole.yml`

---

## 1) Architecture gaps vs "Swift shell only, Mole kernel only"

### P0 - Must fix first

- [x] `CleanModel` still does native scan/delete instead of Mole kernel commands.
  - Evidence: local `FileManager` traversal + `find ... rm -rf` in `MoleUI/Model/CleanModel.swift`
  - Action: move to Mole command orchestration only (`mole clean ... --json` for preview, `mole clean ...` for execution)

- [x] `PurgeModel` still does native scan/delete.
  - Evidence: local artifact discovery + `rm -rf` in `MoleUI/Model/PurgeModel.swift`
  - Action: delegate scan and execute to Mole purge command output contract

- [x] `InstallerModel` is native scanner, not Mole-driven.
  - Evidence: local recursive scanning in `MoleUI/Model/InstallerModel.swift`
  - Action: consume Mole installer output and operate through Mole command path

- [x] `UninstallModel/AppScanModel` is native scan + native uninstall flow.
  - Evidence: app discovery/uninstall logic in `MoleUI/Model/UninstallModel.swift`
  - Action: move uninstall domain behavior to Mole core command flow

- [x] `SafetyController` is not wired into primary Clean action path.
  - Evidence: `CleanView` calls `service.cleanSelected(...)` directly
  - Action: route destructive clean path through `SafetyController.executeClean(...)`

### P1 - Strongly recommended

- [ ] Remove duplicated Mole binary discovery logic across models.
  - Evidence: similar `findMoleBinary` logic in `CLIExecutor`, `DiskModel`, `MetricsModel`
  - Action: one source of truth in `CLIExecutor` or dedicated locator

- [ ] Fix purge path source mismatch.
  - Evidence: code reads `Application Support/MoleUI/purge_paths`, UI text says `~/.config/mole/purge_paths`
  - Action: choose one policy and align model + UI copy

---

## 2) CI completeness and accuracy audit

### P0

- [x] Update compatibility checks to match actual runtime dependencies.
  - Current workflow skips `analyze` check with outdated note, but app uses `mole analyze --json` in `DiskModel`.
  - Action: add real smoke check for `mole analyze --json <path>` (non-TTY path used by GUI)

- [x] Remove stale "native implementation/status-go not tested" notes from workflow PR body.
  - Evidence: `.github/workflows/auto-update-mole.yml` contains stale statements and missing `NATIVE_IMPLEMENTATION.md` link
  - Action: rewrite PR body based on current architecture

### P1

- [ ] Harden tag creation condition in auto-update workflow.
  - Risk: tag step depends on compatibility only, not explicit PR merge confirmation output
  - Action: gate tag creation on PR creation+merge success signal

- [ ] Normalize version compare format in update detector.
  - Risk: if upstream `tag_name` has `v` prefix and local file doesn't, false update detection may happen
  - Action: strip optional `v/V` before compare

- [ ] Ensure docs and workflow agree on actual compatibility checks.
  - AUTO_UPDATE.md currently claims checks stronger than workflow implementation

---

## 3) Test target completeness audit

### P0

- [x] Fix local test execution baseline in Xcode (code-sign conflict for test target).
  - Observed: test run reported all 23 tests "Not run" due signing conflict in current environment
  - Action: align test target signing config for local Xcode test runs

### P1

- [ ] Add integration tests for CLI contract (not only pure value/formatter tests).
  - Missing: command mapping tests for `Clean/Purge/Installer/Uninstall`
  - Missing: JSON contract regression tests for Mole command outputs used by UI
  - Missing: bundled resource existence test (`mole`, scripts, executable bits)

- [ ] Add UI test target for critical user flows.
  - Missing target: UI automation tests for destructive flow confirmations and recoverability

### P2

- [ ] Add test coverage around CI assumptions.
  - e.g. `.mole-cli-version` consistency (root + app copy), version parsing edge cases

---

## 4) Documentation accuracy and freshness audit

### P0

- [x] Remove/replace missing document references.
  - `NATIVE_IMPLEMENTATION.md` is referenced by workflow, but file is missing

- [x] Fix invalid test commands in docs.
  - `README.md`/`CONTRIBUTING.md` use `-scheme MoleUITests`, but project scheme is `MoleUI`

- [x] Update architecture claims to match real code state.
  - Current docs imply full CLI wrapping; code still has significant native business logic in multiple models

### P1

- [ ] Align `AUTO_UPDATE.md` with actual workflow behavior.
  - Avoid claiming checks that are not currently implemented
  - Keep command list in sync with current workflow script

- [ ] Align changelog historical notes with current branch reality.
  - Some entries still describe "native status implementation" that no longer matches current model code path

---

## 5) Execution order recommendation

- [ ] Step 1: Close P0 architecture gaps (Clean/Purge/Installer/Uninstall + SafetyController wiring)
- [ ] Step 2: Repair CI P0 checks and stale messaging
- [ ] Step 3: Fix doc P0 issues (wrong commands, missing links, architecture claims)
- [ ] Step 4: Expand tests (integration + UI), then refresh CI quality gates
