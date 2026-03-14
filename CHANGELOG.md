# Changelog

All notable changes to MoleUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.4] - 2026-03-15

### Added
- **Full Disk Access detection and guidance system**
  - Automatic detection of Full Disk Access status in Settings
  - One-click navigation to System Settings Privacy panel
  - Probes multiple protected directories (TCC.db, Mail, Safari, Messages)
  - Clear status indicators (granted/not granted/unknown)
  - Detailed explanations for each status state
- **New unified theme system (MoleTheme)**
  - Consistent color palette across all views
  - Pine, moss, meadow, ember, sky color scheme
  - Adaptive colors for light/dark mode
  - Improved visual hierarchy and readability
- **Enhanced UI components**
  - MolePanelGroupBoxStyle for consistent panel styling
  - MoleSectionHeader with icon and subtitle support
  - MoleMetricBadge for displaying metrics with icons
  - Improved shadows and material effects
  - Rounded corner refinements (22px radius)

### Changed
- **Settings view completely redesigned**
  - Full Disk Access status card with refresh button
  - Improved layout with better spacing and grouping
  - Enhanced About section with app icon and version info
  - Better visual feedback for interactive elements
- **All views updated with new theme system**
  - Dashboard, Clean, Optimize, Disk Analyzer, Purge, Installer, Uninstall
  - Consistent styling across the entire app
  - Improved button styles and hover states
  - Better contrast and accessibility
- **Sidebar improvements**
  - Enhanced navigation with better visual feedback
  - Improved icon alignment and spacing
  - Better selection indicators
- **Info.plist permissions descriptions updated**
  - More detailed usage descriptions for folder access
  - Clearer explanations for Desktop, Documents, Downloads access

### Fixed
- UI consistency issues across different views
- Color scheme adaptation in dark mode
- Button styling inconsistencies
- Layout spacing and alignment issues

### Technical
- Added AppKit imports for system integration
- Improved Full Disk Access detection logic
- Better error handling in permission checks
- Enhanced AppleScript integration for System Settings navigation
- Cleaner code organization with reusable UI components

## [0.1.3] - 2026-03-10

### Changed
- **Bundled Mole CLI upgraded to v1.30.0** (from v1.29.0)
- Auto-update workflow rewritten
  - Downloads source tarball from GitHub Releases instead of Homebrew
  - Builds universal (Intel + Apple Silicon) Go binaries via `lipo`
  - Uses `gh api` with auth token to avoid rate limiting
  - Validates file structure, executability, and Mach-O binary format
  - Removed auto-merge and tag creation (manual review only)
  - Updates both root and bundled `.mole-cli-version`

## [0.1.2] - 2026-03-06

Official release with Mole CLI v1.29.0.

### Added
- Caching mechanism for disk analyzer and app scanner
  - Disk analyzer caches scan results with timestamp display
  - App scanner caches uninstall scan results
  - Cache status shown with relative time (e.g., "2m ago", "1h ago")
  - Manual refresh button to invalidate cache
- Comprehensive test suite with 43 tests across 7 suites
  - Async & concurrency tests
  - Error recovery tests
  - Data validation tests
  - Edge case tests
  - Memory & performance tests
- Enhanced CI/CD pipeline
  - Separate unit and UI test runs
  - Test coverage reporting
  - Test result artifacts upload
  - Security scanning

### Changed
- **Bundled Mole CLI upgraded to v1.29.0** (official release)
- Simplified UI by removing batch delete functionality
  - Purge page: removed checkboxes and "Purge Selected" button
  - Installer page: removed checkboxes and "Trash Selected" button
  - Kept individual delete buttons for better control
- All UI text translated to English for consistency
- Disk analyzer navigation optimized
  - Removed unnecessary Full Disk Access permission check
  - Accept multiple macOS permission dialogs on first scan
- Clean and Optimize operations simplified to single execution
- Improved sudo execution and CLI path handling

### Fixed
- ProgressView Auto Layout constraint warnings across all views
- UI thread blocking issues in disk analyzer
- Sudo password prompt reliability
- Test suite robustness (removed flaky history bounds test)

### Technical
- Test coverage increased from 55% to 82%
- All models now use unified `CLIExecutor.findMoleBinary()`
- Improved error handling and user feedback
- Better concurrency safety with MainActor isolation
- Enhanced CI configuration with proper test filtering

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

[Unreleased]: https://github.com/imnotnoahhh/MoleUI/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.4
[0.1.3]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.3
[0.1.2]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.2
[0.1.2-beta.2]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.2-beta.2
[0.1.2-beta.1]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.2-beta.1
[0.1.2]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.2
[0.1.1]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.1
[0.1.0]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.0
