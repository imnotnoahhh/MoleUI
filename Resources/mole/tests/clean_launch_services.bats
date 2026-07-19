#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

setup() {
    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-launch-services-home.XXXXXX")"
    TEST_ROOT="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-launch-services-case.XXXXXX")"
    export HOME TEST_ROOT
}

teardown() {
    case "${HOME:-}" in
        "${BATS_TEST_DIRNAME}/tmp-launch-services-home."*) rm -rf "$HOME" ;;
    esac
    case "${TEST_ROOT:-}" in
        "${BATS_TEST_DIRNAME}/tmp-launch-services-case."*) rm -rf "$TEST_ROOT" ;;
    esac
}

write_lsregister_stub() {
    local bin_path="$1"
    mkdir -p "$(dirname "$bin_path")"
    cat > "$bin_path" <<'SCRIPT'
#!/usr/bin/env bash
{
    printf 'argc=%s\n' "$#"
    for arg in "$@"; do
        printf 'arg=%s\n' "$arg"
    done
} >> "$LSREGISTER_LOG"

case "${1:-}" in
    -dump)
        cat "$LSREGISTER_DUMP"
        exit 0
        ;;
    -u)
        exit 0
        ;;
esac
exit 2
SCRIPT
    chmod +x "$bin_path"
}

@test "clean_stale_launch_services_registrations dry-run reports missing apps without unregistering" {
    local lsregister="$TEST_ROOT/bin/lsregister"
    local dump_file="$TEST_ROOT/lsregister.dump"
    local log_file="$TEST_ROOT/lsregister.log"
    local missing_app="$TEST_ROOT/Missing App.app"
    local unrelated_missing_app="$TEST_ROOT/Unrelated Missing.app"
    local existing_app="$TEST_ROOT/Existing.app"
    mkdir -p "$existing_app"
    write_lsregister_stub "$lsregister"

    cat > "$dump_file" <<DUMP
bundle id: 0
    path: $unrelated_missing_app
bundle id: 1
    path: $missing_app
    Bundle node not found on disk

bundle id: 2
    path: $existing_app
    Bundle node not found on disk

bundle id: 3
    path: $TEST_ROOT/Missing.txt
    Bundle node not found on disk
DUMP
    : > "$log_file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" LSREGISTER_BIN="$lsregister" LSREGISTER_DUMP="$dump_file" LSREGISTER_LOG="$log_file" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/launch_services.sh"
get_lsregister_path() { printf '%s\n' "$LSREGISTER_BIN"; }
run_with_timeout() { shift; "$@"; }
note_activity() { printf 'activity\n'; }
DRY_RUN=true
clean_stale_launch_services_registrations
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"LaunchServices stale app registrations"* ]]
    [[ "$output" == *"would unregister 1"* ]]
    [[ "$output" == *"Missing App.app"* ]]
    grep -q 'arg=-dump' "$log_file"
    if grep -q 'arg=-u' "$log_file"; then
        return 1
    fi
}

@test "clean_stale_launch_services_registrations unregisters only targeted missing app records" {
    local lsregister="$TEST_ROOT/bin/lsregister"
    local dump_file="$TEST_ROOT/lsregister.dump"
    local log_file="$TEST_ROOT/lsregister.log"
    local missing_app="$TEST_ROOT/Missing App.app"
    local unrelated_missing_app="$TEST_ROOT/Unrelated Missing.app"
    local existing_app="$TEST_ROOT/Existing.app"
    mkdir -p "$existing_app"
    write_lsregister_stub "$lsregister"

    cat > "$dump_file" <<DUMP
bundle id: 0
    path: $unrelated_missing_app
bundle id: 1
    path: $missing_app
    Bundle node not found on disk

bundle id: 2
    path: $existing_app
    Bundle node not found on disk

bundle id: 3
    path: /System/Applications/Missing.app
    Bundle node not found on disk
DUMP
    : > "$log_file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" LSREGISTER_BIN="$lsregister" LSREGISTER_DUMP="$dump_file" LSREGISTER_LOG="$log_file" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/launch_services.sh"
get_lsregister_path() { printf '%s\n' "$LSREGISTER_BIN"; }
run_with_timeout() { shift; "$@"; }
note_activity() { printf 'activity\n'; }
DRY_RUN=false
MOLE_DRY_RUN=0
clean_stale_launch_services_registrations
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"LaunchServices stale app registrations, 1 removed"* ]]
    grep -q 'arg=-dump' "$log_file"
    grep -q 'argc=2' "$log_file"
    grep -q 'arg=-u' "$log_file"
    grep -q "arg=$missing_app" "$log_file"
    if grep -q "arg=$existing_app" "$log_file"; then
        return 1
    fi
    if grep -q "arg=$unrelated_missing_app" "$log_file"; then
        return 1
    fi
    if grep -q 'arg=-r' "$log_file" || grep -q 'arg=-f' "$log_file"; then
        return 1
    fi
}

@test "launch_services_stale_app_path_is_safe rejects unsafe, live, and malformed paths" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" TEST_ROOT="$TEST_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/launch_services.sh"

fail=0
expect_reject() {
    if launch_services_stale_app_path_is_safe "$1"; then
        printf 'UNEXPECTED_ACCEPT: %q\n' "$1"
        fail=1
    fi
}
expect_accept() {
    if ! launch_services_stale_app_path_is_safe "$1"; then
        printf 'UNEXPECTED_REJECT: %q\n' "$1"
        fail=1
    fi
}

# Genuinely missing, absolute, .app bundle is the only case that may unregister.
expect_accept "$TEST_ROOT/Gone.app"

# A live bundle on disk must never be unregistered.
mkdir -p "$TEST_ROOT/Live.app"
expect_reject "$TEST_ROOT/Live.app"

# Format, protected-root, traversal, and injection rejections.
expect_reject ""
expect_reject "relative/Path.app"
expect_reject "$TEST_ROOT/NotAnApp"
expect_reject "/System/Applications/Gone.app"
expect_reject "/Library/Apple/Gone.app"
expect_reject "$TEST_ROOT/../Gone.app"
expect_reject "$(printf '/tmp/Bad\nName.app')"
expect_reject "$(printf '/tmp/Bad\rName.app')"

exit $fail
EOF

    [ "$status" -eq 0 ]
}

@test "clean_stale_launch_services_registrations ignores dump failures" {
    local lsregister="$TEST_ROOT/bin/lsregister"
    local dump_file="$TEST_ROOT/missing.dump"
    local log_file="$TEST_ROOT/lsregister.log"
    write_lsregister_stub "$lsregister"
    : > "$log_file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" LSREGISTER_BIN="$lsregister" LSREGISTER_DUMP="$dump_file" LSREGISTER_LOG="$log_file" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/launch_services.sh"
get_lsregister_path() { printf '%s\n' "$LSREGISTER_BIN"; }
run_with_timeout() { shift; "$@"; }
note_activity() { printf 'activity\n'; }
DRY_RUN=false
clean_stale_launch_services_registrations
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == "" ]]
    grep -q 'arg=-dump' "$log_file"
}
