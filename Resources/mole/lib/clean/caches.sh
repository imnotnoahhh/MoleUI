#!/bin/bash
# Cache Cleanup Module
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/purge_shared.sh"
# Preflight TCC prompts once to avoid mid-run interruptions.
check_tcc_permissions() {
    [[ -t 1 ]] || return 0
    local permission_flag="$HOME/.cache/mole/permissions_granted"
    [[ -f "$permission_flag" ]] && return 0
    local -a tcc_dirs=(
        "$HOME/Library/Caches"
        "$HOME/Library/Logs"
        "$HOME/Library/Application Support"
        "$HOME/Library/Containers"
        "$HOME/.cache"
    )
    # Quick permission probe (avoid deep scans).
    local needs_permission_check=false
    if ! ls "$HOME/Library/Caches" > /dev/null 2>&1; then
        needs_permission_check=true
    fi
    if [[ "$needs_permission_check" == "true" ]]; then
        echo ""
        echo -e "${BLUE}First-time setup${NC}"
        echo -e "${GRAY}macOS will request permissions to access Library folders.${NC}"
        echo -e "${GRAY}You may see ${GREEN}${#tcc_dirs[@]} permission dialogs${NC}${GRAY}, please approve them all.${NC}"
        echo ""
        echo -ne "${PURPLE}${ICON_ARROW}${NC} Press ${GREEN}Enter${NC} to continue: "
        read -r
        MOLE_SPINNER_PREFIX="" start_inline_spinner "Requesting permissions..."
        # Touch each directory to trigger prompts without deep scanning.
        for dir in "${tcc_dirs[@]}"; do
            [[ -d "$dir" ]] && command find "$dir" -maxdepth 1 -type d > /dev/null 2>&1
        done
        stop_inline_spinner
        echo ""
    fi
    # Mark as granted to avoid repeat prompts.
    ensure_user_file "$permission_flag"
    return 0
}
# Args: $1=browser_name, $2=cache_path
# Clean Service Worker cache while protecting critical web editors.
clean_service_worker_cache() {
    local browser_name="$1"
    local cache_path="$2"
    [[ ! -d "$cache_path" ]] && return 0
    local cleaned_size=0
    local protected_count=0
    while IFS= read -r cache_dir; do
        [[ ! -d "$cache_dir" ]] && continue
        # Extract a best-effort domain name from cache folder.
        local domain=$(basename "$cache_dir" | grep -oE '[a-zA-Z0-9][-a-zA-Z0-9]*\.[a-zA-Z]{2,}' | head -1 || echo "")
        local size=$(run_with_timeout 5 get_path_size_kb "$cache_dir")
        local is_protected=false
        for protected_domain in "${PROTECTED_SW_DOMAINS[@]}"; do
            if [[ "$domain" == *"$protected_domain"* ]]; then
                is_protected=true
                protected_count=$((protected_count + 1))
                break
            fi
        done
        if [[ "$is_protected" == "false" ]]; then
            if [[ "$DRY_RUN" != "true" ]]; then
                safe_remove "$cache_dir" true || true
            fi
            cleaned_size=$((cleaned_size + size))
        fi
    done < <(run_with_timeout 10 sh -c "find '$cache_path' -type d -depth 2 2> /dev/null || true")
    if [[ $cleaned_size -gt 0 ]]; then
        local spinner_was_running=false
        if [[ -t 1 && -n "${INLINE_SPINNER_PID:-}" ]]; then
            stop_inline_spinner
            spinner_was_running=true
        fi
        local cleaned_mb=$((cleaned_size / 1024))
        if [[ "$DRY_RUN" != "true" ]]; then
            if [[ $protected_count -gt 0 ]]; then
                echo -e "  ${GREEN}${ICON_SUCCESS}${NC} $browser_name Service Worker, ${cleaned_mb}MB, ${protected_count} protected"
            else
                echo -e "  ${GREEN}${ICON_SUCCESS}${NC} $browser_name Service Worker, ${cleaned_mb}MB"
            fi
        else
            echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} $browser_name Service Worker, would clean ${cleaned_mb}MB, ${protected_count} protected"
        fi
        note_activity
        if [[ "$spinner_was_running" == "true" ]]; then
            MOLE_SPINNER_PREFIX="  " start_inline_spinner "Scanning browser Service Worker caches..."
        fi
    fi
}
# Check whether a directory looks like a project container.
project_cache_has_indicators() {
    local dir="$1"
    local max_depth="${2:-5}"
    local indicator_timeout="${MOLE_PROJECT_CACHE_DISCOVERY_TIMEOUT:-2}"
    [[ -d "$dir" ]] || return 1

    local -a find_args=("$dir" "-maxdepth" "$max_depth" "(")
    local first=true
    local indicator
    for indicator in "${MOLE_PURGE_PROJECT_INDICATORS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            find_args+=("-o")
        fi
        find_args+=("-name" "$indicator")
    done
    find_args+=(")" "-print" "-quit")

    run_with_timeout "$indicator_timeout" find "${find_args[@]}" 2> /dev/null | grep -q .
}

# Discover candidate project roots without scanning the whole home directory.
discover_project_cache_roots() {
    local -a roots=()
    local -a unique_roots=()
    local -a seen_identities=()
    local root

    for root in "${MOLE_PURGE_DEFAULT_SEARCH_PATHS[@]}"; do
        [[ -d "$root" ]] && roots+=("$root")
    done

    while IFS= read -r root; do
        [[ -d "$root" ]] && roots+=("$root")
    done < <(mole_purge_read_paths_config "$HOME/.config/mole/purge_paths")

    local _indicator_tmp
    _indicator_tmp=$(create_temp_file)
    local -a _indicator_pids=()
    local _max_jobs
    _max_jobs=$(get_optimal_parallel_jobs scan)

    local dir
    local base
    for dir in "$HOME"/*/; do
        [[ -d "$dir" ]] || continue
        dir="${dir%/}"
        base="${dir##*/}"

        case "$base" in
            .* | Library | Applications | Movies | Music | Pictures | Public)
                continue
                ;;
        esac

        (project_cache_has_indicators "$dir" 5 && echo "$dir" >> "$_indicator_tmp") &
        _indicator_pids+=($!)

        if [[ ${#_indicator_pids[@]} -ge $_max_jobs ]]; then
            wait "${_indicator_pids[0]}" 2> /dev/null || true
            _indicator_pids=("${_indicator_pids[@]:1}")
        fi
    done
    for _pid in "${_indicator_pids[@]}"; do
        wait "$_pid" 2> /dev/null || true
    done

    local _found_dir
    while IFS= read -r _found_dir; do
        [[ -n "$_found_dir" ]] && roots+=("$_found_dir")
    done < "$_indicator_tmp"
    rm -f "$_indicator_tmp"

    [[ ${#roots[@]} -eq 0 ]] && return 0

    for root in "${roots[@]}"; do
        local identity
        identity=$(mole_path_identity "$root")
        if [[ ${#seen_identities[@]} -gt 0 ]] && mole_identity_in_list "$identity" "${seen_identities[@]}"; then
            continue
        fi

        seen_identities+=("$identity")
        unique_roots+=("$root")
    done

    [[ ${#unique_roots[@]} -gt 0 ]] && printf '%s\n' "${unique_roots[@]}"
}

# Scan a project root for supported build caches while pruning heavy subtrees.
scan_project_cache_root() {
    local root="$1"
    local output_file="$2"
    local scan_timeout="${MOLE_PROJECT_CACHE_SCAN_TIMEOUT:-6}"
    [[ -d "$root" ]] || return 0

    local -a find_args=(
        find -P "$root" -maxdepth 9 -mount
        "(" -name "Library" -o -name ".Trash" -o -name "node_modules" -o -name ".git" -o -name ".svn" -o -name ".hg" -o -name ".venv" -o -name "venv" -o -name ".pnpm-store" -o -name ".fvm" -o -name "DerivedData" -o -name "Pods" ")"
        -prune -o
        -type d
        "(" -name ".next" -o -name "__pycache__" -o -name ".dart_tool" ")"
        -print
    )

    local status=0
    run_with_timeout "$scan_timeout" "${find_args[@]}" >> "$output_file" 2> /dev/null || status=$?

    if [[ $status -eq 124 ]]; then
        debug_log "Project cache scan timed out: $root"
    elif [[ $status -ne 0 ]]; then
        debug_log "Project cache scan failed (${status}): $root"
    fi

    return 0
}

# Next.js/Python/Flutter project caches scoped to discovered project roots.
clean_project_caches() {
    stop_inline_spinner 2> /dev/null || true

    local matches_tmp_file
    matches_tmp_file=$(create_temp_file)

    local -a scan_roots=()
    local root
    while IFS= read -r root; do
        [[ -n "$root" ]] && scan_roots+=("$root")
    done < <(discover_project_cache_roots)

    [[ ${#scan_roots[@]} -eq 0 ]] && return 0

    if [[ -t 1 ]]; then
        MOLE_SPINNER_PREFIX="  "
        start_inline_spinner "Searching project caches..."
    fi

    local -a _scan_pids=()
    for root in "${scan_roots[@]}"; do
        scan_project_cache_root "$root" "$matches_tmp_file" &
        _scan_pids+=($!)
    done
    for _pid in "${_scan_pids[@]}"; do
        wait "$_pid" 2> /dev/null || true
    done

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    while IFS= read -r cache_dir; do
        case "$(basename "$cache_dir")" in
            ".next")
                [[ -d "$cache_dir/cache" ]] && safe_clean "$cache_dir/cache"/* "Next.js build cache" || true
                ;;
            "__pycache__")
                # Remove the cache directory itself so we avoid expanding every
                # .pyc file into a separate safe_clean target.
                [[ -d "$cache_dir" ]] && safe_clean "$cache_dir" "Python bytecode cache" || true
                ;;
            ".dart_tool")
                if [[ -d "$cache_dir" ]]; then
                    safe_clean "$cache_dir" "Flutter build cache (.dart_tool)" || true
                    local build_dir="$(dirname "$cache_dir")/build"
                    if [[ -d "$build_dir" ]]; then
                        safe_clean "$build_dir" "Flutter build cache (build/)" || true
                    fi
                fi
                ;;
        esac
    done < <(LC_ALL=C sort -u "$matches_tmp_file" 2> /dev/null)
}
