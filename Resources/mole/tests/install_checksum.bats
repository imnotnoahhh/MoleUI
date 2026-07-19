#!/usr/bin/env bats

setup_file() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT

	ORIGINAL_HOME="${HOME:-}"
	export ORIGINAL_HOME

	HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-install-checksum-home.XXXXXX")"
	export HOME
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
	# Safety: refuse to operate on a real home directory.
	if [[ "$HOME" != "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
		printf 'FATAL: HOME is not a test temp dir: %s\n' "$HOME" >&2
		return 1
	fi
	rm -rf "${HOME:?}"/*
	mkdir -p "$HOME/source" "$HOME/config/bin" "$HOME/install"
	cat > "$HOME/source/mole" <<'MOLE'
VERSION="1.2.3"
MOLE
}

load_installer_binary_helpers() {
	eval "$(sed -n '/^get_source_version()/,/^install_files()/p' "$PROJECT_ROOT/install.sh" | sed '$d')"
}
export -f load_installer_binary_helpers

@test "download_binary installs release asset only after checksum verification" {
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail

INSTALL_DIR="$HOME/install"
CONFIG_DIR="$HOME/config"
SOURCE_DIR="$HOME/source"
VERBOSE=1
GREEN='' BLUE='' YELLOW='' RED='' NC=''
ICON_SUCCESS='ok'
ICON_ERROR='err'

load_installer_binary_helpers

start_line_spinner() { :; }
stop_line_spinner() { :; }
log_success() { echo "SUCCESS:$*"; }
log_warning() { echo "WARNING:$*"; }
log_error() { echo "ERROR:$*"; }
# Exercise the checksum-only path deterministically: a real authenticated gh on
# the host would otherwise run `attestation verify` against the fake fixture and
# fail. Attestation policy itself is covered by its own test below.
verify_release_attestation() { return 2; }

content="verified-binary"
asset="analyze-darwin-$(uname -m | sed 's/x86_64/amd64/')"
hash=$(printf '%s' "$content" | shasum -a 256 | awk '{print $1}')

curl() {
	local out="" url=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-o) out="$2"; shift 2 ;;
			http*) url="$1"; shift ;;
			*) shift ;;
		esac
	done
	case "$url" in
		*"${asset}") printf '%s' "$content" > "$out" ;;
		*"SHA256SUMS") printf '%s  %s\n' "$hash" "$asset" > "$out" ;;
		*) return 1 ;;
	esac
}

download_binary "analyze"
grep -q "verified-binary" "$CONFIG_DIR/bin/analyze-go"
test -x "$CONFIG_DIR/bin/analyze-go"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"SUCCESS:Downloaded analyze binary"* ]]
}

@test "download_binary aborts on checksum mismatch without downgrading to a source build" {
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail

INSTALL_DIR="$HOME/install"
CONFIG_DIR="$HOME/config"
SOURCE_DIR="$HOME/source"
VERBOSE=1
GREEN='' BLUE='' YELLOW='' RED='' NC=''
ICON_SUCCESS='ok'
ICON_ERROR='err'

load_installer_binary_helpers

start_line_spinner() { :; }
stop_line_spinner() { :; }
log_success() { echo "SUCCESS:$*"; }
log_warning() { echo "WARNING:$*"; }
log_error() { echo "ERROR:$*"; }
# A tampered asset must NEVER reroute onto an unverified source build.
build_binary_from_source() {
	echo "SOURCE_BUILD_INVOKED"
	printf 'built-from-source' > "$2"
	chmod +x "$2"
	return 0
}
get_latest_release_tag() { echo "V1.2.3"; }

asset="status-darwin-$(uname -m | sed 's/x86_64/amd64/')"
curl() {
	local out="" url=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-o) out="$2"; shift 2 ;;
			http*) url="$1"; shift ;;
			*) shift ;;
		esac
	done
	case "$url" in
		*"${asset}") printf 'tampered-binary' > "$out" ;;
		*"SHA256SUMS") printf '%064d  %s\n' 0 "$asset" > "$out" ;;
		*) return 1 ;;
	esac
}

if download_binary "status"; then
	echo "UNEXPECTED_SUCCESS"
	exit 1
fi
# No unverified artifact left behind under the installed name.
if [[ -e "$CONFIG_DIR/bin/status-go" ]]; then
	grep -q "tampered-binary" "$CONFIG_DIR/bin/status-go" && echo "TAMPERED_INSTALLED"
	grep -q "built-from-source" "$CONFIG_DIR/bin/status-go" && echo "SOURCE_INSTALLED"
fi
EOF

	[ "$status" -eq 0 ]
	[[ "$output" != *"SOURCE_BUILD_INVOKED"* ]]
	[[ "$output" != *"UNEXPECTED_SUCCESS"* ]]
	[[ "$output" != *"TAMPERED_INSTALLED"* ]]
	[[ "$output" != *"SOURCE_INSTALLED"* ]]
	[[ "$output" == *"aborting instead of falling back"* ]]
}

@test "download_binary preserves the installed helper when verification and rebuild fail (#1193)" {
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail

INSTALL_DIR="$HOME/install"
CONFIG_DIR="$HOME/config"
SOURCE_DIR="$HOME/source"
VERBOSE=1
GREEN='' BLUE='' YELLOW='' RED='' NC=''
ICON_SUCCESS='ok'
ICON_ERROR='err'

load_installer_binary_helpers

start_line_spinner() { :; }
stop_line_spinner() { :; }
log_success() { echo "SUCCESS:$*"; }
log_warning() { echo "WARNING:$*"; }
log_error() { echo "ERROR:$*"; }
verify_release_asset_checksum() { return 1; }
get_latest_release_tag() { echo "V1.2.3"; }
build_binary_from_source() { return 1; }
curl() {
    local out=""
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-o" ]]; then
            out="$2"
            shift 2
        else
            shift
        fi
    done
    printf 'unverified-new-binary' > "$out"
}

printf 'known-good-old-binary' > "$CONFIG_DIR/bin/analyze-go"
chmod +x "$CONFIG_DIR/bin/analyze-go"

if download_binary "analyze"; then
    echo "UNEXPECTED_SUCCESS"
    exit 1
fi

grep -qx 'known-good-old-binary' "$CONFIG_DIR/bin/analyze-go"
if find "$CONFIG_DIR/bin" -maxdepth 1 -name '.analyze-go.*' -print -quit | grep -q .; then
    echo "STAGING_FILE_LEAKED"
    exit 1
fi
EOF

	[ "$status" -eq 0 ]
	[[ "$output" != *"UNEXPECTED_SUCCESS"* ]]
	[[ "$output" != *"STAGING_FILE_LEAKED"* ]]
}

@test "download_binary aborts when SHA256SUMS has no matching asset entry" {
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail

INSTALL_DIR="$HOME/install"
CONFIG_DIR="$HOME/config"
SOURCE_DIR="$HOME/source"
VERBOSE=1
GREEN='' BLUE='' YELLOW='' RED='' NC=''
ICON_SUCCESS='ok'
ICON_ERROR='err'

load_installer_binary_helpers

start_line_spinner() { :; }
stop_line_spinner() { :; }
log_success() { echo "SUCCESS:$*"; }
log_warning() { echo "WARNING:$*"; }
log_error() { echo "ERROR:$*"; }
build_binary_from_source() {
	echo "SOURCE_BUILD_INVOKED"
	printf 'rebuilt-after-missing-checksum' > "$2"
	chmod +x "$2"
	return 0
}
get_latest_release_tag() { echo "V1.2.3"; }

asset="analyze-darwin-$(uname -m | sed 's/x86_64/amd64/')"
hash=$(printf 'release-binary' | shasum -a 256 | awk '{print $1}')
curl() {
	local out="" url=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-o) out="$2"; shift 2 ;;
			http*) url="$1"; shift ;;
			*) shift ;;
		esac
	done
	case "$url" in
		*"${asset}") printf 'release-binary' > "$out" ;;
		*"SHA256SUMS") printf '%s  other-asset\n' "$hash" > "$out" ;;
		*) return 1 ;;
	esac
}

if download_binary "analyze"; then
	echo "UNEXPECTED_SUCCESS"
	exit 1
fi
EOF

	[ "$status" -eq 0 ]
	[[ "$output" != *"SOURCE_BUILD_INVOKED"* ]]
	[[ "$output" != *"UNEXPECTED_SUCCESS"* ]]
	[[ "$output" == *"aborting instead of falling back"* ]]
}

@test "download_binary aborts when SHA256SUMS cannot be downloaded" {
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail

INSTALL_DIR="$HOME/install"
CONFIG_DIR="$HOME/config"
SOURCE_DIR="$HOME/source"
VERBOSE=1
GREEN='' BLUE='' YELLOW='' RED='' NC=''
ICON_SUCCESS='ok'
ICON_ERROR='err'

load_installer_binary_helpers

start_line_spinner() { :; }
stop_line_spinner() { :; }
log_success() { echo "SUCCESS:$*"; }
log_warning() { echo "WARNING:$*"; }
log_error() { echo "ERROR:$*"; }
build_binary_from_source() {
	echo "SOURCE_BUILD_INVOKED"
	printf 'rebuilt-after-checksum-404' > "$2"
	chmod +x "$2"
	return 0
}
get_latest_release_tag() { echo "V1.2.3"; }

asset="status-darwin-$(uname -m | sed 's/x86_64/amd64/')"
curl() {
	local out="" url=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-o) out="$2"; shift 2 ;;
			http*) url="$1"; shift ;;
			*) shift ;;
		esac
	done
	case "$url" in
		*"${asset}") printf 'release-binary' > "$out" ;;
		*"SHA256SUMS") return 22 ;;
		*) return 1 ;;
	esac
}

# An unreachable/blocked SHA256SUMS is indistinguishable from a suppressed
# one, so it must fail closed too, not silently build from unverified source.
if download_binary "status"; then
	echo "UNEXPECTED_SUCCESS"
	exit 1
fi
EOF

	[ "$status" -eq 0 ]
	[[ "$output" != *"SOURCE_BUILD_INVOKED"* ]]
	[[ "$output" != *"UNEXPECTED_SUCCESS"* ]]
	[[ "$output" == *"aborting instead of falling back"* ]]
}

@test "download_binary verifies fallback release asset against fallback checksums" {
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail

INSTALL_DIR="$HOME/install"
CONFIG_DIR="$HOME/config"
SOURCE_DIR="$HOME/source"
VERBOSE=1
GREEN='' BLUE='' YELLOW='' RED='' NC=''
ICON_SUCCESS='ok'
ICON_ERROR='err'

load_installer_binary_helpers

start_line_spinner() { :; }
stop_line_spinner() { :; }
log_success() { echo "SUCCESS:$*"; }
log_warning() { echo "WARNING:$*"; }
log_error() { echo "ERROR:$*"; }
get_latest_release_tag() { echo "V1.2.2"; }
# See note above: keep the fallback-checksum path independent of host gh state.
verify_release_attestation() { return 2; }

content="fallback-binary"
asset="status-darwin-$(uname -m | sed 's/x86_64/amd64/')"
hash=$(printf '%s' "$content" | shasum -a 256 | awk '{print $1}')
curl() {
	local out="" url=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-o) out="$2"; shift 2 ;;
			http*) url="$1"; shift ;;
			*) shift ;;
		esac
	done
	case "$url" in
		*"V1.2.3/${asset}") return 22 ;;
		*"V1.2.2/${asset}") printf '%s' "$content" > "$out" ;;
		*"V1.2.2/SHA256SUMS") printf '%s  %s\n' "$hash" "$asset" > "$out" ;;
		*) return 1 ;;
	esac
}

download_binary "status"
grep -q "fallback-binary" "$CONFIG_DIR/bin/status-go"
EOF

	[ "$status" -eq 0 ]
	[[ "$output" == *"SUCCESS:Downloaded status from V1.2.2"* ]]
}

@test "download_binary aborts on fallback-tag checksum mismatch without a source build" {
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail

INSTALL_DIR="$HOME/install"
CONFIG_DIR="$HOME/config"
SOURCE_DIR="$HOME/source"
VERBOSE=1
GREEN='' BLUE='' YELLOW='' RED='' NC=''
ICON_SUCCESS='ok'
ICON_ERROR='err'

load_installer_binary_helpers

start_line_spinner() { :; }
stop_line_spinner() { :; }
log_success() { echo "SUCCESS:$*"; }
log_warning() { echo "WARNING:$*"; }
log_error() { echo "ERROR:$*"; }
get_latest_release_tag() { echo "V1.2.2"; }
verify_release_attestation() { return 2; }
# The fallback tag is the last verification gate before the source-build
# branch; a mismatch there is tampering evidence and must abort too.
build_binary_from_source() {
	echo "SOURCE_BUILD_INVOKED"
	printf 'built-from-source' > "$2"
	chmod +x "$2"
	return 0
}

asset="status-darwin-$(uname -m | sed 's/x86_64/amd64/')"
good_hash=$(printf 'expected-binary' | shasum -a 256 | awk '{print $1}')
curl() {
	local out="" url=""
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-o) out="$2"; shift 2 ;;
			http*) url="$1"; shift ;;
			*) shift ;;
		esac
	done
	case "$url" in
		*"V1.2.3/${asset}") return 22 ;;
		*"V1.2.2/${asset}") printf 'tampered-binary' > "$out" ;;
		*"V1.2.2/SHA256SUMS") printf '%s  %s\n' "$good_hash" "$asset" > "$out" ;;
		*) return 1 ;;
	esac
}

if download_binary "status"; then
	echo "UNEXPECTED_SUCCESS"
	exit 1
fi
if [[ -e "$CONFIG_DIR/bin/status-go" ]]; then
	echo "BINARY_INSTALLED_ANYWAY"
fi
EOF

	[ "$status" -eq 0 ] || return 1
	[[ "$output" != *"SOURCE_BUILD_INVOKED"* ]] || return 1
	[[ "$output" != *"UNEXPECTED_SUCCESS"* ]] || return 1
	[[ "$output" != *"BINARY_INSTALLED_ANYWAY"* ]] || return 1
	[[ "$output" == *"aborting instead of falling back"* ]] || return 1
}


@test "install_files fails closed when sudo is unavailable, even under || caller (#update-incident)" {
	# Old moles invoke `install_files || {...}`, which disables errexit inside
	# the function. Uncached `sudo -n` then failed on every copy while the
	# install still reported success with the OLD entry script in place
	# ("Updated to latest version, 1.45.0" while fetching V1.47.0).
	# MOLE_TEST_NO_AUTH must not leak in: it would take the blocked-in-test-mode
	# branch instead of the real ensure_sudo_ready gate. sudo is a function mock.
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=0 MOLE_TEST_MODE=0 bash --noprofile --norc <<'EOF'
set -euo pipefail

eval "$(sed -n '/^needs_sudo() {/,/^}/p' "$PROJECT_ROOT/install.sh")"
eval "$(sed -n '/^ensure_sudo_ready() {/,/^}/p' "$PROJECT_ROOT/install.sh")"
eval "$(sed -n '/^maybe_sudo() {/,/^}/p' "$PROJECT_ROOT/install.sh")"
eval "$(sed -n '/^install_files() {/,/^}/p' "$PROJECT_ROOT/install.sh")"

INSTALL_DIR="$HOME/rooty-bin"
CONFIG_DIR="$HOME/config"
SOURCE_DIR="$HOME/source"
VERBOSE=1
GREEN='' BLUE='' YELLOW='' RED='' NC=''
ICON_SUCCESS='ok' ICON_ERROR='err' ICON_ADMIN='adm'
MOLE_ASSUME_SUDO_AUTH=1

mkdir -p "$CONFIG_DIR" "$SOURCE_DIR"
printf '#!/bin/bash\nVERSION="9.9.9"\n' > "$SOURCE_DIR/mole"
printf '#!/bin/bash\n' > "$SOURCE_DIR/mo"
# Non-writable install dir: needs_sudo must answer true for a plain user.
mkdir -m 555 "$INSTALL_DIR"

log_error() { echo "ERROR:$*"; }
log_success() { echo "SUCCESS:$*"; }
log_admin() { echo "ADMIN:$*"; }
download_binary() { echo "DOWNLOAD_CALLED:$1"; return 0; }
sudo() {
	echo "sudo: a password is required" >&2
	return 1
}

# Reproduce the exact caller shape from the update flow.
install_files || echo "HANDLED_FAILURE"
EOF

	[ "$status" -eq 0 ] || return 1
	[[ "$output" == *"HANDLED_FAILURE"* ]] || return 1
	[[ "$output" == *"sudo -v && mo update"* ]] || return 1
	[[ "$output" != *"SUCCESS:Installed mole"* ]] || return 1
	[[ "$output" != *"DOWNLOAD_CALLED"* ]] || return 1
}

@test "verify_installation rejects a stale entry script after an update (#update-incident)" {
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -uo pipefail

eval "$(sed -n '/^get_source_version() {/,/^}/p' "$PROJECT_ROOT/install.sh")"
eval "$(sed -n '/^get_installed_version() {/,/^}/p' "$PROJECT_ROOT/install.sh")"
eval "$(sed -n '/^verify_installation() {/,/^}/p' "$PROJECT_ROOT/install.sh")"

INSTALL_DIR="$HOME/bin"
CONFIG_DIR="$HOME/config"
SOURCE_DIR="$HOME/source"
GREEN='' RED='' YELLOW='' NC=''
ICON_ERROR='err'

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR/lib/core" "$SOURCE_DIR"
touch "$CONFIG_DIR/lib/core/common.sh"
# The old entry script survived a failed copy: runnable, wrong version.
printf '#!/bin/bash\nVERSION="1.45.0"\nexit 0\n' > "$INSTALL_DIR/mole"
chmod +x "$INSTALL_DIR/mole"
printf '#!/bin/bash\nVERSION="1.47.0"\n' > "$SOURCE_DIR/mole"

log_error() { echo "ERROR:$*"; }
log_warning() { echo "WARNING:$*"; }

verify_installation
echo "UNEXPECTED_PASS"
EOF

	# verify_installation exits 1 on the mixed-version state.
	[ "$status" -eq 1 ] || return 1
	[[ "$output" != *"UNEXPECTED_PASS"* ]] || return 1
	[[ "$output" == *"was not replaced"* ]] || return 1
	[[ "$output" == *"1.45.0"* && "$output" == *"1.47.0"* ]] || return 1
}

@test "write_install_channel_metadata succeeds for stable channel with empty commit hash" {
	# Regression: the previous `[[ -n "$h" ]] && printf` form returned 1
	# whenever the commit hash was empty (always the case on stable), making
	# the block redirect look like an I/O failure and tripping the warning.
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
CONFIG_DIR="$HOME/config"
mkdir -p "$CONFIG_DIR"

eval "$(sed -n '/^write_install_channel_metadata()/,/^}/p' "$PROJECT_ROOT/install.sh")"

if ! write_install_channel_metadata "stable" ""; then
	echo "WRONG: stable write reported failure"; exit 1
fi
[[ -f "$CONFIG_DIR/install_channel" ]] || { echo "WRONG: file not created"; exit 1; }
grep -q '^CHANNEL=stable$' "$CONFIG_DIR/install_channel" || { echo "WRONG: channel value missing"; cat "$CONFIG_DIR/install_channel"; exit 1; }
grep -q '^COMMIT_HASH=' "$CONFIG_DIR/install_channel" && { echo "WRONG: commit hash leaked"; exit 1; }

# Nightly path with a commit hash should still work.
if ! write_install_channel_metadata "nightly" "deadbeef"; then
	echo "WRONG: nightly write failed"; exit 1
fi
grep -q '^CHANNEL=nightly$' "$CONFIG_DIR/install_channel" || { echo "WRONG: nightly channel"; exit 1; }
grep -q '^COMMIT_HASH=deadbeef$' "$CONFIG_DIR/install_channel" || { echo "WRONG: nightly commit"; exit 1; }

# No leftover temp files.
if ls "$CONFIG_DIR"/install_channel.?????? 2>/dev/null | grep -q .; then
	echo "WRONG: tmp file leaked"; ls "$CONFIG_DIR"; exit 1
fi
EOF

	[ "$status" -eq 0 ]
}

@test "verify_release_attestation maps gh availability and result to 2/0/1" {
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail

eval "$(sed -n '/^verify_release_attestation()/,/^}/p' "$PROJECT_ROOT/install.sh")"

stubdir="$(mktemp -d "${TMPDIR:-/tmp}/mole-gh-stub.XXXXXX")"
cat > "$stubdir/gh" <<'STUB'
#!/bin/bash
case "$1 $2" in
	"auth status") exit "${STUB_AUTH_RC:-0}" ;;
	"attestation verify") exit "${STUB_VERIFY_RC:-0}" ;;
esac
exit 0
STUB
chmod +x "$stubdir/gh"
target="$(mktemp "${TMPDIR:-/tmp}/mole-att-file.XXXXXX")"

# gh missing -> cannot verify (2)
( PATH="/var/empty"; verify_release_attestation "$target" ) && rc=0 || rc=$?
[ "$rc" -eq 2 ] || { echo "WRONG: gh-missing rc=$rc want 2"; exit 1; }

# gh present but unauthenticated -> cannot verify (2)
( PATH="$stubdir:$PATH"; export STUB_AUTH_RC=1; verify_release_attestation "$target" ) && rc=0 || rc=$?
[ "$rc" -eq 2 ] || { echo "WRONG: unauth rc=$rc want 2"; exit 1; }

# gh authenticated + attestation verifies -> 0
( PATH="$stubdir:$PATH"; export STUB_AUTH_RC=0 STUB_VERIFY_RC=0; verify_release_attestation "$target" ) && rc=0 || rc=$?
[ "$rc" -eq 0 ] || { echo "WRONG: verify-ok rc=$rc want 0"; exit 1; }

# gh authenticated + attestation fails -> 1
( PATH="$stubdir:$PATH"; export STUB_AUTH_RC=0 STUB_VERIFY_RC=1; verify_release_attestation "$target" ) && rc=0 || rc=$?
[ "$rc" -eq 1 ] || { echo "WRONG: verify-fail rc=$rc want 1"; exit 1; }

rm -rf "$stubdir" "$target"
EOF

	[ "$status" -eq 0 ]
}

@test "verify_release_asset_checksum enforces attestation policy gate" {
	run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail

eval "$(sed -n '/^extract_release_checksum()/,/^}/p' "$PROJECT_ROOT/install.sh")"
eval "$(sed -n '/^calculate_file_sha256()/,/^}/p' "$PROJECT_ROOT/install.sh")"
eval "$(sed -n '/^verify_release_asset_checksum()/,/^}/p' "$PROJECT_ROOT/install.sh")"

log_success() { echo "SUCCESS:$*"; }
log_error() { echo "ERROR:$*"; }

asset="status-darwin-amd64"
file="$(mktemp "${TMPDIR:-/tmp}/mole-asset.XXXXXX")"
printf 'release-binary' > "$file"
hash="$(printf 'release-binary' | shasum -a 256 | awk '{print $1}')"
download_release_checksums() { printf '%s  %s\n' "$hash" "$asset" > "$2"; return 0; }

# attestation verification failed (status 1) -> fatal, never installs
verify_release_attestation() { return 1; }
out="$(verify_release_asset_checksum V1.0.0 "$asset" "$file")" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || { echo "WRONG: status1 rc=$rc want 1"; exit 1; }
[[ "$out" == *"ERROR:Release attestation verification failed"* ]] || { echo "WRONG: status1 error missing: $out"; exit 1; }

# cannot verify (status 2) + MOLE_REQUIRE_ATTESTATION=1 -> fatal
verify_release_attestation() { return 2; }
out="$(MOLE_REQUIRE_ATTESTATION=1 verify_release_asset_checksum V1.0.0 "$asset" "$file")" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || { echo "WRONG: require-gate rc=$rc want 1"; exit 1; }
[[ "$out" == *"ERROR:MOLE_REQUIRE_ATTESTATION=1 set but gh"* ]] || { echo "WRONG: require-gate error missing: $out"; exit 1; }

# cannot verify (status 2) without the gate -> falls back to checksum-only
verify_release_attestation() { return 2; }
out="$(verify_release_asset_checksum V1.0.0 "$asset" "$file")" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || { echo "WRONG: checksum-only rc=$rc want 0"; exit 1; }

# attestation verified (status 0) + checksum match -> success with combined label
verify_release_attestation() { return 0; }
out="$(verify_release_asset_checksum V1.0.0 "$asset" "$file")" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || { echo "WRONG: verified rc=$rc want 0"; exit 1; }
[[ "$out" == *"SUCCESS:Verified ${asset} (sha256 + attestation)"* ]] || { echo "WRONG: verified success missing: $out"; exit 1; }

rm -f "$file"
EOF

	[ "$status" -eq 0 ]
}
