#!/bin/bash
# Mole - Logging System
# Centralized logging with rotation support

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${MOLE_LOG_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_LOG_LOADED=1

# Ensure base.sh is loaded for colors and icons
if [[ -z "${MOLE_BASE_LOADED:-}" ]]; then
    _MOLE_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=lib/core/base.sh
    source "$_MOLE_CORE_DIR/base.sh"
fi

# ============================================================================
# Logging Configuration
# ============================================================================

readonly LOG_FILE="${HOME}/.config/mole/mole.log"
readonly DEBUG_LOG_FILE="${HOME}/.config/mole/mole_debug_session.log"
readonly OPERATIONS_LOG_FILE="${HOME}/.config/mole/operations.log"
readonly LOG_MAX_SIZE_DEFAULT=1048576   # 1MB
readonly OPLOG_MAX_SIZE_DEFAULT=5242880 # 5MB

# Ensure log directory and file exist with correct ownership
ensure_user_file "$LOG_FILE"
if [[ "${MO_NO_OPLOG:-}" != "1" ]]; then
    ensure_user_file "$OPERATIONS_LOG_FILE"
fi

# ============================================================================
# Log Rotation
# ============================================================================

# Rotate log file if it exceeds maximum size
rotate_log_once() {
    # Skip if already checked this session
    [[ -n "${MOLE_LOG_ROTATED:-}" ]] && return 0
    export MOLE_LOG_ROTATED=1

    local max_size="$LOG_MAX_SIZE_DEFAULT"
    if [[ -f "$LOG_FILE" ]]; then
        local size
        size=$(get_file_size "$LOG_FILE")
        if [[ "$size" -gt "$max_size" ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.old" 2> /dev/null || true
            ensure_user_file "$LOG_FILE"
        fi
    fi

    # Rotate operations log (5MB limit)
    if [[ "${MO_NO_OPLOG:-}" != "1" ]]; then
        local oplog_max_size="$OPLOG_MAX_SIZE_DEFAULT"
        if [[ -f "$OPERATIONS_LOG_FILE" ]]; then
            local size
            size=$(get_file_size "$OPERATIONS_LOG_FILE")
            if [[ "$size" -gt "$oplog_max_size" ]]; then
                mv "$OPERATIONS_LOG_FILE" "${OPERATIONS_LOG_FILE}.old" 2> /dev/null || true
                ensure_user_file "$OPERATIONS_LOG_FILE"
            fi
        fi
    fi
}

# ============================================================================
# Logging Functions
# ============================================================================

# Get current timestamp (centralized for consistency)
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Log informational message
log_info() {
    echo -e "${BLUE}$1${NC}"
    local timestamp
    timestamp=$(get_timestamp)
    echo "[$timestamp] INFO: $1" >> "$LOG_FILE" 2> /dev/null || true
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        echo "[$timestamp] INFO: $1" >> "$DEBUG_LOG_FILE" 2> /dev/null || true
    fi
}

# Log success message
log_success() {
    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} $1"
    local timestamp
    timestamp=$(get_timestamp)
    echo "[$timestamp] SUCCESS: $1" >> "$LOG_FILE" 2> /dev/null || true
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        echo "[$timestamp] SUCCESS: $1" >> "$DEBUG_LOG_FILE" 2> /dev/null || true
    fi
}

# shellcheck disable=SC2329
log_warning() {
    echo -e "${YELLOW}$1${NC}"
    local timestamp
    timestamp=$(get_timestamp)
    echo "[$timestamp] WARNING: $1" >> "$LOG_FILE" 2> /dev/null || true
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        echo "[$timestamp] WARNING: $1" >> "$DEBUG_LOG_FILE" 2> /dev/null || true
    fi
}

# shellcheck disable=SC2329
log_error() {
    echo -e "${YELLOW}${ICON_ERROR}${NC} $1" >&2
    local timestamp
    timestamp=$(get_timestamp)
    echo "[$timestamp] ERROR: $1" >> "$LOG_FILE" 2> /dev/null || true
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        echo "[$timestamp] ERROR: $1" >> "$DEBUG_LOG_FILE" 2> /dev/null || true
    fi
}

# shellcheck disable=SC2329
debug_log() {
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        echo -e "${GRAY}[DEBUG]${NC} $*" >&2
        local timestamp
        timestamp=$(get_timestamp)
        echo "[$timestamp] DEBUG: $*" >> "$DEBUG_LOG_FILE" 2> /dev/null || true
    fi
}

# ============================================================================
# Operation Logging (Enabled by default)
# ============================================================================
# Records all file operations for user troubleshooting
# Disable with MO_NO_OPLOG=1

oplog_enabled() {
    [[ "${MO_NO_OPLOG:-}" != "1" ]]
}

# Log an operation to the operations log file
# Usage: log_operation <command> <action> <path> [detail]
# Example: log_operation "clean" "REMOVED" "/path/to/file" "15.2MB"
# Example: log_operation "clean" "SKIPPED" "/path/to/file" "whitelist"
# Example: log_operation "uninstall" "REMOVED" "/Applications/App.app" "150MB"
log_operation() {
    # Allow disabling via environment variable
    oplog_enabled || return 0

    local command="${1:-unknown}" # clean/uninstall/optimize/purge
    local action="${2:-UNKNOWN}"  # REMOVED/SKIPPED/FAILED/REBUILT
    local path="${3:-}"
    local detail="${4:-}"

    # Skip if no path provided
    [[ -z "$path" ]] && return 0

    local timestamp
    timestamp=$(get_timestamp)

    local log_line="[$timestamp] [$command] $action $path"
    [[ -n "$detail" ]] && log_line+=" ($detail)"

    echo "$log_line" >> "$OPERATIONS_LOG_FILE" 2> /dev/null || true
}

# Log session start marker
# Usage: log_operation_session_start <command>
log_operation_session_start() {
    oplog_enabled || return 0

    local command="${1:-mole}"
    local timestamp
    timestamp=$(get_timestamp)

    {
        echo ""
        echo "# ========== $command session started at $timestamp =========="
    } >> "$OPERATIONS_LOG_FILE" 2> /dev/null || true
}

# shellcheck disable=SC2329
log_operation_session_end() {
    oplog_enabled || return 0

    local command="${1:-mole}"
    local items="${2:-0}"
    local size="${3:-0}"
    local timestamp
    timestamp=$(get_timestamp)

    local size_human=""
    if [[ "$size" =~ ^[0-9]+$ ]] && [[ "$size" -gt 0 ]]; then
        size_human=$(bytes_to_human "$((size * 1024))" 2> /dev/null || echo "${size}KB")
    else
        size_human="0B"
    fi

    {
        echo "# ========== $command session ended at $timestamp, $items items, $size_human =========="
    } >> "$OPERATIONS_LOG_FILE" 2> /dev/null || true
}

# Enhanced debug logging for operations
debug_operation_start() {
    local operation_name="$1"
    local operation_desc="${2:-}"

    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        # Output to stderr for immediate feedback
        echo -e "${GRAY}[DEBUG] === $operation_name ===${NC}" >&2
        [[ -n "$operation_desc" ]] && echo -e "${GRAY}[DEBUG] $operation_desc${NC}" >&2

        # Also log to file
        {
            echo ""
            echo "=== $operation_name ==="
            [[ -n "$operation_desc" ]] && echo "Description: $operation_desc"
        } >> "$DEBUG_LOG_FILE" 2> /dev/null || true
    fi
}

# Log detailed operation information
debug_operation_detail() {
    local detail_type="$1" # e.g., "Method", "Target", "Expected Outcome"
    local detail_value="$2"

    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        # Output to stderr
        echo -e "${GRAY}[DEBUG] $detail_type: $detail_value${NC}" >&2

        # Also log to file
        echo "$detail_type: $detail_value" >> "$DEBUG_LOG_FILE" 2> /dev/null || true
    fi
}

# Log individual file action with metadata
debug_file_action() {
    local action="$1" # e.g., "Would remove", "Removing"
    local file_path="$2"
    local file_size="${3:-}"
    local file_age="${4:-}"

    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        local msg="  * $file_path"
        [[ -n "$file_size" ]] && msg+=", $file_size"
        [[ -n "$file_age" ]] && msg+=", ${file_age} days old"

        # Output to stderr
        echo -e "${GRAY}[DEBUG] $action: $msg${NC}" >&2

        # Also log to file
        echo "$action: $msg" >> "$DEBUG_LOG_FILE" 2> /dev/null || true
    fi
}

# Log risk level for operations
debug_risk_level() {
    local risk_level="$1" # LOW, MEDIUM, HIGH
    local reason="$2"

    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        local color="$GRAY"
        case "$risk_level" in
            LOW) color="$GREEN" ;;
            MEDIUM) color="$YELLOW" ;;
            HIGH) color="$RED" ;;
        esac

        # Output to stderr with color
        echo -e "${GRAY}[DEBUG] Risk Level: ${color}${risk_level}${GRAY}, $reason${NC}" >&2

        # Also log to file
        echo "Risk Level: $risk_level, $reason" >> "$DEBUG_LOG_FILE" 2> /dev/null || true
    fi
}

# Log system information for debugging
log_system_info() {
    # Only allow once per session
    [[ -n "${MOLE_SYS_INFO_LOGGED:-}" ]] && return 0
    export MOLE_SYS_INFO_LOGGED=1

    # Reset debug log file for this new session
    ensure_user_file "$DEBUG_LOG_FILE"
    if ! : > "$DEBUG_LOG_FILE" 2> /dev/null; then
        echo -e "${YELLOW}${ICON_WARNING}${NC} Debug log not writable: $DEBUG_LOG_FILE" >&2
    fi

    # Start block in debug log file
    {
        echo "----------------------------------------------------------------------"
        echo "Mole Debug Session, $(date '+%Y-%m-%d %H:%M:%S')"
        echo "----------------------------------------------------------------------"
        echo "User: $USER"
        echo "Hostname: $(hostname)"
        echo "Architecture: $(uname -m)"
        echo "Kernel: $(uname -r)"
        if command -v sw_vers > /dev/null; then
            echo "macOS: $(sw_vers -productVersion), $(sw_vers -buildVersion)"
        fi
        echo "Shell: ${SHELL:-unknown}, ${TERM:-unknown}"

        # Check sudo status non-interactively
        if sudo -n true 2> /dev/null; then
            echo "Sudo Access: Active"
        else
            echo "Sudo Access: Required"
        fi
        echo "----------------------------------------------------------------------"
    } >> "$DEBUG_LOG_FILE" 2> /dev/null || true

    # Notification to stderr
    echo -e "${GRAY}[DEBUG] Debug logging enabled. Session log: $DEBUG_LOG_FILE${NC}" >&2
}

# ============================================================================
# Command Execution Wrappers
# ============================================================================

# Run command silently (ignore errors)
run_silent() {
    "$@" > /dev/null 2>&1 || true
}

# Run command with error logging
run_logged() {
    local cmd="$1"
    # Log to main file, and also to debug file if enabled
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        if ! "$@" 2>&1 | tee -a "$LOG_FILE" | tee -a "$DEBUG_LOG_FILE" > /dev/null; then
            log_warning "Command failed: $cmd"
            return 1
        fi
    else
        if ! "$@" 2>&1 | tee -a "$LOG_FILE" > /dev/null; then
            log_warning "Command failed: $cmd"
            return 1
        fi
    fi
    return 0
}

# ============================================================================
# Formatted Output
# ============================================================================

# Print formatted summary block
print_summary_block() {
    local heading=""
    local -a details=()
    local saw_heading=false

    # Parse arguments
    for arg in "$@"; do
        if [[ "$saw_heading" == "false" ]]; then
            saw_heading=true
            heading="$arg"
        else
            details+=("$arg")
        fi
    done

    local _tw
    _tw=$(tput cols 2> /dev/null || echo 70)
    [[ "$_tw" =~ ^[0-9]+$ ]] || _tw=70
    [[ $_tw -gt 70 ]] && _tw=70
    local divider
    divider=$(printf '%*s' "$_tw" '' | tr ' ' '=')

    # Print with dividers
    echo ""
    echo "$divider"
    if [[ -n "$heading" ]]; then
        echo -e "${BLUE}${heading}${NC}"
    fi

    # Print details
    for detail in "${details[@]}"; do
        [[ -z "$detail" ]] && continue
        echo -e "${detail}"
    done
    echo "$divider"

    # If debug mode is on, remind user about the log file location
    if [[ "${MO_DEBUG:-}" == "1" ]]; then
        echo -e "${GRAY}Debug session log saved to:${NC} ${DEBUG_LOG_FILE}"
    fi
}

# ============================================================================
# Initialize Logging
# ============================================================================

# Perform log rotation check on module load
rotate_log_once

# If debug mode is enabled, log system info immediately
if [[ "${MO_DEBUG:-}" == "1" ]]; then
    log_system_info
fi
