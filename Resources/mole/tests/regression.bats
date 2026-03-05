#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME/.config/mole"
}


@test "find with non-existent directory doesn't cause script exit (pipefail bug)" {
    result=$(bash -c '
        set -euo pipefail
        find /non/existent/dir -name "*.cache" 2>/dev/null || true
        echo "survived"
    ')
    [[ "$result" == "survived" ]]
}

@test "browser directory check pattern is safe when directories don't exist" {
    result=$(bash -c '
        set -euo pipefail
        search_dirs=()
        [[ -d "/non/existent/chrome" ]] && search_dirs+=("/non/existent/chrome")
        [[ -d "/tmp" ]] && search_dirs+=("/tmp")

        if [[ ${#search_dirs[@]} -gt 0 ]]; then
            find "${search_dirs[@]}" -maxdepth 1 -type f 2>/dev/null || true
        fi
        echo "survived"
    ')
    [[ "$result" == "survived" ]]
}

@test "empty array doesn't cause unbound variable error" {
    result=$(bash -c '
        set -euo pipefail
        search_dirs=()

        if [[ ${#search_dirs[@]} -gt 0 ]]; then
            echo "should not reach here"
        fi
        echo "survived"
    ')
    [[ "$result" == "survived" ]]
}


@test "version comparison works correctly" {
    result=$(bash -c '
        v1="1.11.8"
        v2="1.11.9"
        if [[ "$(printf "%s\n" "$v1" "$v2" | sort -V | head -1)" == "$v1" && "$v1" != "$v2" ]]; then
            echo "update_needed"
        fi
    ')
    [[ "$result" == "update_needed" ]]
}

@test "version comparison with same versions" {
    result=$(bash -c '
        v1="1.11.8"
        v2="1.11.8"
        if [[ "$(printf "%s\n" "$v1" "$v2" | sort -V | head -1)" == "$v1" && "$v1" != "$v2" ]]; then
            echo "update_needed"
        else
            echo "up_to_date"
        fi
    ')
    [[ "$result" == "up_to_date" ]]
}

@test "version prefix v/V is stripped correctly" {
    result=$(bash -c '
        version="v1.11.9"
        clean=${version#v}
        clean=${clean#V}
        echo "$clean"
    ')
    [[ "$result" == "1.11.9" ]]
}

@test "network timeout prevents hanging (simulated)" {
    if ! command -v gtimeout >/dev/null 2>&1 && ! command -v timeout >/dev/null 2>&1; then
        skip "gtimeout/timeout not available"
    fi

    timeout_cmd="timeout"
    command -v timeout >/dev/null 2>&1 || timeout_cmd="gtimeout"

    # shellcheck disable=SC2016
    result=$($timeout_cmd 5 bash -c '
        result=$(curl -fsSL --connect-timeout 1 --max-time 2 "http://192.0.2.1:12345/test" 2>/dev/null || echo "failed")
        if [[ "$result" == "failed" ]]; then
            echo "timeout_works"
        fi
    ')
    [[ "$result" == "timeout_works" ]]
}

@test "empty version string is handled gracefully" {
    result=$(bash -c '
        latest=""
        if [[ -z "$latest" ]]; then
            echo "handled"
        fi
    ')
    [[ "$result" == "handled" ]]
}


@test "grep with no match doesn't cause exit in pipefail mode" {
    result=$(bash -c '
        set -euo pipefail
        echo "test" | grep "nonexistent" || true
        echo "survived"
    ')
    [[ "$result" == "survived" ]]
}

@test "command substitution failure is handled with || true" {
    result=$(bash -c '
        set -euo pipefail
        output=$(false) || true
        echo "survived"
    ')
    [[ "$result" == "survived" ]]
}

@test "arithmetic on zero doesn't cause exit" {
    result=$(bash -c '
        set -euo pipefail
        count=0
        ((count++)) || true
        echo "$count"
    ')
    [[ "$result" == "1" ]]
}


@test "safe_remove pattern doesn't fail on non-existent path" {
    result=$(bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/common.sh'
        safe_remove '$HOME/non/existent/path' true > /dev/null 2>&1 || true
        echo 'survived'
    ")
    [[ "$result" == "survived" ]]
}

@test "module loading doesn't fail" {
    result=$(bash -c "
        set -euo pipefail
        source '$PROJECT_ROOT/lib/core/common.sh'
        echo 'loaded'
    ")
    [[ "$result" == "loaded" ]]
}
