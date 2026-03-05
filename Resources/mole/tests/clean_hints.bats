#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-clean-hints-home.XXXXXX")"
    export HOME
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    rm -rf "${HOME:?}"/*
    mkdir -p "$HOME/.config/mole"
}

@test "probe_project_artifact_hints reuses purge targets and excludes noisy names" {
    local root="$HOME/hints-root"
    mkdir -p "$root/proj/node_modules" "$root/proj/vendor" "$root/proj/bin"
    touch "$root/proj/package.json"
    printf '%s\n' "$root" > "$HOME/.config/mole/purge_paths"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOT1'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
run_with_timeout() { shift; "$@"; }
probe_project_artifact_hints
printf 'count=%s\n' "$PROJECT_ARTIFACT_HINT_COUNT"
printf 'examples=%s\n' "${PROJECT_ARTIFACT_HINT_EXAMPLES[*]}"
EOT1

    [ "$status" -eq 0 ]
    [[ "$output" == *"count=1"* ]]
    [[ "$output" == *"node_modules"* ]]
    [[ "$output" != *"vendor"* ]]
    [[ "$output" != *"/bin"* ]]
}

@test "show_project_artifact_hint_notice renders sampled summary" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOT2'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
probe_project_artifact_hints() {
    PROJECT_ARTIFACT_HINT_DETECTED=true
    PROJECT_ARTIFACT_HINT_COUNT=5
    PROJECT_ARTIFACT_HINT_TRUNCATED=true
    PROJECT_ARTIFACT_HINT_EXAMPLES=("~/www/demo/node_modules" "~/www/demo/target")
    PROJECT_ARTIFACT_HINT_ESTIMATED_KB=2048
    PROJECT_ARTIFACT_HINT_ESTIMATE_SAMPLES=2
    PROJECT_ARTIFACT_HINT_ESTIMATE_PARTIAL=false
}
bytes_to_human() { echo "2.00MB"; }
note_activity() { :; }
show_project_artifact_hint_notice
EOT2

    [ "$status" -eq 0 ]
    [[ "$output" == *"5+"* ]]
    [[ "$output" == *"at least 2.00MB sampled from 2 items"* ]]
    [[ "$output" == *"Examples:"* ]]
    [[ "$output" == *"Review: mo purge"* ]]
}

@test "show_system_data_hint_notice reports large clue paths" {
    mkdir -p "$HOME/Library/Developer/Xcode/DerivedData"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOT3'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
run_with_timeout() {
    shift
    if [[ "${1:-}" == "du" ]]; then
        printf '3145728 %s\n' "${4:-/tmp}"
        return 0
    fi
    "$@"
}
bytes_to_human() { echo "3.00GB"; }
note_activity() { :; }
show_system_data_hint_notice
EOT3

    [ "$status" -eq 0 ]
    [[ "$output" == *"Xcode DerivedData: 3.00GB"* ]]
    [[ "$output" == *"~/Library/Developer/Xcode/DerivedData"* ]]
    [[ "$output" == *"Review: mo analyze, Device backups, docker system df"* ]]
}
