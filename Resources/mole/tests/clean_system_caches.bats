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
    mkdir -p "$HOME/Projects/test-app/.next/cache"
    mkdir -p "$HOME/Projects/python-app/__pycache__"

    touch "$HOME/Projects/test-app/package.json"
    touch "$HOME/Projects/python-app/pyproject.toml"
    touch "$HOME/Projects/test-app/.next/cache/test.cache"
    touch "$HOME/Projects/python-app/__pycache__/module.pyc"

    run bash -c "
        export DRY_RUN=true
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/clean/caches.sh'
        clean_project_caches
    "
    [ "$status" -eq 0 ]

    rm -rf "$HOME/Projects"
}

@test "clean_project_caches scans configured roots instead of HOME" {
    mkdir -p "$HOME/.config/mole"
    mkdir -p "$HOME/CustomProjects/app/.next/cache"
    touch "$HOME/CustomProjects/app/package.json"

    local fake_bin
    fake_bin="$(mktemp -d "$HOME/find-bin.XXXXXX")"
    local find_log="$HOME/find.log"

    cat > "$fake_bin/find" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$find_log"
root=""
prev=""
for arg in "\$@"; do
    if [[ "\$prev" == "-P" ]]; then
        root="\$arg"
        break
    fi
    prev="\$arg"
done
if [[ "\$root" == "$HOME/CustomProjects" ]]; then
    printf '%s\n' "$HOME/CustomProjects/app/.next"
fi
EOF
    chmod +x "$fake_bin/find"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$fake_bin:$PATH" bash --noprofile --norc <<'EOF'
set -euo pipefail
printf '%s\n' "$HOME/CustomProjects" > "$HOME/.config/mole/purge_paths"
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/caches.sh"
run_with_timeout() { shift; "$@"; }
safe_clean() { echo "$2|$1"; }
clean_project_caches
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"Next.js build cache"* ]]
    grep -q -- "-P $HOME/CustomProjects " "$find_log"
    run grep -q -- "-P $HOME " "$find_log"
    [ "$status" -eq 1 ]

    rm -rf "$HOME/CustomProjects" "$HOME/.config/mole" "$fake_bin" "$find_log"
}

@test "clean_project_caches auto-detects top-level project containers" {
    mkdir -p "$HOME/go/src/demo/.next/cache"
    touch "$HOME/go/src/demo/go.mod"
    touch "$HOME/go/src/demo/.next/cache/test.cache"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/caches.sh"
safe_clean() { echo "$2|$1"; }
clean_project_caches
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"Next.js build cache|$HOME/go/src/demo/.next/cache/test.cache"* ]]

    rm -rf "$HOME/go"
}

@test "clean_project_caches auto-detects nested GOPATH-style project containers" {
    mkdir -p "$HOME/go/src/github.com/example/demo/.next/cache"
    touch "$HOME/go/src/github.com/example/demo/go.mod"
    touch "$HOME/go/src/github.com/example/demo/.next/cache/test.cache"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/caches.sh"
safe_clean() { echo "$2|$1"; }
clean_project_caches
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"Next.js build cache|$HOME/go/src/github.com/example/demo/.next/cache/test.cache"* ]]

    rm -rf "$HOME/go"
}

@test "clean_project_caches skips stalled root scans" {
    mkdir -p "$HOME/.config/mole"
    mkdir -p "$HOME/SlowProjects/app"
    printf '%s\n' "$HOME/SlowProjects" > "$HOME/.config/mole/purge_paths"

    local fake_bin
    fake_bin="$(mktemp -d "$HOME/find-timeout.XXXXXX")"

    cat > "$fake_bin/find" <<EOF
#!/bin/bash
root=""
prev=""
for arg in "\$@"; do
    if [[ "\$prev" == "-P" ]]; then
        root="\$arg"
        break
    fi
    prev="\$arg"
done
if [[ "\$root" == "$HOME/SlowProjects" ]]; then
    trap "" TERM
    sleep 30
    exit 0
fi
exit 0
EOF
    chmod +x "$fake_bin/find"

    run /usr/bin/perl -e 'alarm 8; exec @ARGV' env -i HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$fake_bin:$PATH:/usr/bin:/bin:/usr/sbin:/sbin" TERM="${TERM:-xterm-256color}" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/caches.sh"
MO_TIMEOUT_BIN=""
MO_TIMEOUT_PERL_BIN="${MO_TIMEOUT_PERL_BIN:-$(command -v perl)}"
export MOLE_PROJECT_CACHE_DISCOVERY_TIMEOUT=0.5
export MOLE_PROJECT_CACHE_SCAN_TIMEOUT=0.5
SECONDS=0
clean_project_caches
echo "ELAPSED=$SECONDS"
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"ELAPSED="* ]]
    elapsed=$(printf '%s\n' "$output" | awk -F= '/ELAPSED=/{print $2}' | tail -1)
    [[ "$elapsed" =~ ^[0-9]+$ ]]
    (( elapsed < 5 ))

    rm -rf "$HOME/.config/mole" "$HOME/SlowProjects" "$fake_bin"
}

@test "clean_project_caches excludes Library and Trash directories" {
    mkdir -p "$HOME/Library/.next/cache"
    mkdir -p "$HOME/.Trash/.next/cache"
    mkdir -p "$HOME/Projects/app/.next/cache"
    touch "$HOME/Projects/app/package.json"

    run bash -c "
        export DRY_RUN=true
        source '$PROJECT_ROOT/lib/core/common.sh'
        source '$PROJECT_ROOT/lib/clean/caches.sh'
        clean_project_caches
    "
    [ "$status" -eq 0 ]

    rm -rf "$HOME/Projects"
}
