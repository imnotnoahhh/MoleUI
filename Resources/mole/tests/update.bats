#!/usr/bin/env bats

setup_file() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT
}

setup() {
	HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-update-home.XXXXXX")"
	TEST_ROOT="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-update-case.XXXXXX")"
	export HOME TEST_ROOT
}

teardown() {
	case "${HOME:-}" in
		"${BATS_TEST_DIRNAME}/tmp-update-home."*) rm -rf "$HOME" ;;
	esac
	case "${TEST_ROOT:-}" in
		"${BATS_TEST_DIRNAME}/tmp-update-case."*) rm -rf "$TEST_ROOT" ;;
	esac
}

make_manual_mole_install() {
	local install_dir="$1"
	local config_dir="$2"
	local version="$3"
	mkdir -p "$install_dir" "$config_dir/bin"
	sed \
		-e "s|^SCRIPT_DIR=.*|SCRIPT_DIR=\"$config_dir\"|" \
		-e "s/^VERSION=\".*\"$/VERSION=\"$version\"/" \
		"$PROJECT_ROOT/mole" > "$install_dir/mole"
	cp "$PROJECT_ROOT/mo" "$install_dir/mo"
	cp -R "$PROJECT_ROOT/lib" "$config_dir/lib"
	printf '#!/bin/bash\nexit 0\n' > "$config_dir/bin/analyze-go"
	printf '#!/bin/bash\nexit 0\n' > "$config_dir/bin/status-go"
	chmod +x "$install_dir/mole" "$install_dir/mo" "$config_dir/bin/analyze-go" "$config_dir/bin/status-go"
}

make_homebrew_shadow() {
	local bin_dir="$1"
	local cellar_mole="$2"
	mkdir -p "$bin_dir" "$(dirname "$cellar_mole")"
	cp "$PROJECT_ROOT/mole" "$cellar_mole"
	cp -R "$PROJECT_ROOT/lib" "$bin_dir/lib"
	chmod +x "$cellar_mole"
	ln -sf "$cellar_mole" "$bin_dir/mole"
	ln -sf "$cellar_mole" "$bin_dir/mo"

	cat > "$bin_dir/brew" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BREW_LOG"
case "${1:-}" in
	list)
		if [[ "${2:-}" == "--versions" ]]; then
			printf 'mole 9.9.9\n'
		fi
		exit 0
		;;
	update | upgrade)
		exit 0
		;;
esac
exit 0
SCRIPT
	chmod +x "$bin_dir/brew"
}

make_update_curl_stub() {
	local bin_dir="$1"
	local latest_version="$2"
	cat > "$bin_dir/curl" <<SCRIPT
#!/usr/bin/env bash
out=""
url=""
while [[ \$# -gt 0 ]]; do
	case "\$1" in
		-o)
			out="\$2"
			shift 2
			;;
		http*://*)
			url="\$1"
			shift
			;;
		*)
			shift
			;;
	esac
done
[[ -n "\$url" ]] && printf '%s\n' "\$url" >> "\$CURL_URL_LOG"

if [[ -n "\$out" ]]; then
	cat > "\$out" <<'INSTALLER'
#!/usr/bin/env bash
printf '%s\n' "\$*" > "\$INSTALLER_ARGS_LOG"
printf '%s\n' "\${MOLE_VERSION:-}" > "\$INSTALLER_VERSION_LOG"
if [[ -n "\${INSTALLER_SUDO_AUTH_LOG:-}" ]]; then
	printf '%s\n' "\${MOLE_ASSUME_SUDO_AUTH:-}" > "\$INSTALLER_SUDO_AUTH_LOG"
fi
echo "Updated to latest version, \${MOLE_VERSION#V}"
INSTALLER
	exit 0
fi

if [[ "\$url" == *"api.github.com"* ]]; then
	printf '{"tag_name":"%s"}\n' "$latest_version"
	exit 0
fi

printf 'VERSION="%s"\n' "$latest_version"
SCRIPT
	chmod +x "$bin_dir/curl"
}

make_nightly_update_curl_stub() {
	local bin_dir="$1"
	local latest_commit="$2"
	cat > "$bin_dir/curl" <<SCRIPT
#!/usr/bin/env bash
out=""
url=""
while [[ \$# -gt 0 ]]; do
	case "\$1" in
		-o)
			out="\$2"
			shift 2
			;;
		http*://*)
			url="\$1"
			shift
			;;
		*)
			shift
			;;
	esac
done
[[ -n "\$url" ]] && printf '%s\n' "\$url" >> "\$CURL_URL_LOG"

if [[ -n "\$out" ]]; then
	cat > "\$out" <<'INSTALLER'
#!/usr/bin/env bash
printf '%s\n' "\$*" > "\$INSTALLER_ARGS_LOG"
printf '%s\n' "\${MOLE_VERSION:-}" > "\$INSTALLER_VERSION_LOG"
if [[ -n "\${INSTALLER_SUDO_AUTH_LOG:-}" ]]; then
	printf '%s\n' "\${MOLE_ASSUME_SUDO_AUTH:-}" > "\$INSTALLER_SUDO_AUTH_LOG"
fi
echo "Updated to latest version, \${MOLE_VERSION#V}"
INSTALLER
	exit 0
fi

if [[ "\$url" == *"api.github.com/repos/tw93/mole/commits/main"* ]]; then
	printf '{"sha":"%s"}\n' "$latest_commit"
	exit 0
fi

exit 1
SCRIPT
	chmod +x "$bin_dir/curl"
}

@test "mo update repairs missing helpers at the current stable version (#1193)" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_bin="$TEST_ROOT/fake-bin"
	local installer_args_log="$TEST_ROOT/installer.args"
	local installer_version_log="$TEST_ROOT/installer.version"
	local curl_url_log="$TEST_ROOT/curl.urls"
	local current_version

	current_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$PROJECT_ROOT/mole" | head -1)"
	mkdir -p "$fake_bin"
	make_manual_mole_install "$manual_bin" "$manual_config" "$current_version"
	make_update_curl_stub "$fake_bin" "$current_version"
	rm -f "$manual_config/bin/analyze-go"
	touch "$manual_config/.helper_install_incomplete"
	: > "$curl_url_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_bin:/usr/bin:/bin" \
		CURL_URL_LOG="$curl_url_log" \
		INSTALLER_ARGS_LOG="$installer_args_log" \
		INSTALLER_VERSION_LOG="$installer_version_log" \
		"$manual_bin/mo" update

	[ "$status" -eq 0 ]
	[[ "$output" == *"Mole installation needs repair"* ]]
	[[ "$output" == *"missing analyze-go"* ]]
	[ -f "$installer_args_log" ]
	if grep -q -- "--update" "$installer_args_log"; then
		return 1
	fi
	[ "$(cat "$installer_version_log")" = "V$current_version" ]
}

@test "mo update targets the invoked manual install, not another Homebrew mole in PATH" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_brew_bin="$TEST_ROOT/homebrew/bin"
	local fake_brew_mole="$TEST_ROOT/homebrew/Cellar/mole/9.9.9/bin/mole"
	local brew_log="$TEST_ROOT/brew.log"
	local installer_args_log="$TEST_ROOT/installer.args"
	local installer_version_log="$TEST_ROOT/installer.version"
	local curl_url_log="$TEST_ROOT/curl.urls"
	local current_version
	local stale_version="0.0.1"

	current_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$PROJECT_ROOT/mole" | head -1)"
	make_manual_mole_install "$manual_bin" "$manual_config" "$stale_version"
	make_homebrew_shadow "$fake_brew_bin" "$fake_brew_mole"
	make_update_curl_stub "$fake_brew_bin" "$current_version"
	: > "$brew_log"
	: > "$curl_url_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_brew_bin:/usr/bin:/bin" \
		BREW_LOG="$brew_log" \
		CURL_URL_LOG="$curl_url_log" \
		INSTALLER_ARGS_LOG="$installer_args_log" \
		INSTALLER_VERSION_LOG="$installer_version_log" \
		"$manual_bin/mo" update

	[ "$status" -eq 0 ]
	[ -f "$installer_args_log" ]
	grep -q -- "--prefix" "$installer_args_log"
	grep -q -- "$manual_bin" "$installer_args_log"
	[ "$(cat "$installer_version_log")" = "V$current_version" ]
	grep -q "raw.githubusercontent.com/tw93/mole/V${current_version#V}/install.sh" "$curl_url_log"
	if grep -q "raw.githubusercontent.com/tw93/mole/main/install.sh" "$curl_url_log"; then
		return 1
	fi
	if grep -q '^upgrade mole$' "$brew_log"; then
		return 1
	fi
}

@test "mo update --nightly skips reinstall when the installed commit is current" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_bin="$TEST_ROOT/fake-bin"
	local installer_args_log="$TEST_ROOT/installer.args"
	local installer_version_log="$TEST_ROOT/installer.version"
	local curl_url_log="$TEST_ROOT/curl.urls"
	local latest_commit="e31d46faaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

	mkdir -p "$fake_bin"
	make_manual_mole_install "$manual_bin" "$manual_config" "1.41.0"
	make_nightly_update_curl_stub "$fake_bin" "$latest_commit"
	printf 'CHANNEL=nightly\nCOMMIT_HASH=e31d46f\n' > "$manual_config/install_channel"
	: > "$curl_url_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_bin:/usr/bin:/bin" \
		CURL_URL_LOG="$curl_url_log" \
		INSTALLER_ARGS_LOG="$installer_args_log" \
		INSTALLER_VERSION_LOG="$installer_version_log" \
		"$manual_bin/mo" update --nightly

	[ "$status" -eq 0 ]
	[[ "$output" == *"Already on latest nightly, e31d46f"* ]]
	[ ! -e "$installer_args_log" ]
	grep -q "api.github.com/repos/tw93/mole/commits/main" "$curl_url_log"
	if grep -q "raw.githubusercontent.com/tw93/mole/main/install.sh" "$curl_url_log"; then
		return 1
	fi
}

@test "mo update --nightly --force reinstalls even when the installed commit is current" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_bin="$TEST_ROOT/fake-bin"
	local installer_args_log="$TEST_ROOT/installer.args"
	local installer_version_log="$TEST_ROOT/installer.version"
	local curl_url_log="$TEST_ROOT/curl.urls"
	local latest_commit="e31d46faaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

	mkdir -p "$fake_bin"
	make_manual_mole_install "$manual_bin" "$manual_config" "1.41.0"
	make_nightly_update_curl_stub "$fake_bin" "$latest_commit"
	printf 'CHANNEL=nightly\nCOMMIT_HASH=e31d46f\n' > "$manual_config/install_channel"
	: > "$curl_url_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_bin:/usr/bin:/bin" \
		CURL_URL_LOG="$curl_url_log" \
		INSTALLER_ARGS_LOG="$installer_args_log" \
		INSTALLER_VERSION_LOG="$installer_version_log" \
		"$manual_bin/mo" update --nightly --force

	[ "$status" -eq 0 ]
	[ -f "$installer_args_log" ]
	grep -q -- "--prefix" "$installer_args_log"
	[ "$(cat "$installer_version_log")" = "main" ]
	grep -q "raw.githubusercontent.com/tw93/mole/main/install.sh" "$curl_url_log"
}

@test "mo update tells installer to reuse sudo after parent authentication" {
	local manual_bin="$TEST_ROOT/manual/bin"
	local manual_config="$TEST_ROOT/manual/config"
	local fake_bin="$TEST_ROOT/fake-bin"
	local installer_args_log="$TEST_ROOT/installer.args"
	local installer_version_log="$TEST_ROOT/installer.version"
	local installer_sudo_auth_log="$TEST_ROOT/installer.sudo-auth"
	local curl_url_log="$TEST_ROOT/curl.urls"
	local sudo_log="$TEST_ROOT/sudo.log"
	local current_version

	current_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$PROJECT_ROOT/mole" | head -1)"
	mkdir -p "$fake_bin"
	make_manual_mole_install "$manual_bin" "$manual_config" "1.41.0"
	make_update_curl_stub "$fake_bin" "$current_version"
	chmod a-w "$manual_bin/mole"
	cat > "$fake_bin/sudo" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SUDO_LOG"
exit 0
SCRIPT
	chmod +x "$fake_bin/sudo"
	: > "$curl_url_log"
	: > "$sudo_log"

	run env \
		HOME="$HOME" \
		MOLE_TEST_MODE=0 \
		MOLE_TEST_NO_AUTH=0 \
		PATH="$fake_bin:/usr/bin:/bin" \
		CURL_URL_LOG="$curl_url_log" \
		INSTALLER_ARGS_LOG="$installer_args_log" \
		INSTALLER_VERSION_LOG="$installer_version_log" \
		INSTALLER_SUDO_AUTH_LOG="$installer_sudo_auth_log" \
		SUDO_LOG="$sudo_log" \
		"$manual_bin/mo" update --force

	chmod u+w "$manual_bin/mole"

	[ "$status" -eq 0 ]
	[ -f "$installer_sudo_auth_log" ]
	[ "$(cat "$installer_sudo_auth_log")" = "1" ]
	grep -q -- "-n true" "$sudo_log"
	grep -q "raw.githubusercontent.com/tw93/mole/V${current_version#V}/install.sh" "$curl_url_log"
}

@test "installer sudo reuse uses non-interactive sudo checks" {
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_MODE=0 MOLE_TEST_NO_AUTH=0 bash --noprofile --norc <<'EOF'
set -euo pipefail

INSTALL_DIR="$HOME/install"
CONFIG_DIR="$HOME/config"
SOURCE_DIR="$HOME/source"
VERBOSE=1
GREEN='' BLUE='' YELLOW='' RED='' NC=''
ICON_ERROR='err'
SUDO_LOG="$HOME/sudo.log"
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$SOURCE_DIR"
chmod a-w "$INSTALL_DIR"

eval "$(sed -n '/^needs_sudo()/,/^resolve_source_dir()/p' "$PROJECT_ROOT/install.sh" | sed '$d')"

log_error() { echo "ERROR:$*"; }
sudo() {
	printf '%s\n' "$*" >> "$SUDO_LOG"
	return 0
}

MOLE_ASSUME_SUDO_AUTH=1 ensure_sudo_ready
grep -qx -- "-n -v" "$SUDO_LOG" || { echo "WRONG: sudo validation was interactive"; cat "$SUDO_LOG"; exit 1; }

: > "$SUDO_LOG"
MOLE_ASSUME_SUDO_AUTH=1 maybe_sudo true
grep -qx -- "-n true" "$SUDO_LOG" || { echo "WRONG: sudo command was interactive"; cat "$SUDO_LOG"; exit 1; }

chmod u+w "$INSTALL_DIR"
EOF

	[ "$status" -eq 0 ]
}

@test "mo update keeps Homebrew installs on the Homebrew update path" {
	local fake_brew_bin="$TEST_ROOT/homebrew/bin"
	local fake_brew_mole="$TEST_ROOT/homebrew/Cellar/mole/9.9.9/bin/mole"
	local brew_log="$TEST_ROOT/brew.log"

	make_homebrew_shadow "$fake_brew_bin" "$fake_brew_mole"
	: > "$brew_log"

	run env \
		HOME="$HOME" \
		PATH="$fake_brew_bin:/usr/bin:/bin" \
		BREW_LOG="$brew_log" \
		"$fake_brew_bin/mo" update

	[ "$status" -eq 0 ]
	grep -q '^update$' "$brew_log"
	grep -q '^upgrade mole$' "$brew_log"
}
