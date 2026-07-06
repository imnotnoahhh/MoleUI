#!/bin/bash
# Clean Homebrew caches and report orphaned dependencies
# Env: DRY_RUN
# Skips if run within 7 days, runs cleanup with package-manager timeouts
brew_autoremove_preview_has_items() {
    local preview_file="$1"
    [[ -s "$preview_file" ]] || return 1
    grep -Eq '^(==> )?Would autoremove [0-9]+ unneeded formula' "$preview_file"
}

show_brew_autoremove_preview() {
    local preview_file="$1"
    echo -e "  ${GRAY}${ICON_WARNING}${NC} Homebrew autoremove would remove:"
    sed 's/^/    /' "$preview_file"
}

run_brew_autoremove_preview() {
    local timeout_seconds="$1"
    local preview_file="$2"

    HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_COLOR=1 NONINTERACTIVE=1 \
        run_with_timeout "$timeout_seconds" brew autoremove --dry-run > "$preview_file" 2>&1
}

clean_homebrew() {
    command -v brew > /dev/null 2>&1 || return 0
    local cleanup_timeout="${MOLE_TIMEOUT_PKG_CLEANUP_SEC:-20}"
    local autoremove_preview_timeout="${MOLE_TIMEOUT_PKG_LIST_SEC:-10}"
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        # Check if Homebrew cache is whitelisted
        if is_path_whitelisted "$HOME/Library/Caches/Homebrew"; then
            echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Homebrew · skipped (whitelist)"
            note_activity
        else
            echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} Homebrew · would cleanup"
            note_activity
            local dry_run_autoremove_file
            dry_run_autoremove_file=$(create_temp_file)
            local dry_run_autoremove_exit=0
            run_brew_autoremove_preview "$autoremove_preview_timeout" "$dry_run_autoremove_file" || dry_run_autoremove_exit=$?
            if [[ $dry_run_autoremove_exit -eq 0 ]] && brew_autoremove_preview_has_items "$dry_run_autoremove_file"; then
                show_brew_autoremove_preview "$dry_run_autoremove_file"
            elif [[ $dry_run_autoremove_exit -eq 124 ]]; then
                echo -e "  ${GRAY}${ICON_WARNING}${NC} Autoremove preview timed out · run ${GRAY}brew autoremove --dry-run${NC} manually"
            fi
        fi
        return 0
    fi
    # Keep behavior consistent with dry-run preview.
    if is_path_whitelisted "$HOME/Library/Caches/Homebrew"; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Homebrew · skipped (whitelist)"
        note_activity
        return 0
    fi
    # Skip if cleaned recently to avoid repeated heavy operations.
    local brew_cache_file="${HOME}/.cache/mole/brew_last_cleanup"
    local cache_valid_days=7
    local should_skip=false
    if [[ -f "$brew_cache_file" ]]; then
        local last_cleanup
        last_cleanup=$(cat "$brew_cache_file" 2> /dev/null || echo "0")
        local current_time
        current_time=$(get_epoch_seconds)
        local time_diff=$((current_time - last_cleanup))
        local days_diff=$((time_diff / 86400))
        if [[ $days_diff -lt $cache_valid_days ]]; then
            should_skip=true
            local cleaned_when="cleaned ${days_diff}d ago"
            [[ $days_diff -eq 0 ]] && cleaned_when="cleaned today"
            echo -e "  ${GRAY}${ICON_WARNING}${NC} Homebrew · skipped (${cleaned_when})"
            note_activity
        fi
    fi
    [[ "$should_skip" == "true" ]] && return 0
    # Skip cleanup if cache is small; autoremove is previewed separately.
    local skip_cleanup=false
    local brew_cache_size=0
    if [[ -d ~/Library/Caches/Homebrew ]]; then
        brew_cache_size=$(run_with_timeout "$MOLE_TIMEOUT_SHORT_QUERY_SEC" du -skP ~/Library/Caches/Homebrew 2> /dev/null | awk '{print $1}')
        local du_exit=$?
        if [[ $du_exit -eq 0 && -n "$brew_cache_size" && "$brew_cache_size" -lt 51200 ]]; then
            skip_cleanup=true
        fi
    fi
    local brew_tmp_file
    local brew_exit=0
    if [[ "$skip_cleanup" == "false" ]]; then
        brew_tmp_file=$(create_temp_file)
        if [[ -t 1 ]]; then MOLE_SPINNER_PREFIX="  " start_inline_spinner "Homebrew cleanup..."; fi
        HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_AUTOREMOVE=1 NONINTERACTIVE=1 \
            run_with_timeout "$cleanup_timeout" brew cleanup --prune=30 > "$brew_tmp_file" 2>&1 || brew_exit=$?
        if [[ -t 1 ]]; then stop_inline_spinner; fi
    fi

    local brew_success=false
    if [[ "$skip_cleanup" == "false" && $brew_exit -eq 0 ]]; then
        brew_success=true
    fi

    # Process cleanup output and extract metrics
    # Summarize cleanup results.
    if [[ "$skip_cleanup" == "true" ]]; then
        # Cleanup was skipped due to small cache size
        local size_mb=$((brew_cache_size / 1024))
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Homebrew cleanup · cache ${size_mb}MB, skipped"
        note_activity
    elif [[ "$brew_success" == "true" && -f "$brew_tmp_file" ]]; then
        local brew_output
        brew_output=$(cat "$brew_tmp_file" 2> /dev/null || echo "")
        local removed_count freed_space
        removed_count=$(printf '%s\n' "$brew_output" | grep -c "Removing:" 2> /dev/null || true)
        freed_space=$(printf '%s\n' "$brew_output" | grep -o "[0-9.]*[KMGT]B freed" 2> /dev/null | tail -1 || true)
        if [[ $removed_count -gt 0 ]] || [[ -n "$freed_space" ]]; then
            if [[ -n "$freed_space" ]]; then
                echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Homebrew cleanup${NC} · ${GREEN}$freed_space${NC}"
                note_activity
            else
                echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Homebrew cleanup · ${removed_count} items"
                note_activity
            fi
        fi
    elif [[ $brew_exit -eq 124 ]]; then
        echo -e "  ${GRAY}${ICON_WARNING}${NC} Homebrew cleanup timed out · run ${GRAY}brew cleanup${NC} manually"
        note_activity
    fi
    local autoremove_preview_file
    autoremove_preview_file=$(create_temp_file)
    local autoremove_preview_exit=0
    run_brew_autoremove_preview "$autoremove_preview_timeout" "$autoremove_preview_file" || autoremove_preview_exit=$?
    if [[ $autoremove_preview_exit -eq 124 ]]; then
        echo -e "  ${GRAY}${ICON_WARNING}${NC} Autoremove preview timed out · run ${GRAY}brew autoremove --dry-run${NC} manually"
        # Keep the manual-action guidance visible past the idle-section erase.
        note_activity
    elif [[ $autoremove_preview_exit -ne 0 ]]; then
        echo -e "  ${GRAY}${ICON_WARNING}${NC} Autoremove preview failed · run ${GRAY}brew autoremove --dry-run${NC} manually"
        note_activity
    elif brew_autoremove_preview_has_items "$autoremove_preview_file"; then
        show_brew_autoremove_preview "$autoremove_preview_file"
        echo -e "  ${GRAY}${ICON_WARNING}${NC} Homebrew autoremove · skipped (run ${GRAY}brew autoremove${NC} manually)"
        note_activity
    fi
    # Update cache timestamp on successful completion or when cleanup was intelligently skipped
    # This prevents repeated cache size checks within the 7-day window
    # Update cache timestamp when any work succeeded or was intentionally skipped.
    if [[ "$skip_cleanup" == "true" ]] || [[ "$brew_success" == "true" ]]; then
        ensure_user_file "$brew_cache_file"
        get_epoch_seconds > "$brew_cache_file"
    fi
}
