#!/usr/bin/env bats

setup_file() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT

	ORIGINAL_HOME="${HOME:-}"
	export ORIGINAL_HOME

	HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-cli-home.XXXXXX")"
	export HOME

	mkdir -p "$HOME"
}

teardown_file() {
	rm -rf "$HOME/.config/mole"
	rm -rf "$HOME"
	if [[ -n "${ORIGINAL_HOME:-}" ]]; then
		export HOME="$ORIGINAL_HOME"
	fi
}

create_fake_utils() {
	local dir="$1"
	mkdir -p "$dir"

	cat >"$dir/sudo" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$1" == "-n" || "$1" == "-v" ]]; then
    exit 0
fi
exec "$@"
SCRIPT
	chmod +x "$dir/sudo"

	cat >"$dir/bioutil" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$1" == "-r" ]]; then
    echo "Touch ID: 1"
    exit 0
fi
exit 0
SCRIPT
	chmod +x "$dir/bioutil"
}

setup() {
	rm -rf "$HOME/.config/mole"
	mkdir -p "$HOME/.config/mole"
}

@test "mole --help prints command overview" {
	run env HOME="$HOME" "$PROJECT_ROOT/mole" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"mo clean"* ]]
	[[ "$output" == *"mo analyze"* ]]
}

@test "mole --version reports script version" {
	expected_version="$(grep '^VERSION=' "$PROJECT_ROOT/mole" | head -1 | sed 's/VERSION=\"\(.*\)\"/\1/')"
	run env HOME="$HOME" "$PROJECT_ROOT/mole" --version
	[ "$status" -eq 0 ]
	[[ "$output" == *"$expected_version"* ]]
}

@test "mole --version shows nightly channel metadata" {
	expected_version="$(grep '^VERSION=' "$PROJECT_ROOT/mole" | head -1 | sed 's/VERSION=\"\(.*\)\"/\1/')"
	mkdir -p "$HOME/.config/mole"
	cat > "$HOME/.config/mole/install_channel" <<'EOF'
CHANNEL=nightly
EOF

	run env HOME="$HOME" "$PROJECT_ROOT/mole" --version
	[ "$status" -eq 0 ]
	[[ "$output" == *"Mole version $expected_version"* ]]
	[[ "$output" == *"Channel: Nightly"* ]]
}

@test "mole unknown command returns error" {
	run env HOME="$HOME" "$PROJECT_ROOT/mole" unknown-command
	[ "$status" -ne 0 ]
	[[ "$output" == *"Unknown command: unknown-command"* ]]
}

@test "mole uninstall --whitelist returns unsupported option error" {
	run env HOME="$HOME" "$PROJECT_ROOT/mole" uninstall --whitelist
	[ "$status" -ne 0 ]
	[[ "$output" == *"Unknown uninstall option: --whitelist"* ]]
}

@test "show_main_menu hides update shortcut when no update notice is available" {
	run bash --noprofile --norc <<'EOF'
set -euo pipefail
HOME="$(mktemp -d)"
export HOME MOLE_TEST_MODE=1 MOLE_SKIP_MAIN=1
source "$PROJECT_ROOT/mole"
show_brand_banner() { printf 'banner\n'; }
show_menu_option() { printf '%s' "$2"; }
MAIN_MENU_BANNER=""
MAIN_MENU_UPDATE_MESSAGE=""
MAIN_MENU_SHOW_UPDATE=false
show_main_menu 1 true
EOF

	[ "$status" -eq 0 ]
	[[ "$output" != *"U Update"* ]]
}

@test "interactive_main_menu ignores U shortcut when update notice is hidden" {
	run bash --noprofile --norc <<'EOF'
set -euo pipefail
HOME="$(mktemp -d)"
export HOME MOLE_TEST_MODE=1 MOLE_SKIP_MAIN=1
source "$PROJECT_ROOT/mole"
show_brand_banner() { :; }
show_main_menu() { :; }
hide_cursor() { :; }
show_cursor() { :; }
clear() { :; }
update_mole() { echo "UPDATE_CALLED"; }
state_file="$HOME/read_key_state"
read_key() {
    if [[ ! -f "$state_file" ]]; then
        : > "$state_file"
        echo "UPDATE"
    else
        echo "QUIT"
    fi
}
interactive_main_menu
EOF

	[ "$status" -eq 0 ]
	[[ "$output" != *"UPDATE_CALLED"* ]]
}

@test "interactive_main_menu accepts U shortcut when update notice is visible" {
	run bash --noprofile --norc <<'EOF'
set -euo pipefail
HOME="$(mktemp -d)"
export HOME MOLE_TEST_MODE=1 MOLE_SKIP_MAIN=1
mkdir -p "$HOME/.cache/mole"
printf 'update available\n' > "$HOME/.cache/mole/update_message"
source "$PROJECT_ROOT/mole"
show_brand_banner() { :; }
show_main_menu() { :; }
hide_cursor() { :; }
show_cursor() { :; }
clear() { :; }
update_mole() { echo "UPDATE_CALLED"; }
read_key() { echo "UPDATE"; }
interactive_main_menu
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"UPDATE_CALLED"* ]]
}

@test "touchid status reports current configuration" {
	run env HOME="$HOME" "$PROJECT_ROOT/mole" touchid status
	[ "$status" -eq 0 ]
	[[ "$output" == *"Touch ID"* ]]
}

@test "mo optimize command is recognized" {
	run bash -c "grep -q '\"optimize\")' '$PROJECT_ROOT/mole'"
	[ "$status" -eq 0 ]
}

@test "mo analyze binary is valid" {
	if [[ -f "$PROJECT_ROOT/bin/analyze-go" ]]; then
		[ -x "$PROJECT_ROOT/bin/analyze-go" ]
		run file "$PROJECT_ROOT/bin/analyze-go"
		[[ "$output" == *"Mach-O"* ]] || [[ "$output" == *"executable"* ]]
	else
		skip "analyze-go binary not built"
	fi
}

@test "mo clean --debug creates debug log file" {
	mkdir -p "$HOME/.config/mole"
	run env HOME="$HOME" TERM="xterm-256color" MOLE_TEST_MODE=1 MO_DEBUG=1 "$PROJECT_ROOT/mole" clean --dry-run
	[ "$status" -eq 0 ]
	MOLE_OUTPUT="$output"

	DEBUG_LOG="$HOME/.config/mole/mole_debug_session.log"
	[ -f "$DEBUG_LOG" ]

	run grep "Mole Debug Session" "$DEBUG_LOG"
	[ "$status" -eq 0 ]

	[[ "$MOLE_OUTPUT" =~ "Debug session log saved to" ]]
}

@test "mo clean without debug does not show debug log path" {
	mkdir -p "$HOME/.config/mole"
	run env HOME="$HOME" TERM="xterm-256color" MOLE_TEST_MODE=1 MO_DEBUG=0 "$PROJECT_ROOT/mole" clean --dry-run
	[ "$status" -eq 0 ]

	[[ "$output" != *"Debug session log saved to"* ]]
}

@test "mo clean --debug logs system info" {
	mkdir -p "$HOME/.config/mole"
	run env HOME="$HOME" TERM="xterm-256color" MOLE_TEST_MODE=1 MO_DEBUG=1 "$PROJECT_ROOT/mole" clean --dry-run
	[ "$status" -eq 0 ]

	DEBUG_LOG="$HOME/.config/mole/mole_debug_session.log"

	run grep "User:" "$DEBUG_LOG"
	[ "$status" -eq 0 ]

	run grep "Architecture:" "$DEBUG_LOG"
	[ "$status" -eq 0 ]
}

@test "touchid status reflects pam file contents" {
	pam_file="$HOME/pam_test"
	cat >"$pam_file" <<'EOF'
auth       sufficient     pam_opendirectory.so
EOF

	run env MOLE_PAM_SUDO_FILE="$pam_file" "$PROJECT_ROOT/bin/touchid.sh" status
	[ "$status" -eq 0 ]
	[[ "$output" == *"not configured"* ]]

	cat >"$pam_file" <<'EOF'
auth       sufficient     pam_tid.so
EOF

	run env MOLE_PAM_SUDO_FILE="$pam_file" "$PROJECT_ROOT/bin/touchid.sh" status
	[ "$status" -eq 0 ]
	[[ "$output" == *"enabled"* ]]
}

@test "enable_touchid inserts pam_tid line in pam file" {
	pam_file="$HOME/pam_enable"
	cat >"$pam_file" <<'EOF'
auth       sufficient     pam_opendirectory.so
EOF

	fake_bin="$HOME/fake-bin"
	create_fake_utils "$fake_bin"

	run env PATH="$fake_bin:$PATH" MOLE_PAM_SUDO_FILE="$pam_file" "$PROJECT_ROOT/bin/touchid.sh" enable
	[ "$status" -eq 0 ]
	grep -q "pam_tid.so" "$pam_file"
	[[ -f "${pam_file}.mole-backup" ]]
}

@test "disable_touchid removes pam_tid line" {
	pam_file="$HOME/pam_disable"
	cat >"$pam_file" <<'EOF'
auth       sufficient     pam_tid.so
auth       sufficient     pam_opendirectory.so
EOF

	fake_bin="$HOME/fake-bin-disable"
	create_fake_utils "$fake_bin"

	run env PATH="$fake_bin:$PATH" MOLE_PAM_SUDO_FILE="$pam_file" "$PROJECT_ROOT/bin/touchid.sh" disable
	[ "$status" -eq 0 ]
	run grep "pam_tid.so" "$pam_file"
	[ "$status" -ne 0 ]
}

@test "touchid enable --dry-run does not modify pam file" {
	pam_file="$HOME/pam_enable_dry_run"
	cat >"$pam_file" <<'EOF'
auth       sufficient     pam_opendirectory.so
EOF

	run env MOLE_PAM_SUDO_FILE="$pam_file" "$PROJECT_ROOT/bin/touchid.sh" enable --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"DRY RUN MODE"* ]]

	run grep "pam_tid.so" "$pam_file"
	[ "$status" -ne 0 ]
}
