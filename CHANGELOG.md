# Changelog

All notable changes to MoleUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2-beta.2] - 2026-03-05

### Changed
- **Disk Analyzer Engine upgrade**: No longer uses Swift native protocol, switched to calling Go kernel (`mole analyze --json`) for significant performance gains.
- **UI Performance optimization**: Simplified disk analyzer rendering logic and limited display to top 100 entries to fix scrolling lag with large file systems.
- **Improved UI responsiveness**: Asynchronous loading and better thread management for analyzer tasks.

### Fixed
- Fixed UI thread blocking and scrolling lag in Disk Analyzer view.
- Added proper sorting for Go kernel results.

### Technical
- **Architecture Refactor**: Introduced unified `DiskMetrics` protocol to simplify data flow.
- **Documentation**: Updated architecture and CI/CD documentation.

## [0.1.2-beta.1] - 2026-03-04

### Added
- One-click clean and optimize functionality
  - Auto-select safe items after scanning
  - "Clean All" and "Optimize All" buttons with prominent styling
  - Collapsible advanced options for unsafe items
  - Green "safe" badges for safe items
  - Improved confirmation dialog showing safe vs advanced counts
- Network history chart improvements
  - Increased history buffer from 60 to 120 points (4 minutes)
  - Increased sparkline width from 30 to 60 characters
  - Better visualization matching Mole TUI behavior

### Changed
- Clean and Optimize views now default to selecting all safe items
- Individual "Clean" and "Run" buttons removed for cleaner UI
- Developer Tools category marked as unsafe (may contain important build artifacts)
- Network history accumulates over time in MoleUI (fills in ~4-6 minutes)

### Fixed
- Auto-update workflow path resolution using stable `brew --prefix` method
- Network history chart not displaying enough data points

### Technical
- Added `safe` property to CleanCategory and OptimizationTask
- Added Equatable conformance to data models for onChange detection
- Added AppStorage preference for auto-selecting safe items
- Improved user experience with 40% reduction in operation steps (7→5 steps, 5+→2 clicks)

## [0.1.2] - 2026-03-04

### Added
- One-click clean and optimize functionality
  - Auto-select safe items after scanning
  - "Clean All" and "Optimize All" buttons with prominent styling
  - Collapsible advanced options for unsafe items
  - Green "safe" badges for safe items
  - Improved confirmation dialog showing safe vs advanced counts
- Network history chart improvements
  - Increased history buffer from 60 to 120 points (4 minutes)
  - Increased sparkline width from 30 to 60 characters
  - Better visualization matching Mole TUI behavior
- CLI integration tests in `MoleUITests` covering `CLIExecutor.findMoleRoot`, `findMoleBinary`, and JSON parsing
- `AppScanModel.errorMessage` state to surface uninstall scan failures to the UI

### Changed
- Clean and Optimize views now default to selecting all safe items
- Individual "Clean" and "Run" buttons removed for cleaner UI
- Developer Tools category marked as unsafe (may contain important build artifacts)
- Network history accumulates over time in MoleUI (fills in ~4-6 minutes)
- `DiskModel`, `MetricsModel`, `UninstallModel`, `VersionModel`: unified Mole binary discovery via `CLIExecutor.findMoleBinary()` (eliminated four duplicate implementations)
- `AppScanModel.performScan()` now propagates script errors via `throw` instead of silently returning empty results
- `auto-update-mole.yml`: tag creation now gated on `steps.auto_merge.outputs.merged == 'true'` (prevents releasing if PR merge fails due to CI or branch protection)
- `AUTO_UPDATE.md`: added merge-gate documentation

### Fixed
- Auto-update workflow path resolution using stable `brew --prefix` method
- Network history chart not displaying enough data points
- `auto-update-mole.yml`: version-stripping bug where `V` prefix was being stripped from `RAW_TAG` instead of from `LATEST`
- `PurgeView.swift`: UI text now correctly shows Application Support path instead of `~/.config/mole`
- `UninstallModel.swift`: `MOLE_TEST_MODE=1` prevents interactive TUI from blocking non-interactive scan
- `UninstallModel.swift`: `mktemp` template fixed for macOS compatibility
- `UninstallModel.swift`: `SCRIPT_DIR` dynamically patched via `sed` for correct dependency resolution

### Technical
- Added `safe` property to CleanCategory and OptimizationTask
- Added Equatable conformance to data models for onChange detection
- Added AppStorage preference for auto-selecting safe items
- Improved user experience with 40% reduction in operation steps (7→5 steps, 5+→2 clicks)

> **Architecture Note**: MoleUI uses a hybrid architecture. The Dashboard, Clean, and Disk Analyzer models delegate to the Mole CLI Go/Bash kernel for better data accuracy, feature parity with the TUI, and reduced maintenance surface.

## [0.1.1] - 2026-03-03

> **[Editor's Note]**: The native implementations introduced in version 0.1.1 were later reverted in 0.1.2 due to performance regressions and data accuracy issues. MoleUI has fully committed to a hybrid architecture bridging the robust Go/Bash Mole CLI core instead.

### Added
- Bundled Mole CLI version display in Settings
- `.mole-cli-version` file bundled in app resources for version tracking

### Changed
- Independent version numbering system for MoleUI (separate from Mole CLI version)
- Auto-update workflow now increments MoleUI version independently
- PR titles now show both MoleUI and Mole CLI versions
- Release tags use MoleUI version instead of Mole CLI version

### Fixed
- Bundled Mole CLI showing "Unknown" instead of actual version number
- Extra spacing in Settings About section
- Text wrapping issue in Settings preferences
- ProgressView Auto Layout constraint warning

## [0.1.1] - 2026-03-03

### Added
- Bundled Mole CLI version display in Settings
- `.mole-cli-version` file bundled in app resources for version tracking

### Changed
- Independent version numbering system for MoleUI (separate from Mole CLI version)
- Auto-update workflow now increments MoleUI version independently
- PR titles now show both MoleUI and Mole CLI versions
- Release tags use MoleUI version instead of Mole CLI version

### Fixed
- Bundled Mole CLI showing "Unknown" instead of actual version number
- Extra spacing in Settings About section
- Text wrapping issue in Settings preferences
- ProgressView Auto Layout constraint warning

## [0.1.0] - 2026-03-02

### Added
- Initial release of MoleUI
- Native macOS GUI for Mole CLI
- Real-time system status dashboard
- Visual disk space analyzer
- System cleanup with dry run support
- System optimization with dry run support
- Large file purge interface
- Installer management
- App uninstaller
- Whitelist management for protected paths
- Settings and preferences
- Bundled Mole CLI (version 1.28.1)
- Auto-update system with compatibility checks
- GitHub Actions CI/CD pipeline
- Code signing and notarization support

### Technical
- Built with SwiftUI and Swift 6 strict concurrency
- MV (Model-View) architecture with @Observable
- Pure SwiftUI views with @Environment injection
- NavigationSplitView for native macOS experience
- Requires macOS 14.0 (Sonoma) or later

[Unreleased]: https://github.com/imnotnoahhh/MoleUI/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.2
[0.1.1]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.1
[0.1.0]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.0
