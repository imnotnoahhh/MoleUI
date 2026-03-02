# MoleUI TODO List

## ⚠️ URGENT: Auto-Update Workflow Fix

### Fix Auto-Update Workflow (COMPLETED ✅)
- [x] Remove status-go dependency from compatibility checks
  - Removed file existence check for `status-go`
  - Removed `mole status --help` command test
  - Removed JSON schema validation
- [x] Update compatibility checks to only test used features
  - Check analyze-go, shell scripts
  - Test clean, optimize, analyze, purge, installer, uninstall commands
  - Verify script executable permissions
- [x] Update PR description template
  - Add note about native Swift implementation
  - Link to NATIVE_IMPLEMENTATION.md
- [x] Update AUTO_UPDATE.md documentation
  - Explain why status-go checks were removed
  - Document new compatibility check logic

**Why this was urgent:** The old workflow would mark every Mole update as "incompatible" due to status-go's TTY dependency, creating false-positive issues and blocking automatic updates.

**Status:** Fixed in this commit. Future Mole updates will now be handled correctly.

---

## Priority 1: Complete Native Implementation

### SMC Temperature Reading
- [ ] Research SMC data structures and protocols
  - Study existing SMC libraries (e.g., [SMCKit](https://github.com/beltex/SMCKit))
  - Understand SMC key format (4-character codes)
  - Document required IOKit calls
- [ ] Implement SMC connection and key reading
  - Open connection to AppleSMC service
  - Implement `SMCReadKey()` function
  - Handle data type conversions (sp78, flt, etc.)
- [ ] Read CPU temperature sensors
  - TC0P (CPU Proximity)
  - TC0D (CPU Die)
  - TC0E (CPU Core Average)
- [ ] Read GPU temperature sensors
  - TG0P (GPU Proximity)
  - TG0D (GPU Die)
- [ ] Test on different Mac models
  - Intel Macs
  - Apple Silicon (M1/M2/M3/M4)
  - Verify sensor key availability

**Estimated effort**: 8-12 hours
**Difficulty**: High
**Priority**: High (affects health score accuracy)

### GPU Monitoring
- [ ] Research AGXAccelerator IOKit service
  - Identify available properties
  - Document GPU metrics structure
- [ ] Implement GPU usage reading
  - Device utilization percentage
  - Renderer utilization
- [ ] Implement GPU memory reading
  - Used memory
  - Total memory
  - Memory bandwidth
- [ ] Add GPU info to hardware detection
  - GPU model name
  - GPU core count (already partially implemented)
- [ ] Test on different GPU configurations
  - Integrated GPU only
  - Discrete GPU
  - Multiple GPUs

**Estimated effort**: 6-8 hours
**Difficulty**: Medium
**Priority**: Medium

### Fan Monitoring
- [ ] Implement SMC fan key reading
  - F0Ac (Fan 0 Actual Speed)
  - F1Ac (Fan 1 Actual Speed)
  - FNum (Number of Fans)
- [ ] Add fan speed to ThermalStatus
- [ ] Display fan information in UI
- [ ] Handle systems with multiple fans

**Estimated effort**: 2-4 hours
**Difficulty**: Medium
**Priority**: Low

## Priority 2: Improve Existing Features

### Health Score Algorithm
- [ ] Compare with Mole CLI's actual scoring
  - Run both side-by-side
  - Document differences
  - Adjust weights to match
- [ ] Add more factors
  - Disk I/O pressure
  - Network latency/errors
  - Swap usage
- [ ] Add configurable thresholds
  - User preferences for warning levels
  - Custom scoring weights

**Estimated effort**: 4-6 hours
**Difficulty**: Low
**Priority**: Medium

### Disk I/O Monitoring
- [ ] Verify accuracy of I/O rates
  - Compare with `iostat` command
  - Test under heavy I/O load
- [ ] Add per-disk I/O statistics
  - Currently shows aggregate only
  - Show per-disk read/write rates
- [ ] Add I/O wait time metrics

**Estimated effort**: 3-4 hours
**Difficulty**: Low
**Priority**: Low

### Network Monitoring
- [ ] Add network error statistics
  - Packet loss
  - Errors/collisions
- [ ] Add network latency monitoring
  - Ping to gateway
  - DNS resolution time
- [ ] Improve interface detection
  - Better filtering of virtual interfaces
  - Detect VPN connections

**Estimated effort**: 4-6 hours
**Difficulty**: Medium
**Priority**: Low

### Process Monitoring
- [ ] Add accurate CPU usage per process
  - Currently shows 0.0% for all processes
  - Need to track CPU time over intervals
- [ ] Add process filtering options
  - Hide system processes
  - Search/filter by name
- [ ] Add process details
  - PID
  - User
  - Command line

**Estimated effort**: 3-5 hours
**Difficulty**: Medium
**Priority**: Medium

## Priority 3: Fix Mole CLI (Upstream)

### Option A: Submit PR to Mole Repository

- [ ] **Investigation Phase**
  - [ ] Clone Mole repository
  - [ ] Locate TTY dependency in code
    - Search for `/dev/tty` references
    - Identify TUI initialization code
  - [ ] Understand the codebase structure
    - Identify status command implementation
    - Locate JSON output logic
  - [ ] Document current behavior
    - When does it require TTY?
    - What triggers TUI mode?

- [ ] **Design Phase**
  - [ ] Design solution approach
    - Option 1: Add `--no-tty` flag
    - Option 2: Auto-detect TTY availability
    - Option 3: Separate `status-json` command
  - [ ] Write design document
  - [ ] Get feedback from maintainers (open issue first)

- [ ] **Implementation Phase**
  - [ ] Implement TTY detection
    - Check if stdin/stdout is a TTY
    - Gracefully handle missing TTY
  - [ ] Ensure `--json` works without TTY
    - Disable TUI when `--json` is specified
    - Output pure JSON to stdout
  - [ ] Add tests
    - Test in interactive terminal
    - Test in non-interactive environment
    - Test with `--json` flag
  - [ ] Update documentation

- [ ] **Submission Phase**
  - [ ] Create PR with detailed description
  - [ ] Include test cases
  - [ ] Respond to review feedback
  - [ ] Get PR merged

**Estimated effort**: 16-24 hours
**Difficulty**: High (requires Go knowledge + upstream coordination)
**Priority**: Low (native implementation works well)

### Option B: Create Wrapper Binary

- [ ] Create a lightweight wrapper in Swift/C
  - Calls Mole CLI with proper environment
  - Handles TTY emulation if needed
  - Parses and forwards JSON output
- [ ] Bundle wrapper with MoleUI
- [ ] Fall back to native implementation if wrapper fails

**Estimated effort**: 8-12 hours
**Difficulty**: Medium
**Priority**: Low

## Priority 4: Testing & Quality

### Unit Tests
- [ ] Add unit tests for NativeMetricsCollector
  - Test data parsing
  - Test error handling
  - Mock system APIs
- [ ] Add UI tests
  - Test dashboard rendering
  - Test data updates
  - Test error states

**Estimated effort**: 8-12 hours
**Difficulty**: Medium
**Priority**: Medium

### Performance Optimization
- [ ] Profile collection performance
  - Measure time per metric
  - Identify bottlenecks
- [ ] Optimize collection frequency
  - Reduce unnecessary updates
  - Batch API calls
- [ ] Reduce memory usage
  - Limit history buffer sizes
  - Release resources properly

**Estimated effort**: 4-6 hours
**Difficulty**: Medium
**Priority**: Low

### Error Handling
- [ ] Add comprehensive error handling
  - Handle missing sensors gracefully
  - Provide fallback values
  - Log errors for debugging
- [ ] Add user-facing error messages
  - Clear explanations
  - Suggested actions
- [ ] Add retry logic for transient failures

**Estimated effort**: 4-6 hours
**Difficulty**: Low
**Priority**: Medium

## Priority 5: Documentation

### Code Documentation
- [ ] Add inline documentation
  - Document all public APIs
  - Explain complex algorithms
  - Add usage examples
- [ ] Generate API documentation
  - Use Swift DocC
  - Publish to GitHub Pages

**Estimated effort**: 6-8 hours
**Difficulty**: Low
**Priority**: Low

### User Documentation
- [ ] Create user guide
  - How to interpret metrics
  - What each value means
  - Troubleshooting common issues
- [ ] Add FAQ section
- [ ] Create video tutorials

**Estimated effort**: 8-12 hours
**Difficulty**: Low
**Priority**: Low

## Completed ✅

- ✅ CPU monitoring (overall and per-core)
- ✅ Memory monitoring
- ✅ Disk usage monitoring
- ✅ Disk I/O rate monitoring
- ✅ Network monitoring with history
- ✅ Battery monitoring with cycle count
- ✅ Process list (top processes)
- ✅ Proxy detection
- ✅ Health score calculation
- ✅ P/E core detection (Apple Silicon)
- ✅ External disk detection
- ✅ Network history graphs
- ✅ Hardware info (model, CPU, RAM, disk size)

## Notes

### Why Not Use Mole CLI?

See [NATIVE_IMPLEMENTATION.md](NATIVE_IMPLEMENTATION.md) for detailed explanation of why we use native Swift implementation instead of calling Mole CLI's `status-go` binary.

**TL;DR**: `status-go` has hardcoded TTY dependency and cannot be called from GUI applications.

### Contributing

Pick any task from this list and:
1. Comment on the task to claim it
2. Create a feature branch
3. Implement and test
4. Submit a PR with reference to this TODO item

### Priority Levels

- **Priority 1**: Critical features needed for feature parity
- **Priority 2**: Improvements to existing features
- **Priority 3**: Upstream fixes (optional)
- **Priority 4**: Quality and reliability
- **Priority 5**: Documentation and polish
