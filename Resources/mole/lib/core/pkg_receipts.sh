#!/bin/bash
# Mole - pkgutil receipt helpers.
# Finds package-installed app bundles outside the standard app locations.

set -euo pipefail

if [[ -n "${MOLE_PKG_RECEIPTS_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_PKG_RECEIPTS_LOADED=1

_mole_pkg_receipt_app_root() {
    local rel_path="${1#/}"
    [[ -n "$rel_path" ]] || return 1

    local app_path="/$rel_path"
    case "$app_path" in
        /usr/local/*.app | /opt/*.app)
            printf '%s\n' "$app_path"
            return 0
            ;;
        /usr/local/*.app/* | /opt/*.app/*)
            printf '%s.app\n' "${app_path%%.app/*}"
            return 0
            ;;
    esac

    return 1
}

pkg_receipt_nonstandard_app_paths() {
    if ! command -v pkgutil > /dev/null 2>&1; then
        return 0
    fi

    local pkgs_output
    if declare -f run_with_timeout > /dev/null 2>&1; then
        pkgs_output=$(run_with_timeout "${MOLE_PKG_RECEIPT_LIST_TIMEOUT:-3}" pkgutil --pkgs 2> /dev/null || true)
    else
        pkgs_output=$(pkgutil --pkgs 2> /dev/null || true)
    fi
    [[ -n "$pkgs_output" ]] || return 0

    local -a seen_apps=()
    local scan_start=$SECONDS
    local scan_timeout="${MOLE_PKG_RECEIPT_SCAN_TIMEOUT:-8}"
    local pkg_id
    while IFS= read -r pkg_id; do
        if [[ "$scan_timeout" =~ ^[0-9]+$ && $scan_timeout -gt 0 && $((SECONDS - scan_start)) -ge $scan_timeout ]]; then
            break
        fi

        [[ -n "$pkg_id" ]] || continue
        [[ "$pkg_id" =~ ^com\.apple\. ]] && continue

        local pkg_files
        if declare -f run_with_timeout > /dev/null 2>&1; then
            pkg_files=$(run_with_timeout "${MOLE_PKG_RECEIPT_FILES_TIMEOUT:-1}" pkgutil --files "$pkg_id" 2> /dev/null || true)
        else
            pkg_files=$(pkgutil --files "$pkg_id" 2> /dev/null || true)
        fi
        [[ -n "$pkg_files" ]] || continue

        local rel_path app_path duplicate
        while IFS= read -r rel_path; do
            app_path=$(_mole_pkg_receipt_app_root "$rel_path" 2> /dev/null || true)
            [[ -n "$app_path" && -d "$app_path" ]] || continue

            duplicate=false
            local seen
            for seen in "${seen_apps[@]}"; do
                if [[ "$seen" == "$app_path" ]]; then
                    duplicate=true
                    break
                fi
            done
            [[ "$duplicate" == "true" ]] && continue

            seen_apps+=("$app_path")
            printf '%s\n' "$app_path"
        done <<< "$pkg_files"
    done <<< "$pkgs_output"
}
