# Security Policy

## Supported Versions

We release patches for security vulnerabilities in the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

We take the security of MoleUI seriously. If you believe you have found a security vulnerability, please report it to us as described below.

### Please Do Not

- Open a public GitHub issue for security vulnerabilities
- Disclose the vulnerability publicly before it has been addressed

### Please Do

1. **Report via GitHub Security Advisories** (preferred method):
   - Go to https://github.com/imnotnoahhh/MoleUI/security/advisories
   - Click "Report a vulnerability"
   - Fill in the details using the template below

2. **Or email directly** to the repository maintainer (email found in GitHub profile commits)

3. **Include the following information:**
   - Type of vulnerability
   - Full paths of source file(s) related to the vulnerability
   - Location of the affected source code (tag/branch/commit or direct URL)
   - Step-by-step instructions to reproduce the issue
   - Proof-of-concept or exploit code (if possible)
   - Impact of the vulnerability, including how an attacker might exploit it

### What to Expect

- **Acknowledgment:** We will acknowledge receipt of your vulnerability report within 48 hours
- **Communication:** We will keep you informed about the progress of fixing the vulnerability
- **Timeline:** We aim to address critical vulnerabilities within 7 days
- **Credit:** We will credit you in the security advisory (unless you prefer to remain anonymous)

## Security Best Practices

### For Users

1. **Download from Official Sources:** Only download MoleUI from official GitHub Releases
2. **Verify Signatures:** Ensure the DMG is properly signed and notarized by Apple
3. **Keep Updated:** Always use the latest version to benefit from security patches
4. **Review Permissions:** MoleUI requires admin privileges for cleanup operations - review what you're cleaning before proceeding
5. **Use Dry Run Mode:** Test cleanup operations in dry run mode first

### For Contributors

1. **Code Review:** All code changes require review before merging
2. **Dependency Updates:** Keep dependencies up to date and review security advisories
3. **Input Validation:** Always validate and sanitize user input
4. **Privilege Escalation:** Use `SudoHelper` carefully and only when necessary
5. **Secrets Management:** Never commit API keys, tokens, or credentials
6. **Code Signing:** All releases must be properly signed and notarized

## Security Features

MoleUI implements several security measures:

- **Whitelist Protection:** Users can protect critical paths from cleanup
- **Confirmation Dialogs:** Destructive operations require user confirmation
- **Dry Run Mode:** Preview changes before applying them
- **Code Signing:** All releases are signed with Apple Developer ID
- **Notarization:** All releases are notarized by Apple
- **Compatibility Checks:** Auto-update system validates compatibility before merging

## Known Security Considerations

### Admin Privileges

MoleUI requires admin privileges for certain operations (cleanup, optimization). This is necessary because:
- System cleanup requires access to protected directories
- Some optimization tasks require system-level changes

**Mitigation:**
- Privileges are requested only when needed
- Users can review operations in dry run mode first
- Whitelist system protects critical paths

### Bundled Mole CLI

MoleUI bundles the Mole CLI binary. Security considerations:
- CLI is sourced from official Homebrew tap
- Compatibility checks validate CLI behavior
- Auto-update system includes security validation

**Mitigation:**
- Automated compatibility checks before updates
- Manual review for breaking changes
- Rollback mechanism for problematic updates

## Security Updates

Security updates will be released as patch versions (e.g., 0.1.1 → 0.1.2) and announced via:
- GitHub Security Advisories
- Release notes
- In-app update notifications

## Third-Party Dependencies

MoleUI relies on:
- **Mole CLI** (tw93/Mole): System maintenance tool
- **SwiftUI**: Apple's UI framework
- **Foundation**: Apple's core framework

We monitor security advisories for all dependencies and update promptly when vulnerabilities are discovered.

## Compliance

MoleUI follows:
- Apple's App Store Review Guidelines (for potential future distribution)
- macOS security best practices
- OWASP secure coding guidelines

## Questions

If you have questions about this security policy, please open a GitHub Discussion or contact the maintainers.

## Acknowledgments

We appreciate the security research community's efforts in responsibly disclosing vulnerabilities. Contributors who report valid security issues will be acknowledged in our security advisories (with their permission).
