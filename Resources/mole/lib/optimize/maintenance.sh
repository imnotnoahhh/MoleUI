#!/bin/bash
# System Configuration Maintenance Module.
# Fix broken preferences and login items.

set -euo pipefail

# Remove corrupted preference files.
fix_broken_preferences() {
    local prefs_dir="$HOME/Library/Preferences"
    [[ -d "$prefs_dir" ]] || return 0

    local broken_count=0

    while IFS= read -r plist_file; do
        [[ -f "$plist_file" ]] || continue

        local filename
        filename=$(basename "$plist_file")
        case "$filename" in
            com.apple.* | .GlobalPreferences* | loginwindow.plist)
                continue
                ;;
        esac

        plutil -lint "$plist_file" > /dev/null 2>&1 && continue

        safe_remove "$plist_file" true > /dev/null 2>&1 || true
        broken_count=$((broken_count + 1))
    done < <(command find "$prefs_dir" -maxdepth 1 -name "*.plist" -type f 2> /dev/null || true)

    # Check ByHost preferences.
    local byhost_dir="$prefs_dir/ByHost"
    if [[ -d "$byhost_dir" ]]; then
        while IFS= read -r plist_file; do
            [[ -f "$plist_file" ]] || continue

            local filename
            filename=$(basename "$plist_file")
            case "$filename" in
                com.apple.* | .GlobalPreferences*)
                    continue
                    ;;
            esac

            plutil -lint "$plist_file" > /dev/null 2>&1 && continue

            safe_remove "$plist_file" true > /dev/null 2>&1 || true
            broken_count=$((broken_count + 1))
        done < <(command find "$byhost_dir" -name "*.plist" -type f 2> /dev/null || true)
    fi

    echo "$broken_count"
}
