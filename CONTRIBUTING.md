# Contributing to Mole UI

Thank you for your interest in improving Mole UI! This guide focuses on the most valuable contributions: **UI/UX improvements**, **Mole CLI compatibility testing**, **stability**, and **performance**.

---

## 🎨 UI/UX Improvements

We welcome design improvements to make Mole UI more intuitive and visually appealing.

### Current UI Stack
- **SwiftUI** with `NavigationSplitView` layout
- **Native macOS controls** (GroupBox, Label, ProgressView)
- **Monospaced fonts** for metrics display
- **Color coding**: 🟢 Green (good) → 🟡 Yellow (warning) → 🔴 Red (critical)

### Areas for Improvement

**Dashboard (DashboardView.swift)**
- Metrics visualization could be more engaging
- Consider adding charts/graphs for CPU/memory history
- Improve layout responsiveness for different window sizes
- Better visual hierarchy for critical vs. informational data

**Cleanup Views (CleanView, PurgeView, InstallerView)**
- Preview before deletion could be more detailed
- Progress indicators during scanning could show more context
- Consider adding file type icons or thumbnails
- Improve empty state messaging

**Settings & About (SettingsView)**
- Version checking UI could be more prominent
- Whitelist management needs better UX (drag-drop support?)
- Consider adding keyboard shortcuts reference

**General Polish**
- Animations and transitions (currently minimal)
- Dark mode optimization
- Accessibility (VoiceOver, keyboard navigation)
- Localization support (currently English only)

### How to Contribute UI Changes

1. **Fork and create a branch**: `git checkout -b ui/improve-dashboard`
2. **Make changes in `MoleUI/View/` only** — don't modify Model logic
3. **Test on different macOS versions** (14.0+) and window sizes
4. **Screenshot before/after** — include in PR description
5. **Run `just fmt && just lint`** before committing
6. **Open PR** with clear description of UX improvements

---

## 🧪 Mole CLI Compatibility Testing

Mole UI wraps the [Mole CLI tool](https://github.com/tw93/Mole). When Mole CLI updates, we need to verify compatibility.

### What to Test

**When Mole CLI releases a new version:**

1. **Update bundled CLI**: `just update-mole`
2. **Verify all features work**:
   - Dashboard shows real-time metrics (status-go binary)
   - Disk Analyzer scans directories (analyze-go binary)
   - Clean/Optimize/Purge/Installer/Uninstall execute correctly
   - Dry-run mode works for destructive operations
3. **Check for breaking changes**:
   - Does `status-go --json` output match `MetricsSnapshot` struct?
   - Do shell scripts in `Resources/mole/bin/` still exist?
   - Are new subcommands added that GUI should support?
4. **Run automated tests**: `xcodebuild -scheme MoleUITests test CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`
5. **Report issues**: If tests fail or features break, create an issue with:
   - Mole CLI version (check `.mole-cli-version`)
   - Error messages or unexpected behavior
   - Steps to reproduce

### Auto-Update Workflow

The `.github/workflows/auto-update-mole.yml` workflow automatically:
- Checks for new Mole releases daily
- Validates file structure and JSON schema
- Creates PR if compatible, or issue if breaking changes detected

**You can help by**:
- Testing PRs created by the auto-update bot
- Improving compatibility checks in `auto-update-mole.yml`
- Adding more test coverage for edge cases

---

## 🛡️ Stability Improvements

Help make Mole UI more robust and reliable.

### Common Stability Issues

**Error Handling**
- Check `ErrorTranslator.swift` — does it cover all CLI error cases?
- Are error messages user-friendly and actionable?
- Do views gracefully handle missing data or failed operations?

**Edge Cases**
- What happens when Mole CLI binary is missing?
- How does the app behave with no disk space?
- Does it handle permission errors gracefully?
- What if `status-go` crashes or returns invalid JSON?

**Memory Management**
- Check for retain cycles in `@Observable` models
- Verify large file scans don't cause memory spikes
- Test with thousands of files in Disk Analyzer

**Concurrency**
- All models use `@MainActor` — verify no data races
- Check for deadlocks in long-running operations
- Ensure cancellation works (SafetyController.cancel())

### How to Report Stability Issues

1. **Reproduce the crash/bug** consistently
2. **Collect logs**: Check Console.app for crash reports
3. **Create issue** with:
   - macOS version
   - Mole UI version
   - Mole CLI version (`.mole-cli-version`)
   - Steps to reproduce
   - Expected vs. actual behavior
   - Crash logs or error messages

---

## ⚡ Performance Optimization

Help make Mole UI faster and more responsive.

### Performance Bottlenecks

**Disk Scanning (DiskModel.swift)**
- Currently scans directories sequentially
- Large directories (100k+ files) can be slow
- Consider: parallel scanning, incremental updates, caching

**Metrics Streaming (MetricsModel.swift)**
- `status-go --json` streams JSON every 2 seconds
- Parsing and UI updates happen on main thread
- Consider: background parsing, throttling updates

**Cleanup Operations (CleanModel.swift)**
- Calculating directory sizes is I/O intensive
- Preview generation blocks UI
- Consider: streaming results, showing partial progress

**Memory Usage**
- Disk Analyzer loads entire directory tree into memory
- Large scans can use 500MB+ RAM
- Consider: lazy loading, pagination, tree pruning

### How to Contribute Performance Fixes

1. **Profile first**: Use Instruments (Time Profiler, Allocations)
2. **Measure impact**: Before/after benchmarks
3. **Keep architecture clean**: Don't break MV separation
4. **Test on real data**: Large directories, slow disks, old Macs
5. **Document trade-offs**: Speed vs. accuracy, memory vs. features

---

## 🏗️ Architecture Guidelines

**MV (Model-View) with Swift Observation**

- **Models** (`MoleUI/Model/`): `@Observable @MainActor` classes with state + logic
- **Views** (`MoleUI/View/`): Pure SwiftUI, inject models via `@Environment(XxxModel.self)`
- **No business logic in Views** — all logic belongs in Models
- **Swift 6 strict concurrency** — all Codable types must be `Sendable`

### Adding a New Feature

1. Create `Model/NewFeatureModel.swift`:
   ```swift
   @Observable @MainActor
   final class NewFeatureModel {
       var state: String = ""
       func doSomething() async { }
   }
   ```

2. Create `View/NewFeatureView.swift`:
   ```swift
   struct NewFeatureView: View {
       @Environment(NewFeatureModel.self) var model
       var body: some View { }
   }
   ```

3. Inject in `MoleApp.swift`:
   ```swift
   @State private var newFeatureModel = NewFeatureModel()
   // In body:
   .environment(newFeatureModel)
   ```

4. Add tests to `MoleUITests/MoleCoreTests.swift`

---

## 🔍 Code Quality Tools

Before submitting any code, ensure it passes all quality checks.

### SwiftFormat

SwiftFormat automatically formats Swift code to maintain consistent style.

**Installation**:
```bash
brew install swiftformat
```

**Usage**:
```bash
# Format all Swift files
just fmt
# Or directly:
swiftformat MoleUI/
```

**Configuration**: `.swiftformat` (if exists) or uses default rules

### SwiftLint

SwiftLint enforces Swift style and conventions.

**Installation**:
```bash
brew install swiftlint
```

**Usage**:
```bash
# Lint all Swift files
just lint
# Or directly:
swiftlint lint --strict

# Auto-fix issues (where possible)
swiftlint --fix
```

**Configuration**: `.swiftlint.yml` - customized rules for MoleUI:
- Disabled: `trailing_comma` (SwiftFormat adds them), `nesting` (allows nested types), `opening_brace` (SwiftFormat handles it)
- Line length, file length, complexity limits disabled for flexibility
- Opt-in rules: `empty_count`, `closure_spacing`, etc.

### Pre-Commit Checklist

Before committing code, run:

```bash
# 1. Format code
just fmt

# 2. Lint code (must pass with 0 violations)
just lint

# 3. Build project
just build

# 4. Run tests
xcodebuild -scheme MoleUITests test \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

All checks must pass before opening a PR.

---

## 🧪 Testing

Run tests before submitting PR:

```bash
# Format and lint
just fmt && just lint

# Run tests
xcodebuild -scheme MoleUITests test \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

**Test coverage priorities**:
- JSON decoding for Mole CLI output
- Error handling and user-friendly messages
- Edge cases (empty data, missing files, permission errors)
- Performance benchmarks for large datasets

---

## 📝 Pull Request Guidelines

### Before Submitting

**Code Quality**
```bash
just fmt              # Format code with swiftformat
just lint             # Check with swiftlint (must pass)
just build            # Verify it compiles
```

**Testing**
```bash
# Run all tests
xcodebuild -scheme MoleUITests test \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# All 24 tests must pass
```

**Manual Testing**
- Test on macOS 14.0+ (Sonoma or later)
- Try different window sizes (minimum 904x580)
- Test with real data (large directories, many files)
- Verify Dry Run mode works for destructive operations

### PR Structure

**Title Format**
- `feat: Add dark mode support`
- `fix: Resolve memory leak in disk scanner`
- `perf: Optimize directory size calculation`
- `ui: Improve dashboard layout responsiveness`
- `docs: Update architecture diagram`
- `test: Add coverage for error handling`

**Description Template**
```markdown
## What
Brief description of the change (1-2 sentences)

## Why
Explain the motivation — what problem does this solve?

## How
Technical approach — what did you change?

## Testing
- [ ] Ran `just fmt && just lint`
- [ ] All tests pass
- [ ] Tested on macOS 14.0+
- [ ] Manual testing completed

## Screenshots (for UI changes)
Before: [screenshot]
After: [screenshot]

## Breaking Changes
None / List any breaking changes

## Related Issues
Closes #123
```

### PR Checklist

**For All PRs**
- [ ] One feature/fix per PR (split large changes)
- [ ] Clear commit messages (follow conventional commits)
- [ ] Code formatted with `just fmt`
- [ ] Linting passes with `just lint`
- [ ] All tests pass
- [ ] No new compiler warnings

**For UI Changes**
- [ ] Screenshots included (before/after)
- [ ] Tested on different window sizes
- [ ] Verified in both light and dark mode
- [ ] Keyboard navigation works
- [ ] No layout glitches or visual regressions

**For Model/Logic Changes**
- [ ] Added tests for new functionality
- [ ] Error handling implemented
- [ ] Follows MV architecture (no UI in Models)
- [ ] Swift 6 concurrency rules followed (`@MainActor`, `Sendable`)

**For Performance Changes**
- [ ] Profiling data included (Instruments screenshots)
- [ ] Before/after benchmarks with numbers
- [ ] Tested with large datasets (10k+ files)
- [ ] Memory usage measured

**For Mole CLI Integration**
- [ ] Tested with current Mole CLI version (check `.mole-cli-version`)
- [ ] Verified JSON schema compatibility
- [ ] Dry-run mode tested
- [ ] Error handling for missing binaries

### Review Process

1. **Automated checks run** — CI builds and tests
2. **Maintainer review** — usually within 2-3 days
3. **Address feedback** — make requested changes
4. **Approval and merge** — squash merge to main

### Common Rejection Reasons

❌ **Will be rejected**:
- Breaks existing functionality
- Fails tests or linting
- No description or screenshots (for UI changes)
- Violates MV architecture (business logic in Views)
- Introduces memory leaks or performance regressions
- Includes unrelated changes (multiple features in one PR)

✅ **More likely to be accepted**:
- Solves a real user problem
- Includes tests
- Well-documented code
- Follows existing patterns
- Small, focused changes

---

## 🐛 Reporting Issues

**For bugs**: Include macOS version, Mole UI version, steps to reproduce, expected vs. actual behavior

**For feature requests**: Describe the use case, why it's valuable, and any UI mockups

**For performance issues**: Include profiling data, dataset size, and hardware specs

---

## 📚 Resources

- [Mole CLI Repository](https://github.com/tw93/Mole) — Upstream CLI tool
- [Swift Observation](https://developer.apple.com/documentation/observation) — Architecture pattern
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui) — UI framework

---

Thank you for contributing! 🎉
