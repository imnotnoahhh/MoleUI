# Auto-Update System

MoleUI vendors upstream Mole CLI into `Resources/mole` and uses GitHub Actions to detect new upstream releases, rebuild the bundled Go binaries, run compatibility checks, and then either open a PR or raise a breaking-change issue.

This workflow **does not auto-merge PRs or create release tags anymore**. Release packaging stays in the separate [`.github/workflows/release.yml`](.github/workflows/release.yml) workflow and still requires a tag push or manual trigger.

## Workflow

```
Upstream Mole CLI Release
    ↓
Vendor Fresh Resources/mole
    ↓
Rebuild status-go / analyze-go
    ↓
Compatibility Check
    ↓
    ├─ Compatible → Update versions → Create PR → Normal repo CI → Maintainer merge
    └─ Incompatible → Create Issue for manual adaptation

After merge:
    Manual tag or workflow_dispatch → release.yml → signed/notarized DMG
```

## 1. Automatic Update Detection

**Trigger Methods:**
- Automatic daily run at UTC 00:00 (cron: `0 0 * * *`)
- Manual trigger: GitHub Actions → Auto Update Mole CLI → Run workflow

**Detection Logic:**
1. Read current version from `.mole-cli-version` file
2. Fetch latest version from `https://api.github.com/repos/tw93/Mole/releases/latest`
3. Compare versions to determine if update is needed

## 2. Compatibility Checks

When a new version is detected, the workflow validates both the bundled files and the GUI-relevant entry points that MoleUI currently depends on.

### 2.1 File Existence Check

Verifies all required files exist:
```
Resources/mole/mole                    # Main entry script
Resources/mole/bin/analyze-go          # Disk analysis binary
Resources/mole/bin/status-go           # System metrics binary
Resources/mole/bin/clean.sh            # Cleanup script
Resources/mole/bin/optimize.sh         # Optimization script
Resources/mole/bin/purge.sh            # Deep cleanup script
Resources/mole/bin/installer.sh        # Installer script
Resources/mole/bin/uninstall.sh        # Uninstall script
```

### 2.2 Script Executable Check

Verifies all shell scripts have executable permissions:
```bash
Resources/mole/bin/clean.sh
Resources/mole/bin/optimize.sh
Resources/mole/bin/purge.sh
Resources/mole/bin/installer.sh
Resources/mole/bin/uninstall.sh
```

### 2.3 JSON Smoke Validation

Validates the structured outputs that MoleUI currently decodes directly:
```bash
mole status --json
mole analyze --json "$SMOKE_HOME"
bash Resources/mole/lib/check/health_json.sh
```

### 2.4 Dry-Run Smoke Validation

Validates the higher-risk CLI flows that the GUI still delegates to upstream Mole:

```bash
mole clean --dry-run
mole optimize --dry-run
mole purge --dry-run
mole installer --dry-run
mole uninstall --dry-run
```

These dry-run checks run against an isolated temporary home directory with:
- standard folders like `Desktop`, `Documents`, and `Downloads`
- a sample installer file in `Downloads`
- a minimal `Projects/demo/node_modules` tree
- a generated `~/.config/mole/purge_paths`

That keeps the checks deterministic and avoids relying on whatever happens to be in the GitHub runner's real home directory.

## 3. PR and Release Flow

### 3.1 Compatible Update Flow

If compatibility checks pass:

1. **Update Version Number**
   ```bash
   # Auto-increment MoleUI patch version in project.pbxproj
   CURRENT_VERSION=$(grep "MARKETING_VERSION = " MoleUI.xcodeproj/project.pbxproj | head -1 | sed 's/.*MARKETING_VERSION = \(.*\);/\1/')
   IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
   NEW_PATCH=$((PATCH + 1))
   NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"
   sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $NEW_VERSION/" \
     MoleUI.xcodeproj/project.pbxproj
   ```

2. **Create PR**
   - Branch name: `auto-update-mole-{cli_version}`
   - Labels: `dependencies`, `automated`
   - PR description includes:
     - Version change information (both MoleUI and Mole CLI versions)
     - Compatibility check results
     - Upstream release notes link

3. **Wait for Normal Repository CI**
   The PR then goes through the standard [`.github/workflows/ci.yml`](.github/workflows/ci.yml) checks:
   - Code Quality
   - Build & Test
   - Security Scan

4. **Maintainer Review and Merge**
   The current workflow stops at PR creation. A maintainer still decides whether to merge.

5. **Optional Release Tag**
   After merge, create a tag manually if you want to ship a DMG immediately:
   ```bash
   git tag -a "v{moleui_version}" -m "Release v{moleui_version}"
   git push origin "v{moleui_version}"
   ```

6. **Release Workflow**
   Tag push triggers [`.github/workflows/release.yml`](.github/workflows/release.yml), which:
   - archives the app
   - bundles `Resources/mole`
   - signs nested binaries and the app
   - notarizes and staples the app
   - creates and uploads the DMG

### 3.2 Incompatible Update Flow

If compatibility checks fail:

1. **Create Issue**
   - Title: `Breaking: Mole CLI {version} has incompatible changes`
   - Labels: `breaking-change`, `mole-update`
   - Content includes:
     - Failed check details
     - Upstream release notes link
     - Note that manual adaptation is required

2. **Manual Intervention**
   - Developer reviews issue and analyzes incompatibility
   - Modify code to adapt to new version
   - Manually create PR and test
   - Merge and manually create release tag

## 4. Version Number Strategy

**Key Principle: MoleUI uses independent semantic versioning, separate from Mole CLI version**

### Version Sources

- **Mole CLI Version**: `.mole-cli-version` file (e.g., `1.28.1`)
- **MoleUI Version**: `MARKETING_VERSION` in `MoleUI.xcodeproj/project.pbxproj` (e.g., `0.1.0`)
- **Release Tag**: Git tag (e.g., `v0.1.0`)

### Version Synchronization

When Mole CLI updates:
1. Update `.mole-cli-version` to new Mole CLI version (e.g., `1.28.1`)
2. Auto-increment MoleUI patch version (e.g., `0.1.0` → `0.1.1`)
3. Create tag using MoleUI version (e.g., `v0.1.1`)

**Note:** MoleUI and Mole CLI versions are independent. MoleUI follows semantic versioning starting from 0.1.0, incrementing patch version on each Mole CLI update.

## 5. User-Facing Version Check

### 5.1 VersionModel

```swift
@Observable @MainActor
final class VersionModel {
    var currentVersion: String?  // Read from Info.plist
    var latestVersion: String?   // Fetch from GitHub API

    func loadCurrentVersion() async {
        // Read CFBundleShortVersionString
        currentVersion = MoleVersion.current
    }

    func checkForUpdates() async {
        // Check MoleUI releases
        let url = "https://api.github.com/repos/imnotnoahhh/MoleUI/releases/latest"
        // ...
    }
}
```

### 5.2 UI Display

Settings → About → Mole UI version card:
- Display current version (from Info.plist)
- Display latest version (from GitHub API)
- If update available, show "Update available" and "View Release" button
- Clicking "View Release" opens MoleUI releases page

### 5.3 Version Comparison Logic

```swift
private func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
    // Remove v prefix
    let clean1 = v1.hasPrefix("v") ? String(v1.dropFirst()) : v1
    let clean2 = v2.hasPrefix("v") ? String(v2.dropFirst()) : v2

    // Split version (e.g., "1.28.1" → [1, 28, 1])
    let parts1 = clean1.split(separator: ".").compactMap { Int($0) }
    let parts2 = clean2.split(separator: ".").compactMap { Int($0) }

    // Compare segment by segment
    for (p1, p2) in zip(parts1, parts2) {
        if p1 < p2 { return .orderedAscending }
        if p1 > p2 { return .orderedDescending }
    }

    // Compare length (1.0 < 1.0.1)
    if parts1.count < parts2.count { return .orderedAscending }
    if parts1.count > parts2.count { return .orderedDescending }
    return .orderedSame
}
```

## 6. Manual Update Trigger

### 6.1 Trigger Auto-update Check

1. Visit GitHub Actions
2. Select "Auto Update Mole CLI" workflow
3. Click "Run workflow"
4. Select branch (usually `main`)
5. Click "Run workflow" to confirm

### 6.2 Manual Mole CLI Update

If manual update is needed (e.g., auto-update failed):

```bash
# 1. Install latest Mole CLI
brew update && brew upgrade mole

# 2. Extract files to project
MOLE_PATH=$(which mole)
MOLE_REAL=$(readlink "$MOLE_PATH")
MOLE_ROOT=$(dirname $(dirname "$MOLE_REAL"))

rm -rf Resources/mole/*
cp -R "$MOLE_ROOT/libexec/"* Resources/mole/
cp "$MOLE_ROOT/bin/mole" Resources/mole/

# 3. Fix mole script path
sed -i '' 's|SCRIPT_DIR=.*|SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" \&\& pwd)"|' \
  Resources/mole/mole

# 4. Update Mole CLI version
NEW_CLI_VERSION=$(mole version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
echo "$NEW_CLI_VERSION" > .mole-cli-version

# 5. Increment MoleUI patch version
CURRENT_VERSION=$(grep "MARKETING_VERSION = " MoleUI.xcodeproj/project.pbxproj | head -1 | sed 's/.*MARKETING_VERSION = \(.*\);/\1/')
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
NEW_PATCH=$((PATCH + 1))
NEW_MOLEUI_VERSION="$MAJOR.$MINOR.$NEW_PATCH"
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $NEW_MOLEUI_VERSION/" \
  MoleUI.xcodeproj/project.pbxproj

# 6. Run compatibility checks
SMOKE_HOME="$(mktemp -d /tmp/mole-smoke-home.XXXXXX)"
mkdir -p \
  "$SMOKE_HOME/Desktop" \
  "$SMOKE_HOME/Documents" \
  "$SMOKE_HOME/Downloads" \
  "$SMOKE_HOME/Projects/demo/node_modules" \
  "$SMOKE_HOME/.config/mole"
printf '{}' > "$SMOKE_HOME/Projects/demo/package.json"
: > "$SMOKE_HOME/Downloads/sample-installer.dmg"
printf '%s\n' "$SMOKE_HOME/Projects" > "$SMOKE_HOME/.config/mole/purge_paths"

bash Resources/mole/mole version
bash Resources/mole/mole status --json | python3 -m json.tool > /dev/null
bash Resources/mole/mole analyze --json "$SMOKE_HOME" | python3 -m json.tool > /dev/null
bash Resources/mole/lib/check/health_json.sh | python3 -m json.tool > /dev/null
env HOME="$SMOKE_HOME" TERM=dumb MOLE_TEST_MODE=1 MOLE_DRY_RUN=1 DRY_RUN=true bash Resources/mole/mole clean --dry-run > /dev/null
env HOME="$SMOKE_HOME" TERM=dumb MOLE_TEST_MODE=1 bash Resources/mole/mole optimize --dry-run > /dev/null
env HOME="$SMOKE_HOME" TERM=dumb MOLE_TEST_MODE=1 bash Resources/mole/mole purge --dry-run > /dev/null
env HOME="$SMOKE_HOME" TERM=dumb MOLE_TEST_MODE=1 bash Resources/mole/mole installer --dry-run > /dev/null
env HOME="$SMOKE_HOME" TERM=dumb MOLE_TEST_MODE=1 bash Resources/mole/mole uninstall --dry-run > /dev/null

# 7. Commit and create PR
git checkout -b manual-update-mole-$NEW_CLI_VERSION
git add .
git commit -m "chore: manually update Mole CLI to $NEW_CLI_VERSION (MoleUI $NEW_MOLEUI_VERSION)"
git push -u origin manual-update-mole-$NEW_CLI_VERSION
gh pr create --title "Update Mole CLI to $NEW_CLI_VERSION (MoleUI $NEW_MOLEUI_VERSION)" --body "Manual update"
```

## 7. Troubleshooting

### 7.1 Auto-update Failure

**Symptom:** Auto-update workflow fails

**Troubleshooting Steps:**
1. Check GitHub Actions logs
2. Identify specific compatibility check failure
3. If files missing, check Homebrew-installed Mole CLI structure
4. If command execution fails, manually test commands
5. If JSON schema incompatible, check `status-go` output format changes

### 7.2 Version Number Mismatch

**Symptom:** Release tag version doesn't match Info.plist

**Solution:**
1. Manually modify `MARKETING_VERSION` in `project.pbxproj`
2. Commit changes
3. Delete incorrect tag: `git tag -d v{version} && git push origin :refs/tags/v{version}`
4. Recreate correct tag

### 7.3 CI Check Failure

**Symptom:** CI checks fail after PR creation

**Common Causes:**
- SwiftFormat/SwiftLint conflicts: Run `just fmt && just lint` to fix
- Compilation errors: Check if new version introduces API changes
- Test failures: Check if unit tests need updates

### 7.4 PR Is Open But Not Released Yet

**Symptom:** PR exists and CI is green, but no DMG release was created

**Expected Behavior:**
- The auto-update workflow stops after opening the PR
- A maintainer still needs to merge it
- A release still needs a tag push or a manual `release.yml` trigger

**Solution:**
1. Merge the PR after review
2. Push a `v...` tag if you want a release build
3. Or trigger [`.github/workflows/release.yml`](.github/workflows/release.yml) manually

## 8. Security Considerations

### 8.1 PR-Based Update Safety

- ✅ PR is only created if compatibility checks pass
- ✅ Normal repository CI still runs before merge
- ✅ Manual review remains in the loop for upstream integration changes
- ✅ Breaking upstream changes create an issue instead of silently updating the bundle

### 8.2 Version Validation

- ✅ Use Swift Codable structures to validate JSON schema
- ✅ Verify key field values are reasonable
- ✅ Test all subcommands work correctly
- ✅ Check all required files exist

### 8.3 Rollback Mechanism

If auto-update introduces issues:

1. **Immediate Rollback**
   ```bash
   git revert {commit-hash}
   git push origin main
   ```

2. **Delete Incorrect Release**
   ```bash
   gh release delete v{version} --yes
   git tag -d v{version}
   git push origin :refs/tags/v{version}
   ```

3. **Restore Old Version**
   - Download DMG from previous release
   - Or restore `Resources/mole/` directory from Git history

## 9. Future Improvements

### 9.1 In-App Auto-update

**Current:** Users must manually download DMG and install

**Planned:** Integrate Sparkle framework for true in-app auto-update

```swift
import Sparkle

@main
struct MoleApp: App {
    @StateObject private var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}
```

**Benefits:**
- Users click "Update" to automatically download and install
- Support delta updates
- Automatic signature and notarization verification
- Better user experience

### 9.2 Enhanced Compatibility Checks

**Planned:**
- Add more JSON schema field validation
- Test disk analysis functionality (`analyze-go`)
- Verify cleanup script output format
- Add performance benchmarks

### 9.3 Notification Mechanism

**Planned:**
- Send notification after successful auto-update (GitHub Discussions or Issue)
- Email maintainers when compatibility checks fail
- Display latest version badge in README

## 10. Related Files

- `.github/workflows/auto-update-mole.yml` - Auto-update workflow
- `.github/workflows/release.yml` - Release build workflow
- `.github/workflows/ci.yml` - CI check workflow
- `MoleUI/Model/VersionModel.swift` - Version check logic
- `MoleUI/View/MoleVersionView.swift` - Version display UI
- `MoleUI/View/SettingsView.swift` - Settings with version display
- `.mole-cli-version` - Current Mole CLI version
- `MoleUI.xcodeproj/project.pbxproj` - Xcode project config (contains MARKETING_VERSION)

## 11. References

- [Mole CLI Repository](https://github.com/tw93/Mole)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Sparkle Framework](https://sparkle-project.org/)
- [Apple Code Signing Guide](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
