# Changelog

All notable changes to MoleUI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Independent version numbering system for MoleUI (separate from Mole CLI version)
- Dual version display in Settings: MoleUI version and bundled Mole CLI version
- Auto-increment patch version when Mole CLI updates
- Comprehensive auto-update documentation (AUTO_UPDATE.md)

### Changed
- Auto-update workflow now increments MoleUI version independently
- PR titles now show both MoleUI and Mole CLI versions
- Release tags use MoleUI version instead of Mole CLI version

### Fixed
- Text wrapping issue in Settings preferences
- ProgressView Auto Layout constraint warning
- Excessive padding below version check card

## [0.1.0] - 2024-XX-XX

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

[Unreleased]: https://github.com/imnotnoahhh/MoleUI/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/imnotnoahhh/MoleUI/releases/tag/v0.1.0
