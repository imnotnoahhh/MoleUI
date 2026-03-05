#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-brew-uninstall-home.XXXXXX")"
    export HOME
}

teardown_file() {
    rm -rf "$HOME"
    export HOME="$ORIGINAL_HOME"
}

setup() {
    mkdir -p "$HOME/Applications"
    mkdir -p "$HOME/Library/Caches"
    # Create fake Caskroom
    mkdir -p "$HOME/Caskroom/test-app/1.2.3/TestApp.app"
}

@test "get_brew_cask_name detects app in Caskroom (simulated)" {
    # Create fake Caskroom structure with symlink (modern Homebrew style)
    mkdir -p "$HOME/Caskroom/test-app/1.0.0"
    mkdir -p "$HOME/Applications/TestApp.app"
    ln -s "$HOME/Applications/TestApp.app" "$HOME/Caskroom/test-app/1.0.0/TestApp.app"

    run bash <<EOF
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/brew.sh"

# Override the function to use our test Caskroom
get_brew_cask_name() {
    local app_path="\$1"
    [[ -z "\$app_path" || ! -d "\$app_path" ]] && return 1
    command -v brew > /dev/null 2>&1 || return 1

    local app_bundle_name=\$(basename "\$app_path")
    local cask_match
    # Use test Caskroom
    cask_match=\$(find "$HOME/Caskroom" -maxdepth 3 -name "\$app_bundle_name" 2> /dev/null | head -1 || echo "")
    if [[ -n "\$cask_match" ]]; then
        local relative="\${cask_match#$HOME/Caskroom/}"
        echo "\${relative%%/*}"
        return 0
    fi
    return 1
}

get_brew_cask_name "$HOME/Applications/TestApp.app"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == "test-app" ]]
}

@test "get_brew_cask_name handles non-brew apps" {
    mkdir -p "$HOME/Applications/ManualApp.app"

    result=$(bash <<EOF
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/brew.sh"
# Mock brew to return nothing for this
brew() { return 1; }
export -f brew
get_brew_cask_name "$HOME/Applications/ManualApp.app" || echo "not_found"
EOF
    )

    [[ "$result" == "not_found" ]]
}

@test "batch_uninstall_applications uses brew uninstall for casks (mocked)" {
    # Setup fake app
    local app_bundle="$HOME/Applications/BrewApp.app"
    mkdir -p "$app_bundle"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/batch.sh"

# Mock dependencies
request_sudo_access() { return 0; }
start_inline_spinner() { :; }
stop_inline_spinner() { :; }
get_file_owner() { whoami; }
get_path_size_kb() { echo "100"; }
bytes_to_human() { echo "$1"; }
drain_pending_input() { :; }
print_summary_block() { :; }
remove_apps_from_dock() { :; }
force_kill_app() { return 0; }
run_with_timeout() { shift; "$@"; }
export -f run_with_timeout

# Mock brew to track calls
brew() {
    echo "brew call: $*" >> "$HOME/brew_calls.log"
    return 0
}
export -f brew

# Mock get_brew_cask_name to return a name
get_brew_cask_name() { echo "brew-app-cask"; return 0; }
export -f get_brew_cask_name

selected_apps=("0|$HOME/Applications/BrewApp.app|BrewApp|com.example.brewapp|0|Never")
files_cleaned=0
total_items=0
total_size_cleaned=0

# Simulate 'Enter' for confirmation
printf '\n' | batch_uninstall_applications > /dev/null 2>&1

grep -q "uninstall --cask --zap brew-app-cask" "$HOME/brew_calls.log"
EOF

    [ "$status" -eq 0 ]
}

@test "batch_uninstall_applications does not pre-auth sudo for brew-only casks" {
    local app_bundle="$HOME/Applications/BrewPreAuth.app"
    mkdir -p "$app_bundle"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/batch.sh"

start_inline_spinner() { :; }
stop_inline_spinner() { :; }
get_file_owner() { whoami; }
get_path_size_kb() { echo "100"; }
bytes_to_human() { echo "$1"; }
drain_pending_input() { :; }
print_summary_block() { :; }
remove_apps_from_dock() { :; }
force_kill_app() { return 0; }
run_with_timeout() { shift; "$@"; }
export -f run_with_timeout

ensure_sudo_session() {
    echo "UNEXPECTED_ENSURE_SUDO:$*" >> "$HOME/order.log"
    return 1
}

brew() {
    echo "BREW_CALL:$*" >> "$HOME/order.log"
    return 0
}
export -f brew

get_brew_cask_name() { echo "brew-preauth-cask"; return 0; }
export -f get_brew_cask_name

selected_apps=("0|$HOME/Applications/BrewPreAuth.app|BrewPreAuth|com.example.brewpreauth|0|Never")
files_cleaned=0
total_items=0
total_size_cleaned=0

printf '\n' | batch_uninstall_applications > /dev/null 2>&1

grep -q "BREW_CALL:uninstall --cask --zap brew-preauth-cask" "$HOME/order.log"
! grep -q "UNEXPECTED_ENSURE_SUDO:" "$HOME/order.log"
EOF

    [ "$status" -eq 0 ]
}

@test "batch_uninstall_applications runs silent brew autoremove without UX noise" {
    local app_bundle="$HOME/Applications/BrewTimeout.app"
    mkdir -p "$app_bundle"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/batch.sh"

request_sudo_access() { return 0; }
start_inline_spinner() { :; }
stop_inline_spinner() { :; }
get_file_owner() { whoami; }
get_path_size_kb() { echo "100"; }
bytes_to_human() { echo "$1"; }
drain_pending_input() { :; }
print_summary_block() { :; }
force_kill_app() { return 0; }
remove_apps_from_dock() { :; }
refresh_launch_services_after_uninstall() { echo "LS_REFRESH"; }

get_brew_cask_name() { echo "brew-timeout-cask"; return 0; }
brew_uninstall_cask() { return 0; }

run_with_timeout() {
    local duration="$1"
    shift
    echo "TIMEOUT_CALL:$duration:$*" >> "$HOME/timeout_calls.log"
    "$@"
}

selected_apps=("0|$HOME/Applications/BrewTimeout.app|BrewTimeout|com.example.brewtimeout|0|Never")
files_cleaned=0
total_items=0
total_size_cleaned=0

printf '\n' | batch_uninstall_applications

sleep 0.2

if [[ -f "$HOME/timeout_calls.log" ]]; then
    cat "$HOME/timeout_calls.log"
else
    echo "NO_TIMEOUT_CALL"
fi
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"TIMEOUT_CALL:30:brew autoremove"* ]]
    [[ "$output" != *"Checking brew dependencies"* ]]
}

@test "brew_uninstall_cask does not trigger extra sudo pre-auth" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/brew.sh"

debug_log() { :; }
get_path_size_kb() { echo "0"; }
run_with_timeout() { local _timeout="$1"; shift; "$@"; }

sudo() {
  echo "UNEXPECTED_SUDO_CALL:$*"
  return 1
}

brew() {
  if [[ "${1:-}" == "uninstall" ]]; then
    return 0
  fi
  if [[ "${1:-}" == "list" && "${2:-}" == "--cask" ]]; then
    return 0
  fi
  return 0
}
export -f sudo brew

brew_uninstall_cask "mock-cask"
echo "DONE"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"DONE"* ]]
    [[ "$output" != *"UNEXPECTED_SUDO_CALL:"* ]]
}
