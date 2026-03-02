# [Feature Request] Make status-go callable from non-TTY environments

## Problem Description

The `status-go` binary (used by `mo status` command) has a hardcoded dependency on `/dev/tty`, which prevents it from being called programmatically from GUI applications or other non-interactive environments.

### Current Behavior

When calling `status-go` from a GUI application (e.g., SwiftUI, Electron):

```bash
$ /path/to/status-go --json --watch
system status error: could not open a new TTY: open /dev/tty: device not configured
```

### Expected Behavior

The `--json` flag should work in non-TTY environments, outputting pure JSON to stdout without requiring a terminal.

## Use Case

I'm developing **MoleUI**, a native macOS GUI application for Mole. The app needs to call `status-go` to display system metrics in a SwiftUI interface. However, the TTY dependency makes this impossible.

**Repository**: https://github.com/imnotnoahhh/MoleUI

## Attempted Workarounds

I've tried multiple approaches to work around this issue:

| Approach | Result | Issue |
|----------|--------|-------|
| Direct execution | ❌ Failed | No TTY available in GUI app |
| Shell wrapper | ❌ Failed | Path escaping issues |
| `script` command (PTY emulation) | ❌ Failed | Outputs TUI instead of JSON |
| `expect` command | ❌ Failed | Same TUI output issue |
| Environment variables (`TERM=dumb`) | ❌ Failed | No effect |

Even when using PTY emulation, `status-go` outputs TUI (Text User Interface) format with ANSI escape codes instead of respecting the `--json` flag.

## Current Solution

I've had to implement a **native Swift version** of all system monitoring features, which works but requires significant maintenance effort to keep in sync with Mole CLI.

See: [NATIVE_IMPLEMENTATION.md](https://github.com/imnotnoahhh/MoleUI/blob/main/NATIVE_IMPLEMENTATION.md)

## Proposed Solution

### Option 1: Auto-detect TTY availability

```go
// Pseudo-code
if isatty(os.Stdin.Fd()) {
    // Use TUI mode
    initTUI()
} else {
    // Use non-interactive mode
    disableTUI()
}
```

### Option 2: Add `--no-tty` flag

```bash
$ status-go --json --no-tty --watch
# Outputs pure JSON without requiring TTY
```

### Option 3: Respect `--json` flag strictly

When `--json` is specified, disable all TUI features and output pure JSON regardless of TTY availability.

## Benefits

1. **Enables GUI applications**: Apps like MoleUI can use Mole CLI directly
2. **Better automation**: Scripts and CI/CD pipelines can use `status-go`
3. **Wider adoption**: More use cases for Mole CLI
4. **Reduced maintenance**: No need for duplicate implementations

## Technical Details

### Where to look

The TTY dependency is likely in:
- TUI initialization code
- Terminal detection logic
- Output formatting logic

### Testing

The fix should be tested in:
- ✅ Interactive terminal (existing behavior)
- ✅ Non-interactive environment (new behavior)
- ✅ With `--json` flag
- ✅ With `--watch` flag
- ✅ Piped output (`status-go --json | jq`)

## Alternatives Considered

1. **Keep native implementation**: Works but requires maintenance
2. **Create wrapper binary**: Adds complexity and overhead
3. **Use different monitoring tool**: Defeats the purpose of using Mole

## Additional Context

- **Platform**: macOS (but issue affects all platforms)
- **Mole Version**: 1.28.1
- **Use case**: GUI application (SwiftUI)

## Willingness to Contribute

I'm willing to:
- [ ] Submit a PR with the fix
- [ ] Write tests
- [ ] Update documentation
- [ ] Help with code review

However, I need guidance on:
- Preferred solution approach (Option 1, 2, or 3?)
- Codebase structure and conventions
- Testing requirements

## References

- MoleUI Repository: https://github.com/imnotnoahhh/MoleUI
- Native Implementation Docs: [NATIVE_IMPLEMENTATION.md](https://github.com/imnotnoahhh/MoleUI/blob/main/NATIVE_IMPLEMENTATION.md)
- Related Issue: (if any)

---

**Note**: This is a feature request, not a bug report. The current behavior is by design, but it limits the use cases for Mole CLI.
