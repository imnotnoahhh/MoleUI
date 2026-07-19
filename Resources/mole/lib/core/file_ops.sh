#!/bin/bash
# Mole - File Operations
# Safe file and directory manipulation with validation

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${MOLE_FILE_OPS_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_FILE_OPS_LOADED=1

# Error codes for removal operations
readonly MOLE_ERR_SIP_PROTECTED=10
readonly MOLE_ERR_AUTH_FAILED=11
readonly MOLE_ERR_READONLY_FS=12
readonly MOLE_ERR_PROTECTED_PATH=13

# Ensure dependencies are loaded
_MOLE_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${MOLE_BASE_LOADED:-}" ]]; then
    # shellcheck source=lib/core/base.sh
    source "$_MOLE_CORE_DIR/base.sh"
fi
if [[ -z "${MOLE_LOG_LOADED:-}" ]]; then
    # shellcheck source=lib/core/log.sh
    source "$_MOLE_CORE_DIR/log.sh"
fi
if [[ -z "${MOLE_TIMEOUT_LOADED:-}" ]]; then
    # shellcheck source=lib/core/timeout.sh
    source "$_MOLE_CORE_DIR/timeout.sh"
fi

# ============================================================================
# Utility Functions
# ============================================================================

# Format duration in seconds to human readable string (e.g., "5 days", "2 months")
format_duration_human() {
    local seconds="${1:-0}"
    [[ ! "$seconds" =~ ^[0-9]+$ ]] && seconds=0

    local days=$((seconds / 86400))

    if [[ $days -eq 0 ]]; then
        echo "today"
    elif [[ $days -eq 1 ]]; then
        echo "1 day"
    elif [[ $days -lt 7 ]]; then
        echo "${days} days"
    elif [[ $days -lt 30 ]]; then
        local weeks=$((days / 7))
        [[ $weeks -eq 1 ]] && echo "1 week" || echo "${weeks} weeks"
    elif [[ $days -lt 365 ]]; then
        local months=$((days / 30))
        [[ $months -eq 1 ]] && echo "1 month" || echo "${months} months"
    else
        local years=$((days / 365))
        [[ $years -eq 1 ]] && echo "1 year" || echo "${years} years"
    fi
}

# ============================================================================
# Path Validation
# ============================================================================

_mole_normalize_deletion_policy_path() {
    local path="$1"
    local slash="/"
    local double_slash="//"

    while [[ "$path" == *"$double_slash"* ]]; do
        path="${path//$double_slash/$slash}"
    done

    local trimmed="${path%/}"
    [[ -n "$trimmed" ]] && printf '%s\n' "$trimmed" || printf '%s\n' "$path"
}

# Deletion policy only. App/data protection stays in app_protection.sh.
_mole_is_critical_deletion_path() {
    local path="$1"

    case "$path" in
        # Homebrew (Intel) and user-installed software live here; individual
        # entries stay deletable. The Homebrew roots themselves are still
        # critical roots and must fall through to the deny arms below.
        /usr/local/* | /opt/homebrew/*)
            return 1
            ;;
        / | \
            /bin | /bin/* | \
            /sbin | /sbin/* | \
            /usr | /usr/* | \
            /System | /System/* | \
            /Library | /Library/Apple | /Library/Apple/* | \
            /Library/Application\ Support | \
            /Library/Extensions | /Library/Extensions/* | \
            /Library/Keychains | /Library/Keychains/* | \
            /Applications | \
            /Applications/Finder.app | /Applications/Finder.app/* | \
            /Applications/Safari.app | /Applications/Safari.app/* | \
            /Volumes | \
            /opt | /opt/homebrew | \
            /Users | /Users/Shared | /Users/Guest | /Users/Guest/*)
            return 0
            ;;
        /private)
            return 0
            ;;
        /etc | /etc/* | /private/etc | /private/etc/*)
            return 0
            ;;
        /var | /var/db | /var/db/* | /var/audit | /var/audit/* | /var/root | \
            /private/var | /private/var/db | /private/var/db/* | /private/var/audit | /private/var/audit/* | /private/var/root)
            return 0
            ;;
    esac

    # Reject a user home root (/Users/<name>) while keeping its children
    # deletable. A single case glob cannot express "exactly one component
    # under /Users", so match one level here: this catches the empty-variable
    # collapse "/Users/$user/$leaf" -> "/Users/<name>" that would otherwise
    # hand rm -rf an entire home directory.
    if [[ "$path" == /Users/* && "$path" != /Users/*/* ]]; then
        return 0
    fi

    return 1
}

# Validate path for deletion (absolute, no traversal, not system dir)
validate_path_for_deletion() {
    local path="$1"

    # Check path is not empty
    if [[ -z "$path" ]]; then
        log_error "Path validation failed: empty path"
        return 1
    fi

    # Check path is absolute
    if [[ "$path" != /* ]]; then
        log_error "Path validation failed: path must be absolute: $path"
        return 1
    fi

    # Check for path traversal attempts
    # Only reject .. when it appears as a complete path component (/../ or /.. or ../)
    # This allows legitimate directory names containing .. (e.g., Firefox's "name..files")
    if [[ "$path" =~ (^|/)\.\.(\/|$) ]]; then
        log_error "Path validation failed: path traversal not allowed: $path"
        return 1
    fi

    # Check path doesn't contain dangerous characters
    if [[ "$path" =~ [[:cntrl:]] ]] || [[ "$path" =~ $'\n' ]]; then
        log_error "Path validation failed: contains control characters: $path"
        return 1
    fi

    local policy_path
    policy_path=$(_mole_normalize_deletion_policy_path "$path")

    # Check symlink target if path is a symbolic link
    if [[ -L "$path" ]]; then
        local link_target
        link_target=$(readlink "$path" 2> /dev/null) || {
            log_error "Cannot read symlink: $path"
            return 1
        }

        # Resolve relative symlinks to absolute paths for validation
        local resolved_target="$link_target"
        if [[ "$link_target" != /* ]]; then
            local link_dir
            link_dir=$(dirname "$path")
            resolved_target=$(cd "$link_dir" 2> /dev/null && cd "$(dirname "$link_target")" 2> /dev/null && pwd)/$(basename "$link_target") || resolved_target=""
        fi

        # Validate resolved target against protected paths
        if [[ -n "$resolved_target" ]]; then
            resolved_target=$(_mole_normalize_deletion_policy_path "$resolved_target")
            if _mole_is_critical_deletion_path "$resolved_target"; then
                log_error "Symlink points to protected system path: $path -> $resolved_target"
                return 1
            fi
        fi
    fi

    # Ancestor-symlink guard. The checks above (deny list, protection policy)
    # match on the LITERAL path string, and the -L test above only inspects the
    # leaf. If any ANCESTOR component is a symlink, the string matches nothing
    # dangerous while the actual rm follows the link into the real target:
    # a redirected "~/Library/Caches" would let a cache sweep walk into
    # ~/Documents or a system tree. Canonicalize the parent (physical cd
    # resolves every ancestor link) and re-run the deny predicates on the
    # resolved leaf. Deny-only: a resolved path never grants permission the
    # literal path lacked, so legitimate targets keep their existing verdict.
    # Runs BEFORE the allowlists below, which would otherwise early-return past
    # this gate for /private/* paths.
    #
    # This sits on the hot path (every deletion candidate), so the common case
    # must stay fork-free: walk the ancestors with the [[ -L ]] builtin and only
    # pay for the canonicalizing subshell when one of them really is a symlink.
    # A dirname + `cd -P` on every call cost ~2ms, about +23% on validation.
    local parent_dir resolved_parent probe
    local ancestor_is_link=false
    parent_dir="${policy_path%/*}"
    [[ -z "$parent_dir" ]] && parent_dir="/"
    if [[ -d "$parent_dir" ]]; then
        probe="$parent_dir"
        while [[ "$probe" == /?* ]]; do
            if [[ -L "$probe" ]]; then
                ancestor_is_link=true
                break
            fi
            probe="${probe%/*}"
        done
    fi
    if [[ "$ancestor_is_link" == "true" ]]; then
        resolved_parent=$(cd -P "$parent_dir" 2> /dev/null && pwd -P) || resolved_parent=""
        if [[ -n "$resolved_parent" && "$resolved_parent" != "$parent_dir" ]]; then
            local resolved_path
            resolved_path=$(_mole_normalize_deletion_policy_path "${resolved_parent}/${policy_path##*/}")
            if _mole_is_critical_deletion_path "$resolved_path"; then
                log_error "Path validation failed: resolves into a critical system path: $path -> $resolved_path"
                return 1
            fi
            if declare -f should_protect_path > /dev/null 2>&1 && should_protect_path "$resolved_path"; then
                if [[ "${MO_DEBUG:-0}" == "1" ]]; then
                    log_warning "Path validation: resolves into a protected path: $path -> $resolved_path"
                fi
                return 1
            fi
        fi
    fi

    # Allow deletion of coresymbolicationd cache (safe system cache that can be rebuilt)
    case "$policy_path" in
        /System/Library/Caches/com.apple.coresymbolicationd/data | /System/Library/Caches/com.apple.coresymbolicationd/data/*)
            return 0
            ;;
    esac

    # Endpoint-security/EDR agent caches under var/folders look like ordinary
    # rebuildable caches, but deleting anything in a sensor's container trips
    # tamper detection (reported as malware). Reject here, before the
    # /private/var/folders allowlist below, so every deletion caller is covered,
    # not only the cleanup sweeps that pre-check the predicate.
    if declare -f is_endpoint_security_cache_path > /dev/null 2>&1 && is_endpoint_security_cache_path "$policy_path"; then
        if [[ "${MO_DEBUG:-0}" == "1" ]]; then
            log_warning "Path validation: endpoint-security agent cache skipped: $policy_path"
        fi
        return 1
    fi

    # Allow known safe paths under /private
    case "$policy_path" in
        /private/tmp | /private/tmp/* | \
            /private/var/tmp | /private/var/tmp/* | \
            /private/var/log | /private/var/log/* | \
            /private/var/folders | /private/var/folders/* | \
            /private/var/db/diagnostics | /private/var/db/diagnostics/* | \
            /private/var/db/DiagnosticPipeline | /private/var/db/DiagnosticPipeline/* | \
            /private/var/db/powerlog | /private/var/db/powerlog/* | \
            /private/var/db/reportmemoryexception | /private/var/db/reportmemoryexception/* | \
            /private/var/db/receipts/*.bom | /private/var/db/receipts/*.plist)
            return 0
            ;;
    esac

    # Check path isn't critical system directory
    if _mole_is_critical_deletion_path "$policy_path"; then
        log_error "Path validation failed: critical system path: $path"
        return 1
    fi

    # Check if path is protected (keychains, system settings, etc)
    if declare -f should_protect_path > /dev/null 2>&1; then
        if should_protect_path "$policy_path"; then
            if [[ "${MO_DEBUG:-0}" == "1" ]]; then
                log_warning "Path validation: protected path skipped: $policy_path"
            fi
            return 1
        fi
    fi

    return 0
}

# ============================================================================
# Safe Removal Operations
# ============================================================================

# Safe wrapper around rm -rf with validation
safe_remove() {
    local path="$1"
    local silent="${2:-false}"
    local precomputed_size_kb="${3:-}"

    # Validate path. Silent cleanup callers still need the same policy result,
    # but should not print one validation warning per skipped cache item.
    if [[ "$silent" == "true" ]]; then
        validate_path_for_deletion "$path" 2> /dev/null || return 1
    elif ! validate_path_for_deletion "$path"; then
        return 1
    fi

    # Honor the user whitelist here, not just in safe_clean. safe_remove is
    # called directly by several clean/optimize flows (Xcode DerivedData,
    # mail downloads, deep-system caches, broken LaunchAgents) that would
    # otherwise ignore a user's whitelist selection. is_path_whitelisted is
    # a no-op when the whitelist is empty, and uninstall does not route
    # through safe_remove, so this stays scoped to clean/optimize. See #710.
    if declare -f is_path_whitelisted > /dev/null 2>&1 && is_path_whitelisted "$path"; then
        log_operation "${MOLE_CURRENT_COMMAND:-clean}" "SKIPPED" "$path" "whitelist"
        return 1
    fi

    # Check if path exists
    if [[ ! -e "$path" ]]; then
        return 0
    fi

    # Dry-run mode: log but don't delete
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        if [[ "${MO_DEBUG:-}" == "1" ]]; then
            local file_type="file"
            [[ -d "$path" ]] && file_type="directory"
            [[ -L "$path" ]] && file_type="symlink"

            local file_size=""
            local file_age=""

            if [[ -e "$path" ]]; then
                local size_kb
                size_kb=$(get_path_size_kb "$path" 2> /dev/null || echo "0")
                if [[ "$size_kb" -gt 0 ]]; then
                    file_size=$(bytes_to_human "$((size_kb * 1024))")
                fi

                if [[ -f "$path" || -d "$path" ]] && ! [[ -L "$path" ]]; then
                    local mod_time
                    mod_time=$(stat -f%m "$path" 2> /dev/null || echo "0")
                    local now
                    now=$(date +%s 2> /dev/null || echo "0")
                    if [[ "$mod_time" -gt 0 && "$now" -gt 0 ]]; then
                        file_age=$(((now - mod_time) / 86400))
                    fi
                fi
            fi

            debug_file_action "[DRY RUN] Would remove" "$path" "$file_size" "$file_age"
        else
            debug_log "[DRY RUN] Would remove: $path"
        fi
        return 0
    fi

    debug_log "Removing: $path"

    # Calculate size before deletion for logging.
    # Accept pre-computed size to skip redundant I/O when the caller already measured.
    local size_kb=0
    local size_human=""
    if oplog_enabled; then
        if [[ -n "$precomputed_size_kb" && "$precomputed_size_kb" =~ ^[0-9]+$ ]]; then
            size_kb="$precomputed_size_kb"
        elif [[ -e "$path" ]]; then
            size_kb=$(get_path_size_kb "$path" 2> /dev/null || echo "0")
        fi
        if [[ "$size_kb" =~ ^[0-9]+$ ]] && [[ "$size_kb" -gt 0 ]]; then
            size_human=$(bytes_to_human "$((size_kb * 1024))" 2> /dev/null || echo "${size_kb}KB")
        fi
    fi

    # Perform the deletion
    # Use || to capture the exit code so set -e won't abort on rm failures
    local error_msg
    local rm_exit=0
    error_msg=$(rm -rf "$path" 2>&1) || rm_exit=$? # safe_remove

    # Preserve interrupt semantics so callers can abort long-running deletions.
    if [[ $rm_exit -ge 128 ]]; then
        return "$rm_exit"
    fi

    if [[ $rm_exit -eq 0 ]]; then
        # Log successful removal
        log_operation "${MOLE_CURRENT_COMMAND:-clean}" "REMOVED" "$path" "$size_human"
        return 0
    else
        # Check if it's a permission error
        if [[ "$error_msg" == *"Permission denied"* ]] || [[ "$error_msg" == *"Operation not permitted"* ]]; then
            MOLE_PERMISSION_DENIED_COUNT=${MOLE_PERMISSION_DENIED_COUNT:-0}
            MOLE_PERMISSION_DENIED_COUNT=$((MOLE_PERMISSION_DENIED_COUNT + 1))
            export MOLE_PERMISSION_DENIED_COUNT
            debug_log "Permission denied: $path, may need Full Disk Access"
            log_operation "${MOLE_CURRENT_COMMAND:-clean}" "FAILED" "$path" "permission denied"
        else
            [[ "$silent" != "true" ]] && log_error "Failed to remove: $path"
            log_operation "${MOLE_CURRENT_COMMAND:-clean}" "FAILED" "$path" "error"
        fi
        return 1
    fi
}

# Safe symlink removal (for pre-validated symlinks only)
safe_remove_symlink() {
    local path="$1"
    local use_sudo="${2:-false}"

    if [[ ! -L "$path" ]]; then
        return 1
    fi

    if ! validate_path_for_deletion "$path"; then
        return 1
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        debug_log "[DRY RUN] Would remove symlink: $path"
        return 0
    fi

    local rm_exit=0
    if [[ "$use_sudo" == "true" ]]; then
        if [[ "${MOLE_TEST_MODE:-0}" == "1" || "${MOLE_TEST_NO_AUTH:-0}" == "1" ]]; then
            log_operation "${MOLE_CURRENT_COMMAND:-clean}" "FAILED" "$path" "sudo blocked in test mode"
            return 1
        fi
        sudo -n rm "$path" 2> /dev/null || rm_exit=$?
    else
        rm "$path" 2> /dev/null || rm_exit=$?
    fi

    if [[ $rm_exit -eq 0 ]]; then
        log_operation "${MOLE_CURRENT_COMMAND:-clean}" "REMOVED" "$path" "symlink"
        return 0
    else
        log_operation "${MOLE_CURRENT_COMMAND:-clean}" "FAILED" "$path" "symlink removal failed"
        return 1
    fi
}

# Safe sudo removal with symlink protection
safe_sudo_remove() {
    local path="$1"

    if ! validate_path_for_deletion "$path"; then
        if declare -f should_protect_path > /dev/null 2>&1 && should_protect_path "$path"; then
            debug_log "Skipped sudo remove for protected path: $path"
            return "$MOLE_ERR_PROTECTED_PATH"
        else
            log_error "Path validation failed for sudo remove: $path"
        fi
        return 1
    fi

    if [[ ! -e "$path" ]]; then
        return 0
    fi

    if [[ -L "$path" ]]; then
        log_error "Refusing to sudo remove symlink: $path"
        return 1
    fi

    if [[ "${MOLE_TEST_MODE:-0}" == "1" || "${MOLE_TEST_NO_AUTH:-0}" == "1" ]]; then
        if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
            log_info "[DRY-RUN] Would sudo remove: $path"
            return 0
        fi
        log_operation "${MOLE_CURRENT_COMMAND:-clean}" "FAILED" "$path" "sudo blocked in test mode"
        return 1
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        if [[ "${MO_DEBUG:-}" == "1" ]]; then
            local file_type="file"
            [[ -d "$path" ]] && file_type="directory"

            local file_size=""
            local file_age=""

            if sudo -n test -e "$path" 2> /dev/null; then
                local size_kb
                size_kb=$(run_with_timeout "$MOLE_TIMEOUT_DISK_VERIFY_SEC" sudo -n du -skP "$path" 2> /dev/null | awk '{print $1}' || echo "0")
                if [[ "$size_kb" -gt 0 ]]; then
                    file_size=$(bytes_to_human "$((size_kb * 1024))")
                fi

                if sudo -n test -f "$path" 2> /dev/null || sudo -n test -d "$path" 2> /dev/null; then
                    local mod_time
                    mod_time=$(sudo -n stat -f%m "$path" 2> /dev/null || echo "0")
                    local now
                    now=$(date +%s 2> /dev/null || echo "0")
                    if [[ "$mod_time" -gt 0 && "$now" -gt 0 ]]; then
                        local age_seconds=$((now - mod_time))
                        file_age=$(format_duration_human "$age_seconds")
                    fi
                fi
            fi

            log_info "[DRY-RUN] Would sudo remove: $file_type $path"
            [[ -n "$file_size" ]] && log_info "  Size: $file_size"
            [[ -n "$file_age" ]] && log_info "  Age: $file_age"
        else
            log_info "[DRY-RUN] Would sudo remove: $path"
        fi
        return 0
    fi

    local size_kb=0
    local size_human=""
    if oplog_enabled; then
        if sudo -n test -e "$path" 2> /dev/null; then
            size_kb=$(run_with_timeout "$MOLE_TIMEOUT_DISK_VERIFY_SEC" sudo -n du -skP "$path" 2> /dev/null | awk '{print $1}' || echo "0")
            if [[ "$size_kb" =~ ^[0-9]+$ ]] && [[ "$size_kb" -gt 0 ]]; then
                size_human=$(bytes_to_human "$((size_kb * 1024))" 2> /dev/null || echo "${size_kb}KB")
            fi
        fi
    fi

    local output
    local ret=0
    output=$(sudo -n rm -rf "$path" 2>&1) || ret=$? # safe_remove

    if [[ $ret -eq 0 ]]; then
        log_operation "${MOLE_CURRENT_COMMAND:-clean}" "REMOVED" "$path" "$size_human"
        return 0
    fi

    case "$output" in
        *"a password is required"* | *"a terminal is required"* | *"Password:"*)
            log_operation "${MOLE_CURRENT_COMMAND:-clean}" "FAILED" "$path" "auth required"
            return "$MOLE_ERR_AUTH_FAILED"
            ;;
        *"Operation not permitted"*)
            log_operation "${MOLE_CURRENT_COMMAND:-clean}" "FAILED" "$path" "sip/mdm protected"
            return "$MOLE_ERR_SIP_PROTECTED"
            ;;
        *"Read-only file system"*)
            log_operation "${MOLE_CURRENT_COMMAND:-clean}" "FAILED" "$path" "readonly filesystem"
            return "$MOLE_ERR_READONLY_FS"
            ;;
        *"Sorry, try again"* | *"incorrect passphrase"* | *"incorrect credentials"*)
            log_operation "${MOLE_CURRENT_COMMAND:-clean}" "FAILED" "$path" "auth failed"
            return "$MOLE_ERR_AUTH_FAILED"
            ;;
        *)
            log_error "Failed to remove, sudo: $path"
            log_operation "${MOLE_CURRENT_COMMAND:-clean}" "FAILED" "$path" "sudo error"
            return 1
            ;;
    esac
}

# ============================================================================
# Unified deletion helper (Trash + permanent routing with forensic log)
# ============================================================================

# Route a deletion through either macOS Trash or permanent rm, while logging
# every call for forensic review. Designed for destructive paths where undo
# matters (e.g. uninstall). Not used by cache-clean paths.
#
# Usage: mole_delete <path> [needs_sudo=false]
#
# Environment:
#   MOLE_DELETE_MODE      "permanent" (default) or "trash"; other values fail
#   MOLE_DRY_RUN=1        Log intent, do not delete
#   MOLE_TEST_TRASH_DIR   Test-only override; Trash moves go here via `mv`
#                         instead of Finder/trash CLI. Required for bats.
#   MOLE_DELETE_LOG       Override the log file path (default:
#                         ~/Library/Logs/mole/deletions.log)
#
# Returns 0 on success, 1 on failure. Always appends a tab-separated line to
# the deletions log: <iso_ts>\t<mode>\t<size_kb>\t<status>\t<path>.
# size_kb is "unknown" when du could not measure the path (permission denied,
# disappeared mid-call); never silently coerced to 0KB so post-hoc forensics
# can tell measured-zero from measurement-failure.
mole_delete() {
    local path="$1"
    local needs_sudo="${2:-false}"
    local mode="${MOLE_DELETE_MODE:-permanent}"

    [[ -z "$path" ]] && return 1

    case "$mode" in
        permanent | trash) ;;
        *)
            _mole_delete_log "$mode" "unknown" "invalid-mode" "$path"
            if [[ -z "${_MOLE_INVALID_MODE_WARNED:-}" ]]; then
                _MOLE_INVALID_MODE_WARNED=1
                export _MOLE_INVALID_MODE_WARNED
                printf 'Error: invalid MOLE_DELETE_MODE: %s (expected "permanent" or "trash")\n' "$mode" >&2
            fi
            return 1
            ;;
    esac

    # Nothing to do if path does not exist (but a broken symlink still counts).
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        return 0
    fi

    # Validation is delegated to the underlying safe_* helpers (which call
    # validate_path_for_deletion). Trash routing only applies to paths the
    # user could legitimately restore from, so we short-circuit invalid paths
    # up front to avoid a no-op Trash move followed by a validation failure.
    # The rejection itself is recorded in the forensic log so audit trails
    # can distinguish refused-by-policy from never-attempted.
    if ! validate_path_for_deletion "$path"; then
        _mole_delete_log "$mode" "0" "rejected" "$path"
        return 1
    fi

    # Capture size before the delete so the log line is still useful when the
    # path is gone afterwards. Use "unknown" (not 0) on failure so the log
    # never lies about a multi-GB delete by recording it as 0KB.
    local size_kb="unknown"
    if [[ -e "$path" ]]; then
        local raw_size=""
        local du_rc=0
        if [[ "$needs_sudo" == "true" ]]; then
            if [[ "${MOLE_TEST_MODE:-0}" == "1" || "${MOLE_TEST_NO_AUTH:-0}" == "1" ]]; then
                du_rc=1
            else
                raw_size=$(run_with_timeout "$MOLE_TIMEOUT_DISK_VERIFY_SEC" sudo -n du -skP "$path" 2> /dev/null | awk '{print $1; exit}')
                du_rc=${PIPESTATUS[0]}
            fi
        else
            raw_size=$(get_path_size_kb "$path" 2> /dev/null) || du_rc=$?
        fi
        if [[ "$du_rc" -eq 0 && "$raw_size" =~ ^[0-9]+$ ]]; then
            size_kb="$raw_size"
        fi
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        debug_log "[DRY RUN] Would delete ($mode): $path"
        _mole_delete_log "$mode" "$size_kb" "dry-run" "$path"
        return 0
    fi

    if [[ "$needs_sudo" == "true" ]]; then
        if [[ "${MOLE_TEST_MODE:-0}" == "1" || "${MOLE_TEST_NO_AUTH:-0}" == "1" ]]; then
            _mole_delete_log "$mode" "$size_kb" "sudo-blocked-test-mode" "$path"
            return 1
        fi
    fi

    # Trash mode is a recoverable-delete contract. If Trash is unavailable,
    # fail closed instead of silently switching to permanent removal.
    if [[ "$mode" == "trash" ]]; then
        if _mole_move_to_trash "$path" "$needs_sudo"; then
            _mole_delete_log "trash" "$size_kb" "ok" "$path"
            log_operation "${MOLE_CURRENT_COMMAND:-uninstall}" "TRASHED" "$path" "${size_kb}KB"
            return 0
        fi
        _mole_delete_log "trash" "$size_kb" "trash-failed" "$path"
        log_operation "${MOLE_CURRENT_COMMAND:-uninstall}" "SKIPPED" "$path" "trash-failed"
        if [[ -z "${_MOLE_TRASH_UNAVAILABLE_WARNED:-}" ]]; then
            _MOLE_TRASH_UNAVAILABLE_WARNED=1
            export _MOLE_TRASH_UNAVAILABLE_WARNED
            printf 'Error: Trash unavailable; refusing permanent delete. Use --permanent to delete immediately.\n' >&2
        fi
        debug_log "Trash move failed, refusing permanent delete: $path"
        return 1
    fi

    # Permanent path. Delegate to the existing safe_* helpers so path
    # validation, sudo handling, and existing log_operation calls remain
    # unchanged for callers that have always gone through rm -rf.
    local rc=0
    if [[ -L "$path" ]]; then
        safe_remove_symlink "$path" "$needs_sudo" || rc=$?
    elif [[ "$needs_sudo" == "true" ]]; then
        safe_sudo_remove "$path" || rc=$?
    else
        safe_remove "$path" "true" || rc=$?
    fi

    local status_label="ok"
    [[ $rc -ne 0 ]] && status_label="error"
    _mole_delete_log "$mode" "$size_kb" "$status_label" "$path"
    return "$rc"
}

# Move a path to the macOS Trash. Test harnesses set MOLE_TEST_TRASH_DIR to
# redirect the move to a tmpdir, avoiding any Finder/osascript interaction.
_mole_move_to_trash() {
    local path="$1"
    local needs_sudo="${2:-false}"

    if [[ -n "${MOLE_TEST_TRASH_DIR:-}" ]]; then
        mkdir -p "$MOLE_TEST_TRASH_DIR" 2> /dev/null || return 1
        local dest="$MOLE_TEST_TRASH_DIR/$(basename "$path").$$.$(date +%s 2> /dev/null || echo 0)"
        mv "$path" "$dest" 2> /dev/null
        return $?
    fi

    # Blocked in test mode so uninstall tests never hit Finder/AppleScript.
    if [[ "${MOLE_TEST_NO_AUTH:-0}" == "1" ]]; then
        return 1
    fi

    if [[ "$needs_sudo" == "true" ]]; then
        _mole_move_sudo_path_to_user_trash "$path"
        return $?
    fi

    # Prefer the `trash` CLI (Homebrew formula) for normal user-owned paths.
    if command -v trash > /dev/null 2>&1; then
        trash "$path" > /dev/null 2>&1 && return 0
    fi

    # AppleScript fallback. Pass the path via argv so special chars (quotes,
    # backslashes) cannot break out of the quoted string.
    osascript - "$path" > /dev/null 2>&1 << 'APPLESCRIPT'
on run argv
    set p to POSIX file (item 1 of argv)
    tell application "Finder"
        delete p
    end tell
end run
APPLESCRIPT
}

_mole_move_sudo_path_to_user_trash() {
    local path="$1"
    local user_home=""

    if [[ "${MOLE_TEST_MODE:-0}" == "1" || "${MOLE_TEST_NO_AUTH:-0}" == "1" ]]; then
        return 1
    fi

    if declare -f get_invoking_home > /dev/null 2>&1; then
        user_home=$(get_invoking_home)
    else
        user_home="${HOME:-}"
    fi

    if [[ -z "$user_home" || "$user_home" != /* || "$user_home" == "/" || "$user_home" == "/var/root" ]]; then
        debug_log "Refusing sudo Trash move: invalid invoking user home: ${user_home:-<empty>}"
        return 1
    fi

    if [[ -z "$path" ]] || [[ ! -e "$path" && ! -L "$path" ]]; then
        debug_log "Refusing sudo Trash move: path does not exist: ${path:-<empty>}"
        return 1
    fi

    local trash_dir="${user_home%/}/.Trash"

    # The destination must be the invoking user's Trash, even though sudo is
    # needed to unlink the original protected path.
    if [[ -L "$trash_dir" ]]; then
        debug_log "Refusing sudo Trash move: invoking user Trash is a symlink: $trash_dir"
        return 1
    fi
    if ! mkdir -p "$trash_dir" 2> /dev/null; then
        if ! sudo -n mkdir -p "$trash_dir" 2> /dev/null; then
            debug_log "Failed to create invoking user Trash: $trash_dir"
            return 1
        fi
    fi
    if [[ ! -d "$trash_dir" || -L "$trash_dir" ]]; then
        debug_log "Refusing sudo Trash move: invoking user Trash is not a normal directory: $trash_dir"
        return 1
    fi

    local owner_uid="" owner_gid=""
    if declare -f get_invoking_uid > /dev/null 2>&1; then
        owner_uid=$(get_invoking_uid)
    fi
    if declare -f get_invoking_gid > /dev/null 2>&1; then
        owner_gid=$(get_invoking_gid)
    fi
    if [[ "$owner_uid" =~ ^[0-9]+$ && "$owner_gid" =~ ^[0-9]+$ ]]; then
        sudo -n chown "$owner_uid:$owner_gid" "$trash_dir" 2> /dev/null || true
    fi
    if ! chmod 700 "$trash_dir" 2> /dev/null; then
        sudo -n chmod 700 "$trash_dir" 2> /dev/null || true
    fi

    # Avoid Finder-style ':' path weirdness and keep generated names filesystem-safe.
    local base
    base=$(basename "$path")
    base="${base//:/__}"
    base="${base//\//__}"
    [[ -n "$base" && "$base" != "." && "$base" != ".." ]] || base="mole-trash-item"

    local dest="$trash_dir/$base"
    local ts suffix
    ts=$(date +%s 2> /dev/null || echo 0)
    suffix=0

    while [[ -e "$dest" || -L "$dest" ]]; do
        suffix=$((suffix + 1))
        if [[ $suffix -gt 100 ]]; then
            debug_log "Failed to choose unique Trash destination for: $path"
            return 1
        fi
        dest="$trash_dir/$base.$ts.$$.$suffix"
    done

    if ! sudo -n mv -n "$path" "$dest" > /dev/null 2>&1; then
        debug_log "Failed to move sudo-required path to invoking user Trash: $path -> $dest"
        return 1
    fi
    if [[ -e "$path" || -L "$path" ]] || [[ ! -e "$dest" && ! -L "$dest" ]]; then
        debug_log "Failed to move sudo-required path without overwriting destination: $path -> $dest"
        return 1
    fi

    # Best-effort ownership repair makes restored Trash items behave like user files.
    if [[ "$owner_uid" =~ ^[0-9]+$ && "$owner_gid" =~ ^[0-9]+$ ]]; then
        sudo -n chown -R "$owner_uid:$owner_gid" "$dest" 2> /dev/null || true
    fi

    debug_log "Moved sudo-required path to invoking user Trash: $path -> $dest"
    return 0
}

# Batched Trash move for non-sudo, non-symlink paths. Removes the per-file
# subprocess fan-out that made AppleScript-fallback uninstalls feel frozen
# (100 files * ~1s each). Returns 0 only when the entire batch landed in the
# Trash; callers must fall back to the per-file path on non-zero so nothing
# is silently skipped.
_mole_move_to_trash_batch() {
    local -a paths=("$@")
    [[ ${#paths[@]} -eq 0 ]] && return 0

    if [[ -n "${MOLE_TEST_TRASH_DIR:-}" ]]; then
        mkdir -p "$MOLE_TEST_TRASH_DIR" 2> /dev/null || return 1
        local ts
        ts=$(date +%s 2> /dev/null || echo 0)
        local p dest
        for p in "${paths[@]}"; do
            dest="$MOLE_TEST_TRASH_DIR/$(basename "$p").$$.${ts}.$RANDOM"
            mv "$p" "$dest" 2> /dev/null || return 1
        done
        return 0
    fi

    if [[ "${MOLE_TEST_NO_AUTH:-0}" == "1" ]]; then
        return 1
    fi

    if command -v trash > /dev/null 2>&1; then
        trash "${paths[@]}" > /dev/null 2>&1 && return 0
    fi

    # AppleScript fallback: build one POSIX-file list and tell Finder once.
    osascript - "${paths[@]}" > /dev/null 2>&1 << 'APPLESCRIPT'
on run argv
    set posixList to {}
    repeat with a in argv
        set end of posixList to POSIX file (a as text)
    end repeat
    tell application "Finder" to delete posixList
end run
APPLESCRIPT
}

_mole_delete_log() {
    local mode="$1"
    local size_kb="$2"
    local status="$3"
    local target="$4"

    local log_file="${MOLE_DELETE_LOG:-$HOME/Library/Logs/mole/deletions.log}"
    local log_dir
    log_dir=$(dirname "$log_file")

    # Surface log-write failures once per session. The deletions log is the
    # only audit trail for Trash-routed removals; silently no-oping when the
    # log dir is unwritable (root-owned from prior sudo, ENOSPC, read-only
    # volume) defeats the design.
    if ! mkdir -p "$log_dir" 2> /dev/null; then
        _mole_warn_log_broken "create directory: $log_dir"
        return 0
    fi

    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S%z' 2> /dev/null || echo "unknown")

    if ! printf '%s\t%s\t%s\t%s\t%s\n' \
        "$ts" "$mode" "$size_kb" "$status" "$target" \
        >> "$log_file" 2> /dev/null; then
        _mole_warn_log_broken "write to: $log_file"
    fi
}

_mole_warn_log_broken() {
    [[ -n "${_MOLE_DELETE_LOG_WARNED:-}" ]] && return 0
    _MOLE_DELETE_LOG_WARNED=1
    export _MOLE_DELETE_LOG_WARNED
    printf 'Warning: deletions audit log unavailable (%s). Forensic trail incomplete this session.\n' "$1" >&2
}

# ============================================================================
# Safe Find and Delete Operations
# ============================================================================

# Safe file discovery and deletion with depth and age limits
safe_find_delete() {
    local base_dir="$1"
    local pattern="$2"
    local age_days="${3:-7}"
    local type_filter="${4:-f}"

    # Validate base directory exists and is not a symlink
    if [[ ! -d "$base_dir" ]]; then
        log_error "Directory does not exist: $base_dir"
        return 1
    fi

    if [[ -L "$base_dir" ]]; then
        log_error "Refusing to search symlinked directory: $base_dir"
        return 1
    fi

    # Validate type filter
    if [[ "$type_filter" != "f" && "$type_filter" != "d" ]]; then
        log_error "Invalid type filter: $type_filter, must be 'f' or 'd'"
        return 1
    fi

    debug_log "Finding in $base_dir: $pattern, age: ${age_days}d, type: $type_filter"

    local find_args=("-maxdepth" "5" "-name" "$pattern" "-type" "$type_filter")
    if [[ "$age_days" -gt 0 ]]; then
        find_args+=("-mtime" "+$age_days")
    fi

    # Iterate results to respect both system protection and user whitelist.
    # Per-caller whitelist gates were missed in past releases (see #710, #724,
    # #738, #744, #757); enforcing here makes the protection structural so
    # new clean_* functions get whitelist enforcement for free.
    while IFS= read -r -d '' match; do
        if declare -f should_protect_path > /dev/null 2>&1 && should_protect_path "$match"; then
            continue
        fi
        if declare -f is_path_whitelisted > /dev/null && is_path_whitelisted "$match"; then
            continue
        fi
        safe_remove "$match" true || true
    done < <(command find "$base_dir" "${find_args[@]}" -print0 2> /dev/null < /dev/null || true)

    return 0
}

# Safe sudo discovery and deletion
safe_sudo_find_delete() {
    local base_dir="$1"
    local pattern="$2"
    local age_days="${3:-7}"
    local type_filter="${4:-f}"

    if [[ "${MOLE_TEST_MODE:-0}" == "1" || "${MOLE_TEST_NO_AUTH:-0}" == "1" ]]; then
        debug_log "Skipping sudo find/delete in test mode: $base_dir"
        return 0
    fi

    # Keep the entire sudo-probing body independent of the caller's errexit
    # state. macOS 14's /bin/bash build fires the caller's errexit when a
    # sudo shell-function mock returns nonzero inside an if condition (the
    # same bash 3.2.57 on macOS 15+ does not), so the guard must sit above
    # the first sudo probe, not just around the scan/batch loop. The
    # predicates below intentionally return 1 for ordinary "not protected /
    # not whitelisted / no oplog" cases; callers still get explicit nonzero
    # returns from the validation gates, restored to their errexit state.
    local restore_errexit=0
    case $- in
        *e*)
            restore_errexit=1
            set +e
            ;;
    esac

    # Validate base directory (use sudo for permission-restricted dirs)
    if ! sudo -n test -d "$base_dir" 2> /dev/null; then
        debug_log "Directory does not exist, skipping: $base_dir"
        if [[ $restore_errexit -eq 1 ]]; then
            set -e
        fi
        return 0
    fi

    if sudo -n test -L "$base_dir" 2> /dev/null; then
        log_error "Refusing to search symlinked directory: $base_dir"
        if [[ $restore_errexit -eq 1 ]]; then
            set -e
        fi
        return 1
    fi

    # Validate type filter
    if [[ "$type_filter" != "f" && "$type_filter" != "d" ]]; then
        log_error "Invalid type filter: $type_filter, must be 'f' or 'd'"
        if [[ $restore_errexit -eq 1 ]]; then
            set -e
        fi
        return 1
    fi

    debug_log "Finding, sudo, in $base_dir: $pattern, age: ${age_days}d, type: $type_filter"

    local find_args=("-maxdepth" "5")
    # Skip -name if pattern is "*" (matches everything anyway, but adds overhead)
    if [[ "$pattern" != "*" ]]; then
        find_args+=("-name" "$pattern")
    fi
    find_args+=("-type" "$type_filter")
    if [[ "$age_days" -gt 0 ]]; then
        find_args+=("-mtime" "+$age_days")
    fi

    # Iterate results to respect both system protection and user whitelist.
    # See safe_find_delete for rationale (#757).
    #
    # Regular files are removed in one privileged xargs batch instead of one
    # safe_sudo_remove per match: the single-file path costs three sudo forks
    # per file (test -e, du, rm), which turns a sweep over a stale .logarchive
    # bundle (1000+ tracev3 files) into minutes. Every path still passes the
    # same per-file gates before entering the batch; only the rm is batched.
    # Directories and dry-run keep the single-file path so rm -rf handling
    # and preview output stay unchanged.
    local -a batch_files=()
    while IFS= read -r -d '' match; do
        if should_protect_path "$match"; then
            continue
        fi
        if declare -f is_path_whitelisted > /dev/null && is_path_whitelisted "$match"; then
            continue
        fi
        # -type f never emits symlinks; a path that is one now was swapped
        # after find saw it, and the single-file path refuses those.
        if [[ "$type_filter" == "f" && "${MOLE_DRY_RUN:-0}" != "1" && ! -L "$match" ]]; then
            if validate_path_for_deletion "$match"; then
                batch_files+=("$match")
            fi
            continue
        fi
        safe_sudo_remove "$match" || true
    done < <(sudo -n find "$base_dir" "${find_args[@]}" -print0 2> /dev/null || true)

    if [[ ${#batch_files[@]} -gt 0 ]]; then
        local batch_rc=0
        printf '%s\0' "${batch_files[@]}" | sudo -n xargs -0 rm -f -- 2> /dev/null || batch_rc=$?

        # Plain if, not `oplog_enabled && ...`: the short-circuit form returns
        # 1 when the oplog is disabled and would trip set -e in callers.
        local batch_ts=""
        if oplog_enabled; then
            batch_ts=$(get_timestamp)
        fi
        # When the batch failed, confirm sudo credentials are still live
        # before trusting the per-file probe below: with a lapsed credential
        # `sudo -n test -e` fails for every file, which is indistinguishable
        # from "file gone" and would log REMOVED entries for files still on
        # disk. With dead credentials, retry everything through the
        # single-file path so each failure is classified and logged.
        local batch_sudo_alive=1
        if [[ $batch_rc -ne 0 ]] && ! sudo -n true 2> /dev/null; then
            batch_sudo_alive=0
        fi
        local -a removed_lines=()
        local batch_file
        for batch_file in "${batch_files[@]}"; do
            if [[ $batch_rc -ne 0 ]] && { [[ $batch_sudo_alive -eq 0 ]] || sudo -n test -e "$batch_file" 2> /dev/null; }; then
                # Survived the batch (SIP, immutable flag, permissions):
                # retry through the single-file path so the failure is
                # classified and logged exactly as before.
                safe_sudo_remove "$batch_file" || true
            elif [[ -n "$batch_ts" ]]; then
                removed_lines+=("[$batch_ts] [${MOLE_CURRENT_COMMAND:-clean}] REMOVED $batch_file (batch)")
            fi
        done
        if [[ ${#removed_lines[@]} -gt 0 ]]; then
            append_log_lines "$OPERATIONS_LOG_FILE" "${removed_lines[@]}"
        fi
    fi

    if [[ $restore_errexit -eq 1 ]]; then
        set -e
    fi

    return 0
}

# ============================================================================
# Size Calculation
# ============================================================================

# Get path size in KB (returns 0 if not found)
#
# For regular files and symlinks, prefer 'stat' over 'du': it avoids the
# fork+pipe cost of 'du | awk' on every call, which adds up in tight loops
# (e.g. external-volume ._* sweeps, Application Support log scans). 'du -skP'
# and 'stat -f%z' both report logical size without following symlinks on
# macOS, and the 1KB-rounded outputs match for the file types we encounter
# (logs, caches, leftovers). Directories still go through 'du' because 'stat'
# only reports a single directory entry, not recursive content size. .app
# bundles continue to go through mdls because APFS clones make 'du'
# under-report large bundles like Xcode.
get_path_size_kb() {
    local path="$1"
    [[ -z "$path" || ! -e "$path" ]] && {
        echo "0"
        return
    }

    # For .app bundles, prefer mdls logical size as it matches Finder
    # (APFS clone/sparse files make 'du' severely underreport apps like Xcode)
    if [[ "$path" == *.app || "$path" == *.app/ ]]; then
        local mdls_size
        mdls_size=$(mdls -name kMDItemLogicalSize -raw "$path" 2> /dev/null || true)
        if [[ "$mdls_size" =~ ^[0-9]+$ && "$mdls_size" -gt 0 ]]; then
            # Return in KB
            echo "$((mdls_size / 1024))"
            return
        fi
    fi

    # Fast path for regular files and symlinks: avoid forking 'du'.
    if [[ -f "$path" || -L "$path" ]]; then
        local bytes
        bytes=$(stat -f%z "$path" 2> /dev/null || echo "")
        if [[ "$bytes" =~ ^[0-9]+$ ]]; then
            # Round up to whole KB to match 'du -skP' semantics.
            echo $(((bytes + 1023) / 1024))
            return
        fi
    fi

    # Bounded like every other du call site (hints/project/caches): an
    # unbounded walk here wedges one parallel sizing worker forever on a
    # stalled SMB/FUSE mount. On timeout the size reads 0, which only
    # affects display/accounting, never deletion decisions.
    local size
    size=$(run_with_timeout "$MOLE_TIMEOUT_DISK_VERIFY_SEC" du -skP "$path" 2> /dev/null | awk 'NR==1 {print $1; exit}' || true)

    if [[ "$size" =~ ^[0-9]+$ ]]; then
        echo "$size"
    else
        [[ "${MO_DEBUG:-}" == "1" ]] && debug_log "get_path_size_kb: Failed to get size for $path (returned: $size)"
        echo "0"
    fi
}

# Calculate total size for multiple paths
calculate_total_size() {
    local files="$1"
    local total_kb=0
    local -a unique_paths=()

    while IFS= read -r file; do
        if [[ -n "$file" && -e "$file" ]]; then
            local normalized_file="${file%/}"
            [[ -n "$normalized_file" ]] || normalized_file="$file"

            local skip_file=false
            local -a filtered_paths=()
            local existing_file
            for existing_file in "${unique_paths[@]+"${unique_paths[@]}"}"; do
                if [[ "$normalized_file" == "$existing_file" || "$normalized_file" == "$existing_file"/* ]]; then
                    skip_file=true
                    break
                fi
                if [[ "$existing_file" == "$normalized_file"/* ]]; then
                    continue
                fi
                filtered_paths+=("$existing_file")
            done

            if [[ "$skip_file" == "false" ]]; then
                unique_paths=("${filtered_paths[@]+"${filtered_paths[@]}"}")
                unique_paths+=("$normalized_file")
            fi
        fi
    done <<< "$files"

    for file in "${unique_paths[@]+"${unique_paths[@]}"}"; do
        local size_kb
        size_kb=$(get_path_size_kb "$file")
        total_kb=$((total_kb + size_kb))
    done

    echo "$total_kb"
}

diagnose_removal_failure() {
    local exit_code="$1"
    local app_name="${2:-application}"

    local reason=""
    local suggestion=""
    local touchid_file="/etc/pam.d/sudo"

    case "$exit_code" in
        "$MOLE_ERR_SIP_PROTECTED")
            reason="protected by macOS (SIP/MDM)"
            ;;
        "$MOLE_ERR_AUTH_FAILED")
            reason="authentication failed"
            if [[ -f "$touchid_file" ]] && grep -q "pam_tid.so" "$touchid_file" 2> /dev/null; then
                suggestion="Check your credentials or restart Terminal"
            else
                suggestion="Try 'mole touchid' to enable fingerprint auth"
            fi
            ;;
        "$MOLE_ERR_READONLY_FS")
            reason="filesystem is read-only"
            suggestion="Check if disk needs repair"
            ;;
        "$MOLE_ERR_PROTECTED_PATH")
            reason="protected by Mole safety rules"
            ;;
        *)
            reason="permission denied"
            if [[ -f "$touchid_file" ]] && grep -q "pam_tid.so" "$touchid_file" 2> /dev/null; then
                suggestion="Try running again or check file ownership"
            else
                suggestion="Try 'mole touchid' or check with 'ls -l'"
            fi
            ;;
    esac

    echo "$reason|$suggestion"
}
