# MoleUI TODO List

## Priority 1: Performance & User Experience

### Performance Optimization
- [ ] Fix Disk Analyzer scrolling lag
  - Profile and identify bottlenecks
  - Implement virtual scrolling or pagination
  - Optimize view rendering
- [ ] Reduce app startup time
- [ ] Optimize memory usage
- [ ] Reduce CLI call overhead

**Estimated effort**: 6-8 hours
**Difficulty**: Medium
**Priority**: High

### One-Click Optimization for Beginners
- [ ] Add "Quick Clean" mode
  - One button to clean everything safe
  - No configuration needed
  - Show simple before/after results
- [ ] Add "Recommended Actions" dashboard
  - Automatically suggest what to clean/optimize
  - Show potential space savings
  - Explain why each action is recommended
- [ ] Simplify confirmation dialogs
  - Use plain language (avoid technical terms)
  - Show visual previews
  - Add "Trust me, just do it" option
- [ ] Add guided first-run experience
  - Welcome screen with quick tour
  - Explain what MoleUI does
  - Run initial scan and show recommendations

**Estimated effort**: 8-12 hours
**Difficulty**: Medium
**Priority**: High

### Error Handling & Reliability
- [ ] Graceful handling of CLI failures
- [ ] Better error messages for users
- [ ] Add retry logic for transient errors
- [ ] Fallback UI when features unavailable

**Estimated effort**: 4-6 hours
**Difficulty**: Medium
**Priority**: High

## Priority 2: CI & Testing

### CI Pipeline Improvements
- [ ] Add automated UI tests
- [ ] Add integration tests for CLI execution
- [ ] Add performance regression tests
- [ ] Test on multiple macOS versions (14.0, 15.0, 26.0)
- [ ] Add code coverage reporting

**Estimated effort**: 8-12 hours
**Difficulty**: Medium
**Priority**: High

### Build & Release Automation
- [ ] Optimize build time
- [ ] Add automated DMG creation
- [ ] Add automated notarization
- [ ] Add release notes generation

**Estimated effort**: 4-6 hours
**Difficulty**: Low
**Priority**: Medium

### Quality Checks
- [ ] Add SwiftLint to CI
- [ ] Add SwiftFormat verification
- [ ] Add security scanning
- [ ] Add dependency vulnerability checks

**Estimated effort**: 3-4 hours
**Difficulty**: Low
**Priority**: Medium

## Priority 3: Auto-Update System

### Better Conflict Detection
- [ ] Improve compatibility checks
  - Test all CLI commands (not just --help)
  - Validate JSON schema more thoroughly
  - Check for breaking changes in output format
- [ ] Add rollback mechanism
  - Keep previous version as backup
  - Auto-rollback if new version fails
- [ ] Add manual override option
  - Allow skipping specific versions
  - Allow forcing update despite warnings

**Estimated effort**: 6-8 hours
**Difficulty**: High
**Priority**: High

### Enhanced CI Integration
- [ ] Run full test suite before auto-merge
- [ ] Add smoke tests for updated CLI
- [ ] Verify all features work with new version
- [ ] Add performance benchmarks comparison

**Estimated effort**: 4-6 hours
**Difficulty**: Medium
**Priority**: High

### In-App Update (No DMG Download)
- [ ] Integrate Sparkle framework
  - Add in-app update notifications
  - Download and install updates automatically
  - Support delta updates (only changed files)
- [ ] Add update preferences
  - Auto-update vs manual
  - Check frequency
  - Beta channel option
- [ ] Show update progress
  - Download progress bar
  - Installation status
  - Release notes display

**Estimated effort**: 8-12 hours
**Difficulty**: High
**Priority**: High

### Local Update Mechanism
- [ ] Add "Check for Updates" button in Settings
- [ ] Download updates in background
- [ ] Install on next launch (no interruption)
- [ ] Verify signature before installing

**Estimated effort**: 6-8 hours
**Difficulty**: Medium
**Priority**: High

## Priority 4: Documentation

### User Documentation
- [ ] Create comprehensive user guide
  - Getting started
  - Feature explanations (what each button does)
  - Troubleshooting common issues
  - FAQ section
- [ ] Add in-app help
  - Tooltips for all features
  - Help button linking to docs
  - Context-sensitive help
- [ ] Create video tutorials
  - Quick start guide (2-3 min)
  - Feature walkthroughs
  - Tips and tricks

**Estimated effort**: 8-12 hours
**Difficulty**: Low
**Priority**: Medium

### Developer Documentation
- [ ] Document architecture
  - MV pattern explanation
  - CLI integration approach
  - State management
- [ ] Document build process
  - Prerequisites
  - Build steps
  - Release process
- [ ] Document auto-update workflow
  - How it works
  - How to test
  - How to debug issues
- [ ] Add inline code documentation
  - Document public APIs
  - Explain complex logic
  - Add usage examples

**Estimated effort**: 6-8 hours
**Difficulty**: Low
**Priority**: Low

### Contributing Guide
- [ ] Update CONTRIBUTING.md
  - Clear setup instructions
  - Code style guidelines
  - PR process
  - Testing requirements
- [ ] Add issue templates
  - Bug report template
  - Feature request template
  - Question template
- [ ] Add PR template
  - Checklist for contributors
  - Testing checklist

**Estimated effort**: 3-4 hours
**Difficulty**: Low
**Priority**: Low

## Completed ✅

### Core Features
- ✅ Real-time Dashboard (mole status --json)
- ✅ Disk Analyzer (mole analyze --json)
- ✅ System Cleanup with dry-run
- ✅ System Optimization with dry-run
- ✅ Large File Purge
- ✅ Installer Management
- ✅ App Uninstaller
- ✅ Whitelist Management
- ✅ Settings & About

### UX Improvements
- ✅ One-click clean and optimize
- ✅ Auto-select safe items
- ✅ Collapsible advanced options
- ✅ Safe item badges

### Infrastructure
- ✅ Auto-update workflow with compatibility checks
- ✅ Fixed Mole CLI analyze TTY dependency (PR #533)
- ✅ CI with SwiftFormat and SwiftLint
- ✅ Automated DMG build and notarization

### Bug Fixes
- ✅ Disk Analyzer sorting by size
- ✅ Basic performance optimization (limit 100 items)

## Notes

### Current Focus
1. **Performance** - Make the app fast and responsive
2. **Simplicity** - Make it easy for non-technical users
3. **Reliability** - Robust auto-update and error handling
4. **Documentation** - Clear guides for users and developers

### Architecture
- **MV (Model-View)** with Swift Observation
- **CLI Integration**: Wrap bundled Mole CLI binaries
- **Auto-Update**: GitHub Actions workflow with compatibility checks

### Contributing
1. Pick a task from Priority 1 or 2
2. Create a feature branch
3. Implement and test
4. Run `just fmt && just lint`
5. Submit PR

### Priority Levels
- **Priority 1**: Performance & UX (most important)
- **Priority 2**: CI & Testing (quality assurance)
- **Priority 3**: Auto-Update (better update experience)
- **Priority 4**: Documentation (help users and developers)
