#!/bin/bash
# Mole self-update: version discovery (GitHub + Homebrew), install-channel
# detection, the update-available banner cache, and the update flow itself.
# Extracted from the `mole` dispatcher, which now only routes.
#
# VERSION lives in `mole` (install.sh reads it from there); these functions
# read it at call time, so this file must be sourced after it is set.

set -euo pipefail

# The `mole` dispatcher assigns VERSION before sourcing this file, so the
# linter cannot see the assignment from here; declare it as an inherited value.
: "${VERSION:=}"

if [[ -n "${MOLE_MANAGE_UPDATE_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_MANAGE_UPDATE_LOADED=1

get_latest_version() {
    curl -fsSL --connect-timeout 2 --max-time 3 -H "Cache-Control: no-cache" \
        "https://raw.githubusercontent.com/tw93/mole/main/mole" 2> /dev/null |
        grep '^VERSION=' | head -1 | sed 's/VERSION="\(.*\)"/\1/'
}

get_latest_version_from_github() {
    local version
    version=$(curl -fsSL --connect-timeout 2 --max-time 3 \
        "https://api.github.com/repos/tw93/mole/releases/latest" 2> /dev/null |
        grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    version="${version#v}"
    version="${version#V}"
    echo "$version"
}

run_brew_command() {
    local timeout_seconds="$1"
    shift

    HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_AUTO_UPDATE=1 NONINTERACTIVE=1 \
        run_with_timeout "$timeout_seconds" "$@"
}

run_brew_detect() {
    run_brew_command "${MOLE_HOMEBREW_DETECT_TIMEOUT:-2}" "$@"
}

run_brew_query() {
    run_brew_command "${MOLE_HOMEBREW_QUERY_TIMEOUT:-5}" "$@"
}

brew_mole_formula_installed() {
    local brew_cmd="${1:-brew}"
    run_brew_detect "$brew_cmd" list mole > /dev/null 2>&1
}

get_homebrew_latest_version() {
    command -v brew > /dev/null 2>&1 || return 1

    local line candidate=""

    # Prefer local tap outdated info to avoid notifying before formula is available.
    line=$(run_brew_query brew outdated --formula --verbose mole 2> /dev/null | head -1 || true)
    if [[ "$line" == *"< "* ]]; then
        candidate="${line##*< }"
        candidate="${candidate%% *}"
    fi

    # Fallback for environments where outdated output is unavailable.
    if [[ -z "$candidate" ]]; then
        line=$(run_brew_query brew info mole 2> /dev/null | awk 'NR==1 { print; exit }' || true)
        line="${line#==> }"
        line="${line#*: }"
        if [[ "$line" == stable* ]]; then
            candidate=$(printf '%s\n' "$line" | awk '{print $2}')
        fi
    fi

    [[ -n "$candidate" ]] && printf '%s\n' "$candidate"
}
resolve_mole_source_path() {
    # MOLE_ENTRY_SCRIPT is set by the `mole` entrypoint before this file is
    # sourced. Do NOT fall back to BASH_SOURCE[0] first: in here it names this
    # lib file, so the update would target lib/manage/update.sh instead of the
    # mole binary the user invoked.
    local mole_path="${MOLE_ENTRY_SCRIPT:-${BASH_SOURCE[0]:-$0}}"
    if [[ "$mole_path" != /* ]]; then
        if [[ "$mole_path" == */* ]]; then
            mole_path="$(cd "$(dirname "$mole_path")" 2> /dev/null && pwd)/${mole_path##*/}"
        else
            mole_path=$(command -v "$mole_path" 2> /dev/null || true)
        fi
    fi
    [[ -n "$mole_path" ]] && printf '%s\n' "$mole_path"
}

manual_install_repair_reason() {
    local config_root="${MOLE_CONFIG_DIR:-$SCRIPT_DIR}"
    local reason=""
    local helper

    if [[ -f "$config_root/.helper_install_incomplete" ]]; then
        reason="incomplete helper install"
    fi

    for helper in analyze status; do
        if [[ ! -x "$config_root/bin/${helper}-go" ]]; then
            [[ -n "$reason" ]] && reason+=", "
            reason+="missing ${helper}-go"
        fi
    done

    [[ -n "$reason" ]] && printf '%s\n' "$reason"
}

is_homebrew_mole_path() {
    local mole_path="$1"
    local has_brew="$2"
    local link_target=""
    [[ -n "$mole_path" ]] || return 1

    if [[ -L "$mole_path" ]]; then
        link_target=$(readlink "$mole_path" 2> /dev/null) || true
        if [[ "$link_target" == *"Cellar/mole"* ]]; then
            if $has_brew; then
                brew_mole_formula_installed brew && return 0
            fi
            return 1
        fi
        return 1
    fi

    if [[ -f "$mole_path" ]]; then
        # Paths are quoted so Homebrew bottle relocation cannot break parsing
        # when the prefix contains spaces (e.g. Applite under "Application Support").
        case "$mole_path" in
            "/opt/homebrew/bin/mole" | "/usr/local/bin/mole")
                if [[ -d "/opt/homebrew/Cellar/mole" ]] || [[ -d "/usr/local/Cellar/mole" ]]; then
                    if $has_brew; then
                        brew_mole_formula_installed brew && return 0
                    else
                        return 0 # Cellar exists, probably Homebrew install
                    fi
                fi
                ;;
        esac
    fi

    return 1
}

# Install detection (Homebrew vs manual).
# Always follows the invoked Mole script, never PATH, so update and remove act
# on the Mole the user actually ran instead of another copy earlier in PATH.
is_homebrew_install() {
    local has_brew=false
    if command -v brew > /dev/null 2>&1; then
        has_brew=true
    fi

    local mole_path
    mole_path=$(resolve_mole_source_path || true)
    is_homebrew_mole_path "$mole_path" "$has_brew"
}

get_install_channel() {
    # Try user config dir first (matches install.sh behavior), fallback to SCRIPT_DIR
    local channel_file="${MOLE_CONFIG_DIR:-$HOME/.config/mole}/install_channel"
    if [[ ! -f "$channel_file" ]]; then
        channel_file="$SCRIPT_DIR/install_channel"
    fi
    local channel="stable"
    if [[ -f "$channel_file" ]]; then
        channel=$(sed -n 's/^CHANNEL=\(.*\)$/\1/p' "$channel_file" | head -1)
    fi
    case "$channel" in
        nightly | dev | stable) printf '%s\n' "$channel" ;;
        *) printf 'stable\n' ;;
    esac
}

get_install_commit() {
    # Try user config dir first (matches install.sh behavior), fallback to SCRIPT_DIR
    local channel_file="${MOLE_CONFIG_DIR:-$HOME/.config/mole}/install_channel"
    if [[ ! -f "$channel_file" ]]; then
        channel_file="$SCRIPT_DIR/install_channel"
    fi
    if [[ -f "$channel_file" ]]; then
        sed -n 's/^COMMIT_HASH=\(.*\)$/\1/p' "$channel_file" | head -1
    fi
}

get_latest_commit_from_github() {
    local sha
    sha=$(curl -fsSL --connect-timeout 2 --max-time 3 \
        "https://api.github.com/repos/tw93/mole/commits/main" 2> /dev/null |
        grep '"sha"[[:space:]]*:[[:space:]]*"[0-9a-f]\{40\}"' | head -1 | sed -E 's/.*"sha"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/') || sha=""
    echo "$sha"
}

mole_update_message_cache_is_current() {
    local msg_cache="$1"
    [[ -f "$msg_cache" && -s "$msg_cache" ]] || return 1

    local mole_path
    mole_path=$(resolve_mole_source_path || true)
    [[ -n "$mole_path" && -e "$mole_path" ]] || return 0

    local cache_mtime mole_mtime
    cache_mtime=$(get_file_mtime "$msg_cache")
    mole_mtime=$(get_file_mtime "$mole_path")

    if [[ "$cache_mtime" =~ ^[0-9]+$ && "$mole_mtime" =~ ^[0-9]+$ &&
        "$cache_mtime" -gt 0 && "$mole_mtime" -gt 0 &&
        "$cache_mtime" -lt "$mole_mtime" ]]; then
        return 1
    fi

    return 0
}

read_update_message_cache() {
    local msg_cache="$1"
    if mole_update_message_cache_is_current "$msg_cache"; then
        cat "$msg_cache" 2> /dev/null || echo ""
    else
        : > "$msg_cache" 2> /dev/null || true
        echo ""
    fi
}

# Background update notice
check_for_updates() {
    local msg_cache="$HOME/.cache/mole/update_message"
    ensure_user_dir "$(dirname "$msg_cache")"
    ensure_user_file "$msg_cache"

    (
        (
            local channel
            channel=$(get_install_channel)

            if [[ "$channel" == "nightly" ]]; then
                # Nightly: compare commit hashes instead of version numbers
                local installed_commit latest_commit
                installed_commit=$(get_install_commit)
                latest_commit=$(get_latest_commit_from_github)

                if [[ -n "$installed_commit" && -n "$latest_commit" && "${installed_commit:0:7}" != "${latest_commit:0:7}" ]]; then
                    printf "\nNew nightly commit %s available, run %smo update --nightly%s\n\n" "${latest_commit:0:7}" "$GREEN" "$NC" > "$msg_cache"
                else
                    echo -n > "$msg_cache"
                fi
            else
                local latest

                latest=$(get_latest_version_from_github)
                if [[ -z "$latest" ]]; then
                    latest=$(get_latest_version)
                fi

                if [[ -n "$latest" && "$VERSION" != "$latest" && "$(printf '%s\n' "$VERSION" "$latest" | sort -V | head -1)" == "$VERSION" ]]; then
                    if is_homebrew_install; then
                        # For Homebrew, only notify if the brew tap has the new version available locally
                        local brew_latest
                        brew_latest=$(get_homebrew_latest_version || true)
                        if [[ -n "$brew_latest" && "$brew_latest" != "$VERSION" && "$(printf '%s\n' "$VERSION" "$brew_latest" | sort -V | head -1)" == "$VERSION" ]]; then
                            printf "\nUpdate %s available, run %smo update%s\n\n" "$brew_latest" "$GREEN" "$NC" > "$msg_cache"
                        else
                            echo -n > "$msg_cache"
                        fi
                    else
                        printf "\nUpdate %s available, run %smo update%s\n\n" "$latest" "$GREEN" "$NC" > "$msg_cache"
                    fi
                else
                    echo -n > "$msg_cache"
                fi
            fi
        ) > /dev/null 2>&1 < /dev/null &
    )
}

# UI helpers
show_brand_banner() {
    cat << EOF
${GREEN} __  __       _      ${NC}
${GREEN}|  \/  | ___ | | ___ ${NC}
${GREEN}| |\/| |/ _ \| |/ _ \\${NC}
${GREEN}| |  | | (_) | |  __/${NC}  ${BLUE}https://mole.fit${NC}
${GREEN}|_|  |_|\___/|_|\___|${NC}  ${GREEN}${MOLE_TAGLINE}${NC}

EOF
}

show_version() {
    local os_ver
    if command -v sw_vers > /dev/null; then
        os_ver=$(sw_vers -productVersion)
    else
        os_ver="Unknown"
    fi

    local arch
    arch=$(uname -m)

    local kernel
    kernel=$(uname -r)

    local sip_status
    if command -v csrutil > /dev/null; then
        sip_status=$(csrutil status 2> /dev/null | grep -o "enabled\|disabled" || echo "Unknown")
        sip_status="$(LC_ALL=C tr '[:lower:]' '[:upper:]' <<< "${sip_status:0:1}")${sip_status:1}"
    else
        sip_status="Unknown"
    fi

    local disk_free
    disk_free=$(get_free_space)

    local install_method="Manual"
    if is_homebrew_install; then
        install_method="Homebrew"
    fi

    local channel
    channel=$(get_install_channel)

    printf '\nMole version %s\n' "$VERSION"
    if [[ "$channel" == "nightly" ]]; then
        local commit
        commit=$(get_install_commit)
        if [[ -n "$commit" ]]; then
            printf 'Channel: Nightly (%s)\n' "$commit"
        else
            printf 'Channel: Nightly\n'
        fi
    fi
    printf 'macOS: %s\n' "$os_ver"
    printf 'Architecture: %s\n' "$arch"
    printf 'Kernel: %s\n' "$kernel"
    printf 'SIP: %s\n' "$sip_status"
    printf 'Disk Free: %s\n' "$disk_free"
    printf 'Install: %s\n' "$install_method"
    printf 'Shell: %s\n\n' "${SHELL:-Unknown}"
}

show_help() {
    show_brand_banner
    echo
    printf "%s%s%s\n" "$BLUE" "COMMANDS" "$NC"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo" "$NC" "Main menu"
    for entry in "${MOLE_COMMANDS[@]}"; do
        local name="${entry%%:*}"
        local desc="${entry#*:}"
        local display="mo $name"
        [[ "$name" == "help" ]] && display="mo --help"
        [[ "$name" == "version" ]] && display="mo --version"
        printf "  %s%-28s%s %s\n" "$GREEN" "$display" "$NC" "$desc"
    done
    echo
    printf "  %s%-28s%s %s\n" "$GREEN" "mo clean --dry-run" "$NC" "Preview cleanup"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo clean --whitelist" "$NC" "Manage protected caches"

    printf "  %s%-28s%s %s\n" "$GREEN" "mo optimize --dry-run" "$NC" "Preview optimization"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo optimize --whitelist" "$NC" "Manage protected items"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo uninstall --dry-run" "$NC" "Preview app uninstall"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo history --json" "$NC" "Export cleanup history"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo purge --dry-run" "$NC" "Preview project purge"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo installer --dry-run" "$NC" "Preview installer cleanup"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo touchid enable --dry-run" "$NC" "Preview Touch ID setup"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo completion --dry-run" "$NC" "Preview shell completion edits"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo purge --paths" "$NC" "Configure scan directories"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo analyze /Volumes" "$NC" "Analyze external drives only"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo update --force" "$NC" "Force reinstall latest stable version"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo update --nightly" "$NC" "Install latest unreleased main branch build"
    printf "  %s%-28s%s %s\n" "$GREEN" "mo remove --dry-run" "$NC" "Preview Mole removal"
    echo
    printf "%s%s%s\n" "$BLUE" "OPTIONS" "$NC"
    printf "  %s%-28s%s %s\n" "$GREEN" "--debug" "$NC" "Show detailed operation logs"
    echo
}

# Update flow (Homebrew or installer).
update_mole() {
    local force_update="${1:-false}"
    local nightly_update="${2:-false}"
    local update_interrupted=false
    local sudo_keepalive_pid=""

    # Cleanup function for sudo keepalive
    _update_cleanup() {
        [[ -n "$sudo_keepalive_pid" ]] && _stop_sudo_keepalive "$sudo_keepalive_pid" || true
    }
    trap '_update_cleanup; update_interrupted=true; echo ""; exit 130' INT TERM

    if is_homebrew_install; then
        if [[ "$nightly_update" == "true" ]]; then
            local review_icon="${ICON_REVIEW:-☞}"
            log_error "Nightly update is only available for script installations. Homebrew installs follow stable releases."
            printf '%s Reinstall via script to use: mo update --nightly\n' "$review_icon"
            exit 1
        fi
        update_via_homebrew "$VERSION"
        exit 0
    fi

    # Resolve the invoked Mole up front so the installer targets this manual
    # install, not another mole earlier in PATH. Fail before any download.
    local mole_path
    if ! mole_path=$(resolve_mole_source_path); then
        log_error "Unable to resolve current Mole path"
        exit 1
    fi
    local install_dir
    if ! install_dir="$(cd "$(dirname "$mole_path")" && pwd)"; then
        log_error "Unable to resolve current Mole install directory"
        exit 1
    fi

    local latest=""
    local download_label="Downloading latest version..."
    local install_label="Installing update..."
    local final_success_label="latest version"
    local switch_to_stable_channel=false
    local repair_install=false
    local repair_reason=""

    if [[ "$nightly_update" == "true" ]]; then
        latest="main"
        download_label="Downloading nightly installer..."
        install_label="Installing nightly update..."
        final_success_label="nightly build (main)"

        if [[ "$force_update" != "true" ]]; then
            local installed_commit latest_commit
            installed_commit=$(get_install_commit)
            latest_commit=$(get_latest_commit_from_github)

            if [[ "$installed_commit" =~ ^[0-9a-f]{7,40}$ && "$latest_commit" =~ ^[0-9a-f]{40}$ &&
                "${installed_commit:0:7}" == "${latest_commit:0:7}" ]]; then
                repair_reason=$(manual_install_repair_reason || true)
                if [[ -n "$repair_reason" ]]; then
                    repair_install=true
                else
                    echo ""
                    echo -e "${GREEN}${ICON_SUCCESS}${NC} Already on latest nightly, ${latest_commit:0:7}"
                    echo ""
                    exit 0
                fi
            fi
        fi
    else
        latest=$(get_latest_version_from_github)
        [[ -z "$latest" ]] && latest=$(get_latest_version)

        if [[ -z "$latest" ]]; then
            log_error "Unable to check for updates. Check network connection."
            echo -e "${ICON_REVIEW} Check if you can access GitHub, https://github.com"
            echo -e "${ICON_REVIEW} Try again with: ${GRAY}mo update${NC}"
            exit 1
        fi
        if [[ ! "$latest" =~ ^[Vv]?[0-9]+(\.[0-9]+)*$ ]]; then
            log_error "Invalid version response: $latest"
            echo -e "${ICON_REVIEW} Try again later or use: ${GRAY}mo update --nightly${NC}"
            exit 1
        fi

        local install_channel
        install_channel=$(get_install_channel)
        if [[ "$install_channel" == "nightly" || "$install_channel" == "dev" ]]; then
            switch_to_stable_channel=true
        fi

        if [[ "$switch_to_stable_channel" == "true" ]]; then
            install_label="Switching to stable channel..."
        elif [[ "$VERSION" == "$latest" && "$force_update" != "true" ]]; then
            repair_reason=$(manual_install_repair_reason || true)
            if [[ -n "$repair_reason" ]]; then
                repair_install=true
            else
                echo ""
                echo -e "${GREEN}${ICON_SUCCESS}${NC} Already on latest version, ${VERSION}"
                echo ""
                exit 0
            fi
        fi
    fi

    if [[ "$repair_install" == "true" ]]; then
        download_label="Downloading repair installer..."
        install_label="Repairing Mole installation..."
        log_warning "Mole installation needs repair: $repair_reason"
    fi

    if [[ -t 1 ]]; then
        start_inline_spinner "$download_label"
    else
        echo "${download_label%...}"
    fi

    local installer_ref="main"
    if [[ "$nightly_update" != "true" ]]; then
        installer_ref="V${latest#V}"
    fi
    local installer_url="https://raw.githubusercontent.com/tw93/mole/${installer_ref}/install.sh"
    local tmp_installer
    tmp_installer="$(mktemp_file)" || {
        log_error "Update failed"
        exit 1
    }

    local download_error=""
    if command -v curl > /dev/null 2>&1; then
        download_error=$(curl -fsSL --connect-timeout 10 --max-time 60 "$installer_url" -o "$tmp_installer" 2>&1) || {
            local curl_exit=$?
            if [[ -t 1 ]]; then stop_inline_spinner; fi
            rm -f "$tmp_installer"
            log_error "Update failed, curl error: $curl_exit"

            case $curl_exit in
                6) echo -e "${ICON_REVIEW} Could not resolve host. Check DNS or network connection." ;;
                7) echo -e "${ICON_REVIEW} Failed to connect. Check network or proxy settings." ;;
                22) echo -e "${ICON_REVIEW} HTTP 404 Not Found. The installer may have moved." ;;
                28) echo -e "${ICON_REVIEW} Connection timed out. Try again or check firewall." ;;
                *) echo -e "${ICON_REVIEW} Check network connection and try again." ;;
            esac
            echo -e "${ICON_REVIEW} URL: $installer_url"
            exit 1
        }
    elif command -v wget > /dev/null 2>&1; then
        download_error=$(wget --timeout=10 --tries=3 -qO "$tmp_installer" "$installer_url" 2>&1) || {
            if [[ -t 1 ]]; then stop_inline_spinner; fi
            rm -f "$tmp_installer"
            log_error "Update failed, wget error"
            echo -e "${ICON_REVIEW} Check network connection and try again."
            echo -e "${ICON_REVIEW} URL: $installer_url"
            exit 1
        }
    else
        if [[ -t 1 ]]; then stop_inline_spinner; fi
        rm -f "$tmp_installer"
        log_error "curl or wget required"
        echo -e "${ICON_REVIEW} Install curl with: ${GRAY}brew install curl${NC}"
        exit 1
    fi

    if [[ -t 1 ]]; then stop_inline_spinner; fi
    chmod +x "$tmp_installer"

    local requires_sudo="false"
    if [[ ! -w "$install_dir" ]]; then
        requires_sudo="true"
    elif [[ -e "$install_dir/mole" && ! -w "$install_dir/mole" ]]; then
        requires_sudo="true"
    fi

    if [[ "$requires_sudo" == "true" ]]; then
        if ! request_sudo_access "Mole update requires admin access"; then
            log_error "Update aborted, admin access denied"
            rm -f "$tmp_installer"
            exit 1
        fi
        # Start sudo keepalive to prevent cache expiration during install
        sudo_keepalive_pid=$(_start_sudo_keepalive)
    fi

    local installer_assume_sudo_auth="0"
    if [[ "$requires_sudo" == "true" ]]; then
        installer_assume_sudo_auth="1"
    fi

    if [[ -t 1 ]]; then
        start_inline_spinner "$install_label"
    else
        echo "${install_label%...}"
    fi

    process_install_output() {
        local output="$1"
        local fallback_version="$2"
        local success_label="$3"
        if [[ -t 1 ]]; then stop_inline_spinner; fi

        local filtered_output
        filtered_output=$(printf '%s\n' "$output" | sed '/^$/d')
        if [[ -n "$filtered_output" ]]; then
            printf '\n%s\n' "$filtered_output"
        fi

        if ! printf '%s\n' "$output" | grep -Eq "Updated to latest version|Already on latest version"; then
            local new_version
            new_version=$(printf '%s\n' "$output" | sed -n 's/.*-> \([^[:space:]]\{1,\}\).*/\1/p' | head -1)
            if [[ -z "$new_version" ]]; then
                new_version=$(printf '%s\n' "$output" | sed -n 's/.*version[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p' | head -1)
            fi
            if [[ -z "$new_version" ]]; then
                new_version=$("$mole_path" --version 2> /dev/null | awk 'NR==1 && NF {print $NF}' || echo "")
            fi
            if [[ -z "$new_version" ]]; then
                new_version="$fallback_version"
            fi
            printf '\n%s\n\n' "${GREEN}${ICON_SUCCESS}${NC} Updated to ${success_label}, ${new_version:-unknown}"
        else
            printf '\n'
        fi
    }

    local install_output
    local update_tag="V${latest#V}"
    local config_dir="${MOLE_CONFIG_DIR:-$SCRIPT_DIR}"
    if [[ ! -f "$config_dir/lib/core/common.sh" ]]; then
        config_dir="$HOME/.config/mole"
    fi

    if [[ "$nightly_update" == "true" ]]; then
        if install_output=$(MOLE_ASSUME_SUDO_AUTH="$installer_assume_sudo_auth" MOLE_VERSION="main" "$tmp_installer" --prefix "$install_dir" --config "$config_dir" 2>&1); then
            process_install_output "$install_output" "$latest" "$final_success_label"
        else
            if [[ -t 1 ]]; then stop_inline_spinner; fi
            rm -f "$tmp_installer"
            _update_cleanup
            log_error "Nightly update failed"
            echo "$install_output" | tail -10 >&2 # Show last 10 lines of error
            exit 1
        fi
    elif [[ "$force_update" == "true" || "$switch_to_stable_channel" == "true" || "$repair_install" == "true" ]]; then
        if install_output=$(MOLE_ASSUME_SUDO_AUTH="$installer_assume_sudo_auth" MOLE_VERSION="$update_tag" "$tmp_installer" --prefix "$install_dir" --config "$config_dir" 2>&1); then
            process_install_output "$install_output" "$latest" "$final_success_label"
        else
            if [[ -t 1 ]]; then stop_inline_spinner; fi
            rm -f "$tmp_installer"
            _update_cleanup
            log_error "Update failed"
            echo "$install_output" | tail -10 >&2 # Show last 10 lines of error
            exit 1
        fi
    else
        if install_output=$(MOLE_ASSUME_SUDO_AUTH="$installer_assume_sudo_auth" MOLE_VERSION="$update_tag" "$tmp_installer" --prefix "$install_dir" --config "$config_dir" --update 2>&1); then
            process_install_output "$install_output" "$latest" "$final_success_label"
        else
            if install_output=$(MOLE_ASSUME_SUDO_AUTH="$installer_assume_sudo_auth" MOLE_VERSION="$update_tag" "$tmp_installer" --prefix "$install_dir" --config "$config_dir" 2>&1); then
                process_install_output "$install_output" "$latest" "$final_success_label"
            else
                if [[ -t 1 ]]; then stop_inline_spinner; fi
                rm -f "$tmp_installer"
                _update_cleanup
                log_error "Update failed"
                echo "$install_output" | tail -10 >&2 # Show last 10 lines of error
                exit 1
            fi
        fi
    fi

    rm -f "$tmp_installer"
    rm -f "$HOME/.cache/mole/update_message"

    # Cleanup and reset trap
    _update_cleanup
    trap - INT TERM
}
