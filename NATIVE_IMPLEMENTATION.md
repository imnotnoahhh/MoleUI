# Native Swift Implementation for System Monitoring

## Why We Use Swift Instead of Mole's status-go

MoleUI uses a native Swift implementation for system monitoring instead of calling Mole CLI's `status-go` binary due to fundamental TTY (terminal) dependency issues that prevent it from being called from GUI applications.

## The Problem

### 1. Hardcoded TTY Dependency

The `status-go` binary has a hardcoded dependency on `/dev/tty`:

```
system status error: could not open a new TTY: open /dev/tty: device not configured
```

When called from a GUI application (SwiftUI), there is no associated TTY, causing the program to fail immediately.

### 2. TUI Output Mode

Even when we attempted to work around this using PTY (pseudo-terminal) emulation:
- Using `script` command to create a PTY
- Using `expect` tool
- Setting environment variables like `TERM=dumb`

The result was that `status-go` outputs **TUI (Text User Interface) format** with ANSI escape codes and ASCII art, instead of the JSON format requested by the `--json` flag.

### 3. Design Philosophy Mismatch

`status-go` was designed as:
- **Interactive terminal tool**: Meant to be run directly by users in a terminal
- **Real-time TUI display**: Uses ASCII art and animations to show system status
- **Not programmatically callable**: Doesn't consider being called by other programs

## Attempted Solutions

We tried multiple approaches to work around the TTY issue:

| Approach | Result | Issue |
|----------|--------|-------|
| Direct execution | ❌ Failed | No TTY available |
| Shell wrapper | ❌ Failed | Path escaping issues |
| `script` command (PTY) | ❌ Failed | Outputs TUI instead of JSON |
| `expect` command | ❌ Failed | Same TUI output issue |
| Environment variable tricks | ❌ Failed | `TERM=dumb` has no effect |

## Our Solution: Native Swift Implementation

We implemented system monitoring using native macOS APIs in Swift.

### Advantages

- **Full control**: Direct access to macOS system APIs
- **No dependencies**: No need for external binaries
- **More reliable**: No TTY issues
- **Better performance**: No inter-process communication overhead
- **Better integration**: Native Swift code integrates seamlessly with SwiftUI

### Disadvantages

- **More implementation work**: Need to implement all monitoring features
- **Maintenance burden**: Must keep output consistent with Mole CLI
- **Complex features**: Some features (like SMC temperature reading) are complex

## Implementation Status

### ✅ Fully Implemented

- **CPU Monitoring**
  - Overall usage percentage
  - Per-core usage
  - Load averages (1, 5, 15 minutes)
  - P/E core detection (Apple Silicon)
  - Using: `host_processor_info`, `sysctl`

- **Memory Monitoring**
  - Used/total memory
  - Usage percentage
  - Cached memory
  - Memory pressure status
  - Using: `host_statistics64`, `vm_statistics64`

- **Disk Monitoring**
  - Internal/external disk detection
  - Used/total capacity
  - Usage percentage
  - Disk I/O rates (read/write MB/s)
  - Using: `FileManager`, `IOKit` (IOBlockStorageDriver)

- **Network Monitoring**
  - Interface detection
  - IP addresses
  - Upload/download rates
  - Network history (for graphs)
  - Proxy detection (HTTP/HTTPS/SOCKS)
  - Using: `getifaddrs`, `CFNetworkCopySystemProxySettings`

- **Battery Monitoring**
  - Battery percentage
  - Charging status
  - Health status (Normal/Fair/Poor)
  - Cycle count (from IORegistry)
  - Adapter power (watts)
  - Using: `IOPSCopyPowerSourcesInfo`, `IORegistry` (AppleSmartBattery)

- **Process Monitoring**
  - Top processes by CPU usage
  - Memory usage per process
  - Using: `ps` command

- **Health Score Calculation**
  - Based on CPU, memory, disk, and temperature
  - Scoring algorithm matches Mole CLI behavior

### ⚠️ Partially Implemented

- **CPU Temperature**
  - Currently using estimation based on CPU usage
  - Real SMC (System Management Controller) reading is complex
  - Requires specific data structures and IOKit calls
  - **Status**: Estimated values (30-60°C range)

### ❌ Not Yet Implemented

- **GPU Monitoring**
  - GPU usage percentage
  - GPU memory usage
  - GPU temperature
  - **Requires**: IOKit AGXAccelerator service

- **Fan Monitoring**
  - Fan speed (RPM)
  - Fan count
  - **Requires**: SMC key reading

- **Accurate Temperature Reading**
  - CPU die temperature
  - GPU temperature
  - **Requires**: SMC key reading (TC0P, TC0D, TG0P)

## Technical Details

### Key Technologies Used

1. **Darwin/Mach APIs**
   - `host_processor_info`: CPU statistics
   - `host_statistics64`: Memory statistics
   - `sysctl`/`sysctlbyname`: System information

2. **IOKit Framework**
   - `IOServiceMatching`: Device matching
   - `IORegistryEntryCreateCFProperties`: Device properties
   - `IOPSCopyPowerSourcesInfo`: Battery information

3. **BSD APIs**
   - `getifaddrs`: Network interface enumeration
   - `getnameinfo`: IP address resolution

4. **Foundation Framework**
   - `FileManager`: Disk enumeration
   - `Process`: External command execution

### Code Structure

```
MoleUI/Model/
├── MetricsModel.swift          # Main model with @Observable
└── NativeMetricsCollector      # Native implementation (inside MetricsModel.swift)
    ├── collectSnapshot()       # Main collection method
    ├── getCPUStatus()          # CPU monitoring
    ├── getMemoryStatus()       # Memory monitoring
    ├── getDiskStatus()         # Disk monitoring
    ├── getNetworkStatus()      # Network monitoring
    ├── getBatteryStatus()      # Battery monitoring
    ├── getThermalStatus()      # Temperature/power monitoring
    └── getTopProcesses()       # Process monitoring
```

## Future Improvements

### Option 1: Complete Native Implementation

Continue implementing missing features in Swift:

- [ ] Implement SMC temperature reading
  - Research SMC data structures
  - Implement SMC key reading functions
  - Read CPU/GPU temperature sensors

- [ ] Implement GPU monitoring
  - Use IOKit AGXAccelerator service
  - Read GPU usage and memory
  - Read GPU temperature

- [ ] Implement fan monitoring
  - Read fan speed from SMC
  - Detect fan count

### Option 2: Fix Mole CLI

Submit a PR to the Mole repository to fix the TTY dependency:

- [ ] Identify where `/dev/tty` is opened in the code
- [ ] Add a flag to disable TUI mode (e.g., `--no-tty`)
- [ ] Ensure `--json` flag works without TTY
- [ ] Test in non-interactive environments
- [ ] Submit PR with test cases

## Comparison with Mole CLI

| Feature | Mole CLI (status-go) | MoleUI (Swift) | Match |
|---------|---------------------|----------------|-------|
| CPU Usage | ✅ | ✅ | ✅ |
| Per-core CPU | ✅ | ✅ | ✅ |
| Memory | ✅ | ✅ | ✅ |
| Disk Usage | ✅ | ✅ | ✅ |
| Disk I/O | ✅ | ✅ | ✅ |
| Network | ✅ | ✅ | ✅ |
| Battery | ✅ | ✅ | ✅ |
| Processes | ✅ | ✅ | ✅ |
| Proxy | ✅ | ✅ | ✅ |
| Health Score | ✅ | ✅ | ✅ |
| CPU Temp | ✅ | ⚠️ Estimated | ⚠️ |
| GPU | ✅ | ❌ | ❌ |
| Fans | ✅ | ❌ | ❌ |

## References

- [IOKit Framework Documentation](https://developer.apple.com/documentation/iokit)
- [Mach Kernel APIs](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/KernelProgramming/)
- [System Management Controller (SMC)](https://en.wikipedia.org/wiki/System_Management_Controller)
- [Mole CLI Repository](https://github.com/imnotnoahhh/mole)

## Contributing

If you want to help improve the native implementation:

1. Check the TODO list below
2. Pick an unimplemented feature
3. Research the required APIs
4. Implement and test
5. Submit a PR

## TODO List

See [TODO.md](TODO.md) for the complete task list.
