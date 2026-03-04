# Changelog

All notable changes to MoleUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

## [0.1.2] - 2026-03-03

### Added
- Native Swift implementation for system monitoring (replaces status-go)
  - CPU monitoring with per-core usage and P/E core detection
  - Memory monitoring with pressure status
  - Disk monitoring with internal/external detection and I/O rates
  - Network monitoring with interface detection, IP addresses, and traffic history
  - Battery monitoring with cycle count from IORegistry
  - Process monitoring (top processes by CPU usage)
  - Proxy detection (HTTP/HTTPS/SOCKS)
  - Health score calculation based on system metrics
- Documentation for native implementation (NATIVE_IMPLEMENTATION.md)
- Implementation roadmap and TODO list (TODO.md)
- GitHub issue template for upstream Mole CLI fix (MOLE_CLI_ISSUE.md)

### Changed
- Dashboard now uses native Swift APIs instead of calling status-go binary
- Auto-update workflow no longer checks status-go compatibility
- Health score calculation uses more aggressive algorithm
- Machine model display simplified (e.g., "MacBook Pro" instead of full model name)
- macOS version format changed to "macOS 26.3" (from "Version 26.3...")
- Battery health status shows text (Normal/Fair/Poor) instead of percentage
- Disk filtering improved to show iOS Simulator volumes and exclude small DMG images

### Fixed
- status-go TTY dependency preventing Dashboard from working in GUI app
- Battery cycle count showing 0 (now reads from IORegistry AppleSmartBattery)
- Battery health showing "Unknown" (now calculates from battery capacity)
- External disk detection (iOS Simulator volumes now correctly shown as EXTR)
- Network interface IP addresses not displaying
- Network traffic history graphs not updating
- CPU temperature estimation (uses CPU usage-based approximation)
- Disk size showing 0 B (now correctly reads from mounted volumes)
- Deprecated String(cString:) warnings

### Technical
- Added IOKit framework integration for hardware monitoring
- Implemented NativeMetricsCollector class with comprehensive system metrics
- Added Darwin/Mach APIs for CPU and memory statistics
- Added BSD APIs for network interface enumeration
- Removed status-go dependency from compatibility checks

### Known Limitations
- CPU temperature uses estimation (30-60°C range based on CPU usage)
  - Real SMC temperature reading requires complex data structures
- GPU monitoring not yet implemented
- Fan monitoring not yet implemented

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
