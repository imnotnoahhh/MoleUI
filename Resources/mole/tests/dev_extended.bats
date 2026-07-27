#!/usr/bin/env bats

setup_file() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT

	ORIGINAL_HOME="${HOME:-}"
	export ORIGINAL_HOME

	HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-dev-extended.XXXXXX")"
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

@test "clean_dev_elixir cleans hex cache" {
	mkdir -p "$HOME/.mix" "$HOME/.hex"
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
safe_clean() { echo "$2"; }
clean_dev_elixir
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"Hex cache"* ]]
}

@test "clean_dev_elixir does not clean mix archives" {
	mkdir -p "$HOME/.mix/archives"
	touch "$HOME/.mix/archives/test_tool.ez"

	# Source and run the function
	source "$PROJECT_ROOT/lib/core/common.sh"
	source "$PROJECT_ROOT/lib/clean/dev.sh"
	# shellcheck disable=SC2329
	safe_clean() { :; }
	clean_dev_elixir >/dev/null 2>&1 || true

	# Verify the file still exists
	[ -f "$HOME/.mix/archives/test_tool.ez" ]
}

@test "clean_dev_haskell cleans cabal install cache" {
	mkdir -p "$HOME/.cabal" "$HOME/.stack"
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
safe_clean() { echo "$2"; }
clean_dev_haskell
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"Cabal install cache"* ]]
}

@test "clean_dev_haskell does not clean stack programs" {
	mkdir -p "$HOME/.stack/programs/x86_64-osx"
	touch "$HOME/.stack/programs/x86_64-osx/ghc-9.2.8.tar.xz"

	# Source and run the function
	source "$PROJECT_ROOT/lib/core/common.sh"
	source "$PROJECT_ROOT/lib/clean/dev.sh"
	# shellcheck disable=SC2329
	safe_clean() { :; }
	clean_dev_haskell >/dev/null 2>&1 || true

	# Verify the file still exists
	[ -f "$HOME/.stack/programs/x86_64-osx/ghc-9.2.8.tar.xz" ]
}

@test "clean_dev_ocaml cleans opam cache" {
	mkdir -p "$HOME/.opam"
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
safe_clean() { echo "$2"; }
clean_dev_ocaml
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"Opam cache"* ]]
}

@test "check_android_ndk reports multiple NDK versions" {
	run /bin/bash -c 'HOME=$(mktemp -d) && mkdir -p "$HOME/Library/Android/sdk/ndk"/{21.0.1,22.0.0,20.0.0} && source "$0" && note_activity() { :; } && NC="" && GREEN="" && GRAY="" && YELLOW="" && ICON_SUCCESS="✓" && check_android_ndk' "$PROJECT_ROOT/lib/clean/dev.sh"

	[ "$status" -eq 0 ]
	[[ "$output" == *"Android NDK versions · 3 found"* ]]
}

@test "check_android_ndk silent when only one NDK" {
	run /bin/bash -c 'HOME=$(mktemp -d) && mkdir -p "$HOME/Library/Android/sdk/ndk/22.0.0" && source "$0" && note_activity() { :; } && NC="" && GREEN="" && GRAY="" && YELLOW="" && ICON_SUCCESS="✓" && check_android_ndk' "$PROJECT_ROOT/lib/clean/dev.sh"

	[ "$status" -eq 0 ]
	[[ "$output" != *"NDK versions"* ]]
}

@test "clean_xcode_device_support handles empty directories under nounset" {
	local ds_dir="$HOME/EmptyDeviceSupport"
	mkdir -p "$ds_dir"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { :; }
clean_xcode_device_support "$HOME/EmptyDeviceSupport" "iOS DeviceSupport"
echo "survived"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"survived"* ]]
}

@test "clean_xcode_documentation_cache keeps newest DeveloperDocumentation index" {
	local doc_root="$HOME/DocumentationCache"
	mkdir -p "$doc_root"
	touch "$doc_root/DeveloperDocumentation.index"
	touch "$doc_root/DeveloperDocumentation-16.0.index"
	touch -t 202402010000 "$doc_root/DeveloperDocumentation.index"
	touch -t 202401010000 "$doc_root/DeveloperDocumentation-16.0.index"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_XCODE_DOCUMENTATION_CACHE_DIR="$doc_root" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
# Without this the real pgrep runs against the host, so the result depends on
# whether the developer happens to have Xcode open. The sibling case mocks the
# running side; this one has to mock the not-running side.
pgrep() { return 1; }
has_sudo_session() { return 0; }
is_path_whitelisted() { return 1; }
should_protect_path() { return 1; }
safe_sudo_remove() {
    local target="$1"
    echo "CLEAN:$target:Xcode documentation cache (old indexes)"
}
clean_xcode_documentation_cache
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"CLEAN:$doc_root/DeveloperDocumentation-16.0.index:Xcode documentation cache (old indexes)"* ]] || return 1
	[[ "$output" != *"CLEAN:$doc_root/DeveloperDocumentation.index:Xcode documentation cache (old indexes)"* ]]
}

@test "clean_xcode_documentation_cache skips when Xcode is running" {
	local doc_root="$HOME/DocumentationCache"
	mkdir -p "$doc_root"
	touch "$doc_root/DeveloperDocumentation.index"
	touch "$doc_root/DeveloperDocumentation-16.0.index"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_XCODE_DOCUMENTATION_CACHE_DIR="$doc_root" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
pgrep() { return 0; }
safe_sudo_remove() { echo "UNEXPECTED_SAFE_SUDO_REMOVE"; }
clean_xcode_documentation_cache
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"Xcode documentation cache · skipped (Xcode running)"* ]] || return 1
	[[ "$output" != *"UNEXPECTED_SAFE_SUDO_REMOVE"* ]]
}

@test "clean_xcode_system_coresimulator_caches removes only direct cache children" {
	local cache_root="$HOME/SystemCoreSimulatorCaches"
	mkdir -p "$cache_root/dyld/runtime" "$cache_root/metadata"
	touch "$cache_root/dyld/runtime/cache" "$cache_root/metadata/index"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_XCODE_SYSTEM_CORESIMULATOR_CACHE_DIR="$cache_root" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
pgrep() { return 1; }
has_sudo_session() { return 0; }
is_path_whitelisted() { return 1; }
should_protect_path() { return 1; }
safe_sudo_remove() { echo "REMOVE:$1"; }
clean_xcode_system_coresimulator_caches
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"REMOVE:$cache_root/dyld"* ]] || return 1
	[[ "$output" == *"REMOVE:$cache_root/metadata"* ]] || return 1
	[[ "$output"$'\n' != *"REMOVE:$cache_root"$'\n'* ]]
}

@test "clean_xcode_system_coresimulator_caches skips while CoreSimulator is active" {
	local cache_root="$HOME/SystemCoreSimulatorCaches"
	mkdir -p "$cache_root/dyld"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_XCODE_SYSTEM_CORESIMULATOR_CACHE_DIR="$cache_root" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
pgrep() { return 0; }
safe_sudo_remove() { echo "UNEXPECTED_SAFE_SUDO_REMOVE"; }
clean_xcode_system_coresimulator_caches
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"Xcode Simulator system cache · skipped (CoreSimulator running)"* ]] || return 1
	[[ "$output" != *"UNEXPECTED_SAFE_SUDO_REMOVE"* ]]
}

@test "clean_xcode_xctest_devices targets only exact XCTestDevices directory" {
	local developer_root="$HOME/Library/Developer"
	mkdir -p "$developer_root/XCTestDevices" "$developer_root/XCTestDevices-old"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
pgrep() { return 1; }
safe_clean() { printf 'SAFE:%s|%s\n' "$1" "$2"; }
clean_xcode_xctest_devices
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"SAFE:$developer_root/XCTestDevices|Xcode XCTestDevices test data"* ]] || return 1
	[[ "$output" != *"XCTestDevices-old"* ]]
}

@test "clean_xcode_xctest_devices skips while XCTest process is active" {
	local xctest_root="$HOME/Library/Developer/XCTestDevices"
	mkdir -p "$xctest_root"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
pgrep() {
    [[ "$*" == *"xcodebuild"* ]]
}
safe_clean() { echo "UNEXPECTED_SAFE_CLEAN"; }
clean_xcode_xctest_devices
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"Xcode or XCTest running"* ]] || return 1
	[[ "$output" != *"UNEXPECTED_SAFE_CLEAN"* ]]
}

@test "clean_xcode_xctest_devices dry-run keeps XCTestDevices directory" {
	local xctest_root="$HOME/Library/Developer/XCTestDevices"
	mkdir -p "$xctest_root"
	touch "$xctest_root/test-device"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/bin/clean.sh"
DRY_RUN=true
MOLE_DRY_RUN=1
pgrep() { return 1; }
clean_xcode_xctest_devices
[[ -d "$HOME/Library/Developer/XCTestDevices" ]] && echo "STILL_EXISTS"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"Xcode XCTestDevices test data"* ]] || return 1
	[[ "$output" == *"dry"* ]] || return 1
	[[ "$output" == *"STILL_EXISTS"* ]]
}

@test "clean_xcode_xctest_devices respects whitelist" {
	local xctest_root="$HOME/Library/Developer/XCTestDevices"
	mkdir -p "$xctest_root"
	touch "$xctest_root/test-device"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/bin/clean.sh"
WHITELIST_PATTERNS=("$HOME/Library/Developer/XCTestDevices")
pgrep() { return 1; }
clean_xcode_xctest_devices
[[ -d "$HOME/Library/Developer/XCTestDevices" ]] && echo "STILL_EXISTS"
printf 'WHITELIST_SKIPPED:%s\n' "$whitelist_skipped_count"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"STILL_EXISTS"* ]] || return 1
	[[ "$output" == *"WHITELIST_SKIPPED:1"* ]]
}

@test "check_rust_toolchains reports multiple toolchains" {
	run /bin/bash -c 'HOME=$(mktemp -d) && mkdir -p "$HOME/.rustup/toolchains"/{stable,nightly,1.75.0}-aarch64-apple-darwin && source "$0" && note_activity() { :; } && NC="" && GREEN="" && GRAY="" && YELLOW="" && ICON_SUCCESS="✓" && rustup() { :; } && export -f rustup && check_rust_toolchains' "$PROJECT_ROOT/lib/clean/dev.sh"

	[ "$status" -eq 0 ]
	[[ "$output" == *"Rust toolchains · 3 found"* ]]
}

@test "check_rust_toolchains silent when only one toolchain" {
	run /bin/bash -c 'HOME=$(mktemp -d) && mkdir -p "$HOME/.rustup/toolchains/stable-aarch64-apple-darwin" && source "$0" && note_activity() { :; } && NC="" && GREEN="" && GRAY="" && YELLOW="" && ICON_SUCCESS="✓" && rustup() { :; } && export -f rustup && check_rust_toolchains' "$PROJECT_ROOT/lib/clean/dev.sh"

	[ "$status" -eq 0 ]
	[[ "$output" != *"Rust toolchains"* ]]
}

@test "clean_dev_jetbrains_toolbox cleans old versions and bypasses toolbox whitelist" {
	local toolbox_channel="$HOME/Library/Application Support/JetBrains/Toolbox/apps/IDEA/ch-0"
	mkdir -p "$toolbox_channel/241.1" "$toolbox_channel/241.2" "$toolbox_channel/241.3"
	ln -s "241.3" "$toolbox_channel/current"
	touch -t 202401010000 "$toolbox_channel/241.1"
	touch -t 202402010000 "$toolbox_channel/241.2"
	touch -t 202403010000 "$toolbox_channel/241.3"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
toolbox_root="$HOME/Library/Application Support/JetBrains/Toolbox/apps"
WHITELIST_PATTERNS=("$toolbox_root"* "$HOME/Library/Application Support/JetBrains*")
note_activity() { :; }
safe_clean() {
    local target="$1"
    for pattern in "${WHITELIST_PATTERNS[@]+${WHITELIST_PATTERNS[@]}}"; do
        if [[ "$pattern" == "$toolbox_root"* ]]; then
            echo "WHITELIST_NOT_REMOVED"
            exit 1
        fi
    done
    echo "$target"
}
MOLE_JETBRAINS_TOOLBOX_KEEP=1
clean_dev_jetbrains_toolbox
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"/241.1"* ]] || return 1
	[[ "$output" != *"/241.2"* ]]
}

@test "clean_dev_jetbrains_toolbox keeps current directory and removes older versions" {
	local toolbox_channel="$HOME/Library/Application Support/JetBrains/Toolbox/apps/IDEA/ch-0"
	mkdir -p "$toolbox_channel/241.1" "$toolbox_channel/241.2" "$toolbox_channel/current"
	touch -t 202401010000 "$toolbox_channel/241.1"
	touch -t 202402010000 "$toolbox_channel/241.2"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "$1"; }
MOLE_JETBRAINS_TOOLBOX_KEEP=1
clean_dev_jetbrains_toolbox
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"/241.1"* ]] || return 1
	[[ "$output" != *"/241.2"* ]]
}

@test "clean_dev_ai_agents keeps newest version and removes older ones by mtime" {
	local claude_root="$HOME/.local/share/claude/versions"
	local cursor_root="$HOME/.local/share/cursor-agent/versions"
	local copilot_root="$HOME/.copilot/pkg/universal"
	mkdir -p "$claude_root" "$cursor_root" "$copilot_root"
	touch -t 202604170829 "$claude_root/2.1.112"
	touch -t 202604180902 "$claude_root/2.1.113"
	touch -t 202604181002 "$claude_root/2.1.114"
	mkdir -p "$cursor_root/2026.04.08-old" "$cursor_root/2026.04.15-new"
	touch -t 202604080000 "$cursor_root/2026.04.08-old"
	touch -t 202604150000 "$cursor_root/2026.04.15-new"
	mkdir -p "$copilot_root/1.0.5" "$copilot_root/1.0.32" "$copilot_root/1.0.34"
	touch -t 202604010000 "$copilot_root/1.0.5"
	touch -t 202604200000 "$copilot_root/1.0.32"
	touch -t 202604250000 "$copilot_root/1.0.34"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "$1|$2"; }
clean_dev_ai_agents
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"/2.1.112|Claude Code old version"* ]] || return 1
	[[ "$output" == *"/2.1.113|Claude Code old version"* ]] || return 1
	[[ "$output" != *"/2.1.114|"* ]] || return 1
	[[ "$output" == *"/2026.04.08-old|Cursor Agent old version"* ]] || return 1
	[[ "$output" != *"/2026.04.15-new|"* ]] || return 1
	[[ "$output" == *"/1.0.5|GitHub Copilot CLI old version"* ]] || return 1
	[[ "$output" == *"/1.0.32|GitHub Copilot CLI old version"* ]] || return 1
	[[ "$output" != *"/1.0.34|"* ]]
}

@test "clean_dev_ai_agents protects the active version pointed at by ~/.local/bin/<agent>" {
	local claude_root="$HOME/.local/share/claude/versions"
	local cursor_root="$HOME/.local/share/cursor-agent/versions"
	local bin_dir="$HOME/.local/bin"
	rm -rf "$claude_root" "$cursor_root" "$bin_dir"
	mkdir -p "$claude_root" "$cursor_root" "$bin_dir"

	mkdir -p "$claude_root/2.1.112" "$claude_root/2.1.113" "$claude_root/2.1.114"
	touch -t 202604170000 "$claude_root/2.1.112"
	touch -t 202604180000 "$claude_root/2.1.113"
	touch -t 202604200000 "$claude_root/2.1.114"
	ln -s "$claude_root/2.1.113" "$bin_dir/claude"

	mkdir -p "$cursor_root/2026.04.01-old" "$cursor_root/2026.04.10-active" "$cursor_root/2026.04.20-newest"
	touch -t 202604010000 "$cursor_root/2026.04.01-old"
	touch -t 202604100000 "$cursor_root/2026.04.10-active"
	touch -t 202604200000 "$cursor_root/2026.04.20-newest"
	: >"$cursor_root/2026.04.10-active/cursor-agent"
	ln -s "$cursor_root/2026.04.10-active/cursor-agent" "$bin_dir/cursor-agent"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "$1|$2"; }
clean_dev_ai_agents
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"/2.1.112|Claude Code old version"* ]] || return 1
	[[ "$output" != *"/2.1.113|"* ]] || return 1
	[[ "$output" != *"/2.1.114|"* ]] || return 1
	[[ "$output" == *"/2026.04.01-old|Cursor Agent old version"* ]] || return 1
	[[ "$output" != *"/2026.04.10-active|"* ]] || return 1
	[[ "$output" != *"/2026.04.20-newest|"* ]]
}

@test "clean_dev_ai_agents skips cleanup entirely when the active symlink is broken" {
	local claude_root="$HOME/.local/share/claude/versions"
	local bin_dir="$HOME/.local/bin"
	rm -rf "$claude_root" "$bin_dir"
	mkdir -p "$claude_root" "$bin_dir"

	mkdir -p "$claude_root/2.1.112" "$claude_root/2.1.113" "$claude_root/2.1.114"
	touch -t 202604170000 "$claude_root/2.1.112"
	touch -t 202604180000 "$claude_root/2.1.113"
	touch -t 202604200000 "$claude_root/2.1.114"
	ln -s "$claude_root/2.1.999-missing" "$bin_dir/claude"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "$1|$2"; }
clean_dev_ai_agents
EOF

	[ "$status" -eq 0 ]
	[[ "$output" != *"|Claude Code old version"* ]] || return 1
	[[ "$output" == *"Claude Code old version · skipped (active symlink broken)"* ]] || return 1

	rm -f "$bin_dir/claude"
}

@test "clean_dev_ai_agents respects MOLE_AI_AGENTS_KEEP and skips missing roots" {
	local claude_root="$HOME/.local/share/claude/versions"
	# Earlier cases in this file seed versions under the shared HOME; without a
	# reset this sees five versions instead of three and KEEP=2 sweeps 2.1.101 too.
	rm -rf "$claude_root"
	mkdir -p "$claude_root"
	touch -t 202604170000 "$claude_root/2.1.100"
	touch -t 202604180000 "$claude_root/2.1.101"
	touch -t 202604190000 "$claude_root/2.1.102"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "$1"; }
MOLE_AI_AGENTS_KEEP=2 clean_dev_ai_agents
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"/2.1.100"* ]] || return 1
	[[ "$output" != *"/2.1.101"* ]] || return 1
	[[ "$output" != *"/2.1.102"* ]]
}

@test "clean_dev_jetbrains_logs only targets JetBrains logs" {
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
safe_clean() { printf '%s|%s\n' "$1" "$2"; }
clean_dev_jetbrains_logs
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"$HOME/Library/Logs/JetBrains/*|JetBrains IDE logs"* ]] || return 1
	[[ "$output" != *"Library/Caches/JetBrains"* ]]
}

@test "clean_developer_tools includes JetBrains logs but not JetBrains cache sweep" {
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
stop_section_spinner() { :; }
note_activity() { :; }
safe_clean() { printf '%s|%s\n' "$1" "$2"; }
clean_tool_cache() { :; }
check_rust_toolchains() { :; }
clean_dev_npm() { :; }
clean_dev_python() { :; }
clean_dev_go() { :; }
clean_dev_mise() { :; }
clean_dev_rust() { :; }
clean_dev_docker() { :; }
clean_dev_cloud() { :; }
clean_dev_nix() { :; }
clean_dev_shell() { :; }
clean_dev_frontend() { :; }
clean_project_caches() { :; }
clean_dev_mobile() { :; }
clean_dev_jvm() { :; }
clean_dev_jetbrains_toolbox() { :; }
clean_dev_ai_agents() { :; }
clean_dev_other_langs() { :; }
clean_dev_cicd() { :; }
clean_dev_database() { :; }
clean_dev_api_tools() { :; }
clean_dev_network() { :; }
clean_dev_misc() { :; }
clean_dev_elixir() { :; }
clean_dev_haskell() { :; }
clean_dev_ocaml() { :; }
clean_xcode_tools() { :; }
clean_code_editors() { :; }
clean_homebrew() { :; }
clean_developer_tools
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"$HOME/Library/Logs/JetBrains/*|JetBrains IDE logs"* ]] || return 1
	[[ "$output" != *"Library/Caches/JetBrains"* ]] || return 1
	[[ "$output" == *"$HOME/Library/Caches/Homebrew/downloads/*|Homebrew cache"* ]] || return 1
	[[ "$output" != *"$HOME/Library/Caches/Homebrew/*|Homebrew cache"* ]] || return 1
	[[ "$output" != *"Library/Caches/Homebrew/api"* ]] || return 1
	[[ "$output" != *"Library/Caches/Homebrew/bootsnap"* ]]
}

@test "clean_dev_misc does not touch Claude Code state" {
	mkdir -p "$HOME/.claude/projects/project-a/memory"
	mkdir -p "$HOME/.claude/plugins/cache/plugin-a"
	mkdir -p "$HOME/.claude/plugins/marketplaces"
	mkdir -p "$HOME/.claude/paste-cache"
	mkdir -p "$HOME/.claude/tmp"
	mkdir -p "$HOME/.claude/session-env"
	mkdir -p "$HOME/.claude/shell-snapshots"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
safe_clean() { printf 'SAFE:%s|%s\n' "$1" "$2"; }
safe_find_delete() { printf 'FIND:%s|%s|%s|%s\n' "$1" "$2" "$3" "$4"; }
clean_service_worker_cache() { :; }
clean_dev_misc
EOF

	[ "$status" -eq 0 ]
	[[ "$output" != *"$HOME/.claude/projects"* ]] || return 1
	[[ "$output" != *"$HOME/.claude/plugins/cache"* ]] || return 1
	[[ "$output" != *"$HOME/.claude/plugins/marketplaces"* ]] || return 1
	[[ "$output" != *"$HOME/.claude/paste-cache"* ]] || return 1
	[[ "$output" != *"$HOME/.claude/tmp"* ]] || return 1
	[[ "$output" != *"$HOME/.claude/session-env"* ]] || return 1
	[[ "$output" != *"$HOME/.claude/shell-snapshots"* ]]
}

@test "clean_xcode_simulator_runtime_volumes shows scan progress and skips sizing in-use volumes" {
	local volumes_root="$HOME/sim-volumes"
	local cryptex_root="$HOME/sim-cryptex"
	mkdir -p "$volumes_root/in-use-runtime" "$volumes_root/unused-runtime"
	mkdir -p "$cryptex_root"

	# The "scanning N entries" line is deliberately gated behind MO_DEBUG (the
	# spinner carries the feedback otherwise), so this case has to ask for it.
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MO_DEBUG=1 MOLE_XCODE_SIM_RUNTIME_VOLUMES_ROOT="$volumes_root" MOLE_XCODE_SIM_RUNTIME_CRYPTEX_ROOT="$cryptex_root" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"

size_log="$HOME/size-calls.log"
: > "$size_log"
DRY_RUN=false

note_activity() { :; }
has_sudo_session() { return 0; }
is_path_whitelisted() { return 1; }
should_protect_path() { return 1; }
_sim_runtime_mount_points() {
    printf '%s\n' "$MOLE_XCODE_SIM_RUNTIME_VOLUMES_ROOT/in-use-runtime"
}
_sim_runtime_size_kb() {
    local target_path="$1"
    echo "$target_path" >> "$size_log"
    echo "1"
}
safe_sudo_remove() {
    local target_path="$1"
    echo "REMOVE:$target_path"
    return 0
}

clean_xcode_simulator_runtime_volumes
echo "SIZE_LOG_START"
cat "$size_log"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"Xcode runtime volumes · scanning 2 entries"* ]] || return 1
	# 16a8bcaf consolidated the per-stage "cleaning N unused" line into one final
	# result message; assert the line that survived.
	[[ "$output" == *"Xcode runtime volumes · removed 1 ("* ]] || return 1
	[[ "$output" == *"REMOVE:$volumes_root/unused-runtime"* ]] || return 1
	[[ "$output" == *"$volumes_root/unused-runtime"* ]] || return 1
	[[ "$output" != *"$volumes_root/in-use-runtime"* ]]
}

@test "clean_xcode_simulator_runtime_volumes deletes nothing when mount enumeration fails" {
	local volumes_root="$HOME/sim-volumes"
	mkdir -p "$volumes_root/runtime-a" "$volumes_root/runtime-b"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_XCODE_SIM_RUNTIME_VOLUMES_ROOT="$volumes_root" MOLE_XCODE_SIM_RUNTIME_CRYPTEX_ROOT="$HOME/none" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"

DRY_RUN=false
note_activity() { :; }
has_sudo_session() { return 0; }
is_path_whitelisted() { return 1; }
should_protect_path() { return 1; }
# mount failed: no lines. Without the guard every runtime is UNUSED and deleted.
_sim_runtime_mount_points() { printf ''; }
_sim_runtime_size_kb() { echo "1"; }
safe_sudo_remove() { echo "REMOVE:$1"; return 0; }

clean_xcode_simulator_runtime_volumes

# Positive control. The guard makes this path print nothing at all, so "no
# REMOVE line" alone cannot tell a working guard from a run that never reached
# the deletion branch. Same fixture, this time with mounts enumerable.
echo "CONTROL"
_sim_runtime_mount_points() { printf '%s\n' "/"; }
clean_xcode_simulator_runtime_volumes
EOF

	[ "$status" -eq 0 ] || return 1
	guarded="${output%%CONTROL*}"
	control="${output#*CONTROL}"
	[[ "$guarded" != *"REMOVE:"* ]] || { echo "deleted a volume despite unknown mount state"; return 1; }
	[[ "$control" == *"REMOVE:"* ]] || { echo "control run removed nothing, so the guarded run proves nothing"; return 1; }
}

@test "clean_dev_mobile continues cleanup when simctl is unavailable" {
	local tmp_bin
	tmp_bin="$HOME/simctl-unavailable-bin"
	mkdir -p "$tmp_bin"
	cat > "$tmp_bin/xcrun" <<'XEOF'
#!/bin/bash
exit 1
XEOF
	cat > "$tmp_bin/xcode-select" <<'XEOF'
#!/bin/bash
printf '/Library/Developer/CommandLineTools\n'
XEOF
	chmod +x "$tmp_bin/xcrun" "$tmp_bin/xcode-select"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$tmp_bin:$PATH" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"

_MOLE_SIMCTL_XCODE_APP_ROOTS=("$HOME/EmptyApplications")
mkdir -p "${_MOLE_SIMCTL_XCODE_APP_ROOTS[0]}"
check_android_ndk() { :; }
clean_xcode_documentation_cache() { :; }
clean_xcode_system_coresimulator_caches() { :; }
clean_xcode_simulator_runtime_volumes() { :; }
clean_xcode_xctest_devices() { :; }
clean_xcode_device_support() { echo "DEVICE_SUPPORT:$2"; }
safe_clean() { echo "SAFE_CLEAN:$2"; }
note_activity() { :; }
debug_log() { :; }

clean_dev_mobile
EOF

	[ "$status" -eq 0 ] || return 1
	[[ "$output" == *"simctl not available"* ]] || return 1
	[[ "$output" == *"DEVICE_SUPPORT:iOS DeviceSupport"* ]] || return 1
	[[ "$output" == *"SAFE_CLEAN:Android SDK cache"* ]] || return 1
}

@test "clean_dev_mobile retries simctl probe on cold-boot timeout (#890)" {
	# Exercises the timeout-retry branch (the only path the #890 fix touches).
	# Strategy:
	#   - put a real `xcrun` shim on PATH so `command -v xcrun` succeeds AND
	#     `declare -F xcrun` returns false → function falls into the else branch.
	#   - stub `run_with_timeout` so the first probe returns 124 (timeout) and
	#     the second returns 0, mirroring a cold-boot CoreSimulatorService
	#     warmup.
	#   - the shim itself returns empty for the post-probe
	#     `xcrun simctl list devices unavailable` call so we take the
	#     "already clean" branch and don't try to delete anything.
	local tmp_bin
	tmp_bin="$HOME/simctl-retry-bin"
	mkdir -p "$tmp_bin" "$HOME/Xcode.app/Contents/Developer"
	cat > "$tmp_bin/xcrun" <<'XEOF'
#!/bin/bash
exit 0
XEOF
	cat > "$tmp_bin/xcode-select" <<XEOF
#!/bin/bash
printf '$HOME/Xcode.app/Contents/Developer\n'
XEOF
	chmod +x "$tmp_bin/xcrun" "$tmp_bin/xcode-select"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$tmp_bin:$PATH" DRY_RUN=false /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"

check_android_ndk() { :; }
clean_xcode_documentation_cache() { :; }
clean_xcode_system_coresimulator_caches() { :; }
clean_xcode_simulator_runtime_volumes() { :; }
clean_xcode_xctest_devices() { :; }
clean_xcode_device_support() { :; }
safe_clean() { :; }
note_activity() { :; }
debug_log() { echo "debug: $*"; }
sleep() { echo "UNEXPECTED_SLEEP:$*"; return 99; }

# First call (5s timeout) simulates cold-boot warmup → return 124.
# Second call (8s timeout) succeeds.
__rwt_count=0
run_with_timeout() {
    shift
    case " $* " in
        *" xcrun simctl list devices ")
            __rwt_count=$((__rwt_count + 1))
            if [[ $__rwt_count -eq 1 ]]; then
                return 124
            fi
            ;;
    esac
    "$@"
}

clean_dev_mobile
EOF

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"simctl probe succeeded on retry"* ]] || return 1
    [[ "$output" != *"simctl not available"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_SLEEP"* ]] || return 1
}

@test "clean_dev_mobile uses the sole Xcode Beta candidate when CLT is selected (#1261)" {
	local tmp_bin candidate developer_dir
	tmp_bin="$HOME/simctl-single-bin"
	candidate="$HOME/Applications/Xcode-Beta.app"
	developer_dir="$candidate/Contents/Developer"
	mkdir -p "$tmp_bin" "$developer_dir"

	cat > "$tmp_bin/xcrun" <<'XEOF'
#!/bin/bash
if [[ "$*" == "--find simctl" ]]; then
    [[ "${DEVELOPER_DIR:-}" == "$EXPECTED_DEVELOPER_DIR" ]] || exit 1
    exit
fi
printf '%s|%s\n' "${DEVELOPER_DIR:-}" "$*" >> "$SIMCTL_CALL_LOG"
case "$*" in
    "simctl list devices")
        exit 0
        ;;
    "simctl list devices unavailable")
        printf '    iPhone 12 (ABCDEF01-2345-6789-ABCD-EF0123456789) (Shutdown) (unavailable)\n'
        exit 0
        ;;
esac
exit 1
XEOF
	cat > "$tmp_bin/xcode-select" <<'XEOF'
#!/bin/bash
printf '/Library/Developer/CommandLineTools\n'
XEOF
	chmod +x "$tmp_bin/xcrun" "$tmp_bin/xcode-select"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$tmp_bin:$PATH" \
		DRY_RUN=true EXPECTED_DEVELOPER_DIR="$developer_dir" \
		SIMCTL_CALL_LOG="$HOME/simctl-single.log" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"

_MOLE_SIMCTL_XCODE_APP_ROOTS=("$HOME/Applications")
check_android_ndk() { :; }
clean_xcode_documentation_cache() { :; }
clean_xcode_system_coresimulator_caches() { :; }
clean_xcode_simulator_runtime_volumes() { :; }
clean_xcode_xctest_devices() { :; }
clean_xcode_device_support() { :; }
safe_clean() { :; }
note_activity() { :; }
debug_log() { :; }

clean_dev_mobile
EOF

	[ "$status" -eq 0 ] || return 1
	[[ "$output" == *"Xcode unavailable simulators · would clean 1"* ]] || return 1
	[[ -s "$HOME/simctl-single.log" ]] || return 1
	while IFS= read -r call; do
		[[ "$call" == "$developer_dir|"* ]] || return 1
	done < "$HOME/simctl-single.log"
}

@test "clean_dev_mobile skips ambiguous Xcode candidates without choosing one (#1261)" {
	local tmp_bin
	tmp_bin="$HOME/simctl-ambiguous-bin"
	mkdir -p "$tmp_bin"
	for app in Xcode.app Xcode-Beta.app; do
		mkdir -p "$HOME/Applications/$app/Contents/Developer"
	done

	cat > "$tmp_bin/xcrun" <<'XEOF'
#!/bin/bash
if [[ "$*" == "--find simctl" ]]; then
    [[ "${DEVELOPER_DIR:-}" == "$HOME/Applications/Xcode.app/Contents/Developer" ||
        "${DEVELOPER_DIR:-}" == "$HOME/Applications/Xcode-Beta.app/Contents/Developer" ]]
    exit
fi
printf '%s\n' "$*" >> "$SIMCTL_CALL_LOG"
exit 0
XEOF
	cat > "$tmp_bin/xcode-select" <<'XEOF'
#!/bin/bash
printf '/Library/Developer/CommandLineTools\n'
XEOF
	chmod +x "$tmp_bin/xcrun" "$tmp_bin/xcode-select"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$tmp_bin:$PATH" \
		SIMCTL_CALL_LOG="$HOME/simctl-ambiguous.log" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"

_MOLE_SIMCTL_XCODE_APP_ROOTS=("$HOME/Applications")
check_android_ndk() { :; }
clean_xcode_documentation_cache() { :; }
clean_xcode_system_coresimulator_caches() { :; }
clean_xcode_simulator_runtime_volumes() { :; }
clean_xcode_xctest_devices() { :; }
clean_xcode_device_support() { :; }
safe_clean() { :; }
note_activity() { :; }
debug_log() { echo "DEBUG:$*"; }

clean_dev_mobile
EOF

	[ "$status" -eq 0 ] || return 1
	[[ "$output" == *"multiple Xcode apps found; set DEVELOPER_DIR"* ]] || return 1
	[[ "$output" == *"DEBUG:simctl Xcode candidate: $HOME/Applications/Xcode.app"* ]] || return 1
	[[ "$output" == *"DEBUG:simctl Xcode candidate: $HOME/Applications/Xcode-Beta.app"* ]] || return 1
    [[ ! -e "$HOME/simctl-ambiguous.log" ]] || return 1
}

@test "clean_dev_mobile does not replace a selected full Xcode when simctl is unavailable" {
    local tmp_bin selected candidate
    tmp_bin="$HOME/simctl-selected-invalid-bin"
    selected="$HOME/Applications/Xcode-Selected.app/Contents/Developer"
    candidate="$HOME/Applications/Xcode-Beta.app/Contents/Developer"
    mkdir -p "$tmp_bin" "$selected" "$candidate"

    cat > "$tmp_bin/xcrun" <<'XEOF'
#!/bin/bash
printf '%s|%s\n' "${DEVELOPER_DIR:-}" "$*" >> "$SIMCTL_CALL_LOG"
if [[ "${DEVELOPER_DIR:-}" == "$CANDIDATE_DEVELOPER_DIR" ]]; then
    exit 0
fi
exit 1
XEOF
    cat > "$tmp_bin/xcode-select" <<XEOF
#!/bin/bash
printf '$selected\n'
XEOF
    chmod +x "$tmp_bin/xcrun" "$tmp_bin/xcode-select"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$tmp_bin:$PATH" \
        CANDIDATE_DEVELOPER_DIR="$candidate" \
        SIMCTL_CALL_LOG="$HOME/simctl-selected-invalid.log" \
        /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"

_MOLE_SIMCTL_XCODE_APP_ROOTS=("$HOME/Applications")
check_android_ndk() { :; }
clean_xcode_documentation_cache() { :; }
clean_xcode_system_coresimulator_caches() { :; }
clean_xcode_simulator_runtime_volumes() { :; }
clean_xcode_xctest_devices() { :; }
clean_xcode_device_support() { :; }
safe_clean() { :; }
note_activity() { :; }
debug_log() { :; }

clean_dev_mobile
EOF

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"simctl not available"* ]] || return 1
    [[ "$(cat "$HOME/simctl-selected-invalid.log")" == "$selected|--find simctl" ]] || return 1
    [[ "$(cat "$HOME/simctl-selected-invalid.log")" != *"$candidate|"* ]] || return 1
}

@test "clean_dev_mobile does not override an invalid explicit DEVELOPER_DIR (#1261)" {
	local tmp_bin candidate
	tmp_bin="$HOME/simctl-explicit-invalid-bin"
	candidate="$HOME/Applications/Xcode-Beta.app/Contents/Developer"
	mkdir -p "$tmp_bin" "$candidate"

	cat > "$tmp_bin/xcrun" <<'XEOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SIMCTL_CALL_LOG"
exit 0
XEOF
	cat > "$tmp_bin/xcode-select" <<'XEOF'
#!/bin/bash
printf '%s\n' "$*" >> "$XCODE_SELECT_CALL_LOG"
printf '/Library/Developer/CommandLineTools\n'
XEOF
	chmod +x "$tmp_bin/xcrun" "$tmp_bin/xcode-select"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$tmp_bin:$PATH" \
		DEVELOPER_DIR="$HOME/MissingXcode.app/Contents/Developer" \
		SIMCTL_CALL_LOG="$HOME/simctl-explicit-invalid.log" \
		XCODE_SELECT_CALL_LOG="$HOME/xcode-select-explicit-invalid.log" \
		/bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"

_MOLE_SIMCTL_XCODE_APP_ROOTS=("$HOME/Applications")
check_android_ndk() { :; }
clean_xcode_documentation_cache() { :; }
clean_xcode_system_coresimulator_caches() { :; }
clean_xcode_simulator_runtime_volumes() { :; }
clean_xcode_xctest_devices() { :; }
clean_xcode_device_support() { :; }
safe_clean() { :; }
note_activity() { :; }
debug_log() { :; }

clean_dev_mobile
EOF

	[ "$status" -eq 0 ] || return 1
	[[ "$output" == *"DEVELOPER_DIR has no simctl"* ]] || return 1
	[[ ! -e "$HOME/simctl-explicit-invalid.log" ]] || return 1
	[[ ! -e "$HOME/xcode-select-explicit-invalid.log" ]] || return 1
}

@test "clean_dev_mobile does not race a timed-out simctl delete with manual removal" {
	local tmp_bin developer_dir
	tmp_bin="$HOME/simctl-delete-failure-bin"
	developer_dir="$HOME/Xcode-delete-failure.app/Contents/Developer"
	mkdir -p "$tmp_bin" "$developer_dir" \
		"$HOME/Library/Developer/CoreSimulator/Devices/ABCDEF01-2345-6789-ABCD-EF0123456789"

	cat > "$tmp_bin/xcrun" <<'XEOF'
#!/bin/bash
case "$*" in
    "--find simctl" | "simctl list devices")
        exit 0
        ;;
    "simctl list devices unavailable")
        printf '    iPhone 12 (ABCDEF01-2345-6789-ABCD-EF0123456789) (Shutdown) (unavailable)\n'
        exit 0
        ;;
    "simctl delete unavailable")
        exit 124
        ;;
esac
exit 1
XEOF
	cat > "$tmp_bin/xcode-select" <<XEOF
#!/bin/bash
printf '$developer_dir\n'
XEOF
	chmod +x "$tmp_bin/xcrun" "$tmp_bin/xcode-select"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$tmp_bin:$PATH" \
		DRY_RUN=false /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"

check_android_ndk() { :; }
clean_xcode_documentation_cache() { :; }
clean_xcode_system_coresimulator_caches() { :; }
clean_xcode_simulator_runtime_volumes() { :; }
clean_xcode_xctest_devices() { :; }
clean_xcode_device_support() { :; }
safe_clean() { :; }
safe_remove() { echo "UNEXPECTED_FALLBACK:$1"; return 1; }
note_activity() { :; }
debug_log() { :; }
start_section_spinner() { :; }
stop_section_spinner() { :; }

clean_dev_mobile
EOF

	[ "$status" -eq 0 ] || return 1
    [[ "$output" == *"Xcode unavailable simulators · cleanup timed out"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_FALLBACK"* ]] || return 1
    [[ "$output" != *"Xcode unavailable simulators · removed"* ]] || return 1
}

@test "clean_dev_mobile does not bypass simctl when a device becomes busy" {
    local tmp_bin developer_dir
    tmp_bin="$HOME/simctl-busy-bin"
    developer_dir="$HOME/Xcode-busy.app/Contents/Developer"
    mkdir -p "$tmp_bin" "$developer_dir" \
        "$HOME/Library/Developer/CoreSimulator/Devices/ABCDEF01-2345-6789-ABCD-EF0123456789"

    cat > "$tmp_bin/xcrun" <<'XEOF'
#!/bin/bash
case "$*" in
    "--find simctl" | "simctl list devices")
        exit 0
        ;;
    "simctl list devices unavailable")
        printf '    iPhone 12 (ABCDEF01-2345-6789-ABCD-EF0123456789) (Shutdown) (unavailable)\n'
        exit 0
        ;;
    "simctl delete unavailable")
        printf 'device is busy\n' >&2
        exit 1
        ;;
esac
exit 1
XEOF
    cat > "$tmp_bin/xcode-select" <<XEOF
#!/bin/bash
printf '$developer_dir\n'
XEOF
    chmod +x "$tmp_bin/xcrun" "$tmp_bin/xcode-select"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$tmp_bin:$PATH" \
        DRY_RUN=false /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"

check_android_ndk() { :; }
clean_xcode_documentation_cache() { :; }
clean_xcode_system_coresimulator_caches() { :; }
clean_xcode_simulator_runtime_volumes() { :; }
clean_xcode_xctest_devices() { :; }
clean_xcode_device_support() { :; }
safe_clean() { :; }
safe_remove() { echo "UNEXPECTED_FALLBACK:$1"; return 1; }
note_activity() { :; }
debug_log() { :; }
start_section_spinner() { :; }
stop_section_spinner() { :; }

clean_dev_mobile
EOF

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"cleanup failed (device in use)"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_FALLBACK"* ]] || return 1
    [[ "$output" != *"Xcode unavailable simulators · removed"* ]] || return 1
}

@test "clean_dev_mobile never deletes from a timed-out list or reports a timed-out recount as success" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" DRY_RUN=false \
        SIMCTL_SAFETY_LOG="$HOME/simctl-safety.log" \
        SIMCTL_RECOUNT_STATE="$HOME/simctl-recount.state" \
        /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"

check_android_ndk() { :; }
clean_xcode_documentation_cache() { :; }
clean_xcode_system_coresimulator_caches() { :; }
clean_xcode_simulator_runtime_volumes() { :; }
clean_xcode_xctest_devices() { :; }
clean_xcode_device_support() { :; }
safe_clean() { :; }
get_path_size_kb() { echo "1"; }
note_activity() { :; }
debug_log() { :; }
start_section_spinner() { :; }
stop_section_spinner() { :; }
cleanup_result_color_kb() { printf '%s' "$GREEN"; }
xcrun() { return 0; }
_resolve_simctl_developer_dir() {
    _MOLE_SIMCTL_DEVELOPER_DIR="$HOME/Xcode.app/Contents/Developer"
    _MOLE_SIMCTL_RESOLUTION_STATUS="ready"
}

scenario="list-timeout"
_run_simctl() {
    shift
    case "$*" in
        "list devices")
            return 0
            ;;
        "list devices unavailable")
            if [[ "$scenario" == "list-timeout" ]]; then
                echo "    iPhone 12 (ABCDEF01-2345-6789-ABCD-EF0123456789) (Shutdown) (unavailable)"
                return 124
            fi
            if [[ ! -e "$SIMCTL_RECOUNT_STATE" ]]; then
                touch "$SIMCTL_RECOUNT_STATE"
                echo "    iPhone 12 (ABCDEF01-2345-6789-ABCD-EF0123456789) (Shutdown) (unavailable)"
                return 0
            fi
            return 124
            ;;
        "delete unavailable")
            printf 'DELETE\n' >> "$SIMCTL_SAFETY_LOG"
            return 0
            ;;
    esac
    return 1
}

clean_dev_mobile
if [[ -e "$SIMCTL_SAFETY_LOG" ]]; then
    echo "UNEXPECTED_DELETE_AFTER_LIST_TIMEOUT"
fi

scenario="recount-timeout"
clean_dev_mobile
printf 'DELETE_COUNT=%s\n' "$(wc -l < "$SIMCTL_SAFETY_LOG" | tr -d ' ')"
EOF

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"simctl list failed (exit=124)"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_DELETE_AFTER_LIST_TIMEOUT"* ]] || return 1
    [[ "$output" == *"cleanup completed, unable to verify remaining devices"* ]] || return 1
    [[ "$output" == *"DELETE_COUNT=1"* ]] || return 1
    [[ "$output" != *"removed 1"* ]] || return 1
}

@test "clean_dev_ai_agents protects the copilot version pointed at by ~/.local/bin/copilot" {
	local copilot_root="$HOME/.copilot/pkg/universal"
	local bin_dir="$HOME/.local/bin"
	rm -rf "$HOME/.copilot" "$HOME/.local/share/claude" "$HOME/.local/share/cursor-agent" "$bin_dir"
	mkdir -p "$copilot_root" "$bin_dir"

	mkdir -p "$copilot_root/1.0.5" "$copilot_root/1.0.32" "$copilot_root/1.0.34"
	: >"$copilot_root/1.0.32/copilot"
	ln -s "../../.copilot/pkg/universal/1.0.32/copilot" "$bin_dir/copilot"

	# Keep the active version older than a pre-downloaded update. The launcher,
	# not mtime order, must decide which version remains pinned.
	touch -t 202604010000 "$copilot_root/1.0.5"
	touch -t 202604200000 "$copilot_root/1.0.32"
	touch -t 202604250000 "$copilot_root/1.0.34"

	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
note_activity() { :; }
safe_clean() { echo "$1|$2"; }
clean_dev_ai_agents
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"/1.0.5|GitHub Copilot CLI old version"* ]] || return 1
	[[ "$output" != *"/1.0.32|"* ]] || return 1
	[[ "$output" != *"/1.0.34|"* ]]
}
