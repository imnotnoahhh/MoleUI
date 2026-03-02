# Changelog

All notable changes to MoleUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- Comprehensive auto-update documentation (AUTO_UPDATE.md)

### Technical
- Built with SwiftUI and Swift 6 strict concurrency
- MV (Model-View) architecture with @Observable
- Pure SwiftUI views with @Environment injection
- NavigationSplitView for native macOS experience
- Requires macOS 14.0 (Sonoma) or later

[Unreleased]: https://github.com/imnotnoahhh/MoleUI/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.1
[0.1.0]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.0
