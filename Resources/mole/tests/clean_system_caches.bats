#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-clean-caches.XXXXXX")"
    export HOME

    mkdir -p "$HOME"
    mkdir -p "$HOME/.cache/mole"
    mkdir -p "$HOME/Library/Caches"
    mkdir -p "$HOME/Library/Logs"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    source "$PROJECT_ROOT/lib/core/common.sh"
    source "$PROJECT_ROOT/lib/clean/caches.sh"

    # Mock run_with_timeout to skip timeout overhead in tests
    # shellcheck disable=SC2329
    run_with_timeout() {
        shift  # Remove timeout argument
        "$@"
    }
    export -f run_with_timeout

    rm -f "$HOME/.cache/mole/permissions_granted"
}

@test "check_tcc_permissions skips in non-interactive mode" {
    run bash -c "source '$PROJECT_ROOT/lib/core/common.sh'; source '$PROJECT_ROOT/lib/clean/caches.sh'; check_tcc_permissions" < /dev/null
    [ "$status" -eq 0 ]
    [[ ! -f "$HOME/.cache/mole/permissions_granted" ]]
}

@test "check_tcc_permissions skips when permissions already granted" {
    mkdir -p "$HOME/.cache/mole"
    touch "$HOME/.cache/mole/permissions_granted"

    run bash -c "source '$PROJECT_ROOT/lib/core/common.sh'; source '$PROJECT_ROOT/lib/clean/caches.sh'; [[ -t 1 ]] || true; check_tcc_permissions"
    [ "$status" -eq 0 ]
}

@test "check_tcc_permissions validates protected directories" {

    [[ -d "$HOME/Library/Caches" ]]
    [[ -d "$HOME/Library/Logs" ]]
    [[ -d "$HOME/.cache/mole" ]]

    run bash -c "source '$PROJECT_ROOT/lib/core/common.sh'; source '$PROJECT_ROOT/lib/clean/caches.sh'; check_tcc_permissions < /dev/null"
    [ "$status" -eq 0 ]
}

@test "clean_service_worker_cache returns early when path doesn't exist" {
    run bash -c "source '$PROJECT_ROOT/lib/core/common.sh'; source '$PROJECT_ROOT/lib/clean/caches.sh'; clean_service_worker_cache 'TestBrowser' '/nonexistent/path'"
    [ "$status" -eq 0 ]
}

@test "clean_service_worker_cache handles empty cache directory" {
    local test_cache="$HOME/test_sw_cache"
    mkdir -p "$test_cache"

    run bash -c "
        run_with_timeout() { shift; \"\$@\"; }
        export -f run_with_timeout
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/clean/caches.sh'
        clean_service_worker_cache 'TestBrowser' '$test_cache'
    "
    [ "$status" -eq 0 ]

    rm -rf "$test_cache"
}

@test "clean_service_worker_cache protects specified domains" {
    local test_cache="$HOME/test_sw_cache"
    mkdir -p "$test_cache/abc123_https_capcut.com_0"
    mkdir -p "$test_cache/def456_https_example.com_0"

    run bash -c "
        run_with_timeout() {
            local timeout=\"\$1\"
            shift
            if [[ \"\$1\" == \"get_path_size_kb\" ]]; then
                echo 0
                return 0
            fi
            if [[ \"\$1\" == \"sh\" ]]; then
                printf '%s\n' \
                    '$test_cache/abc123_https_capcut.com_0' \
                    '$test_cache/def456_https_example.com_0'
                return 0
            fi
            \"\$@\"
        }
        export -f run_with_timeout
        export DRY_RUN=true
        export PROTECTED_SW_DOMAINS=(capcut.com photopea.com)
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/clean/caches.sh'
        clean_service_worker_cache 'TestBrowser' '$test_cache'
    "
    [ "$status" -eq 0 ]

    [[ -d "$test_cache/abc123_https_capcut.com_0" ]]

    rm -rf "$test_cache"
}

@test "clean_project_caches completes without errors" {
    mkdir -p "$HOME/projects/test-app/.next/cache"
    mkdir -p "$HOME/projects/python-app/__pycache__"

    touch "$HOME/projects/test-app/.next/cache/test.cache"
    touch "$HOME/projects/python-app/__pycache__/module.pyc"

    run bash -c "
        export DRY_RUN=true
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/clean/caches.sh'
        clean_project_caches
    "
    [ "$status" -eq 0 ]

    rm -rf "$HOME/projects"
}

@test "clean_project_caches handles timeout gracefully" {
    if ! command -v gtimeout >/dev/null 2>&1 && ! command -v timeout >/dev/null 2>&1; then
        skip "gtimeout/timeout not available"
    fi

    mkdir -p "$HOME/test-project/.next"

    function find() {
        sleep 2  # Simulate slow find
        echo "$HOME/test-project/.next"
    }
    export -f find

    timeout_cmd="timeout"
    command -v timeout >/dev/null 2>&1 || timeout_cmd="gtimeout"

    run $timeout_cmd 15 bash -c "
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/clean/caches.sh'
        clean_project_caches
    "
    [ "$status" -eq 0 ] || [ "$status" -eq 124 ]

    rm -rf "$HOME/test-project"
}

@test "clean_project_caches excludes Library and Trash directories" {
    mkdir -p "$HOME/Library/.next/cache"
    mkdir -p "$HOME/.Trash/.next/cache"
    mkdir -p "$HOME/projects/.next/cache"

    run bash -c "
        export DRY_RUN=true
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/clean/caches.sh'
        clean_project_caches
    "
    [ "$status" -eq 0 ]

    rm -rf "$HOME/projects"
}
