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
	mkdir -p "$install_dir" "$config_dir"
	sed \
		-e "s|^SCRIPT_DIR=.*|SCRIPT_DIR=\"$config_dir\"|" \
		-e "s/^VERSION=\".*\"$/VERSION=\"$version\"/" \
		"$PROJECT_ROOT/mole" > "$install_dir/mole"
	cp "$PROJECT_ROOT/mo" "$install_dir/mo"
	cp -R "$PROJECT_ROOT/lib" "$config_dir/lib"
	chmod +x "$install_dir/mole" "$install_dir/mo"
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
