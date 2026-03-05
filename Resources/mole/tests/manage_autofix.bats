#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "show_suggestions lists auto and manual items and exports flag" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/base.sh"
source "$PROJECT_ROOT/lib/manage/autofix.sh"

export FIREWALL_DISABLED=true
export FILEVAULT_DISABLED=true
export TOUCHID_NOT_CONFIGURED=true
export CACHE_SIZE_GB=9
export BREW_HAS_WARNINGS=true
export DISK_FREE_GB=25

show_suggestions
echo "AUTO_FLAG=${HAS_AUTO_FIX_SUGGESTIONS}"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Enable Firewall for better security"* ]]
    [[ "$output" == *"Enable FileVault"* ]]
    [[ "$output" == *"Enable Touch ID for sudo"* ]]
    [[ "$output" == *"Low disk space (25GB free)"* ]]
    [[ "$output" == *"AUTO_FLAG=true"* ]]
}

@test "ask_for_auto_fix accepts Enter" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/base.sh"
source "$PROJECT_ROOT/lib/manage/autofix.sh"
HAS_AUTO_FIX_SUGGESTIONS=true
read_key() { echo "ENTER"; return 0; }
ask_for_auto_fix
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"yes"* ]]
}

@test "ask_for_auto_fix rejects other keys" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/base.sh"
source "$PROJECT_ROOT/lib/manage/autofix.sh"
HAS_AUTO_FIX_SUGGESTIONS=true
read_key() { echo "ESC"; return 0; }
ask_for_auto_fix
EOF

    [ "$status" -eq 1 ]
    [[ "$output" == *"no"* ]]
}

@test "perform_auto_fix applies available actions and records summary" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/base.sh"
source "$PROJECT_ROOT/lib/manage/autofix.sh"

has_sudo_session() { return 0; }
ensure_sudo_session() { return 0; }
sudo() {
    case "$1" in
        defaults) return 0 ;;
        bash) return 0 ;;
        /usr/libexec/ApplicationFirewall/socketfilterfw) return 0 ;;
        *) return 0 ;;
    esac
}

export FIREWALL_DISABLED=true
export TOUCHID_NOT_CONFIGURED=true

perform_auto_fix
echo "SUMMARY=${AUTO_FIX_SUMMARY}"
echo "DETAILS=${AUTO_FIX_DETAILS}"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Firewall enabled"* ]]
    [[ "$output" == *"Touch ID configured"* ]]
    [[ "$output" == *"SUMMARY=Auto fixes applied: 2 issues"* ]]
    [[ "$output" == *"DETAILS"* ]]
}
