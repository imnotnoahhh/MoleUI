#!/usr/bin/env bats
# Property-based test: every path in tests/fuzz_corpus/dangerous_paths.txt
# MUST be rejected by validate_path_for_deletion. If even one passes,
# the corpus has caught a real safety regression - investigate, do not
# weaken the corpus.

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME
    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-path-fuzz.XXXXXX")"
    export HOME
    mkdir -p "$HOME"

    CORPUS="$BATS_TEST_DIRNAME/fuzz_corpus/dangerous_paths.txt"
    export CORPUS
}

teardown_file() {
    if [[ "$HOME" == "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
        rm -rf "$HOME"
    fi
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    if [[ "$HOME" != "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
        printf 'FATAL: HOME is not a test temp dir: %s\n' "$HOME" >&2
        return 1
    fi
    # shellcheck source=lib/core/common.sh
    source "$PROJECT_ROOT/lib/core/common.sh"
}

@test "corpus file exists and is non-empty" {
    [ -f "$CORPUS" ]
    [ -s "$CORPUS" ]
}

@test "every dangerous path is rejected by validate_path_for_deletion" {
    [ -f "$CORPUS" ]

    local rejected=0
    local accepted=0
    local -a accepted_paths=()
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        run bash --noprofile --norc -s -- "$line" <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
validate_path_for_deletion "$1"
EOF
        if [[ "$status" -eq 0 ]]; then
            accepted=$((accepted + 1))
            accepted_paths+=("$line")
        else
            rejected=$((rejected + 1))
        fi
    done < "$CORPUS"

    if [[ $accepted -gt 0 ]]; then
        printf 'FAIL: %d dangerous paths were accepted:\n' "$accepted" >&2
        printf '  %s\n' "${accepted_paths[@]}" >&2
    fi
    [ "$accepted" -eq 0 ]
    [ "$rejected" -ge 50 ]
}

@test "generated control-character paths are rejected" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
validate_path_for_deletion $'/Users/me/with\nnewline'
EOF
    [ "$status" -eq 1 ]

    run bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
validate_path_for_deletion $'/Users/me/with\tab'
EOF
    [ "$status" -eq 1 ]
}

@test "corpus has minimum coverage" {
    local active
    active=$(grep -cvE '^\s*(#|$)' "$CORPUS")
    # Lower bound prevents accidental corpus deletion from passing CI.
    [ "$active" -ge 50 ]
}
