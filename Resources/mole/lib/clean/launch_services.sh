#!/bin/bash
# LaunchServices cleanup helpers for `mo clean`.

set -euo pipefail

# shellcheck disable=SC2329
launch_services_extract_app_path_from_line() {
    local line="$1"
    [[ "$line" == */*".app"* ]] || return 1

    local path="/${line#*/}"
    path="${path%%.app*}.app"
    path="${path%/}"

    [[ "$path" == /* && "$path" == *.app ]] || return 1
    printf '%s\n' "$path"
}

# shellcheck disable=SC2329
launch_services_stale_app_path_is_safe() {
    local path="$1"

    [[ -n "$path" ]] || return 1
    [[ "$path" == /* ]] || return 1
    [[ "$path" == *.app ]] || return 1
    [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1

    case "$path" in
        *"/../"* | *"/.." | "../"* | "/System/"* | "/Library/Apple/"*)
            return 1
            ;;
    esac

    [[ ! -e "$path" ]]
}

# shellcheck disable=SC2329
launch_services_emit_missing_record_paths() {
    local -a record_paths=()
    local missing_record=false
    local line app_path

    _flush_launch_services_record() {
        if [[ "$missing_record" == "true" && ${#record_paths[@]} -gt 0 ]]; then
            local record_path
            for record_path in "${record_paths[@]}"; do
                if launch_services_stale_app_path_is_safe "$record_path"; then
                    printf '%s\n' "$record_path"
                fi
            done
        fi
        record_paths=()
        missing_record=false
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" ]]; then
            _flush_launch_services_record
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*bundle[[:space:]] ]]; then
            _flush_launch_services_record
        fi

        if [[ "$line" == *"Bundle node not found on disk"* ]]; then
            missing_record=true
        fi

        if app_path=$(launch_services_extract_app_path_from_line "$line"); then
            record_paths+=("$app_path")
        fi
    done

    _flush_launch_services_record
}

# shellcheck disable=SC2329
collect_stale_launch_services_app_paths() {
    local lsregister="$1"

    [[ -x "$lsregister" ]] || return 0

    run_with_timeout "$MOLE_TIMEOUT_PKG_LIST_SEC" "$lsregister" -dump 2> /dev/null |
        launch_services_emit_missing_record_paths |
        LC_ALL=C sort -u
}

# shellcheck disable=SC2329
clean_stale_launch_services_registrations() {
    local lsregister
    lsregister=$(get_lsregister_path)
    [[ -x "$lsregister" ]] || return 0

    local candidates_file
    candidates_file=$(mktemp_file "launch_services_stale_apps") || return 0

    # The lsregister dump below takes seconds on a large LaunchServices
    # database; without a spinner the section looks hung (per-step loading
    # feedback).
    start_section_spinner "Scanning launch services..."
    if ! collect_stale_launch_services_app_paths "$lsregister" > "$candidates_file"; then
        stop_section_spinner
        debug_log "LaunchServices stale app scan failed"
        return 0
    fi

    local max_items="${MOLE_LAUNCH_SERVICES_STALE_LIMIT:-50}"
    [[ "$max_items" =~ ^[0-9]+$ ]] || max_items=50
    [[ "$max_items" -gt 0 ]] || max_items=50

    local -a stale_apps=()
    local app_path
    while IFS= read -r app_path; do
        [[ -n "$app_path" ]] || continue
        if launch_services_stale_app_path_is_safe "$app_path"; then
            stale_apps+=("$app_path")
            if [[ ${#stale_apps[@]} -ge "$max_items" ]]; then
                break
            fi
        fi
    done < "$candidates_file"

    stop_section_spinner
    [[ ${#stale_apps[@]} -gt 0 ]] || return 0

    note_activity

    local count="${#stale_apps[@]}"
    local count_label="$count"
    local total_candidates
    total_candidates=$(wc -l < "$candidates_file" | tr -d '[:space:]')
    if [[ "$total_candidates" =~ ^[0-9]+$ && "$total_candidates" -gt "$count" ]]; then
        count_label="${count}+"
    fi

    if [[ "${DRY_RUN:-false}" == "true" || "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} LaunchServices stale app registrations · would unregister ${count_label}"
        echo -e "  ${GRAY}${ICON_SUBLIST}${NC} Example: ${GRAY}${stale_apps[0]/#$HOME/~}${NC}"
        return 0
    fi

    local success_count=0
    local failed_count=0
    start_section_spinner "Cleaning stale launch services..."
    for app_path in "${stale_apps[@]}"; do
        debug_log "Unregistering stale LaunchServices app: $app_path"
        if run_with_timeout "$MOLE_TIMEOUT_SHORT_QUERY_SEC" "$lsregister" -u "$app_path" > /dev/null 2>&1; then
            success_count=$((success_count + 1))
        else
            failed_count=$((failed_count + 1))
            debug_log "Failed to unregister stale LaunchServices app: $app_path"
        fi
    done
    stop_section_spinner

    if [[ $success_count -gt 0 ]]; then
        log_success "LaunchServices stale app registrations, $success_count removed"
    fi
    if [[ $failed_count -gt 0 ]]; then
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} LaunchServices stale app registrations, ${failed_count} failed"
    fi
}
