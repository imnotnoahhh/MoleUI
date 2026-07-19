#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-ai-cli-caches.XXXXXX")"
    export HOME

    mkdir -p "$HOME"
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
    [[ "$HOME" == "${BATS_TEST_DIRNAME}/tmp-"* ]] || {
        echo "FATAL: HOME is not a test temp dir: $HOME"
        exit 1
    }
    rm -rf "$HOME/.codex" "$HOME/.gemini" "$HOME/.claude" "$HOME/Library/Application Support/Claude"
}

assert_run_success() {
    [ "$status" -eq 0 ] || {
        echo "expected status 0, got $status"
        echo "$output"
        return 1
    }
}

assert_output_contains() {
    local expected="$1"
    [[ "$output" == *"$expected"* ]] || {
        echo "expected output to contain: $expected"
        echo "$output"
        return 1
    }
}

assert_output_not_contains() {
    local unexpected="$1"
    [[ "$output" != *"$unexpected"* ]] || {
        echo "expected output not to contain: $unexpected"
        echo "$output"
        return 1
    }
}

@test "clean_codex_cli skips codex state by default" {
    mkdir -p "$HOME/.codex/cache" "$HOME/.codex/.tmp" "$HOME/.codex/log" "$HOME/.codex/sessions"
    mkdir -p "$HOME/.codex/cache/codex_app_directory"
    touch "$HOME/.codex/cache/c.bin" "$HOME/.codex/cache/session_index.jsonl"
    touch "$HOME/.codex/cache/codex_app_directory/index.json" "$HOME/.codex/.tmp/t.bin" "$HOME/.codex/log/codex-tui.log"
    touch "$HOME/.codex/sessions/s.jsonl" "$HOME/.codex/auth.json" "$HOME/.codex/history.jsonl"
    touch "$HOME/.codex/state_5.sqlite" "$HOME/.codex/logs_2.sqlite" "$HOME/.codex/session_index.jsonl"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
note_activity() { :; }
pgrep() { return 1; }
clean_codex_cli
EOF

    assert_run_success
    assert_output_contains "Codex CLI state · preserved (sessions, credentials)"
    assert_output_not_contains "SAFE_CLEAN:"
    [ -f "$HOME/.codex/cache/session_index.jsonl" ]
    [ -f "$HOME/.codex/cache/codex_app_directory/index.json" ]
    [ -f "$HOME/.codex/.tmp/t.bin" ]
    [ -f "$HOME/.codex/log/codex-tui.log" ]
    [ -f "$HOME/.codex/sessions/s.jsonl" ]
    [ -f "$HOME/.codex/state_5.sqlite" ]
    [ -f "$HOME/.codex/logs_2.sqlite" ]
}

@test "clean_codex_cli is a no-op when ~/.codex is absent" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
note_activity() { :; }
pgrep() { return 1; }
clean_codex_cli
EOF

    assert_run_success
    assert_output_not_contains "SAFE_CLEAN:"
}

@test "clean_codex_cli reports running Codex without cleaning state" {
    mkdir -p "$HOME/.codex/cache" "$HOME/.codex/.tmp" "$HOME/.codex/log"
    touch "$HOME/.codex/cache/c.bin"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
note_activity() { :; }
pgrep() { return 0; }
clean_codex_cli
EOF

    assert_run_success
    assert_output_contains "Codex CLI state · skipped (Codex running)"
    assert_output_not_contains "SAFE_CLEAN:"
}

@test "clean_antigravity_caches cleans antigravity browser caches" {
    ag="$HOME/.gemini/antigravity-browser-profile"
    mkdir -p "$ag/Default/Cache" "$ag/Default/Code Cache" "$ag/Default/GPUCache"
    mkdir -p "$ag/Default/DawnGraphiteCache" "$ag/Default/DawnWebGPUCache"
    mkdir -p "$ag/GraphiteDawnCache" "$ag/component_crx_cache" "$ag/extensions_crx_cache"
    mkdir -p "$ag/Default/Extensions" "$ag/Default/Storage"
    touch "$ag/Default/Cache/a.bin" "$ag/Default/Code Cache/b.bin" "$ag/Default/GPUCache/c.bin"
    touch "$ag/Default/DawnGraphiteCache/d.bin" "$ag/Default/DawnWebGPUCache/e.bin"
    touch "$ag/GraphiteDawnCache/f.bin" "$ag/component_crx_cache/g.bin" "$ag/extensions_crx_cache/h.bin"
    touch "$ag/Default/Extensions/x.js" "$ag/Default/Storage/y.bin"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
clean_service_worker_cache() { echo "SWC:$1"; }
note_activity() { :; }
clean_antigravity_caches
EOF

    assert_run_success
    assert_output_contains "SAFE_CLEAN:Antigravity browser cache|"
    assert_output_contains "SAFE_CLEAN:Antigravity code cache|"
    assert_output_contains "SAFE_CLEAN:Antigravity GPU cache|"
    assert_output_contains "SAFE_CLEAN:Antigravity Dawn cache|"
    assert_output_contains "SAFE_CLEAN:Antigravity WebGPU cache|"
    assert_output_contains "SAFE_CLEAN:Antigravity Graphite cache|"
    assert_output_contains "SAFE_CLEAN:Antigravity component cache|"
    assert_output_contains "SAFE_CLEAN:Antigravity extension cache|"
    assert_output_contains "SWC:Antigravity"
    assert_output_not_contains "Default/Extensions"
    assert_output_not_contains "Default/Storage"
}

@test "clean_antigravity_caches is a no-op when the profile is absent" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
clean_service_worker_cache() { echo "SWC:$1"; }
note_activity() { :; }
clean_antigravity_caches
EOF

    assert_run_success
    assert_output_not_contains "SAFE_CLEAN:Antigravity"
    assert_output_not_contains "SWC:"
}

@test "clean_antigravity_caches never touches gemini tmp chat checkpoints" {
    mkdir -p "$HOME/.gemini/tmp"
    touch "$HOME/.gemini/tmp/work.bin"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
clean_service_worker_cache() { echo "SWC:$1"; }
note_activity() { :; }
clean_antigravity_caches
EOF

    assert_run_success
    assert_output_not_contains "SAFE_CLEAN:"
    assert_output_not_contains "SWC:"
    [[ -f "$HOME/.gemini/tmp/work.bin" ]]
}

@test "clean_antigravity_caches skips browser profile and gemini tmp while running" {
    ag="$HOME/.gemini/antigravity-browser-profile"
    mkdir -p "$ag/Default/Cache" "$HOME/.gemini/tmp"
    touch "$ag/Default/Cache/a.bin" "$HOME/.gemini/tmp/work.bin"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
clean_service_worker_cache() { echo "SWC:$1"; }
note_activity() { echo "NOTE_ACTIVITY"; }
pgrep() {
    [[ "$1" == "-x" && "$2" == "gemini" ]]
}
clean_antigravity_caches
EOF

    assert_run_success
    assert_output_contains "Antigravity/Gemini caches · skipped"
    assert_output_contains "NOTE_ACTIVITY"
    assert_output_not_contains "SAFE_CLEAN:"
    assert_output_not_contains "SWC:"
}

@test "clean_dev_misc invokes Codex and Antigravity cleanup helpers" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
safe_clean() { :; }
safe_find_delete() { :; }
clean_service_worker_cache() { :; }
clean_codex_runtimes() { :; }
clean_codex_desktop_staging() { echo "CODEX_STAGING_CALLED"; }
note_activity() { :; }
clean_codex_cli() { echo "CODEX_CLI_CALLED"; }
clean_antigravity_caches() { echo "ANTIGRAVITY_CALLED"; }
clean_dev_misc
EOF

    assert_run_success
    assert_output_contains "CODEX_CLI_CALLED"
    assert_output_contains "CODEX_STAGING_CALLED"
    assert_output_contains "ANTIGRAVITY_CALLED"
}

@test "clean_dev_ai_agents reaps stale Claude Desktop bundled versions when active version is known" {
    local claude_support="$HOME/Library/Application Support/Claude"
    mkdir -p "$claude_support/claude-code/2.1.140" "$claude_support/claude-code/2.1.142" "$claude_support/claude-code/2.1.150"
    mkdir -p "$claude_support/claude-code-vm/2.1.140" "$claude_support/claude-code-vm/2.1.142" "$claude_support/claude-code-vm/2.1.150"
    echo "2.1.150" > "$claude_support/claude-code-vm/.sdk-version"
    touch -t 202604010000 "$claude_support/claude-code/2.1.140" "$claude_support/claude-code-vm/2.1.140"
    touch -t 202604150000 "$claude_support/claude-code/2.1.142" "$claude_support/claude-code-vm/2.1.142"
    touch -t 202604250000 "$claude_support/claude-code/2.1.150" "$claude_support/claude-code-vm/2.1.150"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
pgrep() { return 1; }
clean_dev_ai_agents
EOF

    assert_run_success
    assert_output_contains "SAFE_CLEAN:Claude Desktop bundled Claude Code old version|$claude_support/claude-code/2.1.140"
    assert_output_contains "SAFE_CLEAN:Claude Desktop bundled Claude Code VM old version|$claude_support/claude-code-vm/2.1.140"
    assert_output_not_contains "$claude_support/claude-code/2.1.142"
    assert_output_not_contains "$claude_support/claude-code-vm/2.1.142"
    assert_output_not_contains "$claude_support/claude-code/2.1.150"
    assert_output_not_contains "$claude_support/claude-code-vm/2.1.150"
}

@test "clean_dev_ai_agents keeps active Claude Desktop bundled version even when it is older" {
    local claude_support="$HOME/Library/Application Support/Claude"
    mkdir -p "$claude_support/claude-code/2.1.140" "$claude_support/claude-code/2.1.142" "$claude_support/claude-code/2.1.150"
    mkdir -p "$claude_support/claude-code-vm/2.1.140" "$claude_support/claude-code-vm/2.1.142" "$claude_support/claude-code-vm/2.1.150"
    echo "2.1.140" > "$claude_support/claude-code-vm/.sdk-version"
    touch -t 202604010000 "$claude_support/claude-code/2.1.140" "$claude_support/claude-code-vm/2.1.140"
    touch -t 202604150000 "$claude_support/claude-code/2.1.142" "$claude_support/claude-code-vm/2.1.142"
    touch -t 202604250000 "$claude_support/claude-code/2.1.150" "$claude_support/claude-code-vm/2.1.150"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
pgrep() { return 1; }
clean_dev_ai_agents
EOF

    assert_run_success
    assert_output_contains "SAFE_CLEAN:Claude Desktop bundled Claude Code old version|$claude_support/claude-code/2.1.142"
    assert_output_contains "SAFE_CLEAN:Claude Desktop bundled Claude Code VM old version|$claude_support/claude-code-vm/2.1.142"
    assert_output_not_contains "$claude_support/claude-code/2.1.140"
    assert_output_not_contains "$claude_support/claude-code-vm/2.1.140"
    assert_output_not_contains "$claude_support/claude-code/2.1.150"
    assert_output_not_contains "$claude_support/claude-code-vm/2.1.150"
}

@test "clean_dev_ai_agents leaves single Claude Desktop bundled version alone" {
    local claude_support="$HOME/Library/Application Support/Claude"
    mkdir -p "$claude_support/claude-code/2.1.150" "$claude_support/claude-code-vm/2.1.150"
    echo "2.1.150" > "$claude_support/claude-code-vm/.sdk-version"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
pgrep() { return 1; }
clean_dev_ai_agents
EOF

    assert_run_success
    assert_output_not_contains "Claude Desktop bundled Claude Code"
    assert_output_not_contains "SAFE_CLEAN:"
}

@test "clean_dev_ai_agents skips Claude Desktop bundled versions when active version is unknown" {
    local claude_support="$HOME/Library/Application Support/Claude"
    mkdir -p "$claude_support/claude-code/2.1.140" "$claude_support/claude-code/2.1.150"
    mkdir -p "$claude_support/claude-code-vm/2.1.140" "$claude_support/claude-code-vm/2.1.150"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
pgrep() { return 1; }
clean_dev_ai_agents
EOF

    assert_run_success
    assert_output_contains "· skipped (active version unknown)"
    assert_output_not_contains "SAFE_CLEAN:"
}

@test "clean_dev_ai_agents skips Claude Desktop bundled versions when sdk version is path-like" {
    local claude_support="$HOME/Library/Application Support/Claude"
    mkdir -p "$claude_support/claude-code/2.1.140" "$claude_support/claude-code/2.1.150"
    mkdir -p "$claude_support/claude-code-vm/2.1.140" "$claude_support/claude-code-vm/2.1.150"
    echo "../2.1.150" > "$claude_support/claude-code-vm/.sdk-version"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
pgrep() { return 1; }
clean_dev_ai_agents
EOF

    assert_run_success
    assert_output_contains "· skipped (active version unknown)"
    assert_output_not_contains "SAFE_CLEAN:"
}

@test "clean_dev_ai_agents skips Claude Desktop cleanup when active version is missing from one bundled root" {
    local claude_support="$HOME/Library/Application Support/Claude"
    mkdir -p "$claude_support/claude-code/2.1.140" "$claude_support/claude-code/2.1.142"
    mkdir -p "$claude_support/claude-code-vm/2.1.140" "$claude_support/claude-code-vm/2.1.142" "$claude_support/claude-code-vm/2.1.150"
    echo "2.1.150" > "$claude_support/claude-code-vm/.sdk-version"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
pgrep() { return 1; }
clean_dev_ai_agents
EOF

    assert_run_success
    assert_output_contains "· skipped (active version unknown)"
    assert_output_not_contains "SAFE_CLEAN:"
}

@test "clean_dev_ai_agents skips Claude Desktop cleanup when only one bundled root can identify active version" {
    local claude_support="$HOME/Library/Application Support/Claude"
    mkdir -p "$claude_support/claude-code/2.1.140" "$claude_support/claude-code/2.1.150"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
pgrep() { return 1; }
clean_dev_ai_agents
EOF

    assert_run_success
    assert_output_contains "· skipped (active version unknown)"
    assert_output_not_contains "SAFE_CLEAN:"
}

@test "clean_dev_ai_agents skips Claude Desktop bundled versions while Claude Desktop is running" {
    local claude_support="$HOME/Library/Application Support/Claude"
    mkdir -p "$claude_support/claude-code/2.1.140" "$claude_support/claude-code/2.1.150"
    mkdir -p "$claude_support/claude-code-vm/2.1.140" "$claude_support/claude-code-vm/2.1.150"
    echo "2.1.150" > "$claude_support/claude-code-vm/.sdk-version"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "SAFE_CLEAN:$2|$1"; }
pgrep() {
    [[ "$1" == "-x" && "$2" == "Claude" ]]
}
clean_dev_ai_agents
EOF

    assert_run_success
    assert_output_contains "Claude Desktop bundled Claude Code · skipped (Claude Desktop running)"
    assert_output_not_contains "SAFE_CLEAN:"
}
