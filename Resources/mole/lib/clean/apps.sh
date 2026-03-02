#!/bin/bash
# Application Data Cleanup Module
set -euo pipefail

readonly ORPHAN_AGE_THRESHOLD=${ORPHAN_AGE_THRESHOLD:-${MOLE_ORPHAN_AGE_DAYS:-60}}
# Args: $1=target_dir, $2=label
clean_ds_store_tree() {
    local target="$1"
    local label="$2"
    [[ -d "$target" ]] || return 0
    local file_count=0
    local total_bytes=0
    local spinner_active="false"
    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  "
        start_inline_spinner "Cleaning Finder metadata..."
        spinner_active="true"
    fi
    local -a exclude_paths=(
        -path "*/Library/Application Support/MobileSync" -prune -o
        -path "*/Library/Developer" -prune -o
        -path "*/.Trash" -prune -o
        -path "*/node_modules" -prune -o
        -path "*/.git" -prune -o
        -path "*/Library/Caches" -prune -o
    )
    local -a find_cmd=("command" "find" "$target")
    if [[ "$target" == "$HOME" ]]; then
        find_cmd+=("-maxdepth" "5")
    fi
    find_cmd+=("${exclude_paths[@]}" "-type" "f" "-name" ".DS_Store" "-print0")
    while IFS= read -r -d '' ds_file; do
        local size
        size=$(get_file_size "$ds_file")
        total_bytes=$((total_bytes + size))
        file_count=$((file_count + 1))
        if [[ "$DRY_RUN" != "true" ]]; then
            rm -f "$ds_file" 2> /dev/null || true
        fi
        if [[ $file_count -ge $MOLE_MAX_DS_STORE_FILES ]]; then
            break
        fi
    done < <("${find_cmd[@]}" 2> /dev/null || true)
    if [[ "$spinner_active" == "true" ]]; then
        stop_section_spinner
    fi
    if [[ $file_count -gt 0 ]]; then
        local size_human
        size_human=$(bytes_to_human "$total_bytes")
        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} $label${NC}, ${YELLOW}$file_count files, $size_human dry${NC}"
        else
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} $label${NC}, ${GREEN}$file_count files, $size_human${NC}"
        fi
        local size_kb=$(((total_bytes + 1023) / 1024))
        files_cleaned=$((files_cleaned + file_count))
        total_size_cleaned=$((total_size_cleaned + size_kb))
        total_items=$((total_items + 1))
        note_activity
    fi
}
# Orphaned app data (60+ days inactive). Env: ORPHAN_AGE_THRESHOLD, DRY_RUN
# Usage: scan_installed_apps "output_file"
scan_installed_apps() {
    local installed_bundles="$1"
    # Cache installed app scan briefly to speed repeated runs.
    local cache_file="$HOME/.cache/mole/installed_apps_cache"
    local cache_age_seconds=300 # 5 minutes
    if [[ -f "$cache_file" ]]; then
        local cache_mtime=$(get_file_mtime "$cache_file")
        local current_time
        current_time=$(get_epoch_seconds)
        local age=$((current_time - cache_mtime))
        if [[ $age -lt $cache_age_seconds ]]; then
            debug_log "Using cached app list, age: ${age}s"
            if [[ -r "$cache_file" ]] && [[ -s "$cache_file" ]]; then
                if cat "$cache_file" > "$installed_bundles" 2> /dev/null; then
                    return 0
                else
                    debug_log "Warning: Failed to read cache, rebuilding"
                fi
            else
                debug_log "Warning: Cache file empty or unreadable, rebuilding"
            fi
        fi
    fi
    debug_log "Scanning installed applications, cache expired or missing"
    local -a app_dirs=(
        "/Applications"
        "/System/Applications"
        "$HOME/Applications"
        # Homebrew Cask locations
        "/opt/homebrew/Caskroom"
        "/usr/local/Caskroom"
        # Setapp applications
        "$HOME/Library/Application Support/Setapp/Applications"
    )
    # Temp dir avoids write contention across parallel scans.
    local scan_tmp_dir=$(create_temp_dir)
    local pids=()
    local dir_idx=0
    for app_dir in "${app_dirs[@]}"; do
        [[ -d "$app_dir" ]] || continue
        (
            local -a app_paths=()
            while IFS= read -r app_path; do
                [[ -n "$app_path" ]] && app_paths+=("$app_path")
            done < <(find "$app_dir" -name '*.app' -maxdepth 3 -type d 2> /dev/null)
            local count=0
            for app_path in "${app_paths[@]:-}"; do
                local plist_path="$app_path/Contents/Info.plist"
                [[ ! -f "$plist_path" ]] && continue
                local bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist_path" 2> /dev/null || echo "")
                if [[ -n "$bundle_id" ]]; then
                    echo "$bundle_id"
                    count=$((count + 1))
                fi
            done
        ) > "$scan_tmp_dir/apps_${dir_idx}.txt" &
        pids+=($!)
        dir_idx=$((dir_idx + 1))
    done
    # Collect running apps and LaunchAgents to avoid false orphan cleanup.
    (
        local running_apps=$(run_with_timeout 5 osascript -e 'tell application "System Events" to get bundle identifier of every application process' 2> /dev/null || echo "")
        echo "$running_apps" | tr ',' '\n' | sed -e 's/^ *//;s/ *$//' -e '/^$/d' > "$scan_tmp_dir/running.txt"
        # Fallback: lsappinfo is more reliable than osascript
        if command -v lsappinfo > /dev/null 2>&1; then
            run_with_timeout 3 lsappinfo list 2> /dev/null | grep -o '"CFBundleIdentifier"="[^"]*"' | cut -d'"' -f4 >> "$scan_tmp_dir/running.txt" 2> /dev/null || true
        fi
    ) &
    pids+=($!)
    (
        run_with_timeout 5 find ~/Library/LaunchAgents /Library/LaunchAgents \
            -name "*.plist" -type f 2> /dev/null |
            xargs -I {} basename {} .plist > "$scan_tmp_dir/agents.txt" 2> /dev/null || true
    ) &
    pids+=($!)
    debug_log "Waiting for ${#pids[@]} background processes: ${pids[*]}"
    if [[ ${#pids[@]} -gt 0 ]]; then
        for pid in "${pids[@]}"; do
            wait "$pid" 2> /dev/null || true
        done
    fi
    debug_log "All background processes completed"
    cat "$scan_tmp_dir"/*.txt >> "$installed_bundles" 2> /dev/null || true
    safe_remove "$scan_tmp_dir" true
    sort -u "$installed_bundles" -o "$installed_bundles"
    ensure_user_dir "$(dirname "$cache_file")"
    cp "$installed_bundles" "$cache_file" 2> /dev/null || true
    local app_count=$(wc -l < "$installed_bundles" 2> /dev/null | tr -d ' ')
    debug_log "Scanned $app_count unique applications"
}
# Sensitive data patterns that should never be treated as orphaned
# These patterns protect security-critical application data
readonly ORPHAN_NEVER_DELETE_PATTERNS=(
    "*1password*" "*1Password*"
    "*keychain*" "*Keychain*"
    "*bitwarden*" "*Bitwarden*"
    "*lastpass*" "*LastPass*"
    "*keepass*" "*KeePass*"
    "*dashlane*" "*Dashlane*"
    "*enpass*" "*Enpass*"
    "*ssh*" "*gpg*" "*gnupg*"
    "com.apple.keychain*"
)

# Cache file for mdfind results (Bash 3.2 compatible, no associative arrays)
ORPHAN_MDFIND_CACHE_FILE=""

# Usage: is_bundle_orphaned "bundle_id" "directory_path" "installed_bundles_file"
is_bundle_orphaned() {
    local bundle_id="$1"
    local directory_path="$2"
    local installed_bundles="$3"

    # 1. Fast path: check protection list (in-memory, instant)
    if should_protect_data "$bundle_id"; then
        return 1
    fi

    # 2. Fast path: check sensitive data patterns (in-memory, instant)
    local bundle_lower
    bundle_lower=$(echo "$bundle_id" | LC_ALL=C tr '[:upper:]' '[:lower:]')
    for pattern in "${ORPHAN_NEVER_DELETE_PATTERNS[@]}"; do
        # shellcheck disable=SC2053
        if [[ "$bundle_lower" == $pattern ]]; then
            return 1
        fi
    done

    # 3. Fast path: check installed bundles file (file read, fast)
    if grep -Fxq "$bundle_id" "$installed_bundles" 2> /dev/null; then
        return 1
    fi

    # 4. Fast path: hardcoded system components
    case "$bundle_id" in
        loginwindow | dock | systempreferences | systemsettings | settings | controlcenter | finder | safari)
            return 1
            ;;
    esac

    # 5. Fast path: 60-day modification check (stat call, fast)
    if [[ -e "$directory_path" ]]; then
        local last_modified_epoch=$(get_file_mtime "$directory_path")
        local current_epoch
        current_epoch=$(get_epoch_seconds)
        local days_since_modified=$(((current_epoch - last_modified_epoch) / 86400))
        if [[ $days_since_modified -lt ${ORPHAN_AGE_THRESHOLD:-60} ]]; then
            return 1
        fi
    fi

    # 6. Slow path: mdfind fallback with file-based caching (Bash 3.2 compatible)
    # This catches apps installed in non-standard locations
    if [[ -n "$bundle_id" ]] && [[ "$bundle_id" =~ ^[a-zA-Z0-9._-]+$ ]] && [[ ${#bundle_id} -ge 5 ]]; then
        # Initialize cache file if needed
        if [[ -z "$ORPHAN_MDFIND_CACHE_FILE" ]]; then
            ORPHAN_MDFIND_CACHE_FILE=$(mktemp "${TMPDIR:-/tmp}/mole_mdfind_cache.XXXXXX")
            register_temp_file "$ORPHAN_MDFIND_CACHE_FILE"
        fi

        # Check cache first (grep is fast for small files)
        if grep -Fxq "FOUND:$bundle_id" "$ORPHAN_MDFIND_CACHE_FILE" 2> /dev/null; then
            return 1
        fi
        if grep -Fxq "NOTFOUND:$bundle_id" "$ORPHAN_MDFIND_CACHE_FILE" 2> /dev/null; then
            # Already checked, not found - continue to return 0
            :
        else
            # Query mdfind with strict timeout (2 seconds max)
            local app_exists
            app_exists=$(run_with_timeout 2 mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" 2> /dev/null | head -1 || echo "")
            if [[ -n "$app_exists" ]]; then
                echo "FOUND:$bundle_id" >> "$ORPHAN_MDFIND_CACHE_FILE"
                return 1
            else
                echo "NOTFOUND:$bundle_id" >> "$ORPHAN_MDFIND_CACHE_FILE"
            fi
        fi
    fi

    # All checks passed - this is an orphan
    return 0
}
# Orphaned app data sweep.
clean_orphaned_app_data() {
    if ! ls "$HOME/Library/Caches" > /dev/null 2>&1; then
        stop_section_spinner
        echo -e "  ${GRAY}${ICON_WARNING}${NC} Skipped: No permission to access Library folders"
        return 0
    fi
    start_section_spinner "Scanning installed apps..."
    local installed_bundles=$(create_temp_file)
    scan_installed_apps "$installed_bundles"
    stop_section_spinner
    local app_count=$(wc -l < "$installed_bundles" 2> /dev/null | tr -d ' ')
    echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Found $app_count active/installed apps"
    local orphaned_count=0
    local total_orphaned_kb=0
    start_section_spinner "Scanning orphaned app resources..."
    # CRITICAL: NEVER add LaunchAgents or LaunchDaemons (breaks login items/startup apps).
    local -a resource_types=(
        "$HOME/Library/Caches|Caches|com.*:org.*:net.*:io.*"
        "$HOME/Library/Logs|Logs|com.*:org.*:net.*:io.*"
        "$HOME/Library/Saved Application State|States|*.savedState"
        "$HOME/Library/WebKit|WebKit|com.*:org.*:net.*:io.*"
        "$HOME/Library/HTTPStorages|HTTP|com.*:org.*:net.*:io.*"
        "$HOME/Library/Cookies|Cookies|*.binarycookies"
    )
    orphaned_count=0
    for resource_type in "${resource_types[@]}"; do
        IFS='|' read -r base_path label patterns <<< "$resource_type"
        if [[ ! -d "$base_path" ]]; then
            continue
        fi
        if ! ls "$base_path" > /dev/null 2>&1; then
            continue
        fi
        local -a file_patterns=()
        IFS=':' read -ra pattern_arr <<< "$patterns"
        for pat in "${pattern_arr[@]}"; do
            file_patterns+=("$base_path/$pat")
        done
        if [[ ${#file_patterns[@]} -gt 0 ]]; then
            local _nullglob_state
            _nullglob_state=$(shopt -p nullglob || true)
            shopt -s nullglob
            for item_path in "${file_patterns[@]}"; do
                local iteration_count=0
                local old_ifs=$IFS
                IFS=$'\n'
                local -a matches=()
                # shellcheck disable=SC2206
                matches=($item_path)
                IFS=$old_ifs
                if [[ ${#matches[@]} -eq 0 ]]; then
                    continue
                fi
                for match in "${matches[@]}"; do
                    [[ -e "$match" ]] || continue
                    iteration_count=$((iteration_count + 1))
                    if [[ $iteration_count -gt $MOLE_MAX_ORPHAN_ITERATIONS ]]; then
                        break
                    fi
                    local bundle_id=$(basename "$match")
                    bundle_id="${bundle_id%.savedState}"
                    bundle_id="${bundle_id%.binarycookies}"
                    if is_bundle_orphaned "$bundle_id" "$match" "$installed_bundles"; then
                        local size_kb
                        size_kb=$(get_path_size_kb "$match")
                        if [[ -z "$size_kb" || "$size_kb" == "0" ]]; then
                            continue
                        fi
                        if safe_clean "$match" "Orphaned $label: $bundle_id"; then
                            orphaned_count=$((orphaned_count + 1))
                            total_orphaned_kb=$((total_orphaned_kb + size_kb))
                        fi
                    fi
                done
            done
            eval "$_nullglob_state"
        fi
    done
    stop_section_spinner
    if [[ $orphaned_count -gt 0 ]]; then
        local orphaned_mb=$(echo "$total_orphaned_kb" | awk '{printf "%.1f", $1/1024}')
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Cleaned $orphaned_count items, about ${orphaned_mb}MB"
        note_activity
    fi
    rm -f "$installed_bundles"
}

# Clean orphaned system-level services (LaunchDaemons, LaunchAgents, PrivilegedHelperTools)
# These are left behind when apps are uninstalled but their system services remain
clean_orphaned_system_services() {
    # Requires sudo
    if ! sudo -n true 2> /dev/null; then
        return 0
    fi

    start_section_spinner "Scanning orphaned system services..."

    local orphaned_count=0
    local total_orphaned_kb=0
    local -a orphaned_files=()

    # Known bundle ID patterns for common apps that leave system services behind
    # Format: "file_pattern:app_check_command"
    local -a known_orphan_patterns=(
        # Sogou Input Method
        "com.sogou.*:/Library/Input Methods/SogouInput.app"
        # ClashX
        "com.west2online.ClashX.*:/Applications/ClashX.app"
        # ClashMac
        "com.clashmac.*:/Applications/ClashMac.app"
        # Nektony App Cleaner
        "com.nektony.AC*:/Applications/App Cleaner & Uninstaller.app"
        # i4tools (爱思助手)
        "cn.i4tools.*:/Applications/i4Tools.app"
    )

    local mdfind_cache_file=""
    _system_service_app_exists() {
        local bundle_id="$1"
        local app_path="$2"

        [[ -n "$app_path" && -d "$app_path" ]] && return 0

        if [[ -n "$app_path" ]]; then
            local app_name
            app_name=$(basename "$app_path")
            case "$app_path" in
                /Applications/*)
                    [[ -d "$HOME/Applications/$app_name" ]] && return 0
                    [[ -d "/Applications/Setapp/$app_name" ]] && return 0
                    ;;
                /Library/Input\ Methods/*)
                    [[ -d "$HOME/Library/Input Methods/$app_name" ]] && return 0
                    ;;
            esac
        fi

        if [[ -n "$bundle_id" ]] && [[ "$bundle_id" =~ ^[a-zA-Z0-9._-]+$ ]] && [[ ${#bundle_id} -ge 5 ]]; then
            if [[ -z "$mdfind_cache_file" ]]; then
                mdfind_cache_file=$(mktemp "${TMPDIR:-/tmp}/mole_mdfind_cache.XXXXXX")
                register_temp_file "$mdfind_cache_file"
            fi

            if grep -Fxq "FOUND:$bundle_id" "$mdfind_cache_file" 2> /dev/null; then
                return 0
            fi
            if ! grep -Fxq "NOTFOUND:$bundle_id" "$mdfind_cache_file" 2> /dev/null; then
                local app_found
                app_found=$(run_with_timeout 2 mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" 2> /dev/null | head -1 || echo "")
                if [[ -n "$app_found" ]]; then
                    echo "FOUND:$bundle_id" >> "$mdfind_cache_file"
                    return 0
                fi
                echo "NOTFOUND:$bundle_id" >> "$mdfind_cache_file"
            fi
        fi

        return 1
    }

    # Scan system LaunchDaemons
    if [[ -d /Library/LaunchDaemons ]]; then
        while IFS= read -r -d '' plist; do
            local filename
            filename=$(basename "$plist")

            # Skip Apple system files
            [[ "$filename" == com.apple.* ]] && continue

            # Extract bundle ID from filename (remove .plist extension)
            local bundle_id="${filename%.plist}"

            # Check against known orphan patterns
            for pattern_entry in "${known_orphan_patterns[@]}"; do
                local file_pattern="${pattern_entry%%:*}"
                local app_path="${pattern_entry#*:}"

                # shellcheck disable=SC2053
                if [[ "$bundle_id" == $file_pattern ]] && [[ ! -d "$app_path" ]]; then
                    if _system_service_app_exists "$bundle_id" "$app_path"; then
                        continue
                    fi
                    orphaned_files+=("$plist")
                    local size_kb
                    size_kb=$(sudo du -skP "$plist" 2> /dev/null | awk '{print $1}' || echo "0")
                    total_orphaned_kb=$((total_orphaned_kb + size_kb))
                    orphaned_count=$((orphaned_count + 1))
                    break
                fi
            done
        done < <(sudo find /Library/LaunchDaemons -maxdepth 1 -name "*.plist" -print0 2> /dev/null)
    fi

    # Scan system LaunchAgents
    if [[ -d /Library/LaunchAgents ]]; then
        while IFS= read -r -d '' plist; do
            local filename
            filename=$(basename "$plist")

            # Skip Apple system files
            [[ "$filename" == com.apple.* ]] && continue

            local bundle_id="${filename%.plist}"

            for pattern_entry in "${known_orphan_patterns[@]}"; do
                local file_pattern="${pattern_entry%%:*}"
                local app_path="${pattern_entry#*:}"

                # shellcheck disable=SC2053
                if [[ "$bundle_id" == $file_pattern ]] && [[ ! -d "$app_path" ]]; then
                    if _system_service_app_exists "$bundle_id" "$app_path"; then
                        continue
                    fi
                    orphaned_files+=("$plist")
                    local size_kb
                    size_kb=$(sudo du -skP "$plist" 2> /dev/null | awk '{print $1}' || echo "0")
                    total_orphaned_kb=$((total_orphaned_kb + size_kb))
                    orphaned_count=$((orphaned_count + 1))
                    break
                fi
            done
        done < <(sudo find /Library/LaunchAgents -maxdepth 1 -name "*.plist" -print0 2> /dev/null)
    fi

    # Scan PrivilegedHelperTools
    if [[ -d /Library/PrivilegedHelperTools ]]; then
        while IFS= read -r -d '' helper; do
            local filename
            filename=$(basename "$helper")
            local bundle_id="$filename"

            # Skip Apple system files
            [[ "$filename" == com.apple.* ]] && continue

            for pattern_entry in "${known_orphan_patterns[@]}"; do
                local file_pattern="${pattern_entry%%:*}"
                local app_path="${pattern_entry#*:}"

                # shellcheck disable=SC2053
                if [[ "$filename" == $file_pattern ]] && [[ ! -d "$app_path" ]]; then
                    if _system_service_app_exists "$bundle_id" "$app_path"; then
                        continue
                    fi
                    orphaned_files+=("$helper")
                    local size_kb
                    size_kb=$(sudo du -skP "$helper" 2> /dev/null | awk '{print $1}' || echo "0")
                    total_orphaned_kb=$((total_orphaned_kb + size_kb))
                    orphaned_count=$((orphaned_count + 1))
                    break
                fi
            done
        done < <(sudo find /Library/PrivilegedHelperTools -maxdepth 1 -type f -print0 2> /dev/null)
    fi

    stop_section_spinner

    # Report and clean
    if [[ $orphaned_count -gt 0 ]]; then
        echo -e "  ${GRAY}${ICON_WARNING}${NC} Found $orphaned_count orphaned system services"

        for orphan_file in "${orphaned_files[@]}"; do
            local filename
            filename=$(basename "$orphan_file")

            if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
                debug_log "[DRY RUN] Would remove orphaned service: $orphan_file"
            else
                # Unload if it's a LaunchDaemon/LaunchAgent
                if [[ "$orphan_file" == *.plist ]]; then
                    sudo launchctl unload "$orphan_file" 2> /dev/null || true
                fi
                if safe_sudo_remove "$orphan_file"; then
                    debug_log "Removed orphaned service: $orphan_file"
                fi
            fi
        done

        local orphaned_kb_display
        if [[ $total_orphaned_kb -gt 1024 ]]; then
            orphaned_kb_display=$(echo "$total_orphaned_kb" | awk '{printf "%.1fMB", $1/1024}')
        else
            orphaned_kb_display="${total_orphaned_kb}KB"
        fi
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Cleaned $orphaned_count orphaned services, about $orphaned_kb_display"
        note_activity
    fi

}

# ============================================================================
# Orphaned LaunchAgent/LaunchDaemon Cleanup (Generic Detection)
# ============================================================================

# Extract program path from plist (supports both ProgramArguments and Program)
_extract_program_path() {
    local plist="$1"
    local program=""

    program=$(plutil -extract ProgramArguments.0 raw "$plist" 2> /dev/null)
    if [[ -z "$program" ]]; then
        program=$(plutil -extract Program raw "$plist" 2> /dev/null)
    fi

    echo "$program"
}

# Extract associated bundle identifier from plist
_extract_associated_bundle() {
    local plist="$1"
    local associated=""

    # Try array format first
    associated=$(plutil -extract AssociatedBundleIdentifiers.0 raw "$plist" 2> /dev/null)
    if [[ -z "$associated" ]] || [[ "$associated" == "1" ]]; then
        # Try string format
        associated=$(plutil -extract AssociatedBundleIdentifiers raw "$plist" 2> /dev/null)
        # Filter out dict/array markers
        if [[ "$associated" == "{"* ]] || [[ "$associated" == "["* ]]; then
            associated=""
        fi
    fi

    echo "$associated"
}

# Check if a LaunchAgent/LaunchDaemon is orphaned using multi-layer verification
# Returns 0 if orphaned, 1 if not orphaned
is_launch_item_orphaned() {
    local plist="$1"

    # Layer 1: Check if program path exists
    local program=$(_extract_program_path "$plist")

    # No program path - skip (not a standard launch item)
    [[ -z "$program" ]] && return 1

    # Program exists -> not orphaned
    [[ -e "$program" ]] && return 1

    # Layer 2: Check AssociatedBundleIdentifiers
    local associated=$(_extract_associated_bundle "$plist")
    if [[ -n "$associated" ]]; then
        # Check if associated app exists via mdfind
        if run_with_timeout 2 mdfind "kMDItemCFBundleIdentifier == '$associated'" 2> /dev/null | head -1 | grep -q .; then
            return 1 # Associated app found -> not orphaned
        fi

        # Extract vendor name from bundle ID (com.vendor.app -> vendor)
        local vendor=$(echo "$associated" | cut -d'.' -f2)
        if [[ -n "$vendor" ]] && [[ ${#vendor} -ge 3 ]]; then
            # Check if any app from this vendor exists
            if find /Applications ~/Applications -maxdepth 2 -iname "*${vendor}*" -type d 2> /dev/null | grep -iq "\.app"; then
                return 1 # Vendor app exists -> not orphaned
            fi
        fi
    fi

    # Layer 3: Check Application Support directory activity
    if [[ "$program" =~ /Library/Application\ Support/([^/]+)/ ]]; then
        local app_support_name="${BASH_REMATCH[1]}"

        # Check both user and system Application Support
        for base in "$HOME/Library/Application Support" "/Library/Application Support"; do
            local support_path="$base/$app_support_name"
            if [[ -d "$support_path" ]]; then
                # Check if there are files modified in last 7 days (active usage)
                local recent_file=$(find "$support_path" -type f -mtime -7 2> /dev/null | head -1)
                if [[ -n "$recent_file" ]]; then
                    return 1 # Active Application Support -> not orphaned
                fi
            fi
        done
    fi

    # Layer 4: Check if app name from program path exists
    if [[ "$program" =~ /Applications/([^/]+)\.app/ ]]; then
        local app_name="${BASH_REMATCH[1]}"
        # Look for apps with similar names (case-insensitive)
        if find /Applications ~/Applications -maxdepth 2 -iname "*${app_name}*" -type d 2> /dev/null | grep -iq "\.app"; then
            return 1 # Similar app exists -> not orphaned
        fi
    fi

    # Layer 5: PrivilegedHelper special handling
    if [[ "$program" =~ ^/Library/PrivilegedHelperTools/ ]]; then
        local filename=$(basename "$plist")
        local bundle_id="${filename%.plist}"

        # Extract app hint from bundle ID (com.vendor.app.helper -> vendor)
        local app_hint=$(echo "$bundle_id" | sed 's/com\.//; s/\..*helper.*//')

        if [[ -n "$app_hint" ]] && [[ ${#app_hint} -ge 3 ]]; then
            # Look for main app
            if find /Applications ~/Applications -maxdepth 2 -iname "*${app_hint}*" -type d 2> /dev/null | grep -iq "\.app"; then
                return 1 # Helper's main app exists -> not orphaned
            fi
        fi
    fi

    # All checks failed -> likely orphaned
    return 0
}

# Clean orphaned user-level LaunchAgents
# Only processes ~/Library/LaunchAgents (safer than system-level)
clean_orphaned_launch_agents() {
    local launch_agents_dir="$HOME/Library/LaunchAgents"

    [[ ! -d "$launch_agents_dir" ]] && return 0

    start_section_spinner "Scanning orphaned launch agents..."

    local -a orphaned_items=()
    local total_orphaned_kb=0

    # Scan user LaunchAgents
    while IFS= read -r -d '' plist; do
        local filename=$(basename "$plist")

        # Skip Apple's LaunchAgents
        [[ "$filename" == com.apple.* ]] && continue

        local bundle_id="${filename%.plist}"

        # Check if orphaned using multi-layer verification
        if is_launch_item_orphaned "$plist"; then
            local size_kb=$(get_path_size_kb "$plist")
            orphaned_items+=("$bundle_id|$plist")
            total_orphaned_kb=$((total_orphaned_kb + size_kb))
        fi
    done < <(find "$launch_agents_dir" -maxdepth 1 -name "*.plist" -print0 2> /dev/null)

    stop_section_spinner

    local orphaned_count=${#orphaned_items[@]}

    if [[ $orphaned_count -eq 0 ]]; then
        return 0
    fi

    # Clean the orphaned items automatically
    local removed_count=0
    local dry_run_count=0
    local is_dry_run=false
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        is_dry_run=true
    fi
    for item in "${orphaned_items[@]}"; do
        IFS='|' read -r bundle_id plist_path <<< "$item"

        if [[ "$is_dry_run" == "true" ]]; then
            dry_run_count=$((dry_run_count + 1))
            log_operation "clean" "DRY_RUN" "$plist_path" "orphaned launch agent"
            continue
        fi

        # Try to unload first (if currently loaded)
        launchctl unload "$plist_path" 2> /dev/null || true

        # Remove the plist file
        if safe_remove "$plist_path" false; then
            removed_count=$((removed_count + 1))
            log_operation "clean" "REMOVED" "$plist_path" "orphaned launch agent"
        else
            log_operation "clean" "FAILED" "$plist_path" "permission denied"
        fi
    done

    if [[ "$is_dry_run" == "true" ]]; then
        if [[ $dry_run_count -gt 0 ]]; then
            local cleaned_mb=$(echo "$total_orphaned_kb" | awk '{printf "%.1f", $1/1024}')
            echo "  ${YELLOW}${ICON_DRY_RUN}${NC} Would remove $dry_run_count orphaned launch agent(s), ${cleaned_mb}MB"
            note_activity
        fi
    else
        if [[ $removed_count -gt 0 ]]; then
            local cleaned_mb=$(echo "$total_orphaned_kb" | awk '{printf "%.1f", $1/1024}')
            echo "  ${GREEN}${ICON_SUCCESS}${NC} Removed $removed_count orphaned launch agent(s), ${cleaned_mb}MB"
            note_activity
        fi
    fi
}
